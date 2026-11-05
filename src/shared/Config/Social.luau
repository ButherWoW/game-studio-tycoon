--!strict
-- Статус и соцфичи: VIP-статус (владельцы геймпасса vipOffice), подарки, награда за группу,
-- бонус Roblox Premium. Код — VipService, GiftService, SocialService (сервер) и
-- SocialController, GiftPicker (клиент).
-- productId / groupId — из Creator Dashboard (0 = ещё не создан: кнопка «Скоро» / подсказки нет).

local Skins = require(script.Parent.Skins)
local Posters = require(script.Parent.Posters)
local Mascots = require(script.Parent.Mascots)
local Universe = require(script.Parent.Universe)

export type GiftKind = "skin" | "poster" | "mascot"

export type Gift = {
	id: string, -- gift_<itemId>
	kind: GiftKind,
	itemId: string,
	productId: number, -- Developer Product «подарок», 0 = не создан
	robuxPrice: number, -- как у самого предмета
}

-- Dev 1: создать Developer Product «Gift: <название>» с той же ценой, что у предмета,
-- и вставить ID напротив gift_<itemId> (test — вселенная v2, main — основная игра, docs/IDS.md)
local giftProducts: { [string]: Universe.Pair } = {
	gift_neon_streamer = { test = 3728497737, main = 3728498672 },
	gift_cyber_dev = { test = 3728497750, main = 3728498688 },
	gift_space_dev = { test = 3728497769, main = 3728498698 },
	gift_wizard_dev = { test = 3728497787, main = 3728498712 },
	gift_neonCity = { test = 3728497804, main = 3728498731 },
	gift_crystalKingdom = { test = 3728497819, main = 3728498751 },
	gift_mechTitan = { test = 3728497831, main = 3728498769 },
	gift_galaxyLegends = { test = 3728497863, main = 3728498785 },
	gift_goldenController = { test = 3728497878, main = 3728498804 },
	gift_neon_fox = { test = 3728497891, main = 3728498815 },
	gift_dragon_byte = { test = 3728497896, main = 3728498830 },
	gift_golden_trophy = { test = 3728497908, main = 3728498845 },
	gift_cosmic_whale = { test = 3728497923, main = 3728498858 },
}

-- Подарить можно премиум-скины, премиум-постеры и маскотов за Robux; цена — как у предмета
local gifts: { Gift } = {}
for _, skin in Skins.list do
	if skin.premium then
		local id = "gift_" .. skin.id
		table.insert(gifts, {
			id = id,
			kind = "skin",
			itemId = skin.id,
			productId = Universe.pick(giftProducts[id]),
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
			productId = Universe.pick(giftProducts[id]),
			robuxPrice = poster.robuxPrice or 0,
		})
	end
end

for _, mascot in Mascots.list do
	if mascot.how == "robux" then
		local id = "gift_" .. mascot.id
		table.insert(gifts, {
			id = id,
			kind = "mascot",
			itemId = mascot.id,
			productId = Universe.pick(giftProducts[id]),
			robuxPrice = mascot.robuxPrice or 0,
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
