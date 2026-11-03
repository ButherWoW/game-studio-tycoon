--!strict
-- Жанры игр. Веса показывают, какие направления важнее для жанра (в сумме ~1).
-- Чем ближе распределение очков игрока к весам, тем выше оценка.

export type Genre = {
	id: string,
	name: string,
	weights: { gameplay: number, graphics: number, sound: number, story: number },
	unlockCost: number,
}

local Genres: { [string]: Genre } = {
	action = {
		id = "action",
		name = "Экшен",
		weights = { gameplay = 0.4, graphics = 0.3, sound = 0.2, story = 0.1 },
		unlockCost = 0,
	},
	adventure = {
		id = "adventure",
		name = "Приключения",
		weights = { gameplay = 0.2, graphics = 0.25, sound = 0.15, story = 0.4 },
		unlockCost = 0,
	},
	rpg = {
		id = "rpg",
		name = "RPG",
		weights = { gameplay = 0.3, graphics = 0.2, sound = 0.1, story = 0.4 },
		unlockCost = 5_000,
	},
	simulation = {
		id = "simulation",
		name = "Симулятор",
		weights = { gameplay = 0.5, graphics = 0.2, sound = 0.1, story = 0.2 },
		unlockCost = 5_000,
	},
	strategy = {
		id = "strategy",
		name = "Стратегия",
		weights = { gameplay = 0.55, graphics = 0.15, sound = 0.1, story = 0.2 },
		unlockCost = 15_000,
	},
	casual = {
		id = "casual",
		name = "Казуальная",
		weights = { gameplay = 0.45, graphics = 0.3, sound = 0.2, story = 0.05 },
		unlockCost = 0,
	},
}

return Genres
