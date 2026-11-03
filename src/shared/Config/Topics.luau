--!strict
-- Темы игр и их совместимость с жанрами (множитель оценки).
-- 1.2 = отлично, 1.0 = нормально, 0.7 = плохо. Не указан жанр -> 1.0.

export type Topic = {
	id: string,
	name: string,
	fit: { [string]: number },
	unlockCost: number,
}

local Topics: { [string]: Topic } = {
	space = {
		id = "space",
		name = "Космос",
		fit = { action = 1.2, strategy = 1.2, casual = 0.8 },
		unlockCost = 0,
	},
	fantasy = {
		id = "fantasy",
		name = "Фэнтези",
		fit = { rpg = 1.2, adventure = 1.2, simulation = 0.7 },
		unlockCost = 0,
	},
	zombies = {
		id = "zombies",
		name = "Зомби",
		fit = { action = 1.2, casual = 0.7, simulation = 0.8 },
		unlockCost = 0,
	},
	cars = {
		id = "cars",
		name = "Машины",
		fit = { simulation = 1.2, casual = 1.1, rpg = 0.7 },
		unlockCost = 2_000,
	},
	pets = {
		id = "pets",
		name = "Питомцы",
		fit = { casual = 1.2, simulation = 1.2, action = 0.8 },
		unlockCost = 2_000,
	},
	pirates = {
		id = "pirates",
		name = "Пираты",
		fit = { adventure = 1.2, action = 1.1, strategy = 0.9 },
		unlockCost = 4_000,
	},
	business = {
		id = "business",
		name = "Бизнес",
		fit = { simulation = 1.2, strategy = 1.1, action = 0.7 },
		unlockCost = 4_000,
	},
	ninja = {
		id = "ninja",
		name = "Ниндзя",
		fit = { action = 1.2, rpg = 1.1, simulation = 0.7 },
		unlockCost = 8_000,
	},
}

return Topics
