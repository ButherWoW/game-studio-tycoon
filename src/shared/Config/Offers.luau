--!strict
-- Предложения доната в нужный момент (OfferService на сервере, клиент Offers/OfferController).
-- Платных лутбоксов нет. Не спамим: всплывающие окна предложений — не чаще popup.cooldownSeconds,
-- не больше popup.maxPerSession за сессию, не во время туториала и не в первые минуты новичка
-- (кроме стартового набора), не поверх других окон. Продукты (productId) — в Config/Products:
-- offers.doubleRelease, offers.starterPack и deals (скидочные копии для «Сделки дня»).

local ContentDrops = require(script.Parent.ContentDrops)

export type OfferKind =
	"doubleRelease"
	| "x2Reminder"
	| "floorLock"
	| "strike"
	| "longDev"
	| "starterPack"
	| "dailyDeal"
	| "contract"

-- Что можно продать в «Сделке дня»: продукт из Config/Products, премиум-постер или премиум-скин.
-- id — ключ в Products.deals
export type DealItem = { id: string, kind: "product" | "poster" | "skin", itemId: string }

local Offers = {
	-- Выключить предложение целиком — false
	enabled = {
		doubleRelease = true,
		x2Reminder = true,
		floorLock = true,
		strike = true,
		longDev = true,
		starterPack = true,
		dailyDeal = true,
		-- Не донат: предложение контракта издателя (ContractService) — окно по тем же правилам
		contract = true,
	} :: { [string]: boolean },

	-- Показывать предложения, у которых productId/gamePassId ещё 0 (кнопка «Скоро»).
	-- Для проверки интерфейса в Studio; на живом сервере — false (продать всё равно нельзя)
	showWithoutId = false,

	-- Всплывающие окна (этаж, забастовка, стартовый набор)
	popup = {
		cooldownSeconds = 4 * 60, -- между любыми двумя всплывающими предложениями
		maxPerSession = 6,
		sessionWarmupSeconds = 60, -- после входа в игру — тишина
		newPlayerSeconds = 5 * 60, -- первые минуты новичка (от firstJoin) — только стартовый набор
		sameKindSeconds = 15 * 60, -- одно и то же предложение не чаще
	},

	-- ×2 к доходу только что вышедшей игры (кнопка в окне релиза)
	doubleRelease = {
		minScore = 7, -- или хит (HitCartridges.minScore)
		windowSeconds = 60, -- столько после релиза покупка удваивает именно его
		showCooldownSeconds = 3 * 60, -- кнопку показываем не на каждом хорошем релизе
		fallbackProduct = "income10", -- куплено позже/повторно — выдаём этот пакет дохода
	},

	-- «С ×2 ты получил бы ещё +$N» в окне релиза (тем, у кого нет геймпасса doubleCash)
	x2Reminder = {
		everyNthRelease = 3,
		minRevenue = 100,
	},

	-- Игрок у лифта рядом с закрытым этажом и ему не хватает денег — пакет дохода, который покрывает
	-- разницу (или самый большой). Пакеты — id из Config/Products, по возрастанию
	floorLock = {
		packs = { "income10", "income30", "income90" },
	},

	-- Забастовка: пакет, который покрывает невыплаченную зарплату (кнопка в подсказке и окно)
	strike = {
		packs = { "income10", "income30" },
		margin = 1.1, -- запас сверху: аренда тоже списывается
	},

	-- «⚡ Закончить сейчас» у строки прогресса (продукт instantFinish), когда зарядов нет
	longDev = {
		minRemainingSeconds = 60,
	},

	-- Стартовый набор: один раз на аккаунт, 24 ч с первого входа
	starterPack = {
		showAfterSeconds = 5 * 60, -- сессии, и только когда гараж куплен (онбординг, Config/Unlocks)
		durationSeconds = 24 * 60 * 60,
		incomeMinutes = 30, -- $ = доход студии за столько минут
		minCash = 5_000,
		skins = { "hoodie_coder", "pixel_artist" },
		coffeeCount = 3, -- × Products.effects.coffeeSeconds
	},

	-- Сделка дня: один товар на сутки UTC со скидкой (отдельный продукт из Products.deals)
	dailyDeal = {
		discountPercent = 30,
		pool = {
			{ id = "coffee", kind = "product", itemId = "coffee" },
			{ id = "poster_neonCity", kind = "poster", itemId = "neonCity" },
			{ id = "income30", kind = "product", itemId = "income30" },
			{ id = "skin_neon_streamer", kind = "skin", itemId = "neon_streamer" },
			{ id = "patch", kind = "product", itemId = "patch" },
			{ id = "poster_crystalKingdom", kind = "poster", itemId = "crystalKingdom" },
			{ id = "income10", kind = "product", itemId = "income10" },
			{ id = "skin_cyber_dev", kind = "skin", itemId = "cyber_dev" },
			{ id = "poster_mechTitan", kind = "poster", itemId = "mechTitan" },
			{ id = "income90", kind = "product", itemId = "income90" },
			{ id = "skin_space_dev", kind = "skin", itemId = "space_dev" },
			{ id = "poster_galaxyLegends", kind = "poster", itemId = "galaxyLegends" },
			{ id = "instantFinish", kind = "product", itemId = "instantFinish" },
			{ id = "skin_wizard_dev", kind = "skin", itemId = "wizard_dev" },
			{ id = "poster_goldenController", kind = "poster", itemId = "goldenController" },
		} :: { DealItem },
	},

	-- Аналитика: какие события принимает сервер от клиента
	stages = { shown = true, clicked = true, purchased = true } :: { [string]: boolean },
}

local DAY = 24 * 60 * 60

-- Номер суток UTC (по серверному времени)
function Offers.dayOf(unixTime: number): number
	return math.floor(unixTime / DAY)
end

-- Сколько секунд до полуночи UTC
function Offers.secondsToMidnight(unixTime: number): number
	return DAY - (math.floor(unixTime) % DAY)
end

-- Постер или скин ещё не вышел к дню day (Config/ContentDrops) — в сделку дня не берём
local function dealReleased(item: DealItem, day: number): boolean
	if item.kind == "product" then
		return true
	end
	return ContentDrops.isReleased((item.kind :: any) :: ContentDrops.Kind, item.itemId, day * DAY)
end

-- Товар дня: детерминированно от даты, одинаков на всех серверах и у клиента.
-- Невышедший товар пропускаем — берём следующий по пулу (товары-продукты есть всегда)
function Offers.dealFor(day: number): DealItem
	local pool = Offers.dailyDeal.pool
	-- Шаг 7 взаимно прост с длиной пула (15): за 15 дней покажем все товары, соседние дни разные
	local start = (day * 7) % #pool
	for step = 0, #pool - 1 do
		local item = pool[(start + step) % #pool + 1]
		if dealReleased(item, day) then
			return item
		end
	end
	return pool[start + 1]
end

-- «12:05:09» — без слов, одинаково на всех языках
function Offers.clock(seconds: number): string
	local s = math.max(math.floor(seconds), 0)
	return string.format("%02d:%02d:%02d", s // 3600, (s // 60) % 60, s % 60)
end

return Offers
