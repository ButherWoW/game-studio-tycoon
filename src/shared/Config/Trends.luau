--!strict
-- Модные жанры (шаг 4.3): раз в intervalSeconds сервер выбирает случайную пару
-- жанр + тема на весь сервер. Модная пара даёт scoreBonus к оценке (как ✅-сочетание).

local Trends = {
	intervalSeconds = 600, -- 10 минут
	scoreBonus = 1,
}

return Trends
