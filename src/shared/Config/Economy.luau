--!strict
-- Числа экономики для Formulas. Цель (issue #1): гараж -> офис за 11–15 минут,
-- в гараже потолок оценки ~7–8, 9–10 — только с большой командой.

local Economy = {
	-- Вес «попадания в рецепт жанра» и «количества очков» в оценке (в сумме 1)
	balanceWeight = 0.4,
	qualityWeight = 0.6,
	-- quality = log10(1 + очки) / qualityLogDivisor; 5 -> качество 1.0 при 100 000 очков
	qualityLogDivisor = 5,
	-- Тема сдвигает оценку: (fit - 1) * topicFitStrength. ×1.2 -> +0.6, ×0.7 -> -0.9
	topicFitStrength = 3,
	-- Случайный разброс оценки, ±
	reviewNoise = 0.75,
	-- Доход = revenueBase * оценка^2 * бонусы
	revenueBase = 20,
	-- Предметы студии ускоряют разработку не больше чем на эту долю (сумма speed в Config/Upgrades)
	maxUpgradeSpeed = 0.5,
	-- +25% к доходу за каждый уровень студии
	studioLevelBonus = 0.25,
}

return Economy
