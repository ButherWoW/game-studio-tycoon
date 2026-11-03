--!strict
-- Жанры игр. Веса показывают, какие направления важнее для жанра (в сумме 1).
-- Чем ближе распределение очков игрока к весам, тем выше оценка.
-- Список и цены — issue #2. Открытие: 3 жанра со старта, остальные за деньги.

export type Genre = {
	id: string,
	name: string,
	nameEn: string,
	weights: { gameplay: number, graphics: number, sound: number, story: number },
	unlockCost: number,
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
	},
	simulation = {
		id = "simulation",
		name = "Симулятор",
		nameEn = "Simulation",
		weights = { gameplay = 0.5, graphics = 0.2, sound = 0.1, story = 0.2 },
		unlockCost = 1_000,
	},
	puzzle = {
		id = "puzzle",
		name = "Головоломка",
		nameEn = "Puzzle",
		weights = { gameplay = 0.6, graphics = 0.15, sound = 0.15, story = 0.1 },
		unlockCost = 2_000,
	},
	racing = {
		id = "racing",
		name = "Гонки",
		nameEn = "Racing",
		weights = { gameplay = 0.4, graphics = 0.35, sound = 0.2, story = 0.05 },
		unlockCost = 2_000,
	},
	strategy = {
		id = "strategy",
		name = "Стратегия",
		nameEn = "Strategy",
		weights = { gameplay = 0.55, graphics = 0.15, sound = 0.1, story = 0.2 },
		unlockCost = 3_500,
	},
	sports = {
		id = "sports",
		name = "Спорт",
		nameEn = "Sports",
		weights = { gameplay = 0.5, graphics = 0.3, sound = 0.15, story = 0.05 },
		unlockCost = 5_000,
	},
	horror = {
		id = "horror",
		name = "Хоррор",
		nameEn = "Horror",
		weights = { gameplay = 0.2, graphics = 0.25, sound = 0.3, story = 0.25 },
		unlockCost = 8_000,
	},
}

return Genres
