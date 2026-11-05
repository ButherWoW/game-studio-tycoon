--!strict
-- Франшизы (FranchiseService): выпущенная игра с оценкой ≥ minScore может стать франшизой
-- (название франшизы = название игры). «Продолжение франшизы» — в окне «Создать игру».
-- Жанр продолжения = жанр франшизы; та же тема — слабее штраф за повтор (Economy.sequelRepeatFactor).
-- Доход продолжения: хайп от фанатов (+hypePerThousandFans за каждую 1000, не больше maxHype)
-- и усталость: вышло раньше чем через fatigueSeconds после прошлой части или оценка ниже прошлой.

local Franchises = {
	minScore = 8, -- с какой оценки игру можно сделать франшизой
	maxFranchises = 6,
	candidatesKept = 5, -- сколько последних хитов помнить как кандидатов

	-- Фанаты: хорошая часть (оценка ≥ goodScore) +fansPerPoint × (оценка − 7),
	-- плохая (≤ badScore) — фанатов × badKeep; средняя ничего не меняет
	goodScore = 8,
	badScore = 5,
	fansPerPoint = 1_000,
	badKeep = 0.6,

	hypePerThousandFans = 0.03, -- +3% дохода за каждую 1000 фанатов
	maxHype = 0.3,

	fatigueSeconds = 3 * 60, -- части чаще — фанаты устают
	fatigueMultiplier = 0.7,
	worseMultiplier = 0.8, -- оценка ниже прошлой части
	minMultiplier = 0.5,

	-- Тост «можно сделать франшизой» не чаще
	candidateToastSeconds = 10 * 60,
}

-- Хайп (доля к доходу) от числа фанатов
function Franchises.hype(fans: number): number
	return math.min(math.max(fans, 0) / 1000 * Franchises.hypePerThousandFans, Franchises.maxHype)
end

return Franchises
