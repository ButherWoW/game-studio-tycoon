--!strict
-- Выпуск игры по частям (решение владельца 06.11, #14): в день запуска — база (основной цикл,
-- студия, удержание, Rebirth, весь донат основного цикла), крупные системы выходят обновлениями
-- КАЖДУЮ СРЕДУ. Среда n — та же, что у n-й волны предметов (Config/ContentDrops.wednesdayDay):
-- первая среда строго после launchDate (запуск в среду — среда 1 через 7 дней), 00:00 UTC.
-- Таблица дат — docs/LAUNCH.md («Обновления по средам»), тексты обновлений — docs/PATCH_NOTES.md.
--
-- ▶ ВЛАДЕЛЕЦ: перенести обновление — поменять его week; перенести одну систему — переложить её id
--   в другое обновление (или убрать из всех — она выйдет с запуском). Дата запуска —
--   ContentDrops.launchDate (до неё всё ведёт себя как день 0).
--
-- Пока система не вышла (проверяет сервер, FeatureReleaseService и сами сервисы):
--   • её remotes ничего не делают, циклы/NPC/модели/баннеры не запускаются, хуки релиза игры
--     (DevelopmentService) её не зовут — доход, оценка и награды как без неё;
--   • её товары за Robux не продаются (кнопок нет); оплаченный чек всё равно выдаём — деньгами;
--   • уже купленное и данные профиля не трогаем: лежат до выхода и начинают работать сами.
-- Вышла, пока сервер работает, — включается без перезапуска (проверка раз в минуту).
-- Клиент (FeatureGate) показывает кнопки, окна и плашки системы, только если она вышла И открыта
-- по прогрессу (Config/Unlocks). Studio: Debug.featuresAll — всё сразу; Debug.contentDayOffset
-- двигает и волны, и обновления (один «день после запуска»).

local RunService = game:GetService("RunService")

local ContentDrops = require(script.Parent.ContentDrops)
local Debug = require(script.Parent.Debug)

export type Update = {
	id: string, -- тексты upd_<id> (название) и upd_<id>_desc (что вошло)
	week: number, -- номер среды после запуска (0 — база в день запуска)
	icon: string,
	features: { string },
}

local DAY = 24 * 60 * 60

local Features = {}

-- Обновления по средам. Состав — предложение Dev 2, одобрено владельцем (комментарий в #14)
Features.updates = {
	-- Конкуренты (топ индустрии, хиты конкурентов), «Игра недели», Зал славы, рекламные щиты у спавна
	{
		id = "competition",
		week = 1,
		icon = "🏆",
		features = { "rivals", "gotw", "hallOfFame", "billboards" },
	},
	-- 3-й этаж небоскрёба (решение владельца 06.11 11:27): на запуске парк → гараж → этажи 1–2.
	-- Отдельным обновлением, чтобы в окне «Что нового» был свой заголовок. До выхода покупка и
	-- стройка 3-го этажа закрыты на сервере (UnlockService/ConstructionService), кнопка — «Скоро»
	{ id = "thirdFloor", week = 1, icon = "🏢", features = { "floor3" } },
	-- Совместная разработка, холдинги, обмен предметами
	{ id = "together", week = 2, icon = "🤝", features = { "coop", "holdings", "trade" } },
	-- Контракты издателей, франшизы (продолжения), наставничество сотрудников
	{ id = "publishers", week = 3, icon = "📜", features = { "contracts", "franchises", "mentoring" } },
	-- Платформа «Своя консоль» в окне «Создать игру» (ПК и телефоны — с запуска), цепочка своей
	-- консоли (этапы, оборудование, роялти, ускорения за Robux), стример
	{ id = "ownConsole", week = 4, icon = "🎮", features = { "platforms", "console", "streamer" } },
	-- Налоговая, биржа: IPO своей компании, акции других студий, дивиденды
	{ id = "market", week = 5, icon = "📈", features = { "tax", "ipo", "stocks", "dividends" } },
	-- Мини-аркада после релиза, гейм-джем недели, ночь хакатона
	{ id = "arcade", week = 6, icon = "🕹️", features = { "arcade", "gameJam", "hackathon" } },
} :: { Update }

-- Сервер: модуль сервиса -> его система. DevelopmentService (optional) не зовёт хуки невышедших,
-- FeatureReleaseService откладывает их start() до выхода. ConsoleService здесь нет: строка
-- платформ (ПК/телефоны) — с запуска, сама консоль закрыта внутри сервиса
Features.services = {
	RivalService = "rivals",
	GotwService = "gotw",
	HallOfFameService = "hallOfFame",
	BillboardService = "billboards",
	CoopService = "coop",
	HoldingService = "holdings",
	TradeService = "trade",
	ContractService = "contracts",
	FranchiseService = "franchises",
	StreamerService = "streamer",
	TaxService = "tax",
	StockService = "stocks",
	ArcadeService = "arcade",
	GameJamService = "gameJam",
	HackathonService = "hackathon",
} :: { [string]: string }

-- Этап студии (Config/Stages.level) -> система: переезд на этаж закрыт до её выхода.
-- 4 — 3-й этаж (studioLevel 4). Уже переехавших не возвращаем
Features.stages = {
	[4] = "floor3",
} :: { [number]: string }

-- По неделям; в одну среду — в порядке списка (table.sort не устойчивая)
local listed: { [Update]: number } = {}
for i, update in Features.updates do
	listed[update] = i
end

table.sort(Features.updates, function(a, b)
	if a.week ~= b.week then
		return a.week < b.week
	end
	return listed[a] < listed[b]
end)

-- id системы или обновления -> обновление
local byId: { [string]: Update } = {}
for _, update in Features.updates do
	byId[update.id] = update
	for _, id in update.features do
		assert(
			byId[id] == nil or byId[id] == update,
			"Config/Features: система в двух обновлениях: " .. id
		)
		byId[id] = update
	end
end

-- Обновление системы (или само обновление по его id); nil — система базовая (с запуска)
function Features.updateOf(id: string): Update?
	return byId[id]
end

-- Известна ли система графику (иначе — с запуска)
function Features.isScheduled(id: string): boolean
	return byId[id] ~= nil and byId[id].week > 0
end

-- Номер среды выхода (0 — с запуска)
function Features.week(id: string): number
	local update = byId[id]
	return if update then math.max(update.week, 0) else 0
end

-- День выхода, дней от launchDate (0 — с запуска)
function Features.releaseDay(id: string): number
	return ContentDrops.wednesdayDay(Features.week(id))
end

-- Когда система выходит (os.time, 00:00 UTC среды)
function Features.releaseAt(id: string): number
	return ContentDrops.launchAt + Features.releaseDay(id) * DAY
end

local function forcedAll(): boolean
	return (Debug :: any).featuresAll == true and RunService:IsStudio()
end

-- Вышла ли система (или обновление) к моменту now (по умолчанию — сейчас; до запуска — день 0).
-- Неизвестный id — вышел. Studio: Debug.featuresAll — всё; Debug.contentDayOffset — «день»
function Features.isReleased(id: string, now: number?): boolean
	if forcedAll() then
		return true
	end
	local week = Features.week(id)
	if week <= 0 then
		return true
	end
	return ContentDrops.wednesdayDay(week) <= ContentDrops.dayIndex(now)
end

-- Сколько дней до выхода (0 — уже вышла)
function Features.daysUntil(id: string, now: number?): number
	if Features.isReleased(id, now) then
		return 0
	end
	return math.max(Features.releaseDay(id) - ContentDrops.dayIndex(now), 1)
end

-- Вышел ли сервис (Features.services); сервис не из списка — всегда
function Features.serviceReleased(moduleName: string): boolean
	local id = Features.services[moduleName]
	return id == nil or Features.isReleased(id)
end

-- Вышел ли этап студии (Features.stages); этап не из списка — с запуска
function Features.stageReleased(level: number, now: number?): boolean
	local id = Features.stages[level]
	return id == nil or Features.isReleased(id, now)
end

-- Номер последнего вышедшего обновления в Features.updates (0 — ни одного)
function Features.currentIndex(now: number?): number
	local index = 0
	for i, update in Features.updates do
		if update.week > 0 and Features.isReleased(update.id, now) then
			index = i
		end
	end
	return index
end

-- Следующее обновление и сколько до него дней; nil — все вышли
function Features.nextUpdate(now: number?): (Update?, number)
	for _, update in Features.updates do
		if update.week > 0 and not Features.isReleased(update.id, now) then
			return update, Features.daysUntil(update.id, now)
		end
	end
	return nil, 0
end

return Features
