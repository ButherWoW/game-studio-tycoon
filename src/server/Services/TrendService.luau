--!strict
-- Модные жанры (шаг 4.3): раз в Config/Trends.intervalSeconds выбираем случайную пару
-- жанр + тема (из всех, не только открытых) и объявляем её на весь сервер.
-- Клиент читает атрибуты ReplicatedStorage: TrendGenre, TrendTopic, TrendEndsAt (os.time).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local ContentDrops = require(ReplicatedStorage.Shared.Config.ContentDrops)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local Trends = require(ReplicatedStorage.Shared.Config.Trends)

local TrendService = {}

local currentGenre: string? = nil
local currentTopic: string? = nil
local rng = Random.new()

local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for id in map do
		table.insert(keys, id)
	end
	table.sort(keys)
	return keys
end

local genreIds = sortedKeys(Genres)
-- Сезонные темы (Config/Holidays) в тренд не попадают: большую часть года они закрыты
local topicIds = {}
for _, id in sortedKeys(Topics) do
	if not Topics[id].seasonal then
		table.insert(topicIds, id)
	end
end

-- Только вышедшие по графику контента (Config/ContentDrops)
local function released(ids: { string }, kind: ContentDrops.Kind): { string }
	local list = {}
	for _, id in ids do
		if ContentDrops.isReleased(kind, id) then
			table.insert(list, id)
		end
	end
	return if #list > 0 then list else ids
end

local function pickTrend()
	-- Не повторяем ту же пару два раза подряд
	local genres = released(genreIds, "genre")
	local topics = released(topicIds, "topic")
	local genreId, topicId
	repeat
		genreId = genres[rng:NextInteger(1, #genres)]
		topicId = topics[rng:NextInteger(1, #topics)]
	until genreId ~= currentGenre or topicId ~= currentTopic or #genres * #topics <= 1
	currentGenre, currentTopic = genreId, topicId
	ReplicatedStorage:SetAttribute("TrendGenre", genreId)
	ReplicatedStorage:SetAttribute("TrendTopic", topicId)
	ReplicatedStorage:SetAttribute("TrendEndsAt", os.time() + Trends.intervalSeconds)
end

-- Бонус к оценке за модную пару: Config/Trends.scoreBonus или 0
function TrendService.getBonus(genreId: string, topicId: string): number
	if genreId == currentGenre and topicId == currentTopic then
		return Trends.scoreBonus
	end
	return 0
end

-- Текущая модная пара (nil до старта сервиса)
function TrendService.current(): (string?, string?)
	return currentGenre, currentTopic
end

function TrendService.start()
	pickTrend()
	task.spawn(function()
		while true do
			task.wait(Trends.intervalSeconds)
			pickTrend()
		end
	end)
end

return TrendService
