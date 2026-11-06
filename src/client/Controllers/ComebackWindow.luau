--!strict
-- Окно «С возвращением!» (7.21, ComebackService): кого не было Comeback.minAwayDays дней,
-- получает минуты дохода и кофе. Сумму считает сервер и кладёт в атрибуты игрока
-- ComebackCash / ComebackCoffee / ComebackDays (> 0 — есть бонус); «Забрать» просит сервер начислить.
-- Всплывает само, по очереди с другими окнами входа (PopupQueue).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RetentionRemotes = require(ReplicatedStorage.Shared.RetentionRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local ArtIcon = require(script.Parent.Parent.ArtIcon)
local Comeback = require(ReplicatedStorage.Shared.Config.Comeback)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local PopupQueue = require(script.Parent.Parent.PopupQueue)

local HEADER_ART = 64 -- V31: картинка Астры над заголовком (Images.windows), если есть ID

local ComebackWindow = {}
local gui: ScreenGui? = nil
local player = Players.LocalPlayer

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

local function show()
	close()
	local cash = tonumber(player:GetAttribute("ComebackCash")) or 0
	local coffee = tonumber(player:GetAttribute("ComebackCoffee")) or 0
	local days = tonumber(player:GetAttribute("ComebackDays")) or Comeback.minAwayDays
	local screen = Instance.new("ScreenGui")
	screen.Name = "ComebackWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 25
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local window = Ui.window(
		screen,
		"Window",
		Vector2.new(
			460,
			(if coffee > 0 then 360 else 320) + ArtIcon.headerHeight(Images.windows.comeback, HEADER_ART, 10)
		)
	)
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	local layout = Ui.list(body, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	body.Parent = window

	local title = Ui.label(body, ClientState.t("back_title"), 36, Ui.titleFontFor(ClientState.lang))
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 1
	ArtIcon.header(body, Images.windows.comeback, HEADER_ART, 0)
	local away =
		Ui.label(body, ClientState.t("back_away", { days = days }), 24, Enum.Font.GothamBold, Ui.colors.text)
	away.TextXAlignment = Enum.TextXAlignment.Center
	away.LayoutOrder = 2
	local money =
		Ui.label(body, "+" .. Texts.money(cash), 56, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	money.TextXAlignment = Enum.TextXAlignment.Center
	money.LayoutOrder = 3
	if coffee > 0 then
		local coffeeLabel = Ui.label(
			body,
			ClientState.t("back_coffee", { minutes = coffee }),
			26,
			Enum.Font.GothamBold,
			Ui.colors.good
		)
		coffeeLabel.TextXAlignment = Enum.TextXAlignment.Center
		coffeeLabel.LayoutOrder = 4
	end
	local hint = Ui.label(
		body,
		ClientState.t("back_hint", { minutes = Comeback.incomeMinutes }),
		22,
		Enum.Font.GothamMedium,
		Ui.colors.muted
	)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.TextWrapped = true
	hint.LayoutOrder = 5

	local claim = Ui.button(body, ClientState.t("back_claim"), Ui.colors.good, function()
		RetentionRemotes.ClaimComeback:FireServer()
		close()
	end)
	claim.Size = UDim2.new(0.6, 0, 0, 52)
	claim.LayoutOrder = 6
end

function ComebackWindow.start()
	local function check()
		local days = player:GetAttribute("ComebackDays")
		if type(days) == "number" and days > 0 then
			if not gui then
				PopupQueue.push("comeback", function()
					local pending = player:GetAttribute("ComebackDays")
					if not gui and type(pending) == "number" and pending > 0 then
						show()
					end
				end)
			end
		else
			PopupQueue.remove("comeback")
			close()
		end
	end
	player:GetAttributeChangedSignal("ComebackDays"):Connect(check)
	-- Сохранённый язык приходит после входа — перерисовать открытое окно
	ClientState.langChanged:Connect(function()
		if gui then
			show()
		end
	end)
	check()
end

return ComebackWindow
