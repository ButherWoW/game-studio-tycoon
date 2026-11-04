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
	legendary: boolean?, -- нанять можно, только когда открыт (unlockReward / unlockPass)
	unlockReward: string?, -- id из profile.rewards.employees (награда квеста, RewardService)
	unlockPass: string?, -- геймпасс из Config/GamePasses (ShopService.ownsPass)
	reviewBonus: number?, -- прибавка к оценке каждой игры, пока сидит за столом
	offlineMultiplier: number?, -- множитель офлайн-дохода, пока в команде
}

local Employees = {}

-- +50% очков в своё направление, если в фокусе игры оно не меньше 30%
Employees.specBonus = 0.5
Employees.specThreshold = 0.3

-- Увольнение возвращает долю цены найма (Employees.refundFor). Меньше 1 — цикл
-- «нанял → уволил» только тратит деньги; легендарным (бесплатный найм) — 0
Employees.fireRefund = 0.25

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

-- Легендарные (legendary = true): нанимаются, только когда открыты.
-- TODO(#8): robo — исследование «ИИ-ассистент» + $250 000 (небоскрёб).
-- ghost — квест «Выпусти 100 игр» (награда employee = "ghost_coder"): ×2 к столу и офлайн-доход ×2.
-- legend — геймпасс legendaryEmployee: ×2 к столу и +1 к оценке каждой игры.
-- ghost и legend — с гаража (stage = 1): награду и покупку видно сразу, садятся за любой стол.
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
	1
)
ghost.unlockReward = "ghost_coder"
ghost.offlineMultiplier = 2
local legend = employee(
	"legend",
	"Мастер Пиксель",
	"Pixel Master",
	"+1 к оценке",
	"+1 to score",
	nil,
	2,
	0,
	1
)
legend.unlockPass = "legendaryEmployee"
legend.reviewBonus = 1
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

-- Сколько вернут за увольнение (сервер начисляет, окно «Команда» показывает)
function Employees.refundFor(hired: Employee): number
	if hired.legendary then
		return 0
	end
	return math.floor(hired.cost * math.clamp(Employees.fireRefund, 0, 1))
end

return Employees
