--!strict
-- Рекламные кампании: бонус к доходу выпущенной игры.
-- productId — ID Developer Product из Creator Dashboard (заполнить после создания).
-- cashCost — цена за игровую валюту (nil = только за Robux).
-- Бонусы не складываются: действует самый высокий, максимум +100%.

export type AdCampaign = {
	id: string,
	name: string,
	bonus: number, -- 0.3 = +30%
	durationSeconds: number,
	productId: number,
	robuxPrice: number, -- для справки, реальная цена задаётся в Dashboard
	cashCost: number?,
}

local AdCampaigns: { AdCampaign } = {
	{
		id = "social",
		name = "Баннеры в соцсетях",
		bonus = 0.3,
		durationSeconds = 15 * 60,
		productId = 0,
		robuxPrice = 25,
		cashCost = 50_000,
	},
	{
		id = "streamers",
		name = "Стримеры",
		bonus = 0.5,
		durationSeconds = 15 * 60,
		productId = 0,
		robuxPrice = 75,
		cashCost = 250_000,
	},
	{
		id = "tv",
		name = "ТВ-реклама",
		bonus = 0.75,
		durationSeconds = 15 * 60,
		productId = 0,
		robuxPrice = 150,
	},
	{
		id = "worldwide",
		name = "Мировая кампания",
		bonus = 1.0,
		durationSeconds = 15 * 60,
		productId = 0,
		robuxPrice = 299,
	},
}

return AdCampaigns
