--!strict
-- Навыки, перки и внешность сотрудников (StaffService, окно «Команда»).
-- Навык 0..maxLevel по направлению: очки стола сотрудника в это направление × (1 + bonusPerLevel × уровень).
-- Уровень сотрудника = сумма навыков; от него открываются перки.

export type SkillKey = "gameplay" | "graphics" | "sound" | "story"

export type Perk = {
	id: string,
	name: string,
	nameEn: string,
	minLevel: number, -- уровень сотрудника (сумма навыков), с которого перк можно поставить
	-- Эффекты (суммируются по всем сотрудникам за столами, см. StaffService.perkTotals)
	devTime: number?, -- −0.1 = игра делается на 10% быстрее
	reviewBonus: number?, -- прибавка к оценке каждой игры
	bugAlwaysWins: boolean?, -- событие «bug» всегда удачно
	streamerMultiplier: number?, -- событие «streamer» даёт во столько раз больше
	mentorBonus: number?, -- +доля к очкам всех остальных столов
	trendBonus: number?, -- прибавка к оценке, если игра в тренде
	offlineBonus: number?, -- +доля к офлайн-доходу
}

local Skills = {}

Skills.keys = { "gameplay", "graphics", "sound", "story" } :: { SkillKey }
Skills.maxLevel = 5
Skills.bonusPerLevel = 0.15

-- Стартовые уровни: своя специализация 2, остальные 0; универсал (без специализации) — 1 везде;
-- легендарные — 2 везде
Skills.startOwn = 2
Skills.startOther = 0
Skills.startGeneralist = 1
Skills.startLegendary = 2

-- Цена «+1» к навыку: costBase[этап сотрудника] × costGrowth ^ текущий уровень
Skills.costBase = { 600, 3_000, 12_000, 60_000 }
Skills.costGrowth = 2
Skills.legendaryCostStage = 3 -- легендарные бесплатны при найме, навыки — по ценам этажа

-- Перки: слотов у обычного сотрудника и у легендарного
Skills.perkSlots = 1
Skills.legendaryPerkSlots = 2
-- Поставить перк в пустой слот — бесплатно; сменить — costBase[этап] × perkChangeFactor
-- и не чаще раза в perkCooldown секунд (на сотрудника)
Skills.perkChangeFactor = 2
Skills.perkCooldown = 60

Skills.perks = {
	{ id = "cruncher", name = "Кранчер", nameEn = "Cruncher", minLevel = 2, devTime = -0.1 },
	{
		id = "perfectionist",
		name = "Перфекционист",
		nameEn = "Perfectionist",
		minLevel = 3,
		reviewBonus = 0.2,
	},
	{
		id = "bugfighter",
		name = "Багоборец",
		nameEn = "Bug fighter",
		minLevel = 3,
		bugAlwaysWins = true,
	},
	{
		id = "hypebeast",
		name = "Хайпожор",
		nameEn = "Hype hunter",
		minLevel = 4,
		streamerMultiplier = 2,
	},
	{ id = "mentor", name = "Наставник", nameEn = "Mentor", minLevel = 5, mentorBonus = 0.1 },
	{
		id = "trendhunter",
		name = "Тренд-хантер",
		nameEn = "Trend hunter",
		minLevel = 6,
		trendBonus = 0.5,
	},
	{
		id = "nightshift",
		name = "Ночная смена",
		nameEn = "Night shift",
		minLevel = 4,
		offlineBonus = 0.2,
	},
} :: { Perk }

-- ===== Внешность (бесплатно, выбор в окне «Команда») =====
-- shirt 0 — цвет специализации (Config/Employees.shirtColors), 1..N — палитра
Skills.shirts = {
	Color3.fromRGB(235, 70, 70),
	Color3.fromRGB(255, 150, 50),
	Color3.fromRGB(250, 215, 60),
	Color3.fromRGB(110, 200, 80),
	Color3.fromRGB(40, 170, 160),
	Color3.fromRGB(70, 150, 255),
	Color3.fromRGB(120, 90, 230),
	Color3.fromRGB(240, 110, 190),
	Color3.fromRGB(245, 245, 245),
	Color3.fromRGB(40, 40, 48),
} :: { Color3 }
Skills.skins = {
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(255, 214, 180),
	Color3.fromRGB(205, 150, 110),
	Color3.fromRGB(160, 105, 70),
	Color3.fromRGB(110, 70, 45),
	Color3.fromRGB(250, 220, 120),
} :: { Color3 }
-- Головные уборы и предметы на столе собираются из деталей (StaffService), тексты hat_<id>/item_<id>
Skills.hats = { "none", "cap", "headphones", "beanie", "tophat", "crown" }
Skills.items = { "none", "mug", "figurine", "cactus", "duck" }

local perkById: { [string]: Perk } = {}
for _, perk in Skills.perks do
	perkById[perk.id] = perk
end

function Skills.perk(id: string): Perk?
	return perkById[id]
end

function Skills.isKey(key: any): boolean
	return type(key) == "string" and table.find(Skills.keys, key) ~= nil
end

-- Стартовые навыки сотрудника (specialization nil — универсал)
function Skills.start(specialization: string?, legendary: boolean?): { [string]: number }
	local result = {}
	for _, key in Skills.keys do
		if legendary then
			result[key] = Skills.startLegendary
		elseif specialization == nil then
			result[key] = Skills.startGeneralist
		else
			result[key] = if key == specialization then Skills.startOwn else Skills.startOther
		end
	end
	return result
end

local function costStage(stage: number, legendary: boolean?): number
	local s = if legendary then Skills.legendaryCostStage else stage
	return math.clamp(math.floor(s), 1, #Skills.costBase)
end

-- Цена следующего уровня навыка (level — текущий)
function Skills.skillCost(stage: number, legendary: boolean?, level: number): number
	return math.floor(Skills.costBase[costStage(stage, legendary)] * Skills.costGrowth ^ level)
end

function Skills.perkChangeCost(stage: number, legendary: boolean?): number
	return math.floor(Skills.costBase[costStage(stage, legendary)] * Skills.perkChangeFactor)
end

function Skills.slots(legendary: boolean?): number
	return if legendary then Skills.legendaryPerkSlots else Skills.perkSlots
end

return Skills
