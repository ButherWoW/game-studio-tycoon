--!strict
-- Окно «🎟 Коды»: поле для промокода, кнопка «Активировать» и результат.
-- Открывается кнопкой в шапке магазина (ShopWindow). Проверяет и выдаёт награду сервер
-- (CodeService); клиент только показывает ответ CodeResult.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Texts = require(Shared.Config.Texts)
local Skins = require(Shared.Config.Skins)
local Posters = require(Shared.Config.Posters)
local Images = require(Shared.Config.Images)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)
local ArtIcon = require(script.Parent.ArtIcon)

local CodeWindow = {}
local gui: ScreenGui? = nil
local resultLabel: TextLabel? = nil
local connected = false

-- Remotes берём при открытии: если серверный модуль упал, магазин всё равно работает
local function remotes(): any
	return require(Shared.CodeRemotes) :: any
end

-- «$12 000, ☕ кофе 15 мин, скин «…»»
local function rewardText(reward: any): string
	local parts = {}
	if type(reward) ~= "table" then
		return ""
	end
	if type(reward.cash) == "number" then
		table.insert(parts, Texts.money(reward.cash))
	end
	if type(reward.coffeeMinutes) == "number" then
		table.insert(parts, ClientState.t("codes_reward_coffee", { minutes = reward.coffeeMinutes }))
	end
	local skin = Skins.get(reward.skin)
	if skin then
		table.insert(
			parts,
			ClientState.t(
				"codes_reward_item",
				{ item = ClientState.localText("skin_" .. skin.id, skin.name, skin.nameEn) }
			)
		)
	end
	local poster = Posters.get(reward.poster)
	if poster then
		table.insert(
			parts,
			ClientState.t(
				"codes_reward_item",
				{ item = ClientState.localText("poster_" .. poster.id, poster.name, poster.nameEn) }
			)
		)
	end
	return table.concat(parts, ", ")
end

local function onResult(result: any)
	local label = resultLabel
	if not label or not label.Parent or type(result) ~= "table" then
		return
	end
	local reason = if type(result.reason) == "string" then result.reason else "invalid"
	if reason == "ok" then
		label.Text = ClientState.t("codes_ok", { reward = rewardText(result.reward) })
		label.TextColor3 = Ui.colors.good
	else
		local key = "codes_" .. reason
		label.Text = if Texts.en[key] then ClientState.t(key) else ClientState.t("codes_invalid")
		label.TextColor3 = if reason == "limit" then Ui.colors.money else Ui.colors.bad
	end
end

function CodeWindow.close()
	if gui then
		gui:Destroy()
		gui = nil
		resultLabel = nil
		Ui.windowClosed()
	end
end

function CodeWindow.open()
	if gui then
		return
	end
	if not connected then
		connected = true
		remotes().CodeResult.OnClientEvent:Connect(onResult)
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "CodeWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20 -- над магазином (10)
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local window = Ui.window(screen, "Window", Vector2.new(460, 300))
	local title = Ui.label(window, ClientState.t("codes_title"), 34, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 34)
	ArtIcon.prefix(title, "🎟", Images.social.iconCodes, 34)
	local close = Ui.button(window, ClientState.t("create_close"), Ui.colors.locked, CodeWindow.close)
	close.Size = UDim2.fromOffset(40, 40)
	close.Position = UDim2.new(1, -52, 0, 8)

	local hint = Ui.label(window, ClientState.t("codes_hint"), 20, Enum.Font.GothamMedium, Ui.colors.muted)
	hint.Position = UDim2.fromOffset(16, 56)
	hint.Size = UDim2.new(1, -32, 0, 20)

	local box = Instance.new("TextBox")
	box.Position = UDim2.fromOffset(16, 92)
	box.Size = UDim2.new(1, -32, 0, 52)
	box.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
	box.TextColor3 = Ui.colors.text
	box.PlaceholderText = ClientState.t("codes_placeholder")
	box.PlaceholderColor3 = Ui.colors.muted
	box.Font = Ui.bodyFont
	box.TextSize = 26
	box.Text = ""
	box.ClearTextOnFocus = false
	Ui.corner(box, 10)
	box.Parent = window

	local result = Ui.label(window, "", 26, Enum.Font.GothamMedium, Ui.colors.muted)
	result.Position = UDim2.fromOffset(16, 220)
	result.Size = UDim2.new(1, -32, 0, 56)
	result.TextWrapped = true
	result.TextXAlignment = Enum.TextXAlignment.Center
	resultLabel = result

	local function redeem()
		local text = box.Text
		if text:match("%S") == nil then
			return
		end
		result.Text = "…"
		result.TextColor3 = Ui.colors.muted
		remotes().RedeemCode:FireServer(text)
	end
	local button = Ui.button(window, ClientState.t("codes_redeem"), Ui.colors.good, redeem)
	button.Position = UDim2.fromOffset(16, 156)
	button.Size = UDim2.new(1, -32, 0, 52)
	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			redeem()
		end
	end)
end

return CodeWindow
