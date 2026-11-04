--!strict
-- Настройки для тестов в Studio. В опубликованной игре не действуют (DebugService проверяет IsStudio).
-- Перед релизом можно оставить как есть: на живых серверах это ничего не меняет.

local Debug = {
	-- Сколько денег выдать при входе в Studio (0 — выключено)
	studioStartCash = 999_999,
	-- Приставы (BailiffService): через 5 с после входа в Studio поставить баланс −bailiffsDebt
	-- (0 — выключено). Не меньше лимита этапа (Config/Bailiffs, 10 000) — приставы приходят сразу,
	-- меньше — только предупреждение и «разваливающийся» офис. Защита новичка в Studio не действует
	bailiffsDebt = 0,
	-- Событие компании (id из Config/CompanyEvents, например "takeover"): в Studio приходит через ~15 с
	-- после входа с гаражом и потом каждый интервал, без пауз новичка, этапа и кулдауна. nil — обычный режим
	forceCompanyEvent = nil :: string?,
	-- Интервал между событиями компании в Studio, секунд (например 30). nil — как в Config/CompanyEvents
	companyEventInterval = nil :: number?,
}

return Debug
