--!strict
-- Жанры игр. Веса показывают, какие направления важнее для жанра (в сумме 1).
-- Чем ближе распределение очков игрока к весам, тем выше оценка.
-- Список и цены — issue #2. Открытие: 3 жанра со старта (unlockCost = 0), остальные — за деньги
-- (UnlockService) или исследованием (Config/Research), но только когда выполнены условия
-- requires (проверяет shared/UnlockRules): этап студии, число игр, лучшая оценка и т.д.

export type Genre = {
	id: string,
	name: string,
	nameEn: string,
	weights: { gameplay: number, graphics: number, sound: number, story: number },
	unlockCost: number,
	requires: Requires?,
}

-- Условия открытия (все должны выполняться). Описание видов — shared/UnlockRules
export type Requires = {
	studioLevel: number?,
	gamesReleased: number?,
	bestScore: number?,
	genreGames: { genre: string, count: number }?,
	hits: number?,
	employees: number?,
}

local Genres: { [string]: Genre } = {
	action = {
		id = "action",
		name = "Экшен",
		nameEn = "Action",
		weights = { gameplay = 0.4, graphics = 0.3, sound = 0.2, story = 0.1 },
		unlockCost = 0,
	},
	adventure = {
		id = "adventure",
		name = "Приключения",
		nameEn = "Adventure",
		weights = { gameplay = 0.2, graphics = 0.25, sound = 0.15, story = 0.4 },
		unlockCost = 0,
	},
	casual = {
		id = "casual",
		name = "Казуальная",
		nameEn = "Casual",
		weights = { gameplay = 0.45, graphics = 0.3, sound = 0.2, story = 0.05 },
		unlockCost = 0,
	},
	rpg = {
		id = "rpg",
		name = "RPG",
		nameEn = "RPG",
		weights = { gameplay = 0.3, graphics = 0.2, sound = 0.1, story = 0.4 },
		unlockCost = 1_000,
		requires = { genreGames = { genre = "adventure", count = 3 } },
	},
	simulation = {
		id = "simulation",
		name = "Симулятор",
		nameEn = "Simulation",
		weights = { gameplay = 0.5, graphics = 0.2, sound = 0.1, story = 0.2 },
		unlockCost = 1_000,
		requires = { gamesReleased = 5 },
	},
	puzzle = {
		id = "puzzle",
		name = "Головоломка",
		nameEn = "Puzzle",
		weights = { gameplay = 0.6, graphics = 0.15, sound = 0.15, story = 0.1 },
		unlockCost = 2_000,
		requires = { bestScore = 7 },
	},
	racing = {
		id = "racing",
		name = "Гонки",
		nameEn = "Racing",
		weights = { gameplay = 0.4, graphics = 0.35, sound = 0.2, story = 0.05 },
		unlockCost = 2_000,
		requires = { studioLevel = 2 },
	},
	strategy = {
		id = "strategy",
		name = "Стратегия",
		nameEn = "Strategy",
		weights = { gameplay = 0.55, graphics = 0.15, sound = 0.1, story = 0.2 },
		unlockCost = 3_500,
		requires = { studioLevel = 2, employees = 5 },
	},
	sports = {
		id = "sports",
		name = "Спорт",
		nameEn = "Sports",
		weights = { gameplay = 0.5, graphics = 0.3, sound = 0.15, story = 0.05 },
		unlockCost = 5_000,
		requires = { studioLevel = 3 },
	},
	horror = {
		id = "horror",
		name = "Хоррор",
		nameEn = "Horror",
		weights = { gameplay = 0.2, graphics = 0.25, sound = 0.3, story = 0.25 },
		unlockCost = 8_000,
		requires = { studioLevel = 4 },
	},
}

return Genres
