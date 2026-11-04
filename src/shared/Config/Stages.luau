--!strict
-- Этапы студии (issue #8): гараж → трёхэтажный офис (1-й, 2-й, 3-й этаж); небоскрёба нет,
-- id floor/skyscraper оставлены ради старых сохранений. Номер этапа = profile.studioLevel (бонус к доходу в Formulas.revenue).
-- Переезд: нужен купленный апгрейд requiresUpgrade, gamesRequired выпущенных игр и cost денег.
-- model — модель из ServerStorage.Upgrades, которая ставится на участок на этом этапе
-- (нет — WorldService создаёт заглушку). Апгрейды гаража при переезде остаются.
-- Этажи (решение владельца): после гаража — одно трёхэтажное здание. Все три оболочки
-- (Office, Floor, Skyscraper) ставятся сразу после покупки office; некупленный этаж закрыт
-- (PlotService), «переезд» на этаж его открывает. studioLevel 2/3/4 = открыто этажей 1/2/3.
-- floorY — высота пола этажа над полом участка; этажи стоят друг на друге через FLOOR_HEIGHT.

export type Stage = {
	level: number,
	id: string,
	name: string,
	nameEn: string,
	cost: number,
	gamesRequired: number,
	requiresUpgrade: string?,
	model: string?,
	position: Vector3?, -- как в Config/Upgrades: центр основания модели на участке 60×60
	floorY: number, -- высота пола этажа этого этапа (гараж и 1-й этаж — 0)
}

-- Высота этажа (studs): стены оболочек не выше FLOOR_HEIGHT − 1 (docs/VISUAL.md, V7)
local FLOOR_HEIGHT = 14

local Stages: { Stage } = {
	{
		level = 1,
		id = "garage",
		name = "Гараж",
		nameEn = "Garage",
		cost = 0,
		gamesRequired = 0,
		model = "Garage",
		position = Vector3.new(0, 0.5, 0),
		floorY = 0,
	},
	-- Офис оплачивается апгрейдом office (его модель Office ставит PlotService как апгрейд)
	{
		level = 2,
		id = "office",
		name = "Офис",
		nameEn = "Office",
		cost = 0,
		gamesRequired = 0,
		requiresUpgrade = "office",
		floorY = 0,
	},
	{
		level = 3,
		id = "floor",
		name = "Офис: 2-й этаж",
		nameEn = "Office: 2nd floor",
		cost = 60_000,
		gamesRequired = 10,
		model = "Floor",
		position = Vector3.new(0, 0.5 + FLOOR_HEIGHT, 0),
		floorY = FLOOR_HEIGHT,
	},
	-- TODO(#8): ещё условие — исследование «Онлайн-режим», когда появятся исследования
	{
		level = 4,
		id = "skyscraper",
		name = "Офис: 3-й этаж",
		nameEn = "Office: 3rd floor",
		cost = 400_000,
		gamesRequired = 40,
		model = "Skyscraper",
		position = Vector3.new(0, 0.5 + 2 * FLOOR_HEIGHT, 0),
		floorY = 2 * FLOOR_HEIGHT,
	},
}

return Stages
