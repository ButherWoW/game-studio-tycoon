--!strict
-- Настройки для тестов в Studio. В опубликованной игре не действуют (DebugService проверяет IsStudio).
-- Перед релизом можно оставить как есть: на живых серверах это ничего не меняет.

local Debug = {
	-- Сколько денег выдать при входе в Studio (0 — выключено)
	studioStartCash = 999_999,
	-- Событие компании (id из Config/CompanyEvents, например "takeover"): в Studio приходит через ~15 с
	-- после входа с гаражом и потом каждый интервал, без пауз новичка, этапа и кулдауна. nil — обычный режим
	forceCompanyEvent = nil :: string?,
	-- Интервал между событиями компании в Studio, секунд (например 30). nil — как в Config/CompanyEvents
	companyEventInterval = nil :: number?,
}

return Debug
