--!strict
-- Рекламные кампании: бонус к доходу выпущенной игры.
-- productId — ID Developer Product из Creator Dashboard (заполнить после создания).
-- cashCost — цена за игровую валюту (nil = только за Robux).
-- Бонусы не складываются: действует самый высокий, максимум +100%.

local Universe = require(script.Parent.Universe)

export type AdCampaign = {
	id: string,
	name: string,
	bonus: number, -- 0.3 = +30%
	durationSeconds: number,
	productId: number,
	robuxPrice: number, -- для показа в магазине; ПРЕДЛОЖЕНИЕ из #11, финальную решает владелец, реальная — в Dashboard
	cashCost: number?,
}

local AdCampaigns: { AdCampaign } = {
	{
		id = "social",
		name = "Баннеры в соцсетях",
		bonus = 0.3,
		durationSeconds = 15 * 60,
		productId = Universe.pick({ test = 3728447783, main = 0 }),
		robuxPrice = 19, -- #11: было 25
		cashCost = 3_000,
	},
	{
		id = "streamers",
		name = "Стримеры",
		bonus = 0.5,
		durationSeconds = 15 * 60,
		productId = Universe.pick({ test = 3728447889, main = 0 }),
		robuxPrice = 39, -- #11: было 75
		cashCost = 12_000,
	},
	{
		id = "tv",
		name = "ТВ-реклама",
		bonus = 0.75,
		durationSeconds = 15 * 60,
		productId = Universe.pick({ test = 3728447939, main = 0 }),
		robuxPrice = 79, -- #11: было 150
	},
	{
		id = "worldwide",
		name = "Мировая кампания",
		bonus = 1.0,
		durationSeconds = 15 * 60,
		productId = Universe.pick({ test = 3728447942, main = 0 }),
		robuxPrice = 129, -- #11: было 299
	},
}

return AdCampaigns
