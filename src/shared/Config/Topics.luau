--!strict
-- Темы игр и их совместимость с жанрами.
-- 1.2 = отлично, 1.1 = хорошо, 0.8 = так себе, 0.7 = плохо. Не указан жанр -> 1.0.
-- Список и цены — issue #2.

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
		fit = { action = 1.2, strategy = 1.2, racing = 1.1, casual = 0.8, sports = 0.7 },
		unlockCost = 0,
	},
	fantasy = {
		id = "fantasy",
		name = "Фэнтези",
		fit = { rpg = 1.2, adventure = 1.2, horror = 1.1, simulation = 0.7, racing = 0.7 },
		unlockCost = 0,
	},
	zombies = {
		id = "zombies",
		name = "Зомби",
		fit = { action = 1.2, horror = 1.2, simulation = 0.8, casual = 0.7, sports = 0.7 },
		unlockCost = 0,
	},
	pets = {
		id = "pets",
		name = "Питомцы",
		fit = { casual = 1.2, simulation = 1.2, puzzle = 1.1, action = 0.8, horror = 0.7 },
		unlockCost = 800,
	},
	cars = {
		id = "cars",
		name = "Машины",
		fit = { racing = 1.2, simulation = 1.2, casual = 1.1, horror = 0.8, rpg = 0.7 },
		unlockCost = 800,
	},
	cooking = {
		id = "cooking",
		name = "Кулинария",
		fit = { casual = 1.2, simulation = 1.2, puzzle = 1.1, action = 0.7, horror = 0.7 },
		unlockCost = 800,
	},
	pirates = {
		id = "pirates",
		name = "Пираты",
		fit = { adventure = 1.2, action = 1.1, strategy = 0.8, racing = 0.8, sports = 0.7 },
		unlockCost = 1_500,
	},
	business = {
		id = "business",
		name = "Бизнес",
		fit = { simulation = 1.2, strategy = 1.1, action = 0.7, horror = 0.7 },
		unlockCost = 1_500,
	},
	school = {
		id = "school",
		name = "Школа",
		fit = { simulation = 1.2, casual = 1.1, horror = 1.1, racing = 0.8, strategy = 0.7 },
		unlockCost = 1_500,
	},
	ninja = {
		id = "ninja",
		name = "Ниндзя",
		fit = { action = 1.2, rpg = 1.1, sports = 0.8, simulation = 0.7 },
		unlockCost = 3_000,
	},
	robots = {
		id = "robots",
		name = "Роботы",
		fit = { action = 1.2, strategy = 1.2, puzzle = 1.1, sports = 0.7 },
		unlockCost = 3_000,
	},
	football = {
		id = "football",
		name = "Футбол",
		fit = { sports = 1.2, casual = 1.1, simulation = 1.1, rpg = 0.7, horror = 0.7 },
		unlockCost = 3_000,
	},
	superheroes = {
		id = "superheroes",
		name = "Супергерои",
		fit = { action = 1.2, rpg = 1.2, strategy = 0.8, puzzle = 0.7 },
		unlockCost = 5_000,
	},
	detective = {
		id = "detective",
		name = "Детектив",
		fit = { adventure = 1.2, puzzle = 1.2, horror = 1.1, racing = 0.7, sports = 0.7 },
		unlockCost = 5_000,
	},
	ghosts = {
		id = "ghosts",
		name = "Призраки",
		fit = { horror = 1.2, adventure = 1.1, sports = 0.7, racing = 0.7 },
		unlockCost = 5_000,
	},
}

return Topics
