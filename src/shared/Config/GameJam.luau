--!strict
-- Еженедельный гейм-джем: тема (жанр + тема игры) выбирается по номеру недели одинаково
-- на всех серверах и у клиента. Игры по теме за неделю — в общий топ (OrderedDataStore
-- GameJam_<weekId>): лучшая оценка, при равенстве — больше доход. Награды — при входе после конца недели.

local RunService = game:GetService("RunService")

local Debug = require(script.Parent.Debug)
local Genres = require(script.Parent.Genres)
local Topics = require(script.Parent.Topics)

export type Reward = { incomeMinutes: number, flag: string? }
export type Tier = "top10" | "top100" | "participated"

local WEEK = 7 * 24 * 60 * 60
-- 1970-01-01 — четверг: со сдвигом в 4 дня неделя начинается в понедельник 00:00 UTC
local MONDAY_OFFSET = 4 * 24 * 60 * 60
-- Оценка в старших разрядах значения, доход — в младших (тайбрейк)
local SCORE_BASE = 1e12

local GameJam = {
	storePrefix = "GameJam_",
	-- Запись результата игрока не чаще, с
	writeInterval = 120,
	topSize = 100,
	-- Топ перечитывается раз в столько секунд
	topRefreshSeconds = 300,
	-- После конца недели ждём, пока все серверы допишут результаты, потом выдаём награды
	settleSeconds = 180,
	rewards = {
		top10 = { incomeMinutes = 120, flag = "jamTop10" },
		top100 = { incomeMinutes = 60, flag = "jamTop100" },
		participated = { incomeMinutes = 15 },
	} :: { [Tier]: Reward },
}

local function sortedIds(source: { [string]: any }, skip: (any) -> boolean): { string }
	local ids = {}
	for id, item in source do
		if not skip(item) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

local GENRE_IDS = sortedIds(Genres, function()
	return false
end)
-- Праздничные темы открыты не всегда — в джем не берём
local TOPIC_IDS = sortedIds(Topics, function(topic)
	return topic.seasonal ~= nil
end)

local function studio(): boolean
	return RunService:IsStudio()
end

-- Длина недели: в Studio можно укоротить (Config/Debug.jamStudioWeekSeconds)
function GameJam.weekSeconds(): number
	local short = Debug.jamStudioWeekSeconds
	return if short and short > 0 and studio() then short else WEEK
end

-- Номер текущей недели (в Studio можно подменить: Config/Debug.jamForceWeek)
function GameJam.weekIndex(now: number?): number
	local forced = Debug.jamForceWeek
	if forced and studio() then
		return forced
	end
	local length = GameJam.weekSeconds()
	local offset = if length == WEEK then MONDAY_OFFSET else 0
	return ((now or os.time()) - offset) // length
end

function GameJam.weekId(index: number): string
	return "w" .. index
end

-- Конец недели index (os.time)
function GameJam.weekEndsAt(index: number): number
	local length = GameJam.weekSeconds()
	local offset = if length == WEEK then MONDAY_OFFSET else 0
	return (index + 1) * length + offset
end

-- Тема недели: жанр и тема игры. Разные шаги, чтобы пары не повторялись подряд
function GameJam.theme(index: number): (string, string)
	local genre = GENRE_IDS[(index * 7 + 3) % #GENRE_IDS + 1]
	local topic = TOPIC_IDS[(index * 11 + 5) % #TOPIC_IDS + 1]
	return genre, topic
end

-- Значение для OrderedDataStore (целое): оценка × 10^12 + доход (до 10^12 − 1)
function GameJam.encode(score: number, revenue: number): number
	return math.floor(score) * SCORE_BASE + math.clamp(math.floor(revenue), 0, SCORE_BASE - 1)
end

function GameJam.decode(value: number): (number, number)
	return value // SCORE_BASE, value % SCORE_BASE
end

-- Уровень награды по месту (nil — места нет: не попал в топ-100, значит просто участник)
function GameJam.tierFor(rank: number?): Tier
	if rank and rank <= 10 then
		return "top10"
	elseif rank and rank <= GameJam.topSize then
		return "top100"
	end
	return "participated"
end

return GameJam
