--!strict
-- Окно «Магазин» (5.4, 5.5): вкладки «Реклама / Геймпассы / Бусты / Постеры / Скины / Маскоты»
-- (постеры — PosterShop, скины сотрудников — SkinShop, маскоты — MascotShop).
-- В шапке — кнопка «🎟 Коды» (CodeWindow) и, если нет Roblox Premium, «⭐ Premium +10%» (покупка Premium).
-- Клиент только показывает цены и открывает окно покупки Roblox; что куплено и что выдать,
-- решает сервер (ShopService, MonetizationService). ID 0 = товар ещё не создан: кнопка «Скоро».

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local ShopRemotes = require(Shared.ShopRemotes)
local AdCampaigns = require(Shared.Config.AdCampaigns)
local GamePasses = require(Shared.Config.GamePasses)
local Images = require(Shared.Config.Images)
local Products = require(Shared.Config.Products)
local Premium = require(Shared.Config.Premium)
local DailyEvents = require(Shared.Config.DailyEvents)
local Texts = require(Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local PosterShop = require(script.Parent.Parent.PosterShop)
local SkinShop = require(script.Parent.Parent.SkinShop)
local OfferShop = require(script.Parent.Parent.OfferShop)
local MascotShop = require(script.Parent.Parent.MascotShop)
local CodeWindow = require(script.Parent.Parent.CodeWindow)
local ArtIcon = require(script.Parent.Parent.ArtIcon)
local DepthToast = require(script.Parent.Parent.DepthToast)

type Tab = "ads" | "passes" | "boosts" | "posters" | "skins" | "mascots"
type ShopState = {
	passes: { [string]: boolean },
	boosts: { instantFinish: number, patch: number, coffeeUntil: number }?,
	incomePerMinute: number?,
}

local MENU_SLOT = 4
local ROW_HEIGHT = 72
local TABS: { Tab } = { "ads", "passes", "boosts", "posters", "skins", "mascots" }

local ShopWindow = {}
local gui: ScreenGui? = nil
local tab: Tab = "ads"
local state: ShopState = { passes = {} }
local scrollY = 0
local render: () -> ()

local function robuxButton(
	parent: Instance,
	id: number,
	price: number,
	owned: boolean,
	prompt: () -> ()
): TextButton
	local text, color
	if owned then
		text, color = ClientState.t("shop_owned"), Ui.colors.good
	elseif id == 0 then
		text, color = ClientState.t("shop_soon"), Ui.colors.locked
	else
		text, color = ClientState.t("shop_robux", { price = price }), Ui.colors.good
	end
	local b = Ui.button(parent, text, color, function()
		if not owned and id ~= 0 then
			prompt()
		end
	end)
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -8, 0.5, 0)
	b.Size = UDim2.new(0.26, 0, 0, 44)
	return b
end

local function promptProduct(productId: number)
	MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
end

-- Строка: иконка, название, описание, справа кнопки. Возвращает рамку под кнопки.
-- imageId — картинка из Config/Images вместо эмодзи иконки (0/nil — эмодзи)
local function row(
	parent: Instance,
	order: number,
	icon: string,
	title: string,
	description: string,
	imageId: number?
): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
	frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	frame.LayoutOrder = order
	Ui.corner(frame, 10)

	local iconLabel = Ui.label(frame, icon, ROW_HEIGHT, Ui.titleFont)
	iconLabel.Size = UDim2.new(0, 56, 1, 0)
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	local art = Ui.artImage(iconLabel, imageId)
	if art then
		iconLabel.Text = ""
		art.Size = UDim2.fromScale(0.75, 0.75)
	end

	local titleLabel = Ui.label(frame, title, 26, Ui.titleFont)
	titleLabel.Position = UDim2.fromOffset(60, 8)
	titleLabel.Size = UDim2.new(0.62, -64, 0, 26)

	local descLabel = Ui.label(frame, description, 22, Enum.Font.GothamMedium, Ui.colors.muted)
	descLabel.Position = UDim2.fromOffset(60, 38)
	descLabel.Size = UDim2.new(0.62, -64, 0, 22)

	frame.Parent = parent
	return frame
end

local function buildAds(body: Instance)
	local data = ClientState.data
	for i, campaign in AdCampaigns do
		local frame = row(
			body,
			i,
			"📢",
			ClientState.t("ad_name_" .. campaign.id),
			ClientState.t("shop_ad_line", {
				percent = math.floor(campaign.bonus * 100),
				minutes = math.floor(campaign.durationSeconds / 60),
			})
		)
		local robux = robuxButton(frame, campaign.productId, campaign.robuxPrice, false, function()
			promptProduct(campaign.productId)
		end)
		-- Две нижние кампании можно взять и за игровую валюту
		local cost = campaign.cashCost
		if cost then
			robux.Size = UDim2.new(0.18, 0, 0, 44)
			local canPay = data ~= nil and data.cash >= cost
			local cash = Ui.button(
				frame,
				Texts.money(cost),
				if canPay then Ui.colors.money else Ui.colors.locked,
				function()
					if canPay then
						Remotes.BuyAdCampaignWithCash:FireServer(campaign.id)
					end
				end
			)
			cash.TextColor3 = if canPay then Color3.fromRGB(40, 30, 0) else Ui.colors.muted
			cash.AnchorPoint = Vector2.new(1, 0.5)
			cash.Position = UDim2.new(0.82, -16, 0.5, 0)
			cash.Size = UDim2.new(0.18, 0, 0, 44)
		end
	end
	local note = Ui.label(body, ClientState.t("shop_ad_note"), 20, Enum.Font.GothamMedium, Ui.colors.muted)
	note.LayoutOrder = #AdCampaigns + 1
end

local function localized(item: {
	id: string,
	name: string,
	nameEn: string,
	description: string,
	descriptionEn: string,
}): (string, string)
	-- Ключи переводов: pass_<id> для геймпассов, product_<id> для продуктов
	local prefix = "product_"
	for _, pass in GamePasses.list do
		if pass.id == item.id then
			prefix = "pass_"
			break
		end
	end
	local key = prefix .. item.id
	return ClientState.localText(key, item.name, item.nameEn),
		ClientState.localText(key .. "_desc", item.description, item.descriptionEn)
end

local function buildPasses(body: Instance)
	for i, pass in GamePasses.list do
		local name, description = localized(pass)
		-- VIP-офис — корона V14 (Images.vip)
		local frame =
			row(body, i, pass.icon, name, description, if pass.id == "vipOffice" then Images.vip else nil)
		robuxButton(frame, pass.gamePassId, pass.robuxPrice, state.passes[pass.id] == true, function()
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.gamePassId)
		end)
	end
end

local function buildBoosts(body: Instance)
	local boosts = state.boosts
	for i, product in Products.list do
		local name, description = localized(product)
		-- Под описанием — что уже есть у игрока
		if boosts and product.kind == "instantFinish" and boosts.instantFinish > 0 then
			description ..= " · " .. ClientState.t("shop_charges", { count = boosts.instantFinish })
		elseif boosts and product.kind == "patch" and boosts.patch > 0 then
			description ..= " · " .. ClientState.t("shop_charges", { count = boosts.patch })
		elseif boosts and product.kind == "coffee" and boosts.coffeeUntil > os.time() then
			local minutes = math.ceil((boosts.coffeeUntil - os.time()) / 60)
			description = ClientState.t("shop_coffee_left", { minutes = minutes })
		elseif product.kind == "incomePack" and state.incomePerMinute and product.incomeMinutes then
			local amount = Texts.money(state.incomePerMinute * product.incomeMinutes)
			description = ClientState.t("shop_income_amount", { money = amount })
		end
		-- «Кофе-раш» (события дня): кофе продаётся скидочной копией «Сделки дня» (выдаёт OfferService)
		local productId, robuxPrice = product.productId, product.robuxPrice
		local rushDeal = Products.deals[DailyEvents.coffeeRush.dealKey]
		if
			product.kind == "coffee"
			and rushDeal
			and rushDeal.productId > 0
			and DailyEvents.isActive("coffeeRush")
		then
			productId, robuxPrice = rushDeal.productId, rushDeal.robuxPrice
			description = ClientState.t("devent_coffee_sale") .. " · " .. description
		end
		local frame = row(body, i, product.icon, name, description)
		robuxButton(frame, productId, robuxPrice, false, function()
			promptProduct(productId)
		end)
	end
end

render = function()
	if not gui then
		return
	end
	local old = gui:FindFirstChild("Window")
	if old then
		local oldBody = old:FindFirstChild("Body")
		if oldBody and oldBody:IsA("ScrollingFrame") then
			scrollY = oldBody.CanvasPosition.Y
		end
		old:Destroy()
	end

	local window = Ui.window(gui, "Window", Vector2.new(680, 600))

	local title = Ui.label(window, ClientState.t("shop_title"), 36, Ui.titleFont)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -230, 0, 36)
	local close = Ui.button(window, ClientState.t("create_close"), Ui.colors.locked, function()
		ShopWindow.close()
	end)
	close.Size = UDim2.fromOffset(40, 40)
	close.Position = UDim2.new(1, -52, 0, 8)
	-- Промокоды: отдельное маленькое окно поверх магазина
	local codes = Ui.button(window, ClientState.t("codes_button"), Ui.colors.primary, function()
		CodeWindow.open()
	end)
	codes.Size = UDim2.fromOffset(150, 40)
	codes.Position = UDim2.new(1, -212, 0, 8)
	ArtIcon.prefix(codes, "🎟", Images.social.iconCodes, 28)
	-- Roblox Premium: +10% к доходу (PremiumService). Подсказка только тем, у кого его нет
	if Players.LocalPlayer.MembershipType ~= Enum.MembershipType.Premium then
		local premium = Ui.button(
			window,
			ClientState.t("prem_shop_hint", { percent = math.floor(Premium.incomeBonus * 100 + 0.5) }),
			Ui.colors.money,
			function()
				pcall(function()
					MarketplaceService:PromptPremiumPurchase(Players.LocalPlayer)
				end)
			end
		)
		premium.Size = UDim2.fromOffset(170, 40)
		premium.Position = UDim2.new(1, -392, 0, 8)
		title.Size = UDim2.new(1, -410, 0, 36)
	end

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(16, 56)
	tabs.Size = UDim2.new(1, -32, 0, 44)
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 8)
	tabsLayout.Parent = tabs
	tabs.Parent = window
	for _, id in TABS do
		local b = Ui.button(
			tabs,
			ClientState.t("shop_tab_" .. id),
			if id == tab then Ui.colors.primary else Ui.colors.locked,
			function()
				if tab ~= id then
					tab = id
					scrollY = 0
					render()
				end
			end
		)
		b.Size = UDim2.new(1 / #TABS, -6, 1, 0)
	end

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(16, 112)
	body.Size = UDim2.new(1, -32, 1, -124)
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 6
	Ui.list(body, 8)
	body.Parent = window

	if tab == "ads" then
		buildAds(body)
	elseif tab == "passes" then
		buildPasses(body)
	elseif tab == "posters" then
		PosterShop.build(body)
	elseif tab == "skins" then
		SkinShop.build(body)
	elseif tab == "mascots" then
		MascotShop.build(body)
	else
		buildBoosts(body)
	end
	-- Сверху любой вкладки: сделка дня и стартовый набор
	OfferShop.build(body)
	-- Холст растягивается на следующем кадре: восстанавливаем прокрутку после него
	local savedY = scrollY
	task.defer(function()
		if body.Parent then
			body.CanvasPosition = Vector2.new(0, savedY)
		end
	end)
end

function ShopWindow.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "ShopWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	scrollY = 0
	Ui.windowOpened(ShopWindow.close) -- окно меню: закрывает другое открытое окно меню
	render()
	-- Свежие заряды и доход в минуту (рекорд мог вырасти)
	ShopRemotes.ShopStateRequest:FireServer()
	PosterShop.request()
	SkinShop.request()
	MascotShop.request()
	OfferShop.request()
end

function ShopWindow.close()
	CodeWindow.close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

function ShopWindow.start()
	Ui.menuButton(MENU_SLOT, "🛒", function()
		if gui then
			ShopWindow.close()
		else
			ShopWindow.open()
		end
	end, "menu_shop")
	-- Купил Premium в окне Roblox — спасибо, а подсказка больше не нужна
	Players.PlayerMembershipChanged:Connect(function(who: Player)
		if who ~= Players.LocalPlayer then
			return
		end
		if who.MembershipType == Enum.MembershipType.Premium then
			DepthToast.show(
				ClientState.t("prem_thanks", { percent = math.floor(Premium.incomeBonus * 100 + 0.5) }),
				Ui.colors.money
			)
		end
		render()
	end)

	ShopRemotes.ShopState.OnClientEvent:Connect(function(newState: any)
		if type(newState) ~= "table" or type(newState.passes) ~= "table" then
			return
		end
		state = newState
		render()
	end)
	PosterShop.listen(function()
		render()
	end)
	SkinShop.listen(function()
		render()
	end)
	MascotShop.listen(function()
		render()
	end)
	OfferShop.listen(function()
		render()
	end)
	-- Деньги поменялись — перекрасить кнопки «за $»
	ClientState.changed:Connect(function()
		render()
	end)
	-- «Кофе-раш» начался или кончился — другая цена кофе
	ReplicatedStorage:GetAttributeChangedSignal("DailyEventActive"):Connect(function()
		render()
	end)
end

return ShopWindow
