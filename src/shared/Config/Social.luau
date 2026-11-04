--!strict
-- Статус и соцфичи: VIP-статус (владельцы геймпасса vipOffice), подарки, награда за группу,
-- бонус Roblox Premium. Код — VipService, GiftService, SocialService (сервер) и
-- SocialController, GiftPicker (клиент).
-- productId / groupId — из Creator Dashboard (0 = ещё не создан: кнопка «Скоро» / подсказки нет).

local Skins = require(script.Parent.Skins)
local Posters = require(script.Parent.Posters)

export type GiftKind = "skin" | "poster"

export type Gift = {
	id: string, -- gift_<itemId>
	kind: GiftKind,
	itemId: string,
	productId: number, -- Developer Product «подарок», 0 = не создан
	robuxPrice: number, -- как у самого предмета
}

-- Dev 1: создать Developer Product «Gift: <название>» с той же ценой, что у предмета,
-- и вставить ID напротив gift_<itemId>
local giftProducts: { [string]: number } = {
	gift_neon_streamer = 0,
	gift_cyber_dev = 0,
	gift_space_dev = 0,
	gift_wizard_dev = 0,
	gift_neonCity = 0,
	gift_crystalKingdom = 0,
	gift_mechTitan = 0,
	gift_galaxyLegends = 0,
	gift_goldenController = 0,
}

-- Подарить можно премиум-скины и премиум-постеры; цена — как у предмета
local gifts: { Gift } = {}
for _, skin in Skins.list do
	if skin.premium then
		local id = "gift_" .. skin.id
		table.insert(gifts, {
			id = id,
			kind = "skin",
			itemId = skin.id,
			productId = giftProducts[id] or 0,
			robuxPrice = skin.robuxPrice or 0,
		})
	end
end
for _, poster in Posters.list do
	if poster.premium then
		local id = "gift_" .. poster.id
		table.insert(gifts, {
			id = id,
			kind = "poster",
			itemId = poster.id,
			productId = giftProducts[id] or 0,
			robuxPrice = poster.robuxPrice or 0,
		})
	end
end

local Social = {
	-- Группа Roblox. 0 — подсказки «Вступи в группу» и награды нет
	groupId = 0,
	-- Разовая награда за вступление: открытый скин (за $) и N минут дохода
	groupReward = { skin = "intern", incomeMinutes = 10 },
	-- Повторная проверка членства, пока игрок в игре, с
	groupCheckSeconds = 60,

	-- Roblox Premium: прибавка к офлайн-доходу и кофе к ежедневной награде (0 — выключено)
	premium = { offlineBonus = 0.1, dailyCoffeeMinutes = 0 },

	-- VIP-статус даёт геймпасс «VIP-офис» (vipOffice)
	vip = {
		tagMaxDistance = 60, -- табличку «👑 VIP» над головой дальше не видно, studs
		color = Color3.fromRGB(255, 201, 60),
		checkSeconds = 5, -- геймпасс могут купить посреди сессии
	},

	-- Подарок: сколько ждём квитанцию после выбора получателя, с
	giftPendingSeconds = 5 * 60,
	gifts = gifts,
}

function Social.findGift(id: any): Gift?
	if type(id) ~= "string" then
		return nil
	end
	for _, gift in gifts do
		if gift.id == id then
			return gift
		end
	end
	return nil
end

function Social.findGiftByProduct(productId: number): Gift?
	if productId == 0 then
		return nil
	end
	for _, gift in gifts do
		if gift.productId == productId then
			return gift
		end
	end
	return nil
end

-- Подарок для предмета (nil — этот предмет не дарят)
function Social.giftFor(kind: GiftKind, itemId: string): Gift?
	local gift = Social.findGift("gift_" .. itemId)
	return if gift and gift.kind == kind then gift else nil
end

return Social
