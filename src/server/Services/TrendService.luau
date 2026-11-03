--!strict
-- Модные жанры (шаг 4.3): раз в Config/Trends.intervalSeconds выбираем случайную пару
-- жанр + тема (из всех, не только открытых) и объявляем её на весь сервер.
-- Клиент читает атрибуты ReplicatedStorage: TrendGenre, TrendTopic, TrendEndsAt (os.time).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Genres = require(ReplicatedStorage.Shared.Config.Genres)
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
local topicIds = sortedKeys(Topics)

local function pickTrend()
	-- Не повторяем ту же пару два раза подряд
	local genreId, topicId
	repeat
		genreId = genreIds[rng:NextInteger(1, #genreIds)]
		topicId = topicIds[rng:NextInteger(1, #topicIds)]
	until genreId ~= currentGenre or topicId ~= currentTopic or #genreIds * #topicIds <= 1
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
