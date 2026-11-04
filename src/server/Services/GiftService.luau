--!strict
-- Подарки (Config/Social.gifts): премиум-скин или премиум-постер за Robux другому игроку на сервере.
-- 1) Клиент выбирает получателя (GiftSelect) — проверяем и запоминаем «кому» за покупателем,
--    окно покупки открывает сервер.
-- 2) Квитанция gift_<itemId> приходит в MonetizationService.ProcessReceipt -> grantProduct:
--    предмет получает выбранный игрок; если он вышел (или уже получил такой) — сам покупатель.
-- Никогда не дарим себе. Квитанцию и профиль покупателя сохраняет MonetizationService.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Social = require(Shared.Config.Social)
local SocialRemotes = require(Shared.SocialRemotes)
local DataService = require(script.Parent.DataService)
local SkinService = require(script.Parent.SkinService)
local PosterService = require(script.Parent.PosterService)

local SELECT_COOLDOWN = 1

type Pending = { giftId: string, targetUserId: number, targetName: string, at: number }

local GiftService = {}
local pending: { [Player]: Pending } = {}
local lastSelect: { [Player]: number } = {}
-- Квитанции, уже выданные на этом сервере: повтор ProcessReceipt (сейв не удался) не выдаёт второй раз
local delivered: { [string]: boolean } = {}

local function notice(player: Player, payload: { [string]: any })
	SocialRemotes.SocialNotice:FireClient(player, payload)
end

local function ownsItem(profile: DataService.Profile, gift: Social.Gift): boolean
	if gift.kind == "skin" then
		return SkinService.owns(profile, gift.itemId)
	end
	return PosterService.ownsIn(profile, gift.itemId)
end

local function grantItem(player: Player, profile: DataService.Profile, gift: Social.Gift)
	if gift.kind == "skin" then
		SkinService.grantSkin(player, profile, gift.itemId)
	else
		PosterService.grantPoster(player, profile, gift.itemId)
	end
end

local function logGift(player: Player, gift: Social.Gift, toFriend: boolean)
	local analytics = script.Parent:FindFirstChild("AnalyticsService")
	if analytics and analytics:IsA("ModuleScript") then
		pcall((require(analytics) :: any).logGift, player, gift.id, toFriend)
	end
end

local function onSelect(player: Player, giftId: any, userId: any)
	local now = os.clock()
	if (lastSelect[player] or 0) + SELECT_COOLDOWN > now then
		return
	end
	lastSelect[player] = now
	local gift = Social.findGift(giftId)
	if not gift or type(userId) ~= "number" then
		return
	end
	local base = { itemKind = gift.kind, itemId = gift.itemId }
	if gift.productId == 0 then
		notice(player, { kind = "giftSoon" })
		return
	end
	local target = Players:GetPlayerByUserId(userId)
	local targetProfile = target and DataService.get(target)
	if not target or target == player or not targetProfile then
		notice(player, { kind = "giftUnavailable" })
		return
	end
	if ownsItem(targetProfile, gift) then
		notice(
			player,
			{ kind = "giftOwned", name = target.DisplayName, itemKind = base.itemKind, itemId = base.itemId }
		)
		return
	end
	pending[player] =
		{ giftId = gift.id, targetUserId = target.UserId, targetName = target.DisplayName, at = now }
	MarketplaceService:PromptProductPurchase(player, gift.productId)
end

-- Квитанция подарка (зовёт MonetizationService.ProcessReceipt). false — это не подарок
function GiftService.grantProduct(buyer: Player, buyerProfile: DataService.Profile, receipt: any): boolean
	local gift = Social.findGiftByProduct(receipt.ProductId)
	if not gift then
		return false
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if delivered[purchaseId] then
		return true
	end
	local item = { itemKind = gift.kind, itemId = gift.itemId }
	local wish = pending[buyer]
	pending[buyer] = nil
	local target: Player? = nil
	if wish and wish.giftId == gift.id and os.clock() - wish.at <= Social.giftPendingSeconds then
		target = Players:GetPlayerByUserId(wish.targetUserId)
	end
	local targetProfile = if target and target ~= buyer then DataService.get(target) else nil
	if target and targetProfile and not ownsItem(targetProfile, gift) then
		grantItem(target, targetProfile, gift)
		delivered[purchaseId] = true
		-- Подарок в профиле получателя: сохраняем сразу, не ждём автосейва
		task.spawn(DataService.save, target)
		notice(
			target,
			{ kind = "giftReceived", name = buyer.DisplayName, itemKind = item.itemKind, itemId = item.itemId }
		)
		notice(
			buyer,
			{ kind = "giftSent", name = target.DisplayName, itemKind = item.itemKind, itemId = item.itemId }
		)
		logGift(buyer, gift, true)
		return true
	end
	-- Получатель вышел или уже получил такой: деньги списаны — предмет достаётся покупателю
	grantItem(buyer, buyerProfile, gift)
	delivered[purchaseId] = true
	notice(buyer, {
		kind = "giftFallback",
		name = if wish then wish.targetName else "?",
		itemKind = item.itemKind,
		itemId = item.itemId,
	})
	logGift(buyer, gift, false)
	return true
end

function GiftService.start()
	SocialRemotes.GiftSelect.OnServerEvent:Connect(onSelect)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		lastSelect[player] = nil
	end)
end

return GiftService
