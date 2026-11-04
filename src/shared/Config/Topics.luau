--!strict
-- Темы игр и их совместимость с жанрами.
-- 1.2 = отлично, 1.1 = хорошо, 0.8 = так себе, 0.7 = плохо. Не указан жанр -> 1.0.
-- Список и цены — issue #2.
-- seasonal = id ивента (Config/Holidays): тема открыта бесплатно только во время ивента
-- (HolidayService выдаёт и забирает её), не продаётся и не попадает в тренды.

export type Topic = {
	id: string,
	name: string,
	nameEn: string,
	fit: { [string]: number },
	unlockCost: number,
	seasonal: string?,
}

local Topics: { [string]: Topic } = {
	space = {
		id = "space",
		name = "Космос",
		nameEn = "Space",
		fit = { action = 1.2, strategy = 1.2, racing = 1.1, casual = 0.8, sports = 0.7 },
		unlockCost = 0,
	},
	fantasy = {
		id = "fantasy",
		name = "Фэнтези",
		nameEn = "Fantasy",
		fit = { rpg = 1.2, adventure = 1.2, horror = 1.1, simulation = 0.7, racing = 0.7 },
		unlockCost = 0,
	},
	zombies = {
		id = "zombies",
		name = "Зомби",
		nameEn = "Zombies",
		fit = { action = 1.2, horror = 1.2, simulation = 0.8, casual = 0.7, sports = 0.7 },
		unlockCost = 0,
	},
	pets = {
		id = "pets",
		name = "Питомцы",
		nameEn = "Pets",
		fit = { casual = 1.2, simulation = 1.2, puzzle = 1.1, action = 0.8, horror = 0.7 },
		unlockCost = 800,
	},
	cars = {
		id = "cars",
		name = "Машины",
		nameEn = "Cars",
		fit = { racing = 1.2, simulation = 1.2, casual = 1.1, horror = 0.8, rpg = 0.7 },
		unlockCost = 800,
	},
	cooking = {
		id = "cooking",
		name = "Кулинария",
		nameEn = "Cooking",
		fit = { casual = 1.2, simulation = 1.2, puzzle = 1.1, action = 0.7, horror = 0.7 },
		unlockCost = 800,
	},
	pirates = {
		id = "pirates",
		name = "Пираты",
		nameEn = "Pirates",
		fit = { adventure = 1.2, action = 1.1, strategy = 0.8, racing = 0.8, sports = 0.7 },
		unlockCost = 1_500,
	},
	business = {
		id = "business",
		name = "Бизнес",
		nameEn = "Business",
		fit = { simulation = 1.2, strategy = 1.1, action = 0.7, horror = 0.7 },
		unlockCost = 1_500,
	},
	school = {
		id = "school",
		name = "Школа",
		nameEn = "School",
		fit = { simulation = 1.2, casual = 1.1, horror = 1.1, racing = 0.8, strategy = 0.7 },
		unlockCost = 1_500,
	},
	ninja = {
		id = "ninja",
		name = "Ниндзя",
		nameEn = "Ninja",
		fit = { action = 1.2, rpg = 1.1, sports = 0.8, simulation = 0.7 },
		unlockCost = 3_000,
	},
	robots = {
		id = "robots",
		name = "Роботы",
		nameEn = "Robots",
		fit = { action = 1.2, strategy = 1.2, puzzle = 1.1, sports = 0.7 },
		unlockCost = 3_000,
	},
	football = {
		id = "football",
		name = "Футбол",
		nameEn = "Football",
		fit = { sports = 1.2, casual = 1.1, simulation = 1.1, rpg = 0.7, horror = 0.7 },
		unlockCost = 3_000,
	},
	superheroes = {
		id = "superheroes",
		name = "Супергерои",
		nameEn = "Superheroes",
		fit = { action = 1.2, rpg = 1.2, strategy = 0.8, puzzle = 0.7 },
		unlockCost = 5_000,
	},
	detective = {
		id = "detective",
		name = "Детектив",
		nameEn = "Detective",
		fit = { adventure = 1.2, puzzle = 1.2, horror = 1.1, racing = 0.7, sports = 0.7 },
		unlockCost = 5_000,
	},
	ghosts = {
		id = "ghosts",
		name = "Призраки",
		nameEn = "Ghosts",
		fit = { horror = 1.2, adventure = 1.1, sports = 0.7, racing = 0.7 },
		unlockCost = 5_000,
	},
	pumpkins = {
		id = "pumpkins",
		name = "Тыквы",
		nameEn = "Pumpkins",
		fit = { horror = 1.2, casual = 1.1, adventure = 1.1, sports = 0.7, racing = 0.8 },
		unlockCost = 0,
		seasonal = "halloween",
	},
	newyear = {
		id = "newyear",
		name = "Новый год",
		nameEn = "New Year",
		fit = { casual = 1.2, adventure = 1.1, simulation = 1.1, horror = 0.7, strategy = 0.8 },
		unlockCost = 0,
		seasonal = "newyear",
	},
}

return Topics
