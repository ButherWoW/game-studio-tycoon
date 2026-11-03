--!strict
-- «N минут дохода» -> деньги. Общая для сервера (выдача) и клиента (подсказка в окне).

local Formulas = require(script.Parent.Formulas)
local Rewards = require(script.Parent.Config.Rewards)

local RewardFormulas = {}

function RewardFormulas.incomeForMinutes(
	bestScore: number,
	studioLevel: number,
	rebirths: number,
	minutes: number
): number
	local score = math.clamp(math.max(bestScore, Rewards.minScore), 1, 10)
	local perGame = Formulas.revenue(score, studioLevel, 0, 1 + Rewards.rebirthBonus * rebirths)
	local perMinute = perGame * 60 / Rewards.secondsPerGame
	return math.max(math.floor(perMinute * minutes), 1)
end

return RewardFormulas
