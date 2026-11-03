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
	desk: boolean?, -- за этим апгрейдом может сидеть сотрудник (один на стол)
	-- Начинка помещения этапа: видна, пока студия на этом этапе (после переезда прячется)
	shellStage: number?,
	-- Переезд на следующий этап: кнопка появится, только когда куплен весь интерьер
	-- и за каждым столом сидит сотрудник (PlotService)
	move: boolean?,
	-- Где стоит на участке 60×60: центр участка = (0, 0, 0), пол = Y 0.5, +Z — к кнопкам (вход).
	-- Модель строится центром основания в (0, 0, 0); nil — модель уже собрана на своём месте.
	position: Vector3?,
	rotation: number?, -- поворот вокруг Y в градусах, 0 — смотрит на +Z
}

-- Порядок, цены и очки — issue #3 (гараж -> офис за 11–15 минут при Config/Economy).
local Upgrades: { Upgrade } = {
	{
		id = "desk1",
		desk = true,
		position = Vector3.new(-12, 0.5, -20),
		rotation = 0,
		name = "Старый стол",
		cost = 0,
		model = "Desk1",
		pointsPerSecond = 1,
	},
	{
		id = "pc1",
		position = Vector3.new(-12, 3.5, -21),
		rotation = 0,
		name = "Компьютер с барахолки",
		cost = 100,
		model = "PC1",
		requires = "desk1",
		pointsPerSecond = 1,
	},
	{
		id = "walls",
		position = Vector3.new(0, 0.5, 0),
		rotation = 0,
		shellStage = 1,
		name = "Стены и свет гаража",
		cost = 250,
		model = "GarageWalls",
		requires = "pc1",
	},
	{
		id = "chair",
		position = Vector3.new(-12, 0.5, -15),
		rotation = 180,
		name = "Геймерское кресло",
		cost = 500,
		model = "Chair",
		requires = "walls",
		pointsPerSecond = 1,
	},
	{
		id = "desk2",
		desk = true,
		position = Vector3.new(4, 0.5, -20),
		rotation = 0,
		name = "Второй стол с ПК",
		cost = 900,
		model = "Desk2",
		requires = "chair",
		pointsPerSecond = 2,
	},
	{
		id = "coffee",
		position = Vector3.new(25, 0.5, -24),
		rotation = -90,
		name = "Кофемашина",
		cost = 1_500,
		model = "Coffee",
		requires = "desk2",
		pointsPerSecond = 1,
	},
	{
		id = "posters",
		position = Vector3.new(0, 3.5, -28.8),
		rotation = 0,
		name = "Постеры и неоновая вывеска",
		cost = 2_500,
		model = "Posters",
		requires = "coffee",
	},
	{
		id = "pcpro",
		position = Vector3.new(4, 3.5, -21),
		rotation = 0,
		name = "Мощный ПК",
		cost = 4_000,
		model = "PCPro",
		requires = "posters",
		pointsPerSecond = 3,
	},
	{
		id = "office",
		position = Vector3.new(0, 0.5, 0),
		rotation = 0,
		shellStage = 2,
		move = true,
		name = "Переезд в офис",
		cost = 8_000,
		model = "Office",
		requires = "pcpro",
	},
}

return Upgrades
