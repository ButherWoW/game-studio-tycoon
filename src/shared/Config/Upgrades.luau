--!strict
-- Тайкун-кнопки на участке. model — имя модели в ServerStorage.Upgrades.
-- requires — что должно быть куплено раньше (кнопка появится после этого).

local Stages = require(script.Parent.Stages)

export type Upgrade = {
	id: string,
	name: string,
	cost: number,
	model: string,
	requires: string?,
	pointsPerSecond: number?, -- рабочее место добавляет очки разработки (больше очков — выше оценка)
	speed: number?, -- на сколько быстрее делаются игры: 0.05 = −5% времени (сумма, предел в Economy)
	reviewBonus: number?, -- прибавка к оценке каждой игры (декор и атмосфера)
	desk: boolean?, -- за этим апгрейдом может сидеть сотрудник (один на стол)
	-- Начинка помещения этапа: видна, пока студия на этом этапе (после переезда прячется).
	-- Только гараж: этажи офиса стоят друг на друге, их интерьер не прячется
	shellStage: number?,
	-- С какого этапа студии предмет виден и продаётся (nil — с гаража). Интерьер этажей офиса:
	-- stage = номер этапа, стоит на высоте своего этажа (Stages.floorY) и остаётся навсегда
	stage: number?,
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
		-- Стол игрока: за ним он сам сидит и делает игры (PcSeat), сотрудников сюда не сажаем
		position = Vector3.new(-12, 0.5, -20),
		rotation = 0,
		name = "Старый стол",
		cost = 0,
		model = "Desk1",
		pointsPerSecond = 1,
	},
	{
		id = "pc1",
		speed = 0.05,
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
		speed = 0.05,
		reviewBonus = 0.2,
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
		speed = 0.05,
		position = Vector3.new(-12, 0.5, -17.2),
		rotation = 180,
		name = "Геймерское кресло",
		cost = 500,
		model = "Chair",
		requires = "walls",
		pointsPerSecond = 1,
	},
	{
		id = "desk2",
		speed = 0.05,
		desk = true,
		-- Гаражный стол после переезда прячется: сотрудник за ним пересаживается за стол офиса
		shellStage = 1,
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
		speed = 0.1,
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
		reviewBonus = 0.3,
		position = Vector3.new(0, 3.5, -28.8),
		rotation = 0,
		name = "Постеры и неоновая вывеска",
		cost = 2_500,
		model = "Posters",
		requires = "coffee",
	},
	{
		id = "pcpro",
		speed = 0.1,
		-- Стоит на гаражном столе desk2 и прячется вместе с ним
		shellStage = 1,
		position = Vector3.new(4, 3.5, -21),
		rotation = 0,
		name = "Мощный ПК",
		cost = 3_000,
		model = "PCPro",
		requires = "posters",
		pointsPerSecond = 3,
	},
	{
		id = "office",
		speed = 0.1,
		reviewBonus = 0.5,
		position = Vector3.new(0, 0.5, 0),
		rotation = 0,
		-- Оболочка 1-го этажа: остаётся, когда открываются 2-й и 3-й этажи над ней
		move = true,
		name = "Переезд в офис",
		cost = 6_500,
		model = "Office",
		requires = "pcpro",
	},
}

-- ===== Интерьер офиса, этажа и небоскрёба (задача 3.7) =====
-- Покупается по цепочке requires после переезда; переезд дальше — когда куплен весь интерьер
-- этапа и за каждым столом сидит сотрудник. Цены: офис → этаж ~40–50 мин, этаж → небоскрёб
-- ~2 ч (симуляция в PR). Столов сотрудников: гараж 1, офис 3, этаж 7, небоскрёб 11
-- (+ стол игрока desk1 — по #8 «2 / 4 / 8 / 12»).
local function interior(
	stage: number,
	requires: string?,
	id: string,
	name: string,
	cost: number,
	model: string,
	x: number,
	z: number,
	rotation: number,
	extra: { pointsPerSecond: number?, speed: number?, reviewBonus: number? }
): Upgrade
	return {
		id = id,
		name = name,
		cost = cost,
		model = model,
		requires = requires,
		stage = stage,
		desk = extra.pointsPerSecond ~= nil,
		pointsPerSecond = extra.pointsPerSecond,
		speed = extra.speed,
		reviewBonus = extra.reviewBonus,
		-- На полу своего этажа: этажи стоят друг на друге
		position = Vector3.new(x, 0.5 + Stages[stage].floorY, z),
		rotation = rotation,
	}
end

-- Столы смотрят на +Z (сотрудник садится со стороны +Z). Свободно от кнопок (+Z 22..29),
-- полки хитов (−27.6, −15), стола игрока (−12, −20), кофемашины (25, −24) и мебели модели этапа.
local OFFICE_DESK = { pointsPerSecond = 3 }
local FLOOR_DESK = { pointsPerSecond = 5 }
local SKY_DESK = { pointsPerSecond = 8 }

local stageInterior: { { any } } = {
	-- Офис: 3 стола, кулер, переговорка ($10–32k)
	{
		2,
		"office",
		"officeDesk1",
		"Офисный стол с ПК",
		10_000,
		"OfficeDesk",
		2,
		-20,
		0,
		OFFICE_DESK,
	},
	{
		2,
		"officeDesk1",
		"cooler",
		"Кулер с водой",
		14_000,
		"Cooler",
		26,
		-12,
		-90,
		{ speed = 0.05, reviewBonus = 0.1 },
	},
	{
		2,
		"cooler",
		"officeDesk2",
		"Второй офисный стол",
		18_000,
		"OfficeDesk",
		12,
		-20,
		0,
		OFFICE_DESK,
	},
	{
		2,
		"officeDesk2",
		"officeDesk3",
		"Третий офисный стол",
		26_000,
		"OfficeDesk",
		-4,
		-8,
		0,
		OFFICE_DESK,
	},
	{
		2,
		"officeDesk3",
		"meetingRoom",
		"Переговорка",
		32_000,
		"MeetingRoom",
		-14,
		10,
		0,
		{ speed = 0.05, reviewBonus = 0.3 },
	},
	-- Этаж: 7 столов, серверная, зона отдыха ($20–55k)
	{
		3,
		nil,
		"floorDesk1",
		"Рабочее место: ряд 1",
		20_000,
		"FloorDesk",
		0,
		-20,
		0,
		FLOOR_DESK,
	},
	{
		3,
		"floorDesk1",
		"floorDesk2",
		"Рабочее место: ряд 1, второе",
		25_000,
		"FloorDesk",
		9,
		-20,
		0,
		FLOOR_DESK,
	},
	{
		3,
		"floorDesk2",
		"serverRoom",
		"Серверная",
		35_000,
		"ServerRoom",
		26.5,
		-14,
		-90,
		{ speed = 0.05, reviewBonus = 0.2 },
	},
	{
		3,
		"serverRoom",
		"floorDesk3",
		"Рабочее место: ряд 1, третье",
		30_000,
		"FloorDesk",
		18,
		-20,
		0,
		FLOOR_DESK,
	},
	{
		3,
		"floorDesk3",
		"floorDesk4",
		"Рабочее место: ряд 2",
		35_000,
		"FloorDesk",
		-12,
		-6,
		0,
		FLOOR_DESK,
	},
	{ 3, "floorDesk4", "lounge", "Зона отдыха", 55_000, "Lounge", 2, 11, 0, { reviewBonus = 0.3 } },
	{
		3,
		"lounge",
		"floorDesk5",
		"Рабочее место: ряд 2, второе",
		40_000,
		"FloorDesk",
		-2,
		-6,
		0,
		FLOOR_DESK,
	},
	{
		3,
		"floorDesk5",
		"floorDesk6",
		"Рабочее место: ряд 2, третье",
		45_000,
		"FloorDesk",
		8,
		-6,
		0,
		FLOOR_DESK,
	},
	{
		3,
		"floorDesk6",
		"floorDesk7",
		"Рабочее место: ряд 2, четвёртое",
		50_000,
		"FloorDesk",
		18,
		-6,
		0,
		FLOOR_DESK,
	},
	-- Небоскрёб: 11 столов, студия звукозаписи, арт-стена ($400k–1.5M)
	{ 4, nil, "skyDesk1", "Топ-место 1", 400_000, "SkyDesk", -3, -20, 0, SKY_DESK },
	{ 4, "skyDesk1", "skyDesk2", "Топ-место 2", 450_000, "SkyDesk", 5, -20, 0, SKY_DESK },
	{ 4, "skyDesk2", "skyDesk3", "Топ-место 3", 500_000, "SkyDesk", 13, -20, 0, SKY_DESK },
	{ 4, "skyDesk3", "skyDesk4", "Топ-место 4", 560_000, "SkyDesk", 21, -20, 0, SKY_DESK },
	{
		4,
		"skyDesk4",
		"soundStudio",
		"Студия звукозаписи",
		1_200_000,
		"SoundStudio",
		-18,
		14,
		0,
		{ speed = 0.05, reviewBonus = 0.3 },
	},
	{ 4, "soundStudio", "skyDesk5", "Топ-место 5", 620_000, "SkyDesk", -18, -8, 0, SKY_DESK },
	{ 4, "skyDesk5", "skyDesk6", "Топ-место 6", 690_000, "SkyDesk", -9, -8, 0, SKY_DESK },
	{ 4, "skyDesk6", "skyDesk7", "Топ-место 7", 760_000, "SkyDesk", 0, -8, 0, SKY_DESK },
	{ 4, "skyDesk7", "skyDesk8", "Топ-место 8", 840_000, "SkyDesk", 9, -8, 0, SKY_DESK },
	{ 4, "skyDesk8", "artWall", "Арт-стена", 1_500_000, "ArtWall", 15, 16, 0, { reviewBonus = 0.4 } },
	{ 4, "artWall", "skyDesk9", "Топ-место 9", 920_000, "SkyDesk", 18, -8, 0, SKY_DESK },
	{ 4, "skyDesk9", "skyDesk10", "Топ-место 10", 1_000_000, "SkyDesk", -6, 4, 0, SKY_DESK },
	{ 4, "skyDesk10", "skyDesk11", "Топ-место 11", 1_100_000, "SkyDesk", 6, 4, 0, SKY_DESK },
}
for _, row in stageInterior do
	table.insert(
		Upgrades,
		interior(row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8], row[9], row[10])
	)
end

return Upgrades
