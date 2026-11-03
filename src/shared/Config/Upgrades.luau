--!strict
-- Тайкун-кнопки на участке. model — имя модели в ServerStorage.Upgrades.
-- requires — что должно быть куплено раньше (кнопка появится после этого).

export type Upgrade = {
	id: string,
	name: string,
	cost: number,
	model: string,
	requires: string?,
	pointsPerSecond: number?, -- рабочее место добавляет очки разработки
}

local Upgrades: { Upgrade } = {
	{ id = "desk1", name = "Старый стол", cost = 0, model = "Desk1", pointsPerSecond = 1 },
	{
		id = "pc1",
		name = "Компьютер",
		cost = 250,
		model = "PC1",
		requires = "desk1",
		pointsPerSecond = 1,
	},
	{ id = "walls", name = "Стены гаража", cost = 600, model = "GarageWalls", requires = "pc1" },
	{
		id = "desk2",
		name = "Второй стол",
		cost = 1_500,
		model = "Desk2",
		requires = "walls",
		pointsPerSecond = 2,
	},
	{ id = "coffee", name = "Кофемашина", cost = 3_000, model = "Coffee", requires = "desk2" },
	{
		id = "office",
		name = "Переезд в офис",
		cost = 25_000,
		model = "Office",
		requires = "coffee",
	},
}

return Upgrades
