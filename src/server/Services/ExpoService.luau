--!strict
-- Игровая выставка раз в час: лучшая игра сервера за раунд получает приз.
-- Вход — ExpoService.onGameReleased из DevelopmentService.release.
-- Ушедший игрок остаётся в зачёте до конца часа; если он победил офлайн,
-- приз ждёт его в DataStore и начисляется при следующем входе.
-- Против фарма: раунды идут по часам одновременно на всех серверах, нужен минимум
-- участников, и один игрок получает не больше одного приза за раунд во всех серверах.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Expo = require(ReplicatedStorage.Shared.Config.Expo)
local ExpoRemotes = require(ReplicatedStorage.Shared.ExpoRemotes)
local DataService = require(script.Parent.DataService)

type Entry = { userId: number, displayName: string, game: string, score: number, points: number, at: number }

local ExpoService = {}
-- Лучшая игра каждого игрока за текущий раунд (по UserId: игрок может выйти)
local best: { [number]: Entry } = {}
local leader: Entry? = nil

local pendingStore: DataStore? = nil
pcall(function()
	pendingStore = DataStoreService:GetDataStore("ExpoPrizes_v1")
end)

-- Запись в ExpoPrizes с повтором, как DataService.write: 3 попытки, пауза 1 с, 2 с.
-- Отчёт #2 п. 8: одна ошибка AccessForbidden — и приз раунда пропадал
local WRITE_ATTEMPTS = 3
-- Офлайн-победителю: если и повторы не помогли, пробуем ещё позже в фоне (с)
local LATE_RETRY_DELAYS = { 30, 120, 300 }

local function updateWithRetry(key: string, transform: (any) -> any): (boolean, any)
	local store = pendingStore
	if not store then
		return false, "DataStore unavailable"
	end
	local lastErr: any = nil
	for attempt = 1, WRITE_ATTEMPTS do
		local ok, err = pcall(function()
			store:UpdateAsync(key, transform :: any)
		end)
		if ok then
			return true, nil
		end
		lastErr = err
		if attempt < WRITE_ATTEMPTS then
			task.wait(attempt)
		end
	end
	return false, lastErr
end

local function better(a: Entry, b: Entry?): boolean
	if not b then
		return true
	end
	if a.score ~= b.score then
		return a.score > b.score
	end
	if a.points ~= b.points then
		return a.points > b.points
	end
	return a.at < b.at
end

local function publishLeader()
	ReplicatedStorage:SetAttribute("ExpoLeaderPlayer", if leader then leader.displayName else nil)
	ReplicatedStorage:SetAttribute("ExpoLeaderGame", if leader then leader.game else nil)
	ReplicatedStorage:SetAttribute("ExpoLeaderScore", if leader then leader.score else nil)
end

-- name уже отфильтрован TextService в DevelopmentService (его видят все игроки)
function ExpoService.onGameReleased(player: Player, info: { name: string, score: number, points: number })
	local entry: Entry = {
		userId = player.UserId,
		displayName = player.DisplayName,
		game = info.name,
		score = info.score,
		points = info.points,
		at = os.clock(),
	}
	if better(entry, best[player.UserId]) then
		best[player.UserId] = entry
		if better(entry, leader) then
			leader = entry
			publishLeader()
		end
	end
end

-- Приз победителю, который уже вышел: копим в DataStore до его входа
local function savePending(userId: number, amount: number)
	if not pendingStore then
		return
	end
	local ok, err = updateWithRetry("user_" .. userId, function(old)
		local data = if type(old) == "table" then old else { amount = tonumber(old) or 0 }
		data.amount = (tonumber(data.amount) or 0) + amount
		return data
	end)
	if not ok then
		warn(
			"[ExpoService] Не удалось сохранить приз офлайн-победителю:",
			userId,
			amount,
			err
		)
	end
end

local function claimPending(player: Player)
	local store = pendingStore
	if not store then
		return
	end
	-- Сначала дождаться профиля: если игрока кикнет защита сессий или он выйдет,
	-- приз должен остаться в копилке, а не пропасть
	while not DataService.get(player) and player.Parent do
		task.wait(0.2)
	end
	if not DataService.get(player) then
		return
	end
	local amount = 0
	local ok, err = updateWithRetry("user_" .. player.UserId, function(old)
		local data = if type(old) == "table" then old else { amount = tonumber(old) or 0 }
		amount = tonumber(data.amount) or 0
		if amount <= 0 then
			return nil
		end
		data.amount = 0
		return data
	end)
	if not ok then
		-- Приз остался в копилке: заберём при следующем входе
		warn(
			"[ExpoService] Не удалось забрать приз выставки:",
			player.UserId,
			err
		)
	end
	if not ok or amount <= 0 then
		return
	end
	if player.Parent and DataService.get(player) then
		DataService.addCash(player, amount)
		task.spawn(DataService.save, player)
	else
		-- Вышел, пока шёл запрос: вернуть приз в копилку
		task.spawn(savePending, player.UserId, amount)
	end
end

-- Отметить победу в раунде во всех серверах сразу. toPending — положить приз в копилку
-- для офлайн-игрока. "ok" — приз можно выдать (в этом раунде он ещё не выигрывал),
-- "duplicate" — уже выиграл на другом сервере, "error" — DataStore не ответил и после повторов
local function claimRound(userId: number, roundId: number, toPending: boolean): string
	if not pendingStore then
		-- Нет DataStore (Studio без API Services): выдаём только онлайн-игроку
		return if toPending then "error" else "ok"
	end
	local allowed = false
	local ok, err = updateWithRetry("user_" .. userId, function(old)
		local data = if type(old) == "table" then old else { amount = tonumber(old) or 0 }
		if data.lastRound == roundId then
			allowed = false
			return nil
		end
		allowed = true
		data.lastRound = roundId
		if toPending then
			data.amount = (tonumber(data.amount) or 0) + Expo.prize
		end
		return data
	end)
	if not ok then
		warn(
			"[ExpoService] Не удалось записать победу в выставке:",
			userId,
			roundId,
			err
		)
		return "error"
	end
	return if allowed then "ok" else "duplicate"
end

-- Офлайн-победитель, а DataStore не ответил: пробуем записать приз ещё несколько раз позже
local function claimRoundLater(userId: number, roundId: number)
	for _, delay in LATE_RETRY_DELAYS do
		task.wait(delay)
		local result = claimRound(userId, roundId, true)
		if result ~= "error" then
			return
		end
	end
	warn(
		"[ExpoService] Приз выставки не сохранён после всех повторов:",
		userId,
		roundId,
		Expo.prize
	)
end

local function finishRound(roundId: number, minParticipants: number)
	local winner = leader
	local participants = 0
	for _ in best do
		participants += 1
	end
	table.clear(best)
	leader = nil
	publishLeader()
	if not winner then
		ExpoRemotes.ExpoResult:FireAllClients({ prize = Expo.prize })
		return
	end
	if participants < minParticipants then
		ExpoRemotes.ExpoResult:FireAllClients({ prize = Expo.prize, tooFew = true, need = minParticipants })
		return
	end
	local online = Players:GetPlayerByUserId(winner.userId)
	if online and DataService.get(online) then
		local result = claimRound(winner.userId, roundId, false)
		if result == "duplicate" then
			return
		end
		-- "error": всё равно выдаём онлайн-победителю. Дубль почти невозможен: раунд кончается
		-- одновременно везде, а профиль открыт только на одном сервере (метка сессии DataService).
		-- Лишний приз возможен, только если он же победил офлайн на другом сервере И здесь
		-- DataStore сбоит — игрок этим не управляет, а потерять честный приз хуже
		if result == "error" then
			warn(
				"[ExpoService] Победа не отмечена в DataStore, приз выдаём по данным сервера:",
				winner.userId,
				roundId
			)
		end
		if not online.Parent or not DataService.get(online) then
			-- Вышел, пока ждали DataStore: приз — в копилку (раунд уже отмечен — просто сумму)
			if result == "ok" then
				task.spawn(savePending, winner.userId, Expo.prize)
			elseif pendingStore then
				task.spawn(claimRoundLater, winner.userId, roundId)
			end
		else
			DataService.addCash(online, Expo.prize)
			task.spawn(DataService.save, online)
		end
	else
		local result = claimRound(winner.userId, roundId, true)
		if result == "duplicate" or (result == "error" and not pendingStore) then
			return
		elseif result == "error" then
			task.spawn(claimRoundLater, winner.userId, roundId)
		end
	end
	ExpoRemotes.ExpoResult:FireAllClients({
		winner = winner.displayName,
		winnerId = winner.userId,
		game = winner.game,
		score = winner.score,
		prize = Expo.prize,
	})
end

function ExpoService.start()
	local isStudio = RunService:IsStudio()
	local interval = if isStudio then Expo.studioIntervalSeconds else Expo.intervalSeconds
	local minParticipants = if isStudio then Expo.studioMinParticipants else Expo.minParticipants
	Players.PlayerAdded:Connect(function(player)
		task.spawn(claimPending, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(claimPending, player)
	end
	task.spawn(function()
		while true do
			-- Раунд кончается на границе часа одновременно на всех серверах: номер раунда общий
			local endsAt = (os.time() // interval + 1) * interval
			ReplicatedStorage:SetAttribute("ExpoEndsAt", endsAt)
			task.wait(math.max(endsAt - os.time(), 1))
			finishRound(endsAt // interval, minParticipants)
		end
	end)
end

return ExpoService
