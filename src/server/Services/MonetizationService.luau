--!strict
-- Покупки за Robux (Developer Products) и рекламные кампании за игровую валюту.
-- Важно: бонус сохраняется в профиль ДО возврата PurchaseGranted.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AdCampaigns = require(ReplicatedStorage.Shared.Config.AdCampaigns)
local DataService = require(script.Parent.DataService)
local ShopService = require(script.Parent.ShopService)
local PosterService = require(script.Parent.PosterService)
local SkinService = require(script.Parent.SkinService)
local GiftService = require(script.Parent.GiftService)
local OfferService = require(script.Parent.OfferService)
local MascotService = require(script.Parent.MascotService)
local SeasonService = require(script.Parent.SeasonService)
local FurnitureStyleService = require(script.Parent.FurnitureStyleService)
local InteriorFinishService = require(script.Parent.InteriorFinishService)
local ConsoleService = require(script.Parent.ConsoleService)

local MonetizationService = {}

-- Повторы ProcessReceipt приходят вскоре после покупки; старые квитанции хранить незачем,
-- иначе запись в DataStore растёт до лимита
local MAX_STORED_RECEIPTS = 50

local function rememberReceipt(profile: DataService.Profile, purchaseId: string)
	profile.processedReceipts[purchaseId] = true
	table.insert(profile.receiptLog, purchaseId)
	while #profile.receiptLog > MAX_STORED_RECEIPTS do
		local oldest = table.remove(profile.receiptLog, 1) :: string
		profile.processedReceipts[oldest] = nil
	end
end

-- paid = куплено за Robux: деньги уже списаны, отказать нельзя
local function applyAd(player: Player, campaign: AdCampaigns.AdCampaign, paid: boolean?): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	local now = os.time()
	local current = profile.activeAd
	-- Бонусы не складываются. Слабая реклама не продлевает сильную (иначе дешёвая кампания
	-- за $ держала бы купленные за Robux +100% бесконечно): пока идёт сильная — отказ
	if current and current.expiresAt > now and current.bonus > campaign.bonus then
		if not paid then
			return false
		end
		-- Купил слабую за Robux поверх сильной: продлеваем сильную на «равноценное» время
		current.expiresAt += math.floor(campaign.durationSeconds * campaign.bonus / current.bonus)
		DataService.replicate(player)
		return true
	end
	-- Такая же реклама уже идёт: продлеваем, а не перезапускаем (иначе оплаченное время пропадало)
	if current and current.expiresAt > now and current.bonus == math.min(campaign.bonus, 1) then
		current.expiresAt += campaign.durationSeconds
		DataService.replicate(player)
		return true
	end
	profile.activeAd = { bonus = math.min(campaign.bonus, 1), expiresAt = now + campaign.durationSeconds }
	DataService.replicate(player)
	return true
end

-- Последняя игра — на рекламные щиты у спавна (BillboardService); без модуля ничего не ломается
local function toBillboards(player: Player, campaign: AdCampaigns.AdCampaign, paid: boolean)
	local module = script.Parent:FindFirstChild("BillboardService")
	if not module or not module:IsA("ModuleScript") then
		return
	end
	local ok, err = pcall(function()
		(require(module) :: any).onAdPurchased(player, campaign, paid)
	end)
	if not ok then
		warn("[Monetization] Billboards failed:", err)
	end
end

local function findByProduct(productId: number): AdCampaigns.AdCampaign?
	for _, c in AdCampaigns do
		if c.productId ~= 0 and c.productId == productId then
			return c
		end
	end
	return nil
end

local function processReceipt(receipt): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = player and DataService.get(player)
	if not player or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if profile.processedReceipts[receipt.PurchaseId] then
		-- Эффект уже выдан; подтверждаем, только когда он точно записан в DataStore
		return if DataService.save(player)
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Диспетчер по productId: реклама здесь, премиум-постеры — PosterService, премиум-скины —
	-- SkinService, стиль мебели «Неон» — FurnitureStyleService, отделка студии — InteriorFinishService,
	-- остальное — ShopService
	-- Ошибка посреди выдачи: часть эффекта уже в профиле. Квитанцию всё равно записываем —
	-- лучше недодать, чем выдать второй раз на повторе чека
	local ok, handled = pcall(function(): boolean
		local campaign = findByProduct(receipt.ProductId)
		if campaign then
			applyAd(player, campaign, true)
			toBillboards(player, campaign, true)
			return true
		end
		-- Подарки (gift_<itemId>) — GiftService: предмет получает выбранный игрок
		return GiftService.grantProduct(player, profile, receipt)
			or PosterService.grantProduct(player, profile, receipt.ProductId)
			or SkinService.grantProduct(player, profile, receipt.ProductId)
			or MascotService.grantProduct(player, profile, receipt.ProductId)
			or ShopService.grantProduct(player, profile, receipt.ProductId)
			or OfferService.grantProduct(player, profile, receipt.ProductId)
			or SeasonService.grantProduct(player, profile, receipt.ProductId)
			or FurnitureStyleService.grantProduct(player, profile, receipt.ProductId)
			or InteriorFinishService.grantProduct(player, profile, receipt.ProductId)
			or ConsoleService.grantProduct(player, profile, receipt.ProductId)
	end)
	if not ok then
		warn("[Monetization] Grant failed:", receipt.ProductId, receipt.PurchaseId, handled)
	elseif not handled then
		warn("[Monetization] Unknown product", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Эффект и квитанция попадают в DataStore одной записью ДО PurchaseGranted
	rememberReceipt(profile, receipt.PurchaseId)
	if not DataService.save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function onBuyWithCash(player: Player, campaignId: any)
	if type(campaignId) ~= "string" then
		return
	end
	for _, c in AdCampaigns do
		if c.id == campaignId and c.cashCost then
			-- Слабую рекламу поверх более сильной не продаём: деньги не списываем
			local profile = DataService.get(player)
			local current = profile and profile.activeAd
			if current and current.expiresAt > os.time() and current.bonus > c.bonus then
				return
			end
			if DataService.trySpend(player, c.cashCost) and applyAd(player, c) then
				toBillboards(player, c, false)
			end
			return
		end
	end
end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = processReceipt
	Remotes.BuyAdCampaignWithCash.OnServerEvent:Connect(onBuyWithCash)
end

return MonetizationService
