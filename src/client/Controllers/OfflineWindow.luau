--!strict
-- Окно «Пока тебя не было: +$X» (шаг 4.4). Сумму считает OfflineService и кладёт
-- в атрибут игрока OfflinePending; «Забрать» просит сервер начислить её.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RetentionRemotes = require(ReplicatedStorage.Shared.RetentionRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local OfflineWindow = {}
local gui: ScreenGui? = nil
local shownAmount = 0

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

local function show(amount: number)
	close()
	shownAmount = amount
	local screen = Instance.new("ScreenGui")
	screen.Name = "OfflineWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 25
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local window = Ui.window(screen, "Window", Vector2.new(440, 280))
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	local layout = Ui.list(body, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	body.Parent = window

	local title = Ui.label(body, ClientState.t("offline_title"), 36, Ui.titleFontFor(ClientState.lang))
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 1
	local money = Ui.label(
		body,
		ClientState.t("offline_amount", { money = Texts.money(amount) }),
		56,
		Ui.titleFontFor(ClientState.lang),
		Ui.colors.money
	)
	money.TextXAlignment = Enum.TextXAlignment.Center
	money.LayoutOrder = 2
	local hint = Ui.label(body, ClientState.t("offline_hint"), 22, Enum.Font.GothamMedium, Ui.colors.muted)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.LayoutOrder = 3

	local claim = Ui.button(body, ClientState.t("offline_claim"), Ui.colors.good, function()
		RetentionRemotes.ClaimOffline:FireServer()
		close()
	end)
	claim.Size = UDim2.new(0.6, 0, 0, 52)
	claim.LayoutOrder = 4
end

function OfflineWindow.start()
	local player = Players.LocalPlayer
	local function check()
		local amount = player:GetAttribute("OfflinePending")
		if type(amount) == "number" and amount > 0 then
			if not gui then
				show(amount)
			end
		else
			close()
		end
	end
	player:GetAttributeChangedSignal("OfflinePending"):Connect(check)
	-- Окно открывается при входе, а сохранённый язык приходит позже — перерисовать (отчёт #2, п. 3)
	ClientState.langChanged:Connect(function()
		if gui then
			show(shownAmount)
		end
	end)
	check()
end

return OfflineWindow
