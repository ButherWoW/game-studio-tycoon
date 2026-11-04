--!strict
-- Настройки для тестов в Studio. В опубликованной игре не действуют (DebugService проверяет IsStudio).
-- Перед релизом можно оставить как есть: на живых серверах это ничего не меняет.

local Debug = {
	-- Сколько денег выдать при входе в Studio (0 — выключено)
	studioStartCash = 999_999,
	-- Сезон и гейм-джем, хакатон (только Studio; nil/false/1 — как на живых серверах)
	seasonForceIndex = nil :: number?, -- номер сезона вместо текущего (0 — первый): проверить сброс
	seasonXpMultiplier = 1, -- ×опыт сезона, чтобы пройти уровни быстро (например 20)
	seasonForcePremium = false, -- премиум-дорожка без покупки
	jamForceWeek = nil :: number?, -- номер недели джема (другая тема)
	jamStudioWeekSeconds = nil :: number?, -- короткая «неделя» (например 300): проверить награды за джем
	hackathonForce = false, -- хакатон идёт всё время
}

return Debug
