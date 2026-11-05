--!strict
-- Окно «🆕 Что нового» (график контента, Config/ContentDrops): первый вход после новой волны —
-- заголовок волны и что в ней вышло. Номер волны присылает ContentDropService в атрибуте игрока
-- ContentDropNew (0 — нечего показывать); «Круто!» говорит серверу, что окно увидено.
-- Всплывает само, по очереди с другими окнами входа (PopupQueue).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ContentDrops = require(ReplicatedStorage.Shared.Config.ContentDrops)
local ContentDropRemotes = require(ReplicatedStorage.Shared.ContentDropRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local ContentDropClient = require(script.Parent.Parent.ContentDropClient)
local Ui = require(script.Parent.Parent.Ui)
local PopupQueue = require(script.Parent.Parent.PopupQueue)

local MAX_LINES = 8 -- больше не влезает на телефон: остальное — одной строкой «и ещё N»
local LINE_HEIGHT = 24

local WhatsNewWindow = {}
local gui: ScreenGui? = nil
local shownIndex = 0
local player = Players.LocalPlayer

local function pendingIndex(): number
	local index = player:GetAttribute("ContentDropNew")
	return if type(index) == "number" and ContentDrops.drops[index] then index else 0
end

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

local function show(index: number)
	close()
	local drop = ContentDrops.drops[index]
	if not drop then
		return
	end
	shownIndex = index
	local items = ContentDrops.items(drop)
	local lines = math.min(#items, MAX_LINES) + (if #items > MAX_LINES then 1 else 0)
	local hasNext = ContentDropClient.nextText() ~= nil

	local screen = Instance.new("ScreenGui")
	screen.Name = "WhatsNewWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 25
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local height = 210 + lines * (LINE_HEIGHT + 6) + (if hasNext then 30 else 0)
	local window = Ui.window(screen, "Window", Vector2.new(480, height))
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	local layout = Ui.list(body, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	body.Parent = window

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local head = Ui.label(body, ClientState.t("drop_whats_new"), 24, Enum.Font.GothamBold, Ui.colors.muted)
	head.TextXAlignment = Enum.TextXAlignment.Center
	head.LayoutOrder = nextOrder()
	local title =
		Ui.label(body, ContentDropClient.title(drop), 36, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = nextOrder()
	for i, item in items do
		if i > MAX_LINES then
			local more = Ui.label(
				body,
				ClientState.t("drop_more", { count = #items - MAX_LINES }),
				LINE_HEIGHT - 4,
				Enum.Font.GothamMedium,
				Ui.colors.muted
			)
			more.TextXAlignment = Enum.TextXAlignment.Center
			more.LayoutOrder = nextOrder()
			break
		end
		local line = Ui.label(
			body,
			ClientState.t("drop_kind_" .. item.kind) .. ": " .. ContentDropClient.itemName(item.kind, item.id),
			LINE_HEIGHT,
			Enum.Font.GothamMedium
		)
		line.TextXAlignment = Enum.TextXAlignment.Center
		line.LayoutOrder = nextOrder()
	end
	local hint = Ui.label(body, ClientState.t("drop_hint"), 20, Enum.Font.GothamMedium, Ui.colors.muted)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.TextWrapped = true
	hint.LayoutOrder = nextOrder()
	local nextLabel = ContentDropClient.nextLine(body, nextOrder())
	if nextLabel then
		nextLabel.TextXAlignment = Enum.TextXAlignment.Center
	end

	local ok = Ui.button(body, ClientState.t("drop_ok"), Ui.colors.good, function()
		ContentDropRemotes.SeenDrop:FireServer(index)
		close()
	end)
	ok.Size = UDim2.new(0.6, 0, 0, 52)
	ok.LayoutOrder = nextOrder()
end

function WhatsNewWindow.start()
	local function check()
		local index = pendingIndex()
		if index > 0 then
			if not gui or shownIndex ~= index then
				PopupQueue.push("whatsNew", function()
					local pending = pendingIndex()
					if pending > 0 and (not gui or shownIndex ~= pending) then
						show(pending)
					end
				end)
			end
		else
			PopupQueue.remove("whatsNew")
			close()
		end
	end
	player:GetAttributeChangedSignal("ContentDropNew"):Connect(check)
	-- Сохранённый язык приходит после входа — перерисовать открытое окно
	ClientState.langChanged:Connect(function()
		if gui and shownIndex > 0 then
			show(shownIndex)
		end
	end)
	check()
end

return WhatsNewWindow
