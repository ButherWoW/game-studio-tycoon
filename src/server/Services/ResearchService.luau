--!strict
-- Исследования (шаг 3.4, issue #8): ОИ за выпущенные игры и покупка узлов дерева.
-- Данные — profile.research = { points, owned } (лениво, defaultProfile не трогаем).
-- Жанры открываем здесь; остальные эффекты отдаём через getModifiers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Research = require(ReplicatedStorage.Shared.Config.Research)
local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local ResearchRemotes = require(ReplicatedStorage.Shared.ResearchRemotes)
local DataService = require(script.Parent.DataService)

type ResearchData = { points: number, owned: { [string]: boolean } }

local REQUEST_COOLDOWN = 0.5 -- секунд между запросами состояния от одного игрока

local ResearchService = {}
local lastRequest: { [Player]: number } = {}

-- Данные исследований игрока; nil, пока профиль не загружен
local function getData(player: Player): ResearchData?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local p = profile :: any
	if type(p.research) ~= "table" then
		p.research = { points = 0, owned = {} }
	end
	local data = p.research :: ResearchData
	if type(data.points) ~= "number" or data.points ~= data.points then
		data.points = 0
	end
	if type(data.owned) ~= "table" then
		data.owned = {}
	end
	return data
end

local function replicate(player: Player)
	local data = getData(player)
	if data then
		ResearchRemotes.ResearchChanged:FireClient(player, {
			points = data.points,
			owned = data.owned,
		})
	end
end

-- Вызывать из DevelopmentService при релизе: ОИ = оценка игры
function ResearchService.onGameReleased(player: Player, score: number)
	if type(score) ~= "number" or score ~= score or score == math.huge then
		return
	end
	local data = getData(player)
	if not data then
		return
	end
	local gained = math.floor(math.clamp(score, 0, 10)) * Research.POINTS_PER_SCORE
	if gained <= 0 then
		return
	end
	data.points += gained
	replicate(player)
end

-- Множители от изученных узлов (см. Research.Modifiers). Без профиля — нейтральные
function ResearchService.getModifiers(player: Player): Research.Modifiers
	local data = getData(player)
	return Research.modifiers(if data then data.owned else {})
end

function ResearchService.isResearched(player: Player, nodeId: string): boolean
	local data = getData(player)
	return data ~= nil and data.owned[nodeId] == true
end

local function onBuy(player: Player, nodeId: any)
	if type(nodeId) ~= "string" then
		return
	end
	local node = Research.byId[nodeId]
	local profile = DataService.get(player)
	local data = getData(player)
	if not node or not profile or not data then
		return
	end
	if data.owned[nodeId] or not Research.requirementsMet(node, data.owned) or data.points < node.cost then
		return
	end

	-- Без yield между проверкой и списанием: двойной клик не спишет дважды
	data.points -= node.cost
	data.owned[nodeId] = true

	local genreId = node.effect.unlockGenre
	if genreId and Genres[genreId] and not profile.unlockedGenres[genreId] then
		profile.unlockedGenres[genreId] = true
		DataService.replicate(player)
	end
	replicate(player)
end

local function onRequest(player: Player)
	local now = os.clock()
	local last = lastRequest[player]
	if last and now - last < REQUEST_COOLDOWN then
		return
	end
	lastRequest[player] = now
	replicate(player)
end

function ResearchService.start()
	ResearchRemotes.BuyResearch.OnServerEvent:Connect(onBuy)
	ResearchRemotes.RequestResearch.OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return ResearchService
