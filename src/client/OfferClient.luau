--!strict
-- Предложения доната на клиенте (Config/Offers): состояние с сервера, «можно ли сейчас показать
-- окно», окно предложения, покупка и аналитика. Не контроллер: общий модуль для OfferController,
-- окна релиза, HUD, подсказки о забастовке и магазина (OfferShop).
-- Окно предложения не спамит: общий кулдаун, лимит за сессию, не в туториале, не в первые минуты
-- новичка (кроме стартового набора), не поверх других окон. Выдаёт купленное только сервер.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Images = require(Shared.Config.Images)
local Offers = require(Shared.Config.Offers)
local Products = require(Shared.Config.Products)
local GamePasses = require(Shared.Config.GamePasses)
local HitCartridges = require(Shared.Config.HitCartridges)
local Texts = require(Shared.Config.Texts)
local OfferRemotes = require(Shared.OfferRemotes)
local ShopRemotes = require(Shared.ShopRemotes)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

export type State = {
	firstJoin: number,
	starterBought: boolean,
	starterShown: boolean,
	starterEndsAt: number,
	starterCash: number,
	incomePerMinute: number,
	dealOwned: boolean,
}

export type Pack = { product: Products.Product, amount: number }

-- Продукты, покупку которых сервер логирует сам (из квитанции)
local SERVER_LOGGED: { [string]: boolean } = { doubleRelease = true, starterPack = true, dailyDeal = true }

local player = Players.LocalPlayer
local OfferClient = {}

OfferClient.state = {
	firstJoin = os.time(),
	starterBought = true, -- до ответа сервера стартовый набор не показываем
	starterShown = true,
	starterEndsAt = 0,
	starterCash = 0,
	incomePerMinute = 0,
	dealOwned = false,
} :: State
OfferClient.loaded = false
OfferClient.passes = {} :: { [string]: boolean }

local changed = Instance.new("BindableEvent")
OfferClient.changed = changed.Event

local sessionStart = os.clock()
local lastPopup = -math.huge
local popupCount = 0
local lastByKind: { [string]: number } = {}
local tracked: { [string]: boolean } = {}
-- Окно покупки Roblox открыто нами: productId/gamePassId -> вид предложения
local pendingProduct: { [number]: string } = {}
local pendingPass: { [number]: string } = {}
local purchasedCallbacks: { [number]: () -> () } = {}
local releaseCount = 0
local lastDoubleShown = -math.huge
local gui: ScreenGui? = nil

local function num(value: any, default: number): number
	return if type(value) == "number" and value == value then value else default
end

-- Серверное время (unix): часы клиента могут врать
function OfferClient.now(): number
	return workspace:GetServerTimeNow()
end

-- Есть что продать: id создан в Dashboard (или проверка интерфейса в Studio)
function OfferClient.hasId(id: number): boolean
	return id ~= 0 or Offers.showWithoutId
end

-- Текст кнопки цены: «R$ 25» или «Скоро»
function OfferClient.priceText(id: number, price: number): string
	return if id ~= 0 then ClientState.t("shop_robux", { price = price }) else ClientState.t("shop_soon")
end

-- ===== Аналитика =====

function OfferClient.track(kind: string, stage: string)
	OfferRemotes.OfferEvent:FireServer(kind, stage)
end

-- Один раз за сессию по ключу (показ баннера в магазине, кнопки у одного проекта)
function OfferClient.trackOnce(key: string, kind: string, stage: string)
	if not tracked[key] then
		tracked[key] = true
		OfferClient.track(kind, stage)
	end
end

-- ===== Покупка =====

-- onPurchased — после успешной покупки (например, сразу потратить заряд)
function OfferClient.buyProduct(kind: string, productId: number, onPurchased: (() -> ())?)
	OfferClient.track(kind, "clicked")
	if productId == 0 then
		return
	end
	pendingProduct[productId] = kind
	if onPurchased then
		purchasedCallbacks[productId] = onPurchased
	else
		purchasedCallbacks[productId] = nil
	end
	MarketplaceService:PromptProductPurchase(player, productId)
end

function OfferClient.buyPass(kind: string, gamePassId: number)
	OfferClient.track(kind, "clicked")
	if gamePassId == 0 then
		return
	end
	pendingPass[gamePassId] = kind
	MarketplaceService:PromptGamePassPurchase(player, gamePassId)
end

-- ===== Когда можно показать окно =====

-- Сколько секунд игрок «новичок» ещё будет (0 — уже нет)
local function newPlayerLeft(): number
	return OfferClient.state.firstJoin + Offers.popup.newPlayerSeconds - OfferClient.now()
end

function OfferClient.sessionSeconds(): number
	return os.clock() - sessionStart
end

-- Можно ли сейчас показать всплывающее предложение этого вида
function OfferClient.canPopup(kind: string): boolean
	local cfg = Offers.popup
	if not Offers.enabled[kind] or not OfferClient.loaded or gui ~= nil then
		return false
	end
	if Ui.anyWindowOpen() or player:GetAttribute("TutorialActive") == true then
		return false
	end
	local now = os.clock()
	if popupCount >= cfg.maxPerSession or now - lastPopup < cfg.cooldownSeconds then
		return false
	end
	if now - (lastByKind[kind] or -math.huge) < cfg.sameKindSeconds then
		return false
	end
	if OfferClient.sessionSeconds() < cfg.sessionWarmupSeconds then
		return false
	end
	-- Стартовый набор — исключение для новичка (у него свой порог по времени сессии)
	return kind == "starterPack" or newPlayerLeft() <= 0
end

-- Окно предложения сейчас открыто (карточка события компании его не перекрывает)
function OfferClient.popupOpen(): boolean
	return gui ~= nil
end

-- Сколько секунд прошло с последнего всплывающего предложения
function OfferClient.secondsSincePopup(): number
	return os.clock() - lastPopup
end

-- Не показывать предложения ещё seconds секунд (после карточки события компании — не друг за другом)
function OfferClient.holdPopups(seconds: number)
	lastPopup = math.max(lastPopup, os.clock() + seconds - Offers.popup.cooldownSeconds)
end

-- ===== Пакеты дохода =====

local function productById(id: string): Products.Product?
	for _, product in Products.list do
		if product.id == id then
			return product
		end
	end
	return nil
end

-- Самый дешёвый пакет из списка, который покрывает gap (или самый большой). nil — продать нечего
function OfferClient.packFor(gap: number, ids: { string }): Pack?
	local perMinute = OfferClient.state.incomePerMinute
	local best: Pack? = nil
	for _, id in ids do
		local product = productById(id)
		if product and product.incomeMinutes and OfferClient.hasId(product.productId) then
			local pack = { product = product, amount = perMinute * product.incomeMinutes }
			best = pack
			if pack.amount >= gap then
				return pack
			end
		end
	end
	return best
end

function OfferClient.productName(product: Products.Product): string
	return ClientState.localText("product_" .. product.id, product.name, product.nameEn)
end

-- Пакет, который покрывает невыплаченную зарплату (nil — не забастовка или продать нечего)
function OfferClient.strikePack(): (Pack?, number)
	if not Offers.enabled.strike or player:GetAttribute("StaffStrike") ~= true then
		return nil, 0
	end
	local due = tonumber(player:GetAttribute("PaydayAmount")) or 0
	local cash = ClientState.data and tonumber(ClientState.data.cash) or 0
	local gap = math.ceil(due * Offers.strike.margin - cash)
	if gap <= 0 then
		return nil, 0
	end
	return OfferClient.packFor(gap, Offers.strike.packs), gap
end

-- ===== Окно предложения =====

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

export type PopupSpec = {
	kind: string,
	title: string,
	lines: { string },
	buyText: string,
	onBuy: () -> (),
	-- Строка с обратным отсчётом: текст по секундам до конца (nil — без отсчёта)
	countdown: ((secondsLeft: number) -> string)?,
	endsAt: number?,
	-- Вторая кнопка: свой текст и действие (контракт: «Отказаться»); nil — «Не сейчас»
	laterText: string?,
	onLater: (() -> ())?,
	-- Баннер 2:1 над заголовком (id из Config/Images); nil/0 — без баннера
	banner: number?,
}

local BANNER_HEIGHT = 150

-- Показать окно (проверку canPopup делает вызывающий). Считается в кулдаун и лимит сессии
function OfferClient.popup(spec: PopupSpec)
	close()
	popupCount += 1
	lastPopup = os.clock()
	lastByKind[spec.kind] = lastPopup
	OfferClient.track(spec.kind, "shown")

	local screen = Instance.new("ScreenGui")
	screen.Name = "OfferPopup"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 22
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local bannerId = spec.banner or 0
	local height = 190
		+ #spec.lines * 34
		+ (if spec.countdown then 34 else 0)
		+ (if bannerId > 0 then BANNER_HEIGHT + 8 else 0)
	local window = Ui.window(screen, "Window", Vector2.new(520, height))
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	local layout = Ui.list(body, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	body.Parent = window

	if bannerId > 0 then
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(1, 0, 0, BANNER_HEIGHT)
		holder.LayoutOrder = 0
		holder.Parent = body
		local art = Ui.artImage(holder, bannerId)
		if art then
			art.SizeConstraint = Enum.SizeConstraint.RelativeXY
			art.Size = UDim2.fromOffset(BANNER_HEIGHT * 2, BANNER_HEIGHT)
			Ui.corner(art, 12)
		end
	end
	local title = Ui.label(body, spec.title, 40, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 1
	for i, line in spec.lines do
		local l = Ui.label(body, line, 26, Enum.Font.GothamMedium)
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.LayoutOrder = 1 + i
	end
	local countdown = spec.countdown
	local endsAt = spec.endsAt
	if countdown and endsAt then
		local timer = Ui.label(body, "", 24, nil, Ui.colors.bad)
		timer.TextXAlignment = Enum.TextXAlignment.Center
		timer.LayoutOrder = 50
		task.spawn(function()
			while timer.Parent do
				local left = endsAt - OfferClient.now()
				if left <= 0 then
					close()
					return
				end
				timer.Text = countdown(left)
				task.wait(1)
			end
		end)
	end

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 52)
	buttons.LayoutOrder = 60
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.Padding = UDim.new(0, 10)
	row.Parent = buttons
	buttons.Parent = body
	local buy = Ui.button(buttons, spec.buyText, Ui.colors.good, function()
		close()
		spec.onBuy()
	end)
	buy.Size = UDim2.new(0.6, 0, 1, 0)
	Ui.button(buttons, spec.laterText or ClientState.t("offer_later"), Ui.colors.locked, function()
		close()
		if spec.onLater then
			spec.onLater()
		end
	end).Size =
		UDim2.new(0.36, 0, 1, 0)
end

-- ===== Стартовый набор =====

-- Идёт ли ещё (не куплен и таймер не вышел)
function OfferClient.starterActive(): boolean
	local s = OfferClient.state
	return Offers.enabled.starterPack
		and OfferClient.loaded
		and not s.starterBought
		and OfferClient.now() < s.starterEndsAt
		and OfferClient.hasId(Products.offers.starterPack.productId)
end

-- Окно стартового набора (авто-показ — из OfferController, повторно — из магазина)
function OfferClient.showStarter()
	local cfg = Offers.starterPack
	local product = Products.offers.starterPack
	local function skinName(id: string): string
		return ClientState.localText("skin_" .. id, id, id)
	end
	local skins = cfg.skins
	OfferClient.popup({
		kind = "starterPack",
		title = ClientState.t("offer_starter_title"),
		lines = {
			ClientState.t("offer_starter_cash", { money = Texts.money(OfferClient.state.starterCash) }),
			ClientState.t(
				"offer_starter_skins",
				{ a = skinName(skins[1] or ""), b = skinName(skins[2] or "") }
			),
			ClientState.t("offer_starter_coffee", {
				count = cfg.coffeeCount,
				minutes = math.floor(Products.effects.coffeeSeconds * cfg.coffeeCount / 60),
			}),
			ClientState.t("offer_starter_badge"),
			ClientState.t("offer_starter_once"),
		},
		buyText = OfferClient.priceText(product.productId, product.robuxPrice),
		onBuy = function()
			OfferClient.buyProduct("starterPack", product.productId)
		end,
		countdown = function(left: number): string
			return ClientState.t("offer_starter_timer", { time = Offers.clock(left) })
		end,
		endsAt = OfferClient.state.starterEndsAt,
		banner = Images.monetization.starterBanner,
	})
end

-- ===== Окно релиза =====

-- Строка предложения под итогом релиза: «×2 к доходу этой игры» или напоминание о геймпассе ×2.
-- nil — сейчас ничего не предлагаем. Вызывать один раз на релиз (считает релизы)
function OfferClient.releaseOffer(info: any): ((parent: Instance, order: number) -> ())?
	releaseCount += 1
	local score = num(info.score, 0)
	local revenue = num(info.revenue, 0)
	if revenue <= 0 then
		return nil
	end
	local now = os.clock()

	local double = Offers.doubleRelease
	local doubleProduct = Products.offers.doubleRelease
	local good = score >= double.minScore or score >= HitCartridges.minScore
	if
		Offers.enabled.doubleRelease
		and good
		and OfferClient.hasId(doubleProduct.productId)
		and now - lastDoubleShown >= double.showCooldownSeconds
	then
		lastDoubleShown = now
		return function(parent: Instance, order: number)
			OfferClient.track("doubleRelease", "shown")
			local b: TextButton
			b = Ui.button(
				parent,
				ClientState.t("offer_double_release", { price = doubleProduct.robuxPrice }),
				Ui.colors.good,
				function()
					-- Купил — кнопку прячем (повторная покупка дала бы уже только пакет-замену)
					OfferClient.buyProduct("doubleRelease", doubleProduct.productId, function()
						b.Visible = false
					end)
				end
			)
			b.Size = UDim2.new(0.8, 0, 0, 48)
			b.LayoutOrder = order
			-- После окна в минуту кнопка исчезает (сервер всё равно выдал бы замену)
			task.delay(double.windowSeconds - 5, function()
				if b.Parent then
					b.Visible = false
				end
			end)
		end
	end

	local reminder = Offers.x2Reminder
	local pass: GamePasses.GamePass? = nil
	for _, candidate in GamePasses.list do
		if candidate.id == "doubleCash" then
			pass = candidate
		end
	end
	if
		Offers.enabled.x2Reminder
		and pass
		and not OfferClient.passes.doubleCash
		and OfferClient.hasId(pass.gamePassId)
		and revenue >= reminder.minRevenue
		and releaseCount % reminder.everyNthRelease == 0
	then
		local doubleCash = pass :: GamePasses.GamePass
		local extra = revenue * (GamePasses.effects.doubleCashMultiplier - 1)
		return function(parent: Instance, order: number)
			OfferClient.track("x2Reminder", "shown")
			local frame = Instance.new("Frame")
			frame.BackgroundTransparency = 1
			frame.Size = UDim2.new(1, 0, 0, 48)
			frame.LayoutOrder = order
			local line = Ui.label(
				frame,
				ClientState.t("offer_x2_line", { money = Texts.money(extra) }),
				48,
				nil,
				Ui.colors.money
			)
			line.Size = UDim2.new(0.6, -8, 1, 0)
			local b = Ui.button(
				frame,
				ClientState.t("offer_x2_buy", { price = doubleCash.robuxPrice }),
				Ui.colors.good,
				function()
					OfferClient.buyPass("x2Reminder", doubleCash.gamePassId)
				end
			)
			b.AnchorPoint = Vector2.new(1, 0)
			b.Position = UDim2.new(1, 0, 0, 0)
			b.Size = UDim2.new(0.4, 0, 1, 0)
			frame.Parent = parent
		end
	end
	return nil
end

-- ===== Долгая разработка =====

-- Показать «⚡ Закончить сейчас» (купить заряд), если до релиза больше minRemainingSeconds
function OfferClient.longDevOffer(remaining: number?): boolean
	local product = productById("instantFinish")
	return Offers.enabled.longDev
		and OfferClient.loaded
		and product ~= nil
		and OfferClient.hasId(product.productId)
		and type(remaining) == "number"
		and remaining > Offers.longDev.minRemainingSeconds
		and player:GetAttribute("TutorialActive") ~= true
end

function OfferClient.longDevText(): string
	local product = productById("instantFinish")
	return ClientState.t("offer_finish_now", { price = if product then product.robuxPrice else 0 })
end

-- Купить заряд и сразу потратить его на этот проект
function OfferClient.buyInstantFinish(onPurchased: () -> ())
	local product = productById("instantFinish")
	if product then
		OfferClient.buyProduct("longDev", product.productId, onPurchased)
	end
end

-- ===== Состояние =====

function OfferClient.request()
	OfferRemotes.OfferStateRequest:FireServer()
end

OfferRemotes.OfferState.OnClientEvent:Connect(function(raw: any)
	if type(raw) ~= "table" then
		return
	end
	OfferClient.state = {
		firstJoin = num(raw.firstJoin, os.time()),
		starterBought = raw.starterBought == true,
		starterShown = raw.starterShown == true,
		starterEndsAt = num(raw.starterEndsAt, 0),
		starterCash = num(raw.starterCash, 0),
		incomePerMinute = num(raw.incomePerMinute, 0),
		dealOwned = raw.dealOwned == true,
	}
	OfferClient.loaded = true
	changed:Fire()
end)

ShopRemotes.ShopState.OnClientEvent:Connect(function(raw: any)
	if type(raw) == "table" and type(raw.passes) == "table" then
		OfferClient.passes = raw.passes
		changed:Fire()
	end
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(
	function(userId: number, productId: number, purchased: boolean)
		if userId ~= player.UserId then
			return
		end
		local kind = pendingProduct[productId]
		local callback = purchasedCallbacks[productId]
		pendingProduct[productId] = nil
		purchasedCallbacks[productId] = nil
		if purchased and kind then
			if not SERVER_LOGGED[kind] then
				OfferClient.track(kind, "purchased")
			end
			if callback then
				callback()
			end
		end
	end
)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(
	function(who: Player, gamePassId: number, purchased: boolean)
		if who ~= player then
			return
		end
		local kind = pendingPass[gamePassId]
		pendingPass[gamePassId] = nil
		if purchased and kind then
			OfferClient.track(kind, "purchased")
		end
	end
)

ClientState.langChanged:Connect(close)

return OfferClient
