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

-- Порядок, цены и очки — issue #3 (гараж -> офис за 11–15 минут при Config/Economy).
local Upgrades: { Upgrade } = {
	{ id = "desk1", name = "Старый стол", cost = 0, model = "Desk1", pointsPerSecond = 1 },
	{
		id = "pc1",
		name = "Компьютер с барахолки",
		cost = 100,
		model = "PC1",
		requires = "desk1",
		pointsPerSecond = 1,
	},
	{
		id = "walls",
		name = "Стены и свет гаража",
		cost = 250,
		model = "GarageWalls",
		requires = "pc1",
	},
	{
		id = "chair",
		name = "Геймерское кресло",
		cost = 500,
		model = "Chair",
		requires = "walls",
		pointsPerSecond = 1,
	},
	{
		id = "desk2",
		name = "Второй стол с ПК",
		cost = 900,
		model = "Desk2",
		requires = "chair",
		pointsPerSecond = 2,
	},
	{
		id = "coffee",
		name = "Кофемашина",
		cost = 1_500,
		model = "Coffee",
		requires = "desk2",
		pointsPerSecond = 1,
	},
	{
		id = "posters",
		name = "Постеры и неоновая вывеска",
		cost = 2_500,
		model = "Posters",
		requires = "coffee",
	},
	{
		id = "pcpro",
		name = "Мощный ПК",
		cost = 4_000,
		model = "PCPro",
		requires = "posters",
		pointsPerSecond = 3,
	},
	{
		id = "office",
		name = "Переезд в офис",
		cost = 8_000,
		model = "Office",
		requires = "pcpro",
	},
}

return Upgrades
