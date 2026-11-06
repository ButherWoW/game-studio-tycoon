--!strict
-- Окно «Пока тебя не было: +$X» (шаг 4.4). Сумму считает OfflineService и кладёт
-- в атрибут игрока OfflinePending; «Забрать» просит сервер начислить её.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RetentionRemotes = require(ReplicatedStorage.Shared.RetentionRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local ArtIcon = require(script.Parent.Parent.ArtIcon)
local Offline = require(ReplicatedStorage.Shared.Config.Offline)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local PopupQueue = require(script.Parent.Parent.PopupQueue)

local HEADER_ART = 64 -- V31: картинка Астры над заголовком (Images.windows), если есть ID

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

-- «Тебя не было 3 ч 20 мин» (+ «копится не больше 4 ч», если упёрлись в лимит)
local function awayText(): string?
	local away = Players.LocalPlayer:GetAttribute("OfflineAway")
	if type(away) ~= "number" or away <= 0 then
		return nil
	end
	local minutes = math.floor(away / 60)
	local duration = if minutes >= 60
		then ClientState.t("offline_time_hm", { h = minutes // 60, m = minutes % 60 })
		else ClientState.t("offline_time_m", { m = minutes })
	local text = ClientState.t("offline_away", { time = duration })
	if away > Offline.maxSeconds then
		text ..= " · " .. ClientState.t("offline_capped", { hours = Offline.maxSeconds // 3600 })
	end
	return text
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

	local away = awayText()
	local window = Ui.window(
		screen,
		"Window",
		Vector2.new(
			440,
			(if away then 316 else 280) + ArtIcon.headerHeight(Images.windows.offline, HEADER_ART, 10)
		)
	)
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
	ArtIcon.header(body, Images.windows.offline, HEADER_ART, 0)
	local money = Ui.label(
		body,
		ClientState.t("offline_amount", { money = Texts.money(amount) }),
		56,
		Ui.titleFontFor(ClientState.lang),
		Ui.colors.money
	)
	money.TextXAlignment = Enum.TextXAlignment.Center
	money.LayoutOrder = 2
	if away then
		local awayLabel = Ui.label(body, away, 24, Enum.Font.GothamBold, Ui.colors.text)
		awayLabel.TextXAlignment = Enum.TextXAlignment.Center
		awayLabel.LayoutOrder = 3
	end
	local hint = Ui.label(body, ClientState.t("offline_hint"), 22, Enum.Font.GothamMedium, Ui.colors.muted)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.LayoutOrder = 4

	local claim = Ui.button(body, ClientState.t("offline_claim"), Ui.colors.good, function()
		RetentionRemotes.ClaimOffline:FireServer()
		close()
	end)
	claim.Size = UDim2.new(0.6, 0, 0, 52)
	claim.LayoutOrder = 5
end

function OfflineWindow.start()
	local player = Players.LocalPlayer
	local function check()
		local amount = player:GetAttribute("OfflinePending")
		if type(amount) == "number" and amount > 0 then
			-- По очереди с другими окнами входа и не во время туториала (PopupQueue)
			if not gui then
				PopupQueue.push("offline", function()
					local pending = player:GetAttribute("OfflinePending")
					if not gui and type(pending) == "number" and pending > 0 then
						show(pending)
					end
				end)
			end
		else
			PopupQueue.remove("offline")
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
