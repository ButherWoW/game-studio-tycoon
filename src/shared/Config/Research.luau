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
	minutes: number, -- сколько длится исследование (реальное время, идёт и офлайн), см. TIMING ниже
}

local Research = {}

local branches: { Branch } = { "genres", "tech", "studio" }
Research.BRANCHES = branches

-- Сколько ОИ даёт выпущенная игра: оценка 1–10 как есть
Research.POINTS_PER_SCORE = 1

-- «Тест-группа»: примерная оценка в окне «Создать игру» — ожидаемая оценка ± PREVIEW_SPREAD
Research.PREVIEW_SPREAD = 1

-- «Издательство»: роялти с последних выпущенных игр, пока игрок онлайн.
-- В минуту = share × сумма дохода последних maxGames игр; выплата раз в intervalSeconds
Research.PUBLISHING = {
	share = 0.01,
	maxGames = 10,
	intervalSeconds = 60,
}

-- TIMING (просьба владельца 05.11: «открытие новой категории и все исследования занимают время»).
-- Узел дерева и платное открытие жанра/темы (UnlockService) идут через одну «лабораторию»:
-- одно активное исследование, ОИ или $ списываются при старте, эффект — по окончании таймера.
-- Таймер по os.time: идёт офлайн и на другом сервере, готовое закрывается при входе.
-- Почему такие числа (minutes у узлов):
--   * Ранние узлы (1-я ступень веток, 10–30 ОИ) — 2–3 мин: новичок видит таймер, но успевает
--     дождаться за пару игр (игра ~30–40 с, Economy.devSeconds).
--   * Средние (40–150 ОИ) — 10–20 мин: одна-две сессии игры, «вернусь — будет готово».
--   * Поздние (300–400 ОИ, атмосфера 90) — 45–75 мин: на них ОИ копятся часами, таймер
--     меньше времени накопления, поэтому прогресс не тормозит, а выход из игры не мешает.
--   * Всё дерево — 290 мин (~4.8 ч) лабораторного времени, жанры/темы за $ — ещё ~1.8 ч (109 мин)
--     (CATEGORY_MINUTES). Это ~25% от ~26.7 ч активной игры до 1-го Rebirth (docs/BALANCE.md),
--     причём таймер идёт и офлайн (между сессиями 18 дней забега), поэтому вехи почти не сдвигаются
--     (tools/balance_sim.py --all моделирует таймер узлов).
-- Ускорения: перк Rebirth «Лаборатория» (RebirthPerks.researchTime, до −30%) и Robux-товары
-- Products.research (−5 мин, −30 мин, «Завершить сейчас»). Кофе на исследования не действует.
-- Отмена — полный возврат ОИ/$: эффект не получен, а таймер и так не ускоряет ничего, кроме себя.
Research.TIMING = {
	-- Пол длительности после всех скидок: «мгновенно» только за Robux
	minSeconds = 30,
	-- Сколько последних секунд считать «почти готово»: «Завершить сейчас» прячем, остаётся −5 мин
	skipHideSeconds = 5 * 60,
}

-- Открытие жанра/темы за $ (Config/Genres, Config/Topics, unlockCost): длительность по цене.
-- Первая подходящая ступень, где cost <= maxCost. Дешёвые темы ($800) — 2 мин, хоррор ($8 000) — 15 мин
Research.CATEGORY_MINUTES = {
	{ maxCost = 1_000, minutes = 2 },
	{ maxCost = 1_500, minutes = 3 },
	{ maxCost = 3_000, minutes = 5 },
	{ maxCost = 5_000, minutes = 10 },
	{ maxCost = math.huge, minutes = 15 },
}

local nodes: { Node } = {
	-- Жанровая ветка: второй, «бесплатный» путь к жанрам (за деньги они тоже открываются).
	-- Узел жанра не изучается, пока не выполнены условия жанра (Genres.requires, shared/UnlockRules)
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
		minutes = 2,
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
		minutes = 3,
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
		minutes = 5,
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
		minutes = 10,
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
		minutes = 20,
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
		minutes = 45,
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
		minutes = 2,
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
		minutes = 10,
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
		minutes = 10,
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
		minutes = 20,
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
		minutes = 60,
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
		minutes = 3,
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
		minutes = 10,
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
		minutes = 15,
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
		minutes = 75,
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

-- ---------- Таймер лаборатории (TIMING) ----------

-- "node" — узел дерева (id = Node.id, плата в ОИ); "genre"/"topic" — открытие за $ (UnlockService)
export type ActiveKind = "node" | "genre" | "topic"

export type Active = {
	kind: ActiveKind,
	id: string,
	startedAt: number, -- os.time старта
	endsAt: number, -- os.time конца (ускорения за Robux его двигают, но не раньше «сейчас»)
	paid: number, -- сколько списано (ОИ или $) — столько вернёт отмена
}

-- profile.research (DataService.defaultProfile, проверка — Research.sanitize)
export type Data = {
	points: number,
	owned: { [string]: boolean },
	active: Active?,
	-- Ускорения за Robux, купленные без активного исследования: применятся к следующему
	creditSeconds: number,
	creditSkips: number,
}

function Research.defaultData(): Data
	return { points = 0, owned = {}, active = nil, creditSeconds = 0, creditSkips = 0 }
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Сохранённые данные → корректные (битые поля — по умолчанию; изученное не теряется)
function Research.sanitize(raw: any): Data
	local data = Research.defaultData()
	if type(raw) ~= "table" then
		return data
	end
	if finite(raw.points) then
		data.points = math.max(math.floor(raw.points), 0)
	end
	if type(raw.owned) == "table" then
		for id, value in raw.owned do
			-- Неизвестные id (узлы из будущих версий) не удаляем
			if type(id) == "string" and value == true then
				data.owned[id] = true
			end
		end
	end
	local a = raw.active
	if
		type(a) == "table"
		and (a.kind == "node" or a.kind == "genre" or a.kind == "topic")
		and type(a.id) == "string"
		and #a.id <= 64
		and finite(a.startedAt)
		and finite(a.endsAt)
		and finite(a.paid)
	then
		data.active = {
			kind = a.kind,
			id = a.id,
			startedAt = a.startedAt,
			endsAt = a.endsAt,
			paid = math.max(a.paid, 0),
		}
	end
	if finite(raw.creditSeconds) then
		data.creditSeconds = math.max(math.floor(raw.creditSeconds), 0)
	end
	if finite(raw.creditSkips) then
		data.creditSkips = math.max(math.floor(raw.creditSkips), 0)
	end
	return data
end

-- Минуты открытия жанра/темы за $ по цене (CATEGORY_MINUTES)
function Research.categoryMinutes(unlockCost: number): number
	for _, tier in Research.CATEGORY_MINUTES do
		if unlockCost <= tier.maxCost then
			return tier.minutes
		end
	end
	return Research.CATEGORY_MINUTES[#Research.CATEGORY_MINUTES].minutes
end

-- Длительность в секундах: базовые минуты × (1 − ускорение «Лаборатории»), не меньше minSeconds
function Research.durationSeconds(minutes: number, timeReduction: number): number
	local base = math.max(minutes, 0) * 60
	local factor = 1 - math.clamp(timeReduction, 0, 0.5)
	return math.max(math.floor(base * factor + 0.5), Research.TIMING.minSeconds)
end

-- Время «1:05:09» / «4:07» (одинаково на всех языках)
function Research.formatTime(seconds: number): string
	local s = math.max(math.ceil(seconds), 0)
	local h = s // 3600
	if h > 0 then
		return string.format("%d:%02d:%02d", h, (s % 3600) // 60, s % 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

return Research
