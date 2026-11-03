--!strict
-- Таблица лидеров (шаг 4.5): OrderedDataStore «лучшая оценка» и «всего игр».
-- Запись — не чаще раза в WRITE_INTERVAL на игрока и только если значение изменилось.
-- Топ-10 читается раз в TOP_INTERVAL и рассылается всем. Все вызовы DataStore — в pcall:
-- в Studio без доступа к API Services клиент получает available = false («недоступно»).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestRemotes = require(ReplicatedStorage.Shared.QuestRemotes)
local DataService = require(script.Parent.DataService)

local WRITE_INTERVAL = 60
local WRITE_CHECK = 10
local TOP_INTERVAL = 120
local TOP_SIZE = 10
local REQUEST_COOLDOWN = 1

type Entry = { name: string, value: number }
type Board = { available: boolean, best: { Entry }, games: { Entry } }
type Written = { best: number, games: number, at: number }

local LeaderboardService = {}

local bestStore: OrderedDataStore? = nil
local gamesStore: OrderedDataStore? = nil
do
	local ok, err = pcall(function()
		bestStore = DataStoreService:GetOrderedDataStore("Leaderboard_BestScore_v1")
		gamesStore = DataStoreService:GetOrderedDataStore("Leaderboard_Games_v1")
	end)
	if not ok then
		warn("[LeaderboardService] OrderedDataStore недоступен:", err)
	end
end

local board: Board = { available = false, best = {}, games = {} }
local written: { [number]: Written } = {} -- по UserId: переживает выход игрока
local pendingWrite: { [number]: boolean } = {}
local names: { [number]: string } = {}
local lastRequest: { [Player]: number } = {}

local function write(userId: number, best: number, games: number)
	local key = tostring(userId)
	local okBest, errBest = pcall(function()
		(bestStore :: OrderedDataStore):SetAsync(key, best)
	end)
	local okGames, errGames = pcall(function()
		(gamesStore :: OrderedDataStore):SetAsync(key, games)
	end)
	if not okBest or not okGames then
		warn("[LeaderboardService] Запись не удалась:", errBest, errGames)
	end
end

-- Записать, если значения изменились и с прошлой записи прошло WRITE_INTERVAL;
-- иначе (при выходе игрока) — отложить до конца интервала
local function maybeWrite(userId: number, best: number, games: number, deferIfEarly: boolean)
	if not bestStore or not gamesStore or userId <= 0 then
		return
	end
	local w = written[userId]
	if w and w.best == best and w.games == games then
		return
	end
	local now = os.clock()
	local wait = if w then w.at + WRITE_INTERVAL - now else 0
	if wait > 0 then
		if deferIfEarly and not pendingWrite[userId] then
			pendingWrite[userId] = true
			task.delay(wait, function()
				pendingWrite[userId] = nil
				maybeWrite(userId, best, games, false)
			end)
		end
		return
	end
	-- Отмечаем до yield, чтобы параллельный вызов не записал второй раз
	written[userId] = { best = best, games = games, at = now }
	write(userId, best, games)
end

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.Name
	end
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and type(result) == "string" then result else "#" .. userId
	names[userId] = name
	return name
end

local function readTop(store: OrderedDataStore): { Entry }?
	local ok, result = pcall(function()
		return store:GetSortedAsync(false, TOP_SIZE):GetCurrentPage()
	end)
	if not ok then
		warn("[LeaderboardService] Чтение топа не удалось:", result)
		return nil
	end
	local entries: { Entry } = {}
	for _, item in result :: any do
		local userId = tonumber(item.key)
		if userId then
			table.insert(entries, { name = nameOf(userId), value = item.value })
		end
	end
	return entries
end

local function refreshTop()
	if not bestStore or not gamesStore then
		board = { available = false, best = {}, games = {} }
	else
		local best = readTop(bestStore)
		local games = readTop(gamesStore)
		if best and games then
			board = { available = true, best = best, games = games }
		else
			board = { available = false, best = {}, games = {} }
		end
	end
	QuestRemotes.LeaderboardData:FireAllClients(board)
end

function LeaderboardService.start()
	QuestRemotes.RequestQuestData.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
			return
		end
		lastRequest[player] = now
		QuestRemotes.LeaderboardData:FireClient(player, board)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		local profile = DataService.get(player)
		if profile then
			maybeWrite(player.UserId, profile.bestScore, profile.gamesReleased, true)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(WRITE_CHECK)
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile then
					task.spawn(maybeWrite, player.UserId, profile.bestScore, profile.gamesReleased, false)
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			refreshTop()
			task.wait(TOP_INTERVAL)
		end
	end)
end

return LeaderboardService
