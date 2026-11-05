--!strict
-- Достижения (AchievementService). Прогресс — счётчики profile.achievements.stats[stat],
-- Rebirth их не сбрасывает. Достижение выполнено, когда stats[stat] >= target; награда
-- выдаётся один раз через RewardService.grant (деньги — в минутах дохода, растут с этапом).
-- Тексты — ключи ach_<id> и ach_<id>_desc в Texts и Locales; name/nameEn — запасные.
--
-- Счётчики (stat):
--   по профилю (опрос, хранится максимум): garage, stage, upgrades, posters, research, games,
--     bestScore, employees, skillMax, legend, genresOwned, rebirths, steals, catches, caught;
--   по событиям: score9 (игр 9+), hitGames (игр >= HitCartridges.minScore), combos (разных
--     жанр/тема), qtePerfect (идеальных быстрых событий), earned (доход с релизов), expoWins,
--     loansRepaid, strikes (пережитых забастовок), days (дней со входом), flops (игр с оценкой
--     <= 2), laptopStars (игр 8+ на ноутбуке в парке), likesReceived (лайков студии, TourService).
-- tier: 1 бронза, 2 серебро, 3 золото (nil — без медали).
-- badgeId > 0 — ещё и значок Roblox (BadgeService); id заведёт Dev 1 в badgeIds ниже.
-- hidden — до получения в окне «???».

local Genres = require(script.Parent.Genres)
local Rewards = require(script.Parent.Rewards)
local Research = require(script.Parent.Research)
local Skills = require(script.Parent.Skills)
local Universe = require(script.Parent.Universe)

export type Reward = Rewards.Reward
export type Category = "studio" | "games" | "team" | "money" | "rivals" | "special"

export type Achievement = {
	id: string,
	category: Category,
	stat: string,
	target: number,
	tier: number?,
	name: string,
	nameEn: string,
	reward: Reward,
	badgeId: number,
	hidden: boolean?,
}

local Achievements = {}

-- Порядок вкладок окна
Achievements.categories = { "studio", "games", "team", "money", "rivals", "special" } :: { Category }

-- Достижения за прогресс до появления системы (первый вход): выдаём всё заслуженное,
-- но награды суммой не больше этого (иначе ветеран получил бы сразу часы дохода)
Achievements.backfillCap = {
	incomeMinutes = 30,
	researchPoints = 30,
	coffeeMinutes = 30,
} :: { [string]: number }

-- Деньги на счётчике earned и в описаниях: краткая запись
Achievements.moneyStats = { earned = true } :: { [string]: boolean }

-- Значки Roblox по id достижения: test — вселенная v2, main — основная игра (docs/IDS.md).
-- Нет в таблице или 0 — без значка. Пример: office_2 = { test = 123, main = 0 },
local badgeIds: { [string]: Universe.Pair } = {}

local genreCount = 0
for _ in Genres do
	genreCount += 1
end

local function ach(
	id: string,
	category: Category,
	stat: string,
	target: number,
	tier: number?,
	name: string,
	nameEn: string,
	reward: Reward,
	hidden: boolean?
): Achievement
	return {
		id = id,
		category = category,
		stat = stat,
		target = target,
		tier = tier,
		name = name,
		nameEn = nameEn,
		reward = reward,
		badgeId = Universe.pick(badgeIds[id]),
		hidden = hidden,
	}
end

Achievements.list = {
	-- Студия
	ach(
		"garage",
		"studio",
		"garage",
		1,
		nil,
		"Свой угол",
		"A Place of Our Own",
		{ incomeMinutes = 1 }
	),
	ach(
		"office_1",
		"studio",
		"stage",
		2,
		1,
		"Переезд в офис",
		"Moving to an Office",
		{ incomeMinutes = 4 }
	),
	ach("office_2", "studio", "stage", 3, 2, "Второй этаж", "Second Floor", { incomeMinutes = 8 }),
	ach("office_3", "studio", "stage", 4, 3, "Третий этаж", "Third Floor", { incomeMinutes = 15 }),
	ach(
		"upgrades_5",
		"studio",
		"upgrades",
		5,
		1,
		"Обустройство",
		"Settling In",
		{ incomeMinutes = 2 }
	),
	ach(
		"upgrades_30",
		"studio",
		"upgrades",
		30,
		3,
		"Студия мечты",
		"Dream Studio",
		{ incomeMinutes = 15 }
	),
	ach(
		"poster_1",
		"studio",
		"posters",
		1,
		nil,
		"Искусство на стене",
		"Wall Art",
		{ coffeeMinutes = 10 }
	),
	ach(
		"research_all",
		"studio",
		"research",
		#Research.list,
		nil,
		"Мозговой центр",
		"Think Tank",
		{
			researchPoints = 20,
		}
	),

	-- Игры
	ach("games_10", "games", "games", 10, 1, "Разогрев", "Warming Up", { incomeMinutes = 2 }),
	ach("games_100", "games", "games", 100, 2, "Конвейер", "Assembly Line", { incomeMinutes = 10 }),
	ach(
		"games_1000",
		"games",
		"games",
		1000,
		3,
		"Легенда индустрии",
		"Industry Legend",
		{ incomeMinutes = 30 }
	),
	ach(
		"score_8",
		"games",
		"bestScore",
		8,
		1,
		"Хорошая игра",
		"A Good Game",
		{ incomeMinutes = 2 }
	),
	ach(
		"score_9",
		"games",
		"bestScore",
		9,
		2,
		"Отличная игра",
		"A Great Game",
		{ researchPoints = 5 }
	),
	ach("score_10", "games", "bestScore", 10, 3, "Шедевр", "Masterpiece", { incomeMinutes = 15 }),
	ach(
		"score9_3",
		"games",
		"score9",
		3,
		nil,
		"Без случайностей",
		"No Fluke",
		{ coffeeMinutes = 15 }
	),
	ach("hits_10", "games", "hitGames", 10, 1, "Хитмейкер", "Hitmaker", { incomeMinutes = 3 }),
	ach(
		"combos_10",
		"games",
		"combos",
		10,
		1,
		"Экспериментатор",
		"Experimenter",
		{ researchPoints = 5 }
	),
	ach(
		"genres_all",
		"games",
		"genresOwned",
		genreCount,
		nil,
		"Все жанры",
		"Every Genre",
		{ incomeMinutes = 10 }
	),
	ach(
		"qte_10",
		"games",
		"qtePerfect",
		10,
		1,
		"Быстрые руки",
		"Quick Hands",
		{ coffeeMinutes = 10 }
	),
	ach(
		"qte_100",
		"games",
		"qtePerfect",
		100,
		3,
		"Реакция кота",
		"Cat Reflexes",
		{ coffeeMinutes = 30 }
	),

	-- Команда
	ach(
		"hire_1",
		"team",
		"employees",
		1,
		1,
		"Первый сотрудник",
		"First Hire",
		{ incomeMinutes = 1 }
	),
	ach("hire_5", "team", "employees", 5, 2, "Команда", "A Real Team", { incomeMinutes = 5 }),
	ach(
		"hire_10",
		"team",
		"employees",
		10,
		3,
		"Большая студия",
		"Big Studio",
		{ incomeMinutes = 15 }
	),
	ach(
		"skill_max",
		"team",
		"skillMax",
		Skills.maxLevel,
		nil,
		"Профи",
		"True Pro",
		{ researchPoints = 10 }
	),
	ach(
		"legend",
		"team",
		"legend",
		1,
		nil,
		"Легенда в штате",
		"A Legend on Staff",
		{ coffeeMinutes = 15 }
	),
	ach(
		"strike_1",
		"team",
		"strikes",
		1,
		nil,
		"Пережили забастовку",
		"Strike Survivors",
		{ coffeeMinutes = 10 }
	),

	-- Деньги
	ach(
		"earn_10k",
		"money",
		"earned",
		10_000,
		1,
		"Первые деньги",
		"First Money",
		{ incomeMinutes = 2 }
	),
	ach(
		"earn_1m",
		"money",
		"earned",
		1_000_000,
		2,
		"Миллионер",
		"Millionaire",
		{ incomeMinutes = 10 }
	),
	ach("earn_100m", "money", "earned", 100_000_000, 3, "Магнат", "Tycoon", { incomeMinutes = 30 }),
	ach(
		"loan_repaid",
		"money",
		"loansRepaid",
		1,
		nil,
		"Долг погашен",
		"Debt Free",
		{ incomeMinutes = 3 }
	),

	-- Соперники и хиты
	ach(
		"expo_1",
		"rivals",
		"expoWins",
		1,
		1,
		"Звезда выставки",
		"Expo Star",
		{ incomeMinutes = 3 }
	),
	ach(
		"expo_5",
		"rivals",
		"expoWins",
		5,
		2,
		"Любимец публики",
		"Crowd Favorite",
		{ incomeMinutes = 8 }
	),
	ach(
		"expo_25",
		"rivals",
		"expoWins",
		25,
		3,
		"Король выставок",
		"Expo King",
		{ incomeMinutes = 20 }
	),
	ach(
		"steal_1",
		"rivals",
		"steals",
		1,
		1,
		"Ловкие руки",
		"Sticky Fingers",
		{ coffeeMinutes = 10 }
	),
	ach(
		"steal_10",
		"rivals",
		"steals",
		10,
		2,
		"Гроза полок",
		"Shelf Raider",
		{ incomeMinutes = 5 }
	),
	ach("catch_1", "rivals", "catches", 1, 1, "Попался!", "Gotcha!", { coffeeMinutes = 10 }),
	ach("catch_10", "rivals", "catches", 10, 2, "Охрана", "Security", { incomeMinutes = 5 }),

	-- Особые
	ach(
		"rebirth_1",
		"special",
		"rebirths",
		1,
		1,
		"Новое начало",
		"Fresh Start",
		{ researchPoints = 5 }
	),
	ach("rebirth_3", "special", "rebirths", 3, 2, "Ветеран", "Veteran", { researchPoints = 10 }),
	ach(
		"rebirth_10",
		"special",
		"rebirths",
		10,
		3,
		"Бессмертная студия",
		"Immortal Studio",
		{ researchPoints = 25 }
	),
	ach("days_7", "special", "days", 7, 1, "Неделя в деле", "One Week In", { coffeeMinutes = 15 }),
	ach("days_30", "special", "days", 30, 3, "Верный фанат", "Loyal Fan", { incomeMinutes = 15 }),
	-- Лайки студии от посетителей (TourService)
	ach(
		"likes_10",
		"special",
		"likesReceived",
		10,
		1,
		"Уютная студия",
		"Cozy Studio",
		{ coffeeMinutes = 10 }
	),
	ach(
		"likes_100",
		"special",
		"likesReceived",
		100,
		2,
		"Звезда района",
		"Local Star",
		{ incomeMinutes = 15 }
	),
	ach(
		"likes_1000",
		"special",
		"likesReceived",
		1000,
		3,
		"Культовая студия",
		"Cult Studio",
		{ researchPoints = 25 }
	),
	-- Секретные
	ach("flop", "special", "flops", 1, nil, "Это провал", "Total Flop", { coffeeMinutes = 5 }, true),
	ach(
		"got_caught",
		"special",
		"caught",
		1,
		nil,
		"Пойман с поличным",
		"Caught Red-Handed",
		{ coffeeMinutes = 5 },
		true
	),
	ach(
		"laptop_star",
		"special",
		"laptopStars",
		1,
		nil,
		"Гений с ноутбуком",
		"Laptop Genius",
		{ incomeMinutes = 2 },
		true
	),
} :: { Achievement }

-- Оценка игры <= этого — «провал» (секретное «Это провал»)
Achievements.flopScore = 2
-- Оценка игры на ноутбуке в парке >= этого — «Гений с ноутбуком»
Achievements.laptopStarScore = 8
-- Оценка для счётчика score9
Achievements.greatScore = 9

local byId: { [string]: Achievement } = {}
for _, a in Achievements.list do
	byId[a.id] = a
end

function Achievements.find(id: string): Achievement?
	return byId[id]
end

return Achievements
