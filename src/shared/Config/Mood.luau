--!strict
-- Настроение команды (0–100): считает MoodService, показывают HUD, «Команда» и окно «Студия».
-- Цель = база + удобства студии (Config/Upgrades по id) + постеры на стенах + декор (Config/Decor)
-- − теснота − забастовка − «осадок» после забастовки. Текущее значение плавно идёт к цели.
-- Действует, только когда в команде есть сотрудники (соло в гараже настроение ни на что не влияет).
-- Числа апгрейдов здесь, а не в Config/Upgrades: цены и бонусы там балансирует отдельно.

local Mood = {}

Mood.base = 40
Mood.min = 0
Mood.max = 100

-- Удобства студии: id апгрейда из Config/Upgrades -> очки настроения
Mood.upgrades = {
	walls = 3, -- свет и стены гаража
	coffee = 6,
	posters = 4,
	office = 3, -- переезд в настоящий офис
	cooler = 4,
	meetingRoom = 4,
	serverRoom = 2,
	lounge = 6,
	soundStudio = 4,
	artWall = 5,
} :: { [string]: number }

-- Постеры (Config/Posters), которые висят на стенах сейчас: обычные и премиум, всего не больше cap
Mood.posterCash = 1
Mood.posterPremium = 3
Mood.posterCap = 12

-- Теснота: первые comfortBase сотрудников уютно и так, каждый предмет декора на участке
-- даёт место ещё comfortPerDecor; за каждого «лишнего» — crowdingPerEmployee, не больше crowdingCap
Mood.comfortBase = 2
Mood.comfortPerDecor = 1
Mood.crowdingPerEmployee = 3
Mood.crowdingCap = 30

-- Забастовка (нечем платить зарплату, ExpensesService): сразу минус strikePenalty к цели, а после неё
-- ещё «осадок» strikeAftermath, который тает на aftermathDecayPerMinute в минуту
Mood.strikePenalty = 35
Mood.strikeAftermath = 20
Mood.aftermathDecayPerMinute = 4

-- Плавность: на сколько очков в минуту значение растёт к цели и падает к ней
Mood.risePerMinute = 6
Mood.fallPerMinute = 10
Mood.tickSeconds = 5

-- Эффекты (только при сотрудниках в команде)
-- Скорость разработки: ×speedAtMin при 0, ×1 при neutral, ×speedAtMax при 100 (линейно)
Mood.neutral = 50
Mood.speedAtMin = 0.85
Mood.speedAtMax = 1.15
-- Оценка игры: +highBonus при настроении ≥ highFrom, lowPenalty при < lowBelow
Mood.highFrom = 80
Mood.highBonus = 0.2
Mood.lowBelow = 20
Mood.lowPenalty = -0.2

-- Цвет в HUD: красный ниже redBelow, жёлтый ниже yellowBelow, иначе зелёный
Mood.redBelow = 30
Mood.yellowBelow = 60

function Mood.speedMultiplier(value: number): number
	local v = math.clamp(value, Mood.min, Mood.max)
	if v < Mood.neutral then
		return Mood.speedAtMin + (1 - Mood.speedAtMin) * (v / Mood.neutral)
	end
	return 1 + (Mood.speedAtMax - 1) * ((v - Mood.neutral) / (Mood.max - Mood.neutral))
end

function Mood.reviewBonus(value: number): number
	if value >= Mood.highFrom then
		return Mood.highBonus
	elseif value < Mood.lowBelow then
		return Mood.lowPenalty
	end
	return 0
end

return Mood
