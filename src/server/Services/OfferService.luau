--!strict
-- Предложения доната (Config/Offers): серверная часть. Когда и что показать, решает клиент
-- (это только интерфейс), а выдачу за Robux — здесь: MonetizationService.ProcessReceipt зовёт
-- grantProduct (эффект в профиле, сохраняет MonetizationService до PurchaseGranted).
--   • doubleRelease — +доход последнего релиза, если куплено в течение windowSeconds и релиз ещё
--     не удвоен; иначе пакет fallbackProduct (оплаченное не пропадает).
--   • starterPack — $ за incomeMinutes дохода (не меньше minCash), скины, кофе, значок «Стартер».
--   • deals — скидочные копии товаров «Сделки дня»: выдают тот же товар; уже открытый
--     постер/скин заменяется пакетом fallbackProduct.
-- Аналитика: показ/клик/покупку присылает клиент (OfferEvent), покупки своих продуктов пишем тут.
-- Данные: profile.offers = { firstJoin, starterBought, starterShown, starterBadge }; клиенту — атрибут StarterBadge.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Offers = require(Shared.Config.Offers)
local Products = require(Shared.Config.Products)
local HitCartridges = require(Shared.Config.HitCartridges)
local OfferRemotes = require(Shared.OfferRemotes)
local DataService = require(script.Parent.DataService)
local ShopService = require(script.Parent.ShopService)
local SkinService = require(script.Parent.SkinService)
local PosterService = require(script.Parent.PosterService)

type OfferData = { firstJoin: number, starterBought: boolean, starterShown: boolean, starterBadge: boolean }
type Release = { id: number, revenue: number, at: number, doubled: boolean }

local STATE_REQUEST_COOLDOWN = 1
-- Аналитика от клиента: не чаще и не больше за сессию (событие можно заспамить)
local EVENT_COOLDOWN = 0.2
local EVENTS_PER_SESSION = 120

local OfferService = {}
local lastRelease: { [Player]: Release } = {}
local lastRequest: { [Player]: number } = {}
local lastEvent: { [Player]: number } = {}
local eventCount: { [Player]: number } = {}

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

local function logOffer(player: Player, kind: string, stage: string)
	local analytics = optional("AnalyticsService")
	if analytics and type(analytics.logOffer) == "function" then
		pcall(analytics.logOffer, player, kind, stage)
	end
end

-- Поле профиля в порядке: старые сохранения без него и мусор
local function data(profile: DataService.Profile): OfferData
	local raw = (profile :: any).offers
	if type(raw) ~= "table" then
		raw = {}
	end
	local firstJoin = tonumber(raw.firstJoin)
	local fixed: OfferData = {
		firstJoin = if firstJoin and firstJoin == firstJoin and firstJoin > 0 then firstJoin else os.time(),
		starterBought = raw.starterBought == true,
		starterShown = raw.starterShown == true,
		starterBadge = raw.starterBadge == true,
	}
	profile.offers = fixed
	return fixed
end

local function productWithId(product: Products.OfferProduct?): number
	return if product then product.productId else 0
end

-- Стартовый набор: $ за incomeMinutes дохода, не меньше minCash
local function starterCash(player: Player, profile: DataService.Profile): number
	local cfg = Offers.starterPack
	return math.max(ShopService.incomePerMinute(player, profile) * cfg.incomeMinutes, cfg.minCash)
end

local function dealOwned(player: Player, profile: DataService.Profile): boolean
	local deal = Offers.dealFor(Offers.dayOf(os.time()))
	if deal.kind == "poster" then
		return PosterService.owns(player, deal.itemId)
	elseif deal.kind == "skin" then
		return SkinService.ownsSkin(profile, deal.itemId)
	end
	return false
end

function OfferService.pushState(player: Player)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	local offers = data(profile)
	local release = lastRelease[player]
	local window = Offers.doubleRelease.windowSeconds
	OfferRemotes.OfferState:FireClient(player, {
		firstJoin = offers.firstJoin,
		starterBought = offers.starterBought,
		starterShown = offers.starterShown,
		starterEndsAt = offers.firstJoin + Offers.starterPack.durationSeconds,
		starterCash = starterCash(player, profile),
		incomePerMinute = ShopService.incomePerMinute(player, profile),
		dealOwned = dealOwned(player, profile),
		serverTime = os.time(),
		doubleRelease = if release
				and not release.doubled
				and os.time() < release.at + window
			then { id = release.id, revenue = release.revenue, endsAt = release.at + window }
			else nil,
	})
end

-- Релиз (зовёт DevelopmentService): запомнить для «×2 к доходу этой игры»
function OfferService.onGameReleased(
	player: Player,
	info: { projectId: number, revenue: number, score: number }
)
	local cfg = Offers.doubleRelease
	local good = info.score >= cfg.minScore or info.score >= HitCartridges.minScore
	if good and info.revenue > 0 then
		lastRelease[player] = { id = info.projectId, revenue = info.revenue, at = os.time(), doubled = false }
	end
	-- Рекорд мог вырасти — пересчитать $ пакетов и стартового набора
	OfferService.pushState(player)
end

local function addCash(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	DataService.addCash(player, amount)
	-- Как пакеты дохода: не засчитываем в задания «заработай»
	local reward = optional("RewardService")
	if reward and type(reward.noteNonEarned) == "function" then
		pcall(reward.noteNonEarned, player, amount)
	end
end

-- Замена, когда выдать купленное как есть нельзя (поздно, повторно, уже открыто)
local function grantFallback(player: Player, profile: DataService.Profile)
	local product = ShopService.productById(Offers.doubleRelease.fallbackProduct)
	if product then
		ShopService.applyProduct(player, profile, product)
	else
		addCash(player, ShopService.incomePerMinute(player, profile) * 10)
	end
end

local function grantDoubleRelease(player: Player, profile: DataService.Profile)
	local release = lastRelease[player]
	if release and not release.doubled and os.time() <= release.at + Offers.doubleRelease.windowSeconds then
		release.doubled = true
		addCash(player, release.revenue)
	else
		grantFallback(player, profile)
	end
end

local function grantStarter(player: Player, profile: DataService.Profile)
	local cfg = Offers.starterPack
	local offers = data(profile)
	-- Купил дважды (два сервера, повтор окна) — всё равно выдаём: Robux уже списаны
	addCash(player, starterCash(player, profile))
	local gotSkin = false
	for _, skinId in cfg.skins do
		if SkinService.grantSkin(player, profile, skinId) then
			gotSkin = true
		end
	end
	-- Все скины уже были (купил за $) — вместо них пакет дохода
	if not gotSkin and #cfg.skins > 0 then
		grantFallback(player, profile)
	end
	local boosts = profile.boosts
	boosts.coffeeUntil = math.max(boosts.coffeeUntil, os.time())
		+ Products.effects.coffeeSeconds * cfg.coffeeCount
	offers.starterBought = true
	offers.starterBadge = true
	player:SetAttribute("StarterBadge", true)
end

local function grantDeal(player: Player, profile: DataService.Profile, dealId: string)
	-- Скидка только на сделку дня (или вчерашнюю — покупка на стыке суток), иначе товар со скидкой
	-- можно было купить в любой день через PromptProductPurchase
	local today = Offers.dayOf(os.time())
	if Offers.dealFor(today).id ~= dealId and Offers.dealFor(today - 1).id ~= dealId then
		grantFallback(player, profile)
		return
	end
	for _, item in Offers.dailyDeal.pool do
		if item.id ~= dealId then
			continue
		end
		if item.kind == "product" then
			local product = ShopService.productById(item.itemId)
			if product then
				ShopService.applyProduct(player, profile, product)
				return
			end
		elseif item.kind == "poster" then
			if PosterService.grantPoster(player, profile, item.itemId) then
				return
			end
		elseif item.kind == "skin" then
			if SkinService.grantSkin(player, profile, item.itemId) then
				return
			end
		end
	end
	-- Уже открыто или товар убрали из пула — не пропадать оплате
	grantFallback(player, profile)
end

-- Продукт предложения (зовёт MonetizationService.ProcessReceipt). false — это не наш продукт
function OfferService.grantProduct(player: Player, profile: DataService.Profile, productId: number): boolean
	if productId == 0 then
		return false
	end
	local kind: string? = nil
	if productId == productWithId(Products.offers.doubleRelease) then
		grantDoubleRelease(player, profile)
		kind = "doubleRelease"
	elseif productId == productWithId(Products.offers.starterPack) then
		grantStarter(player, profile)
		kind = "starterPack"
	else
		for dealId, product in Products.deals do
			if product.productId == productId then
				grantDeal(player, profile, dealId)
				kind = "dailyDeal"
				break
			end
		end
	end
	if not kind then
		return false
	end
	DataService.replicate(player)
	ShopService.refresh(player) -- заряды и кофе в магазине и HUD
	logOffer(player, kind, "purchased")
	task.defer(OfferService.pushState, player)
	return true
end

local function onStateRequest(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + STATE_REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	OfferService.pushState(player)
end

local function onEvent(player: Player, kind: any, stage: any)
	if type(kind) ~= "string" or type(stage) ~= "string" then
		return
	end
	if Offers.enabled[kind] == nil or not Offers.stages[stage] then
		return
	end
	-- Покупки своих продуктов сервер пишет сам (из квитанции)
	if stage == "purchased" and (kind == "doubleRelease" or kind == "starterPack" or kind == "dailyDeal") then
		return
	end
	local now = os.clock()
	if (lastEvent[player] or 0) + EVENT_COOLDOWN > now then
		return
	end
	local count = eventCount[player] or 0
	if count >= EVENTS_PER_SESSION then
		return
	end
	lastEvent[player] = now
	eventCount[player] = count + 1
	-- Стартовый набор сам открывается один раз на аккаунт (потом — только из магазина)
	if kind == "starterPack" and stage == "shown" then
		local profile = DataService.get(player)
		if profile then
			data(profile).starterShown = true
		end
	end
	logOffer(player, kind, stage)
end

function OfferService.start()
	DataService.onProfileLoaded(function(player, profile)
		local offers = data(profile)
		player:SetAttribute("StarterBadge", offers.starterBadge)
		OfferService.pushState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRelease[player] = nil
		lastRequest[player] = nil
		lastEvent[player] = nil
		eventCount[player] = nil
	end)
	OfferRemotes.OfferStateRequest.OnServerEvent:Connect(onStateRequest)
	OfferRemotes.OfferEvent.OnServerEvent:Connect(onEvent)
end

return OfferService
