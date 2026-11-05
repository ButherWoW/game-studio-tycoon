--!strict
-- Сезонный пропуск (без лутбоксов): сезон 28 дней, 30 уровней, бесплатная и премиум-дорожка.
-- Сезоны идут подряд от epoch (UTC) — одинаково на всех серверах, id = "s<номер>".
-- Опыт: релизы (больше за высокую оценку), хиты, идеальные быстрые события, ежедневные задания.
-- Награды выдаёт SeasonService; предмет уже есть или его некуда выдать — fallbackMinutes дохода.

local RunService = game:GetService("RunService")

local Debug = require(script.Parent.Debug)

export type Reward = {
	incomeMinutes: number?, -- деньги: N минут дохода (RewardService)
	coffeeMinutes: number?, -- ×2 скорость разработки
	researchPoints: number?, -- очки исследований
	poster: string?, -- id из Config/Posters
	skin: string?, -- id из Config/Skins
	mascot: string?, -- id талисмана (MascotService, если он есть на сервере)
	title: boolean?, -- сезонное звание (флаг в профиле, только в этом сезоне)
	fallbackMinutes: number?, -- предмет уже есть или сервиса нет — столько минут дохода
}

export type Tier = { free: Reward, premium: Reward }

export type Info = { index: number, id: string, startsAt: number, endsAt: number }

local DAY = 24 * 60 * 60

local function income(minutes: number): Reward
	return { incomeMinutes = minutes }
end
local function coffee(minutes: number): Reward
	return { coffeeMinutes = minutes }
end
local function research(points: number): Reward
	return { researchPoints = points }
end
local function poster(id: string, fallback: number): Reward
	return { poster = id, fallbackMinutes = fallback }
end
local function skin(id: string, fallback: number): Reward
	return { skin = id, fallbackMinutes = fallback }
end
local function mascot(id: string, fallback: number): Reward
	return { mascot = id, fallbackMinutes = fallback }
end

local Season = {
	-- Начало первого сезона: понедельник 2026-11-02 00:00 UTC
	epoch = 1_793_577_600,
	lengthSeconds = 28 * DAY,
	xpPerTier = 400,
	-- Опыт за действия
	xp = {
		releaseBase = 5, -- за любой релиз
		perScore = 3, -- + оценка × 3 (оценка 10 — 35 опыта)
		hit = 15, -- оценка >= HitCartridges.minScore
		quickPerfect = 10, -- идеальное быстрое событие
		daily = 80, -- забрал ежедневное задание
		-- Опыт за релизы и хиты в сутки (UTC) не больше: авто-релиз не проходит сезон за ночь
		releaseDailyCap = 1500,
	},
	-- Developer Products (Dev 1 создаёт в Dashboard и вписывает productId; 0 — кнопка «скоро»).
	-- robuxPrice — предложение, финальную цену решает владелец
	products = {
		seasonPass = { productId = 3728448106, robuxPrice = 399 }, -- премиум-дорожка до конца сезона
		seasonSkip = { productId = 3728448111, robuxPrice = 49 }, -- +1 уровень
	},
	-- Награда, если премиум купили повторно в том же сезоне (минут дохода)
	repeatPassMinutes = 60,
	tiers = {
		{ free = income(5), premium = { coffeeMinutes = 10, incomeMinutes = 10 } },
		{ free = research(2), premium = income(15) },
		{ free = coffee(5), premium = poster("neonCity", 20) },
		{ free = income(5), premium = research(5) },
		{ free = poster("pixelHero", 5), premium = skin("neon_streamer", 30) },
		{ free = income(6), premium = income(20) },
		{ free = research(3), premium = coffee(15) },
		{ free = coffee(5), premium = poster("crystalKingdom", 25) },
		{ free = income(8), premium = research(8) },
		{ free = poster("ninjaCat", 8), premium = skin("cyber_dev", 40) },
		{ free = income(8), premium = income(25) },
		{ free = research(4), premium = coffee(20) },
		{ free = coffee(10), premium = poster("mechTitan", 30) },
		{ free = income(10), premium = research(10) },
		{ free = poster("robotArena", 10), premium = mascot("slime_star", 45) },
		{ free = income(10), premium = income(30) },
		{ free = research(5), premium = coffee(20) },
		{ free = coffee(10), premium = poster("galaxyLegends", 35) },
		{ free = income(12), premium = research(12) },
		{ free = poster("dragonValley", 12), premium = skin("space_dev", 50) },
		{ free = income(12), premium = income(35) },
		{ free = research(6), premium = coffee(25) },
		{ free = coffee(10), premium = poster("goldenController", 40) },
		{ free = income(15), premium = research(15) },
		{ free = poster("ghostManor", 15), premium = mascot("robo_owl", 60) },
		{ free = income(15), premium = income(40) },
		{ free = research(8), premium = coffee(30) },
		{ free = coffee(15), premium = skin("wizard_dev", 60) },
		{ free = income(20), premium = research(20) },
		{ free = income(30), premium = { incomeMinutes = 90, title = true } },
	} :: { Tier },
}

-- Номер сезона (0 — первый). В Studio можно подменить (Config/Debug.seasonForceIndex)
function Season.index(now: number?): number
	local forced = Debug.seasonForceIndex
	if forced and RunService:IsStudio() then
		return forced
	end
	return math.max(((now or os.time()) - Season.epoch) // Season.lengthSeconds, 0)
end

function Season.info(now: number?): Info
	local index = Season.index(now)
	local startsAt = Season.epoch + index * Season.lengthSeconds
	return {
		index = index,
		id = "s" .. (index + 1),
		startsAt = startsAt,
		endsAt = startsAt + Season.lengthSeconds,
	}
end

function Season.maxXp(): number
	return #Season.tiers * Season.xpPerTier
end

-- Сколько уровней открыто при таком опыте (0..30)
function Season.tierOf(xp: number): number
	return math.clamp(xp // Season.xpPerTier, 0, #Season.tiers)
end

-- Опыт за релиз (без суточного потолка)
function Season.releaseXp(score: number, hit: boolean): number
	return Season.xp.releaseBase
		+ math.max(score, 0) * Season.xp.perScore
		+ (if hit then Season.xp.hit else 0)
end

return Season
