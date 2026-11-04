--!strict
-- Этапы студии (issue #8): гараж → трёхэтажный офис (1-й, 2-й, 3-й этаж); небоскрёба нет,
-- id floor/skyscraper оставлены ради старых сохранений. Номер этапа = profile.studioLevel (бонус к доходу в Formulas.revenue).
-- Переезд: нужен купленный апгрейд requiresUpgrade, gamesRequired выпущенных игр и cost денег.
-- model — модель из ServerStorage.Upgrades, которая ставится на участок на этом этапе
-- (нет — WorldService создаёт заглушку). Апгрейды гаража при переезде остаются.

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
}

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
	},
	{
		level = 3,
		id = "floor",
		name = "Офис: 2-й этаж",
		nameEn = "Office: 2nd floor",
		cost = 60_000,
		gamesRequired = 10,
		model = "Floor",
		position = Vector3.new(0, 0.5, 0),
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
		position = Vector3.new(0, 0.5, 0),
	},
}

return Stages
