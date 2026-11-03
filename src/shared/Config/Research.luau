--!strict
-- Дерево исследований (issue #8, шаг 3.4). Очки исследований (ОИ) = оценка каждой выпущенной игры.
-- requires — узлы, которые должны быть изучены раньше (все из списка).
-- effect — что даёт узел. Открытие жанра применяет ResearchService, остальное отдаёт
-- ResearchService.getModifiers(player), а применяют разработка/доход/найм.

export type Branch = "genres" | "tech" | "studio"

export type Effect = {
	unlockGenre: string?, -- открыть жанр без денег
	devTime: number?, -- доля к времени разработки: -0.1 = на 10% быстрее
	graphicsPoints: number?, -- доля к очкам графики: 0.1 = +10%
	soundPoints: number?, -- доля к очкам звука
	revenue: number?, -- доля к доходу (складывается между узлами)
	robotHire: boolean?, -- открывает найм РОБО-9000 (#7)
	reviewPreview: boolean?, -- тест-группа: после разработки видна примерная оценка
	projectSlots: number?, -- сколько игр можно делать одновременно
	publishing: boolean?, -- издательство: пассивный доход от старых игр
}

export type Node = {
	id: string,
	branch: Branch,
	order: number, -- порядок в колонке
	name: string,
	nameEn: string,
	description: string,
	descriptionEn: string,
	cost: number, -- в ОИ
	requires: { string },
	effect: Effect,
}

local Research = {}

local branches: { Branch } = { "genres", "tech", "studio" }
Research.BRANCHES = branches

-- Сколько ОИ даёт выпущенная игра: оценка 1–10 как есть
Research.POINTS_PER_SCORE = 1

local nodes: { Node } = {
	-- Жанровая ветка: второй, «бесплатный» путь к жанрам (за деньги они тоже открываются)
	{
		id = "story_games",
		branch = "genres",
		order = 1,
		name = "Сюжетные игры",
		nameEn = "Story games",
		description = "Открывает жанр RPG",
		descriptionEn = "Unlocks the RPG genre",
		cost = 10,
		requires = {},
		effect = { unlockGenre = "rpg" },
	},
	{
		id = "logic",
		branch = "genres",
		order = 2,
		name = "Логика",
		nameEn = "Logic",
		description = "Открывает жанр «Головоломка»",
		descriptionEn = "Unlocks the Puzzle genre",
		cost = 15,
		requires = { "story_games" },
		effect = { unlockGenre = "puzzle" },
	},
	{
		id = "car_physics",
		branch = "genres",
		order = 3,
		name = "Физика машин",
		nameEn = "Car physics",
		description = "Открывает жанр «Гонки»",
		descriptionEn = "Unlocks the Racing genre",
		cost = 25,
		requires = { "logic" },
		effect = { unlockGenre = "racing" },
	},
	{
		id = "enemy_ai",
		branch = "genres",
		order = 4,
		name = "ИИ противников",
		nameEn = "Enemy AI",
		description = "Открывает жанр «Стратегия»",
		descriptionEn = "Unlocks the Strategy genre",
		cost = 40,
		requires = { "car_physics" },
		effect = { unlockGenre = "strategy" },
	},
	{
		id = "sports_animation",
		branch = "genres",
		order = 5,
		name = "Анимация спорта",
		nameEn = "Sports animation",
		description = "Открывает жанр «Спорт»",
		descriptionEn = "Unlocks the Sports genre",
		cost = 60,
		requires = { "enemy_ai" },
		effect = { unlockGenre = "sports" },
	},
	{
		id = "atmosphere",
		branch = "genres",
		order = 6,
		name = "Атмосфера",
		nameEn = "Atmosphere",
		description = "Открывает жанр «Хоррор»",
		descriptionEn = "Unlocks the Horror genre",
		cost = 90,
		requires = { "sports_animation" },
		effect = { unlockGenre = "horror" },
	},

	-- Технологии
	{
		id = "easy_engine",
		branch = "tech",
		order = 1,
		name = "Удобный движок",
		nameEn = "Friendly engine",
		description = "Разработка на 10% быстрее",
		descriptionEn = "Development is 10% faster",
		cost = 20,
		requires = {},
		effect = { devTime = -0.1 },
	},
	{
		id = "graphics_3d",
		branch = "tech",
		order = 2,
		name = "3D-графика",
		nameEn = "3D graphics",
		description = "+10% очков графики",
		descriptionEn = "+10% graphics points",
		cost = 50,
		requires = { "easy_engine" },
		effect = { graphicsPoints = 0.1 },
	},
	{
		id = "surround_sound",
		branch = "tech",
		order = 3,
		name = "Объёмный звук",
		nameEn = "Surround sound",
		description = "+10% очков звука",
		descriptionEn = "+10% sound points",
		cost = 50,
		requires = { "easy_engine" },
		effect = { soundPoints = 0.1 },
	},
	{
		id = "online_mode",
		branch = "tech",
		order = 4,
		name = "Онлайн-режим",
		nameEn = "Online mode",
		description = "+15% к доходу с игр",
		descriptionEn = "+15% game revenue",
		cost = 120,
		requires = { "graphics_3d", "surround_sound" },
		effect = { revenue = 0.15 },
	},
	{
		id = "ai_assistant",
		branch = "tech",
		order = 5,
		name = "ИИ-ассистент",
		nameEn = "AI assistant",
		description = "Можно нанять РОБО-9000",
		descriptionEn = "You can hire ROBO-9000",
		cost = 300,
		requires = { "online_mode" },
		effect = { robotHire = true },
	},

	-- Студия
	{
		id = "marketing",
		branch = "studio",
		order = 1,
		name = "Маркетинг",
		nameEn = "Marketing",
		description = "+10% к доходу с игр",
		descriptionEn = "+10% game revenue",
		cost = 30,
		requires = {},
		effect = { revenue = 0.1 },
	},
	{
		id = "test_group",
		branch = "studio",
		order = 2,
		name = "Тест-группа",
		nameEn = "Playtest group",
		description = "После разработки видно примерную оценку",
		descriptionEn = "See an estimated score after development",
		cost = 60,
		requires = { "marketing" },
		effect = { reviewPreview = true },
	},
	{
		id = "second_project",
		branch = "studio",
		order = 3,
		name = "Второй проект",
		nameEn = "Second project",
		description = "Две игры одновременно",
		descriptionEn = "Two games at once",
		cost = 150,
		requires = { "test_group" },
		effect = { projectSlots = 2 },
	},
	{
		id = "publishing",
		branch = "studio",
		order = 4,
		name = "Издательство",
		nameEn = "Publishing",
		description = "Старые игры приносят пассивный доход",
		descriptionEn = "Old games bring passive income",
		cost = 400,
		requires = { "second_project" },
		effect = { publishing = true },
	},
}

Research.list = nodes

Research.byId = {} :: { [string]: Node }
for _, node in nodes do
	Research.byId[node.id] = node
end

-- Узлы ветки в порядке колонки
function Research.branchNodes(branch: Branch): { Node }
	local result = {}
	for _, node in nodes do
		if node.branch == branch then
			table.insert(result, node)
		end
	end
	table.sort(result, function(a, b)
		return a.order < b.order
	end)
	return result
end

-- Все ли зависимости изучены
function Research.requirementsMet(node: Node, owned: { [string]: boolean }): boolean
	for _, id in node.requires do
		if not owned[id] then
			return false
		end
	end
	return true
end

export type Modifiers = {
	devTime: number, -- множитель времени разработки (0.9 = на 10% быстрее)
	graphicsPoints: number, -- множитель очков графики
	soundPoints: number, -- множитель очков звука
	revenue: number, -- множитель дохода
	projectSlots: number,
	robotHire: boolean,
	reviewPreview: boolean,
	publishing: boolean,
}

-- Суммарные модификаторы по набору изученных узлов. Проценты складываются: +10% и +15% = ×1.25
function Research.modifiers(owned: { [string]: boolean }): Modifiers
	local devTime, graphics, sound, revenue = 0, 0, 0, 0
	local result: Modifiers = {
		devTime = 1,
		graphicsPoints = 1,
		soundPoints = 1,
		revenue = 1,
		projectSlots = 1,
		robotHire = false,
		reviewPreview = false,
		publishing = false,
	}
	for _, node in nodes do
		if not owned[node.id] then
			continue
		end
		local e = node.effect
		devTime += e.devTime or 0
		graphics += e.graphicsPoints or 0
		sound += e.soundPoints or 0
		revenue += e.revenue or 0
		if e.projectSlots then
			result.projectSlots = math.max(result.projectSlots, e.projectSlots)
		end
		result.robotHire = result.robotHire or e.robotHire == true
		result.reviewPreview = result.reviewPreview or e.reviewPreview == true
		result.publishing = result.publishing or e.publishing == true
	end
	result.devTime = math.max(1 + devTime, 0.1)
	result.graphicsPoints = 1 + graphics
	result.soundPoints = 1 + sound
	result.revenue = 1 + revenue
	return result
end

return Research
