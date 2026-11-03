--!strict
-- Награды за вход 7 дней подряд (issue #10). Пропуск дня -> снова день 1, после дня 7 -> день 1.
-- День считается по UTC (смена в 00:00 UTC).

local Rewards = require(script.Parent.Rewards)

local DailyRewards: { Rewards.Reward } = {
	{ incomeMinutes = 5 },
	{ researchPoints = 10 },
	{ incomeMinutes = 10 },
	{ coffeeMinutes = 10 }, -- кофе: ×2 скорость разработки
	{ incomeMinutes = 20 },
	{ adBonus = 0.3, adMinutes = 15 }, -- бесплатная реклама +30%
	{ incomeMinutes = 30, researchPoints = 25, trophy = "weekly_cup" }, -- декор «Кубок недели», копится
}

return DailyRewards
