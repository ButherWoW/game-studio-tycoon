--!strict
-- «N минут дохода» -> деньги. Общая для сервера (выдача) и клиента (подсказка в окне).
-- Отчёт #2: раньше минуту дохода считали как у гаража с оценкой 5 даже у новичка в парке
-- (день 1 давал ~$5 000 при гараже за $750), а после Rebirth — по лучшей оценке за всё время.

local Formulas = require(script.Parent.Formulas)
local Rewards = require(script.Parent.Config.Rewards)
local StartPark = require(script.Parent.Config.StartPark)

export type IncomeState = {
	score: number, -- лучшая оценка с последнего Rebirth (profile.runBestScore)
	studioLevel: number,
	rebirths: number,
	ownsGarage: boolean, -- нет гаража — доход ноутбука в парке
}

local RewardFormulas = {}

-- Доход студии в минуту: без гаража — ноутбук в парке, с гаражом — релизы студии
function RewardFormulas.perMinute(state: IncomeState): number
	local score = math.clamp(math.max(state.score, Rewards.minScore), 1, 10)
	local rebirthMultiplier = 1 + Rewards.rebirthBonus * state.rebirths
	if not state.ownsGarage then
		local perGame = Formulas.revenue(score, 1, 0, rebirthMultiplier) * StartPark.laptopRevenueMultiplier
		return perGame * 60 / Rewards.parkSecondsPerGame
	end
	local perGame = Formulas.revenue(score, state.studioLevel, 0, rebirthMultiplier)
	return perGame * 60 / Rewards.secondsPerGame
end

-- Потолок награды без гаража: доля цены гаража, больше для наград на больше минут
function RewardFormulas.parkCap(minutes: number): number
	local progress = math.clamp(
		(minutes - Rewards.parkCapBaseMinutes) / (Rewards.parkCapFullMinutes - Rewards.parkCapBaseMinutes),
		0,
		1
	)
	local multiplier = 1 + (Rewards.parkCapMaxMultiplier - 1) * progress
	return StartPark.garagePrice * Rewards.parkMaxGarageShare * multiplier
end

-- Награда «N минут дохода». Без гаража — не больше потолка parkCap: этап парка не пропустить
function RewardFormulas.incomeForMinutes(state: IncomeState, minutes: number): number
	local cash = RewardFormulas.perMinute(state) * minutes
	if not state.ownsGarage then
		cash = math.min(cash, RewardFormulas.parkCap(minutes))
	end
	return math.max(math.floor(cash), 1)
end

-- Цель задания «Заработай N минут дохода»: без потолка, это не выдача денег
function RewardFormulas.incomeTarget(state: IncomeState, minutes: number): number
	return math.max(math.floor(RewardFormulas.perMinute(state) * minutes), 1)
end

return RewardFormulas
