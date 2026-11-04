--!strict
-- Игровая выставка раз в час: лучшая игра сервера за раунд получает приз.
-- Вход — ExpoService.onGameReleased из DevelopmentService.release.
-- Ушедший игрок остаётся в зачёте до конца часа; если он победил офлайн,
-- приз ждёт его в DataStore и начисляется при следующем входе.

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
	local store = pendingStore
	if not store then
		return
	end
	local ok, err = pcall(function()
		store:UpdateAsync("user_" .. userId, function(old)
			return (tonumber(old) or 0) + amount
		end)
	end)
	if not ok then
		warn(
			"[ExpoService] Не удалось сохранить приз офлайн-победителю:",
			err
		)
	end
end

local function claimPending(player: Player)
	local store = pendingStore
	if not store then
		return
	end
	local amount = 0
	local ok = pcall(function()
		store:UpdateAsync("user_" .. player.UserId, function(old)
			amount = tonumber(old) or 0
			return if amount > 0 then 0 else nil
		end)
	end)
	if not ok or amount <= 0 then
		return
	end
	-- Профиль грузится асинхронно в DataService
	while not DataService.get(player) and player.Parent do
		task.wait(0.2)
	end
	if DataService.get(player) then
		DataService.addCash(player, amount)
	end
end

local function finishRound()
	local winner = leader
	table.clear(best)
	leader = nil
	publishLeader()
	if not winner then
		ExpoRemotes.ExpoResult:FireAllClients({ prize = Expo.prize })
		return
	end
	local online = Players:GetPlayerByUserId(winner.userId)
	if online and DataService.get(online) then
		DataService.addCash(online, Expo.prize)
	else
		task.spawn(savePending, winner.userId, Expo.prize)
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
	local interval = if RunService:IsStudio() then Expo.studioIntervalSeconds else Expo.intervalSeconds
	Players.PlayerAdded:Connect(function(player)
		task.spawn(claimPending, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(claimPending, player)
	end
	task.spawn(function()
		while true do
			ReplicatedStorage:SetAttribute("ExpoEndsAt", os.time() + interval)
			task.wait(interval)
			finishRound()
		end
	end)
end

return ExpoService
