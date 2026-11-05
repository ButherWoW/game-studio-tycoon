--!strict
-- «Игра недели» между серверами (GotwService) и «Зал славы» в парке (HallOfFameService).
-- Неделя — как у рейтингов экскурсий (Tours.weekId: UTC, с понедельника); ключ хранилища —
-- ISO-неделя «2026-W45» (Gotw.weekKey).
--
-- DataStore:
--   GOTW_<isoWeek> (OrderedDataStore): ключ userId -> score × scoreFactor + доход (лучшая игра недели)
--   GotwEntries_v1 (DataStore): ключ "<isoWeek>_<userId>" -> { name, studio, genreId, score, revenue }
--   StudioCards_v1 (DataStore): ключ userId -> { studio } — название студии для Зала славы

local Tours = require(script.Parent.Tours)

local DAY = 86400
local WEEK = 7 * DAY
local WEEK_SHIFT = 3 * DAY -- как в Tours: неделя с понедельника

local Gotw = {
	-- Сортировка: сначала оценка, при равенстве — доход. Доход не больше scoreFactor − 1,
	-- 10 × scoreFactor < 2^53: число без потери точности
	scoreFactor = 1e14,
	topSize = 10,

	-- Запись: изменённых игроков раз в flushSeconds, не больше writeBatch за проход и не чаще
	-- writeSeconds на игрока; при выходе и BindToClose — сразу
	flushSeconds = 60,
	writeBatch = 8,
	writeSeconds = 2 * 60,
	-- Чтение топа текущей недели (один GetSortedAsync + GetAsync только изменившихся строк)
	readSeconds = 5 * 60,
	-- Запрос окна от клиента не чаще
	requestCooldown = 2,

	-- Награда за место 1..10 прошлой недели: минуты дохода (RewardService), титул и статуэтка
	rewardMinutes = { 60, 50, 45, 40, 35, 30, 30, 25, 25, 20 } :: { number },
	-- Титул над головой и статуэтка на полке хитов — до конца недели награждения
	-- Статуэтка: модель ServerStorage.Upgrades.Trophy_GOTW (импорт), иначе из деталей
	trophyModel = "Trophy_GOTW",
	trophyOffset = CFrame.new(4.4, 5, 0), -- на крыше полки HitShelf (верхняя доска y 4.9 ± 0.1, локально)

	-- Зал славы: топ-3 студии прошлой недели = лайки недели (TourService, LikesWeekly_<weekId>)
	-- + очки за место в «Игре недели»
	hallRefreshSeconds = 4 * 60,
	hallLikesTop = 20, -- сколько строк лайков прошлой недели читать
	hallGotwPoints = { 50, 40, 32, 26, 21, 17, 14, 11, 9, 7 } :: { number },
	hallAvatarScale = 0.7,
}

-- ISO-неделя «2026-W45» по Tours.weekId: четверг недели определяет год и номер
function Gotw.weekKey(weekId: number): string
	local monday = weekId * WEEK - WEEK_SHIFT
	local thursday = os.date("!*t", monday + 3 * DAY) :: any
	local week = (thursday.yday - 1) // 7 + 1
	return string.format("%d-W%02d", thursday.year, week)
end

function Gotw.storeName(weekId: number): string
	return "GOTW_" .. Gotw.weekKey(weekId)
end

function Gotw.entryKey(weekId: number, userId: number): string
	return Gotw.weekKey(weekId) .. "_" .. userId
end

-- Значение для OrderedDataStore
function Gotw.value(score: number, revenue: number): number
	local s = math.clamp(math.floor(score), 0, 10)
	local r = math.clamp(math.floor(revenue), 0, Gotw.scoreFactor - 1)
	return s * Gotw.scoreFactor + r
end

-- Воскресенье по UTC: день объявления (плашка «итоги сегодня»)
function Gotw.isSunday(now: number?): boolean
	local t = os.date("!*t", math.floor(now or os.time())) :: any
	return t.wday == 1
end

function Gotw.weekId(now: number?): number
	return Tours.weekId(now)
end

function Gotw.weekLeft(now: number?): number
	return Tours.weekLeft(now)
end

-- Конец недели weekId (os.time)
function Gotw.weekEndsAt(weekId: number): number
	return (weekId + 1) * WEEK - WEEK_SHIFT
end

return Gotw
