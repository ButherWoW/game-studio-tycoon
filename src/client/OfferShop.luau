--!strict
-- Верх окна магазина (ShopWindow): «Сделка дня» (−30% на один товар в сутки UTC, отсчёт до
-- полуночи UTC) и строка стартового набора, пока идёт его таймер. Товар дня — Offers.dealFor,
-- скидочный продукт — Products.deals; что выдать, решает сервер (OfferService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Offers = require(Shared.Config.Offers)
local Products = require(Shared.Config.Products)
local Posters = require(Shared.Config.Posters)
local Skins = require(Shared.Config.Skins)
local ClientState = require(script.Parent.ClientState)
local OfferClient = require(script.Parent.OfferClient)
local Ui = require(script.Parent.Ui)

local ROW_HEIGHT = 72
local BANNER_COLOR = Color3.fromRGB(92, 52, 30)
local STARTER_COLOR = Color3.fromRGB(40, 70, 52)

local OfferShop = {}

-- Название, иконка и обычная цена товара дня
local function describe(item: Offers.DealItem): (string, string, number)
	if item.kind == "poster" then
		local poster = Posters.get(item.itemId)
		if poster then
			return ClientState.localText("poster_" .. poster.id, poster.name, poster.nameEn),
				"🖼",
				poster.robuxPrice or 0
		end
	elseif item.kind == "skin" then
		local skin = Skins.get(item.itemId)
		if skin then
			return ClientState.localText("skin_" .. skin.id, skin.name, skin.nameEn),
				skin.emoji,
				skin.robuxPrice or 0
		end
	else
		for _, product in Products.list do
			if product.id == item.itemId then
				return OfferClient.productName(product), product.icon, product.robuxPrice
			end
		end
	end
	return item.id, "🎁", 0
end

local function frame(parent: Instance, order: number, color: Color3): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	f.LayoutOrder = order
	Ui.corner(f, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.money
	stroke.Parent = f
	f.Parent = parent
	return f
end

local function texts(f: Frame, icon: string, title: string): TextLabel
	local iconLabel = Ui.label(f, icon, ROW_HEIGHT, Ui.titleFont)
	iconLabel.Size = UDim2.new(0, 56, 1, 0)
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	local titleLabel = Ui.label(f, title, 26, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	titleLabel.Position = UDim2.fromOffset(60, 8)
	titleLabel.Size = UDim2.new(0.62, -64, 0, 26)
	titleLabel.RichText = true
	local sub = Ui.label(f, "", 22, Enum.Font.GothamMedium, Ui.colors.muted)
	sub.Position = UDim2.fromOffset(60, 38)
	sub.Size = UDim2.new(0.62, -64, 0, 22)
	return sub
end

-- Обновлять подпись каждую секунду, пока строка на экране
local function tick(label: TextLabel, text: () -> string)
	task.spawn(function()
		while label.Parent do
			label.Text = text()
			task.wait(1)
		end
	end)
end

local function buildDeal(body: Instance)
	local item = Offers.dealFor(Offers.dayOf(OfferClient.now()))
	local deal = Products.deals[item.id]
	if not deal or not OfferClient.hasId(deal.productId) then
		return
	end
	local name, icon, oldPrice = describe(item)
	local percent = Offers.dailyDeal.discountPercent
	local f = frame(body, -1, BANNER_COLOR)
	local sub = texts(f, icon, ClientState.t("offer_deal_title", { percent = percent }) .. " · " .. name)
	tick(sub, function()
		return ClientState.t(
			"offer_deal_timer",
			{ time = Offers.clock(Offers.secondsToMidnight(OfferClient.now())) }
		)
	end)
	OfferClient.trackOnce("deal_" .. item.id, "dailyDeal", "shown")

	local owned = OfferClient.state.dealOwned
	local text = if owned
		then ClientState.t("offer_deal_owned")
		elseif deal.productId == 0 then ClientState.t("shop_soon")
		else (if oldPrice > 0 then `<s>{oldPrice}</s> ` else "") .. ClientState.t(
			"shop_robux",
			{ price = deal.robuxPrice }
		)
	local b = Ui.button(f, text, if owned then Ui.colors.locked else Ui.colors.good, function()
		if not owned then
			OfferClient.buyProduct("dailyDeal", deal.productId)
		end
	end)
	b.RichText = true
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -8, 0.5, 0)
	b.Size = UDim2.new(0.3, 0, 0, 44)
end

local function buildStarter(body: Instance)
	if not OfferClient.starterActive() then
		return
	end
	local f = frame(body, -2, STARTER_COLOR)
	local sub = texts(f, "🎁", ClientState.t("offer_starter_title"))
	tick(sub, function()
		local left = OfferClient.state.starterEndsAt - OfferClient.now()
		return ClientState.t("offer_starter_shop", { time = Offers.clock(left) })
	end)
	local b = Ui.button(f, ClientState.t("offer_starter_open"), Ui.colors.good, function()
		OfferClient.showStarter()
	end)
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -8, 0.5, 0)
	b.Size = UDim2.new(0.26, 0, 0, 44)
end

-- Добавить строки в начало списка вкладки (LayoutOrder < 1)
function OfferShop.build(body: Instance)
	if Offers.enabled.starterPack then
		buildStarter(body)
	end
	if Offers.enabled.dailyDeal then
		buildDeal(body)
	end
end

-- Свежие данные (цена набора, куплен ли товар дня) — при открытии магазина
function OfferShop.request()
	OfferClient.request()
end

-- Перерисовать магазин, когда пришло новое состояние
function OfferShop.listen(callback: () -> ())
	OfferClient.changed:Connect(callback)
end

return OfferShop
