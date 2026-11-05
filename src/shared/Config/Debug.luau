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
	-- Сезон и гейм-джем, хакатон (только Studio; nil/false/1 — как на живых серверах)
	seasonForceIndex = nil :: number?, -- номер сезона вместо текущего (0 — первый): проверить сброс
	seasonXpMultiplier = 1, -- ×опыт сезона, чтобы пройти уровни быстро (например 20)
	seasonForcePremium = false, -- премиум-дорожка без покупки
	jamForceWeek = nil :: number?, -- номер недели джема (другая тема)
	jamStudioWeekSeconds = nil :: number?, -- короткая «неделя» (например 300): проверить награды за джем
	hackathonForce = false, -- хакатон идёт всё время
	-- Франшизы и контракты (только Studio): контракт предлагается через 15 с и потом раз в минуту,
	-- даже в гараже; хит конкурента — через 20 с после старта сервера
	contractForceOffer = false,
	rivalForceHit = false,
	-- Своя консоль и стример (только Studio): консоль открыта на любом этапе, этапы бесплатные;
	-- этапу хватает consoleStageGames игр (nil — как в Config/Console); хайп и донаты стримера
	-- идут в streamerSpeed раз быстрее (например 10)
	consoleForceUnlock = false,
	consoleStageGames = nil :: number?,
	streamerSpeed = 1,
	-- События дня (Config/DailyEvents, только Studio): dailyEventForce — id события (например
	-- "bugHunt"), без dailyEventShort оно идёт всё время; dailyEventShort — короткий цикл
	-- (событие каждые 6 мин на 3 мин, анонс за 30 с, золотой час каждые 10 мин на 2 мин);
	-- dailyGoldenForce — золотой час идёт всё время. nil/false — как на живых серверах
	dailyEventForce = nil :: string?,
	dailyEventShort = false,
	dailyGoldenForce = false,
	-- Набор ID товаров/геймпассов/значков (Config/Universe, docs/IDS.md), только Studio:
	-- "main" — как в основной игре (где main = 0 — «Скоро»), "test" — тестовая v2.
	-- nil — по game.GameId
	forceUniverse = nil :: string?,
	-- График контента (Config/ContentDrops, только Studio): какой день после запуска изображать
	-- (например 7 — вышла «Неделя роботов», 60 — всё). nil — по настоящей дате (до запуска — день 0)
	contentDayOffset = nil :: number?,
}

return Debug
