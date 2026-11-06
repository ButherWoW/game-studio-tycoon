--!strict
-- Компактный HUD (отзыв владельца 06.11: «дохуя информации посреди экрана»).
-- Верхняя строка (HudController): значки (фанаты, игры, расходы, настроение, мощность…).
-- Деньги и доход — в правом нижнем углу (блок «Money»; на телефоне левее кнопки прыжка).
-- Плашки событий (Ui.bannerStack) — значки в лотке справа; новая плашка один раз объявляется
-- полосой сверху на announceSeconds, потом сворачивается в значок. Нажатие на значок — карточка
-- с полным текстом и кнопками плашки.

local Hud = {}

-- Порядок значков в лотке сверху вниз: меньше — выше. Ключ задаёт контроллер (Ui.bannerMeta).
-- Плашки без ключа (тосты, итоги выставки) — после всех (othersPriority)
Hud.bannerPriority = {
	bailiff = 1, -- долг и приставы (BailiffBanner)
	hitAlarm = 2, -- вор уносит хит (HitController) — срочно, сразу за долгом
	construction = 3, -- стройка этажа (ConstructionController)
	research = 4, -- идёт исследование (ResearchBanner)
	contract = 5, -- контракт издателя (ContractController)
	dailyEvent = 6, -- событие дня и «Золотой час» (DailyEventBanner)
	hackathon = 7, -- «Ночная смена» (LiveOpsBanner)
	expo = 8, -- выставка (ExpoBanner)
	trend = 9, -- тренд (TrendBanner)
	gotw = 10, -- «Игра недели» по воскресеньям (GotwController)
	holiday = 11, -- праздник (HolidayController)
	rivalHit = 12, -- хит конкурента (RivalWindow)
	coop = 13, -- совместная разработка (CoopController)
	companyEvents = 14, -- значки событий компании 📉 🛡 ⭐ (CompanyEventController)
} :: { [string]: number }
Hud.othersPriority = 100
-- Плашка «в фоне» (атрибут BannerIdle: событие дня между событиями) — в конец лотка
Hud.idlePriority = 200

-- Эти объявляются всегда, даже в первые joinQuietSeconds после входа
Hud.announceImportant = {
	bailiff = true,
	hitAlarm = true,
	dailyEvent = true,
} :: { [string]: boolean }
Hud.announceSeconds = 4
-- После входа плашек много сразу: объявляем только важные, остальные — сразу значками
Hud.joinQuietSeconds = 6
-- Одна и та же плашка не объявляется чаще (мигание Visible)
Hud.announceCooldown = 30
-- В очереди объявлений не больше (лишние неважные — сразу значками)
Hud.announceQueueMax = 3

-- Лоток справа
Hud.chipSize = 42
Hud.chipSizeTouch = 44
Hud.chipGap = 4
Hud.maxChips = 6 -- больше — последний значок «+N», нажатие раскрывает все
Hud.trayTouchTop = 8 -- тач: сверху справа (список игроков там свёрнут в кнопку верхней панели)
Hud.trayTouchBottom = 140 -- тач: снизу справа кнопка прыжка
Hud.trayDesktopShare = 0.7 -- ПК: лоток по центру справа, не выше этой доли экрана
Hud.cardWidth = 280

-- Верхняя строка
Hud.topBarHeight = 40 -- значки 16–18 px читаемы
Hud.topBarWidth = 420
Hud.topBarWidthTouch = 340 -- = Ui.HUD_PLATE_WIDTH: боковое меню на тач-экране правее не заходит
Hud.popoverSeconds = 3

return Hud
