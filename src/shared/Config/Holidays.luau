--!strict
-- Праздничные ивенты (шаг 4.9, issue #10). Активный ивент сервер определяет по дате UTC
-- (HolidayService). Даты from/to — включительно; если from позже to, ивент идёт через Новый год.
-- Сезон = id .. "-" .. год начала ивента: квест ивента и календарь подарков — раз за сезон.

local Rewards = require(script.Parent.Rewards)

export type MonthDay = { month: number, day: number }

export type HolidayQuest = {
	target: number,
	-- Засчитываются релизы в этих жанрах ИЛИ с этими темами
	genres: { string }?,
	topics: { string }?,
	reward: Rewards.Reward,
	cosmetic: string?, -- косметика навсегда (profile.holidays.cosmetics)
}

export type Holiday = {
	id: string,
	icon: string,
	from: MonthDay,
	to: MonthDay,
	-- +reviewBonus к оценке, если жанр в bonusGenres или тема в bonusTopics (не складывается)
	reviewBonus: number?,
	bonusGenres: { string }?,
	bonusTopics: { string }?,
	-- × к доходу для жанров revenueGenres
	revenueMultiplier: number?,
	revenueGenres: { string }?,
	decor: string?, -- "pumpkins" | "tree": декор у спавна и участков, снимается после ивента
	quest: HolidayQuest?,
	calendar: { Rewards.Reward }?, -- подарок в день (один раз в день UTC), без сброса серии
}

local Holidays = {}

Holidays.list = {
	{
		id = "halloween",
		icon = "🎃",
		from = { month = 10, day = 20 },
		to = { month = 11, day = 3 },
		reviewBonus = 1,
		bonusGenres = { "horror" },
		bonusTopics = { "ghosts", "pumpkins" },
		decor = "pumpkins",
		quest = {
			target = 5,
			genres = { "horror" },
			topics = { "ghosts", "pumpkins" },
			reward = { incomeMinutes = 20 },
			cosmetic = "halloween_sign", -- оранжевая неон-вывеска у участка
		},
	},
	{
		id = "newyear",
		icon = "🎄",
		from = { month = 12, day = 20 },
		to = { month = 1, day = 10 },
		reviewBonus = 1,
		bonusTopics = { "newyear" },
		decor = "tree",
		calendar = {
			{ incomeMinutes = 5 },
			{ researchPoints = 10 },
			{ incomeMinutes = 10 },
			{ coffeeMinutes = 10 },
			{ trophy = "souvenir_cartridge" }, -- картридж-сувенир в коллекцию
			{ incomeMinutes = 15 },
			{ adBonus = 0.3, adMinutes = 15 },
			{ incomeMinutes = 20 },
			{ researchPoints = 20 },
			{ trophy = "souvenir_cartridge", incomeMinutes = 10 },
			{ coffeeMinutes = 15 },
			{ incomeMinutes = 25 },
			{ adBonus = 0.5, adMinutes = 15 },
			{ incomeMinutes = 40, researchPoints = 30, trophy = "golden_cartridge" },
		},
	},
	{
		id = "summer",
		icon = "☀️",
		from = { month = 7, day = 1 },
		to = { month = 7, day = 31 },
		revenueMultiplier = 1.5,
		revenueGenres = { "casual", "sports" },
	},
} :: { Holiday }

-- Только в Studio: включить ивент вручную ("halloween" | "newyear" | "summer"), nil — по дате
Holidays.studioForce = nil :: string?
-- Только в Studio: длина «дня» календаря подарков в секундах (проверять без ожидания суток)
Holidays.studioDaySeconds = 60

-- Как часто сервер сверяет ивент, декор, сезонные темы и прогресс квеста
Holidays.pollSeconds = 2

function Holidays.find(id: any): Holiday?
	for _, holiday in Holidays.list do
		if holiday.id == id then
			return holiday
		end
	end
	return nil
end

return Holidays
