--!strict
-- Покупки за Robux (Developer Products) и рекламные кампании за игровую валюту.
-- Важно: бонус сохраняется в профиль ДО возврата PurchaseGranted.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AdCampaigns = require(ReplicatedStorage.Shared.Config.AdCampaigns)
local DataService = require(script.Parent.DataService)

local MonetizationService = {}

local function applyAd(player: Player, campaign: AdCampaigns.AdCampaign)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local now = os.time()
	local current = profile.activeAd
	-- Бонусы не складываются: берём больший, время продлеваем
	local bonus = campaign.bonus
	if current and current.expiresAt > now then
		bonus = math.max(bonus, current.bonus)
	end
	profile.activeAd = { bonus = math.min(bonus, 1), expiresAt = now + campaign.durationSeconds }
	DataService.replicate(player)
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
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local campaign = findByProduct(receipt.ProductId)
	if not campaign then
		warn("[Monetization] Unknown product", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	applyAd(player, campaign)
	profile.processedReceipts[receipt.PurchaseId] = true
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
			if DataService.trySpend(player, c.cashCost) then
				applyAd(player, c)
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
