--!strict
-- График контента (live-ops): не всё открыто в день запуска — жанры, темы, скины, маскоты, постеры,
-- декор, стили мебели, отделка и события дня выходят волнами по средам после launchDate, чтобы игроки
-- возвращались: волна n — в n-ю среду, в тот же день, что и n-е обновление систем (Config/Features).
-- Таблица по датам — docs/LAUNCH.md, «График контента».
--
-- ▶ ВЛАДЕЛЕЦ: дату запуска меняйте здесь, в launchDate ("ГГГГ-ММ-ДД", полночь UTC). День 0 — сам
--   запуск; до него всё ведёт себя как день 0 (можно тестировать заранее). Сдвинуть волну —
--   поменять её week (номер среды). Предмета нет ни в одной волне — он открыт с запуска.
--   Среда 1 — первая среда строго после запуска (запуск в среду — среда 1 через 7 дней).
--
-- Правила (проверяет сервер, клиент только показывает «Скоро: через N дн.»):
--   • невыпущенное не продаётся ни за $, ни за Robux (кнопки нет), не выдаётся сезоном и «Сделкой дня»
--     (сезон даёт fallbackMinutes дохода, сделка дня — следующий выпущенный товар);
--   • жанр/тема до выхода закрыты в UnlockRules (покупка, исследование, «Создать игру»);
--   • событие дня до выхода не выпадает (DailyEvents, одинаково на всех серверах), в гейм-джем
--     и тренды невыпущенные жанры и темы не попадают;
--   • уже купленное никогда не забираем; оплаченный чек Robux выдаём всегда (деньги списаны).
-- Праздники (Config/Holidays) идут по календарю — здесь их нет.
-- Studio: Config/Debug.contentDayOffset — какой день после запуска изображать (только Studio).
-- Админ-панель (AdminService, «Тестовый сервер»): атрибут ReplicatedStorage AdminContentDay — то же
-- самое, но только в Studio или на закрытом сервере игры (ReserveServer), см. adminDayAllowed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Debug = require(script.Parent.Debug)

export type Kind = "genre" | "topic" | "skin" | "mascot" | "poster" | "decor" | "style" | "finish" | "dailyEvent"

export type Drop = {
	id: string, -- тексты drop_<id> (заголовок) и drop_<id>_desc (подзаголовок)
	week: number, -- номер среды после запуска (0 — сам запуск), см. ContentDrops.wednesdayDay
	day: number?, -- дней от launchDate: считается из week при загрузке (не задавать руками)
	icon: string,
	genres: { string }?,
	topics: { string }?,
	skins: { string }?,
	mascots: { string }?,
	posters: { string }?,
	decor: { string }?,
	styles: { string }?,
	finishes: { string }?,
	dailyEvents: { string }?,
}

local DAY = 24 * 60 * 60

-- Поле волны для каждого вида (в порядке показа в окне «Что нового»)
local FIELDS: { { kind: Kind, field: string } } = {
	{ kind = "genre", field = "genres" },
	{ kind = "topic", field = "topics" },
	{ kind = "skin", field = "skins" },
	{ kind = "mascot", field = "mascots" },
	{ kind = "poster", field = "posters" },
	{ kind = "decor", field = "decor" },
	{ kind = "style", field = "styles" },
	{ kind = "finish", field = "finishes" },
	{ kind = "dailyEvent", field = "dailyEvents" },
}

local ContentDrops = {
	-- ▶ Дата запуска (UTC). Плейсхолдер — владелец ставит настоящую перед публикацией
	launchDate = "2026-11-16", -- понедельник (владелец, 06.11); до этой даты — бетатест (день 0)

	-- Волны по дням. Набор запуска (день 0) — всё, что нужно до 1-го Rebirth: 8 из 10 жанров
	-- (вся цепочка исследований до «Стратегии»), у каждого жанра есть тема с совместимостью 1.2,
	-- стартовые скины набора/группы, маскоты за достижение и группу, 6 из 10 событий дня
	-- (все, что дают деньги в docs/BALANCE.md). Позже — разнообразие и косметика.
	drops = {
		{
			id = "launch",
			week = 0,
			icon = "🎉",
			genres = { "action", "adventure", "casual", "rpg", "simulation", "puzzle", "racing", "strategy" },
			topics = {
				"space",
				"fantasy",
				"zombies",
				"pets",
				"cars",
				"cooking",
				"business",
				"school",
				"detective",
			},
			skins = { "hoodie_coder", "pixel_artist", "sound_nerd", "writer", "intern", "neon_streamer" },
			mascots = {
				"pixel_cat",
				"bug_beetle",
				"coffee_cup",
				"floppy_dog",
				"cloud_ghost",
				"slime_star",
				"neon_fox",
			},
			posters = {
				"pixelHero",
				"puzzleBlocks",
				"turboRacer",
				"starBlaster",
				"neonCity",
				"crystalKingdom",
			},
			decor = {
				"plant",
				"rug",
				"pendantLamp",
				"wallBench",
				"beanBags",
				"bookshelf",
				"sofa",
				"coffeeTable",
				"miniFridge",
			},
			styles = { "classic", "cozy" },
			finishes = { "classic", "obsidianGold" },
			dailyEvents = { "coffeeRush", "investors", "bugHunt", "blitzJam", "critics", "pizza" },
		},
		{
			id = "robots",
			week = 1,
			icon = "🤖",
			topics = { "robots" },
			skins = { "cyber_dev" },
			mascots = { "robo_owl" },
			posters = { "mechTitan", "robotArena" },
			decor = { "neonSign" },
			dailyEvents = { "cartridgeRush" },
		},
		{
			id = "sports",
			week = 2,
			icon = "⚽",
			genres = { "sports" },
			topics = { "football" },
			skins = { "speedrunner" },
			mascots = { "controller_bunny" },
			styles = { "minimal" },
			dailyEvents = { "flashSale" },
		},
		{
			id = "ninja",
			week = 3,
			icon = "🥷",
			topics = { "ninja" },
			skins = { "bug_hunter" },
			posters = { "ninjaCat" },
			finishes = { "sakura" },
			dailyEvents = { "talentHunt" },
		},
		{
			id = "horror",
			week = 4,
			icon = "👻",
			genres = { "horror" },
			topics = { "ghosts" },
			skins = { "retro_gamer" },
			posters = { "ghostManor" },
		},
		{
			id = "pirates",
			week = 5,
			icon = "🏴‍☠️",
			topics = { "pirates" },
			skins = { "wizard_dev" },
			mascots = { "dragon_byte" },
			posters = { "dragonValley" },
			decor = { "aquarium" },
			dailyEvents = { "mascotParade" },
		},
		{
			id = "heroes",
			week = 6,
			icon = "🦸",
			topics = { "superheroes" },
			skins = { "space_dev" },
			mascots = { "cosmic_whale" },
			posters = { "galaxyLegends" },
			styles = { "neon" },
			finishes = { "aurora" },
		},
		{
			id = "golden",
			week = 7,
			icon = "🏆",
			mascots = { "golden_trophy" },
			posters = { "goldenController" },
			decor = { "arcade" },
		},
	} :: { Drop },
}

ContentDrops.FIELDS = FIELDS

-- Полночь UTC даты запуска (os.time)
local function parseDate(text: string): number
	local y, m, d = string.match(text, "^(%d+)-(%d+)-(%d+)$")
	assert(y and m and d, "ContentDrops.launchDate: нужен формат ГГГГ-ММ-ДД")
	return DateTime.fromUniversalTime(tonumber(y) :: number, tonumber(m) :: number, tonumber(d) :: number).UnixTimestamp
end

ContentDrops.launchAt = parseDate(ContentDrops.launchDate)

-- Сколько дней от запуска до среды номер week (0 — сам запуск). Среда 1 — первая среда строго
-- после launchDate; запуск в среду — среда 1 через 7 дней. Общая для волн и Config/Features
local WEDNESDAY = 4 -- os.date wday: 1 — воскресенье
local launchWeekday = (os.date("!*t", ContentDrops.launchAt) :: any).wday :: number
local firstWednesday = (WEDNESDAY - launchWeekday) % 7
if firstWednesday == 0 then
	firstWednesday = 7
end
function ContentDrops.wednesdayDay(week: number): number
	if week <= 0 then
		return 0
	end
	return firstWednesday + 7 * (math.floor(week) - 1)
end
for _, drop in ContentDrops.drops do
	drop.day = ContentDrops.wednesdayDay(drop.week)
end

-- День выхода каждого предмета: kind -> id -> day (не в списке — 0)
local releaseDays: { [string]: { [string]: number } } = {}
for _, entry in FIELDS do
	releaseDays[entry.kind] = {}
end
table.sort(ContentDrops.drops, function(a, b)
	return a.week < b.week
end)
for _, drop in ContentDrops.drops do
	for _, entry in FIELDS do
		local ids = (drop :: any)[entry.field] :: { string }?
		if ids then
			for _, id in ids do
				releaseDays[entry.kind][id] = drop.day :: number
			end
		end
	end
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Какой сегодня день после запуска (0 — день запуска и всё до него).
-- В Studio — Config/Debug.contentDayOffset, если задан
-- Где действует AdminContentDay: Studio или закрытый сервер, созданный игрой (ReserveServer:
-- PrivateServerId есть, владельца VIP-сервера нет). На обычных и VIP-серверах атрибут не читаем
function ContentDrops.adminDayAllowed(): boolean
	return RunService:IsStudio() or (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0)
end

function ContentDrops.dayIndex(now: number?): number
	local admin = ReplicatedStorage:GetAttribute("AdminContentDay")
	if type(admin) == "number" and admin == admin and admin >= 0 and ContentDrops.adminDayAllowed() then
		return math.min(math.floor(admin), 100_000)
	end
	local forced = Debug.contentDayOffset
	if forced and RunService:IsStudio() then
		return math.max(math.floor(forced), 0)
	end
	local t = now or serverNow()
	return math.max((math.floor(t) - ContentDrops.launchAt) // DAY, 0)
end

-- День выхода предмета (дней от запуска; 0 — с запуска)
function ContentDrops.releaseDay(kind: Kind, id: string): number
	local days = releaseDays[kind]
	return if days then days[id] or 0 else 0
end

-- Когда предмет выходит (os.time полуночи UTC)
function ContentDrops.releasedAt(kind: Kind, id: string): number
	return ContentDrops.launchAt + ContentDrops.releaseDay(kind, id) * DAY
end

-- Вышел ли предмет к моменту now (по умолчанию — сейчас)
function ContentDrops.isReleased(kind: Kind, id: string, now: number?): boolean
	return ContentDrops.releaseDay(kind, id) <= ContentDrops.dayIndex(now)
end

-- Сколько дней до выхода (0 — уже вышел)
function ContentDrops.daysUntil(kind: Kind, id: string, now: number?): number
	return math.max(ContentDrops.releaseDay(kind, id) - ContentDrops.dayIndex(now), 0)
end

-- Номер последней вышедшей волны (1 — запуск)
function ContentDrops.currentIndex(now: number?): number
	local day = ContentDrops.dayIndex(now)
	local index = 1
	for i, drop in ContentDrops.drops do
		if (drop.day :: number) <= day then
			index = i
		end
	end
	return index
end

-- Следующая волна и сколько до неё дней; nil — все вышли
function ContentDrops.nextDrop(now: number?): (Drop?, number)
	local day = ContentDrops.dayIndex(now)
	for _, drop in ContentDrops.drops do
		local dropDay = drop.day :: number
		if dropDay > day then
			return drop, dropDay - day
		end
	end
	return nil, 0
end

-- Предметы волны по порядку FIELDS: { kind, id }
function ContentDrops.items(drop: Drop): { { kind: Kind, id: string } }
	local list = {}
	for _, entry in FIELDS do
		local ids = (drop :: any)[entry.field] :: { string }?
		if ids then
			for _, id in ids do
				table.insert(list, { kind = entry.kind, id = id })
			end
		end
	end
	return list
end

return ContentDrops
