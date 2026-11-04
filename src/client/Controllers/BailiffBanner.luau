--!strict
-- Плашка долга (BailiffService, Config/Bailiffs): баланс в минусе — сколько должен и когда придут
-- приставы, кнопки «Кредит» (окно банка), «Закрыть долг за R$» (пакет дохода, Config/Offers.strike)
-- и «Уволить» (окно «Команда»). Тосты: приставы забрали предмет / долг погашен, приставы ушли.
-- Состояние — атрибуты игрока BailiffDebt, BailiffLimit, BailiffsActive.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Bailiffs = require(Shared.Config.Bailiffs)
local Decor = require(Shared.Config.Decor)
local Offers = require(Shared.Config.Offers)
local Texts = require(Shared.Config.Texts)
local StudioLayout = require(Shared.StudioLayout)
local BailiffRemotes = require(Shared.BailiffRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local OfferClient = require(script.Parent.Parent.OfferClient)
local LoanWindow = require(script.Parent.LoanWindow)
local TeamWindow = require(script.Parent.TeamWindow)

-- Плашка — первая в общем стеке под HUD (тренд 1, выставка 2, итоги 3)
local WIDTH = 520
local TEXT_HEIGHT = 30
local BUTTONS_HEIGHT = 34
local TOAST_HEIGHT = 34
local TOAST_SECONDS = 5

local BailiffBanner = {}

local function attr(name: string): number
	return tonumber(Players.LocalPlayer:GetAttribute(name)) or 0
end

local function itemName(kind: any, id: any): string
	if type(id) ~= "string" then
		return "?"
	end
	if kind == "decor" then
		local item = Decor.get(id)
		return if item then ClientState.localText("decor_" .. id, item.name, item.nameEn) else id
	end
	local upgrade = StudioLayout.get(id)
	if upgrade then
		local key = "upgrade_" .. id
		return ClientState.localText(key, upgrade.name, Texts.en[key] or upgrade.name)
	end
	return id
end

function BailiffBanner.start()
	local stack = Ui.bannerStack()
	local panel = Instance.new("Frame")
	panel.Name = "BailiffBanner"
	panel.LayoutOrder = 0
	panel.Size = UDim2.fromOffset(WIDTH, TEXT_HEIGHT + BUTTONS_HEIGHT + 14)
	panel.BackgroundColor3 = Ui.colors.panel
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	Ui.corner(panel, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Ui.colors.bad
	stroke.Thickness = 2
	stroke.Parent = panel
	local layout = Ui.list(panel, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = panel
	panel.Parent = stack

	local text = Ui.label(panel, "", TEXT_HEIGHT, Ui.titleFontFor(ClientState.lang), Ui.colors.bad)
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.LayoutOrder = 1

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, BUTTONS_HEIGHT)
	row.LayoutOrder = 2
	row.Parent = panel
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.Parent = row

	local packShown = false
	local currentPack: OfferClient.Pack? = nil
	local bank = Ui.button(row, "", Ui.colors.primary, function()
		LoanWindow.open()
	end)
	bank.Size = UDim2.new(0.28, 0, 1, 0)
	bank.LayoutOrder = 1
	local pay = Ui.button(row, "", Ui.colors.good, function()
		local pack = currentPack
		if pack then
			OfferClient.buyProduct("strike", pack.product.productId)
		end
	end)
	pay.Size = UDim2.new(0.38, 0, 1, 0)
	pay.LayoutOrder = 2
	local fire = Ui.button(row, "", Ui.colors.locked, function()
		TeamWindow.open()
	end)
	fire.Size = UDim2.new(0.28, 0, 1, 0)
	fire.LayoutOrder = 3

	local function refresh()
		local debt = attr("BailiffDebt")
		panel.Visible = debt > 0
		if debt <= 0 then
			packShown = false
			return
		end
		local font = Ui.titleFontFor(ClientState.lang)
		text.Font = font
		local vars = {
			debt = Texts.money(debt),
			limit = Texts.money(attr("BailiffLimit")),
			percent = math.floor(Bailiffs.sellShare * 100),
		}
		local active = Players.LocalPlayer:GetAttribute("BailiffsActive") == true
		text.Text = ClientState.t(if active then "bailiff_active" else "bailiff_warning", vars)
		bank.Text = ClientState.t("bailiff_bank")
		fire.Text = ClientState.t("bailiff_fire")
		-- Пакет дохода, который закрывает долг (те же пакеты, что при забастовке)
		currentPack = if Offers.enabled.strike then OfferClient.packFor(debt, Offers.strike.packs) else nil
		local pack = currentPack
		pay.Visible = pack ~= nil and pack.product.productId ~= 0
		if pack then
			pay.Text = ClientState.t("bailiff_pack", { price = pack.product.robuxPrice })
			if pay.Visible and not packShown then
				packShown = true
				OfferClient.track("strike", "shown")
			end
		end
	end

	-- Тост под плашкой: что забрали / приставы ушли
	local function toast(message: string, color: Color3)
		local label = Ui.label(stack, message, TOAST_HEIGHT, Ui.titleFontFor(ClientState.lang), color)
		label.Size = UDim2.fromOffset(WIDTH, TOAST_HEIGHT)
		label.LayoutOrder = 0
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.BackgroundTransparency = 0.15
		label.BackgroundColor3 = Ui.colors.panel
		Ui.corner(label, 10)
		task.delay(TOAST_SECONDS, function()
			label:Destroy()
		end)
	end

	BailiffRemotes.BailiffSeized.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then
			return
		end
		if data.left == true then
			toast(ClientState.t("bailiff_left"), Ui.colors.good)
			return
		end
		toast(
			ClientState.t("bailiff_seized", {
				item = itemName(data.kind, data.id),
				amount = Texts.money(tonumber(data.amount) or 0),
			}),
			Ui.colors.bad
		)
	end)

	local player = Players.LocalPlayer
	for _, name in { "BailiffDebt", "BailiffLimit", "BailiffsActive" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	ClientState.langChanged:Connect(refresh)
	refresh()
end

return BailiffBanner
