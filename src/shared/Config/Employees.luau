--!strict
-- Сотрудники (issue #7). Сотрудник садится за свободный стол (купленный апгрейд с pointsPerSecond)
-- и умножает очки этого стола. stage — с какого этапа студии можно нанять (Config/Stages).

export type Specialization = "gameplay" | "graphics" | "sound" | "story"

export type Employee = {
	id: string,
	name: string,
	nameEn: string,
	role: string,
	roleEn: string,
	specialization: Specialization?, -- nil — усиливает все направления одинаково
	multiplier: number,
	cost: number,
	stage: number,
	legendary: boolean?, -- нанять пока нельзя: условия не реализованы
}

local Employees = {}

-- +50% очков в своё направление, если в фокусе игры оно не меньше 30%
Employees.specBonus = 0.5
Employees.specThreshold = 0.3

-- Цвет футболки NPC по специализации
Employees.shirtColors = {
	gameplay = Color3.fromRGB(61, 123, 255),
	graphics = Color3.fromRGB(255, 110, 180),
	sound = Color3.fromRGB(61, 200, 110),
	story = Color3.fromRGB(150, 80, 220),
	all = Color3.fromRGB(255, 201, 60),
} :: { [string]: Color3 }

local function employee(
	id: string,
	name: string,
	nameEn: string,
	role: string,
	roleEn: string,
	specialization: Specialization?,
	multiplier: number,
	cost: number,
	stage: number
): Employee
	return {
		id = id,
		name = name,
		nameEn = nameEn,
		role = role,
		roleEn = roleEn,
		specialization = specialization,
		multiplier = multiplier,
		cost = cost,
		stage = stage,
	}
end

Employees.list = {
	-- Гараж
	employee(
		"mila",
		"Мила",
		"Mila",
		"джун-программист",
		"junior programmer",
		"gameplay",
		1.5,
		1_500,
		1
	),
	employee(
		"tim",
		"Тим",
		"Tim",
		"пиксель-художник",
		"pixel artist",
		"graphics",
		1.5,
		1_500,
		1
	),
	employee(
		"zoe",
		"Зоя",
		"Zoe",
		"звукарь-самоучка",
		"self-taught sound guy",
		"sound",
		1.5,
		2_000,
		1
	),
	employee(
		"ilya",
		"Илья",
		"Ilya",
		"сценарист-фантазёр",
		"dreamer writer",
		"story",
		1.5,
		2_000,
		1
	),
	-- Офис
	employee(
		"oleg",
		"Олег",
		"Oleg",
		"гейм-дизайнер",
		"game designer",
		"gameplay",
		2,
		10_000,
		2
	),
	employee("sara", "Сара", "Sara", "3D-художница", "3D artist", "graphics", 2, 10_000, 2),
	employee("max", "Макс", "Max", "композитор", "composer", "sound", 2, 12_000, 2),
	employee(
		"nika",
		"Ника",
		"Nika",
		"нарративщица",
		"narrative designer",
		"story",
		2,
		12_000,
		2
	),
	-- Этаж
	employee("den", "Ден", "Den", "техлид", "tech lead", "gameplay", 3, 40_000, 3),
	employee("aya", "Ая", "Aya", "арт-директор", "art director", "graphics", 3, 40_000, 3),
	employee("leo", "Лео", "Leo", "саунд-директор", "sound director", "sound", 3, 45_000, 3),
	employee(
		"vera",
		"Вера",
		"Vera",
		"главный сценарист",
		"lead writer",
		"story",
		3,
		45_000,
		3
	),
} :: { Employee }

-- Легендарные — небоскрёб. Условия найма ещё не реализованы, поэтому legendary = true:
-- TODO(#8): robo — исследование «ИИ-ассистент» + $250 000.
-- TODO(#7): ghost — квест «Выпусти 100 игр», эффект — офлайн-доход ×2 (пока просто ×2 к столу).
-- TODO(#11): legend — геймпасс «Легендарный сотрудник», эффект +1 к оценке (пока просто ×2 к столу).
local robo = employee(
	"robo",
	"РОБО-9000",
	"ROBO-9000",
	"ИИ-ассистент",
	"AI assistant",
	nil,
	4,
	250_000,
	4
)
local ghost = employee(
	"ghost",
	"Призрачный кодер",
	"Ghost Coder",
	"работает офлайн",
	"works offline",
	nil,
	2,
	0,
	4
)
local legend = employee(
	"legend",
	"Мастер Пиксель",
	"Pixel Master",
	"+1 к оценке",
	"+1 to score",
	nil,
	2,
	0,
	4
)
for _, e in { robo, ghost, legend } do
	e.legendary = true
	table.insert(Employees.list, e)
end

local byId: { [string]: Employee } = {}
for _, e in Employees.list do
	byId[e.id] = e
end

function Employees.get(id: string): Employee?
	return byId[id]
end

return Employees
