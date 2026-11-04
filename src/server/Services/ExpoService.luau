--!strict
-- Игровая выставка раз в час: лучшая игра сервера за раунд получает приз.
-- Вход — ExpoService.onGameReleased из DevelopmentService.release.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Expo = require(ReplicatedStorage.Shared.Config.Expo)
local ExpoRemotes = require(ReplicatedStorage.Shared.ExpoRemotes)
local DataService = require(script.Parent.DataService)

type Entry = { player: Player, game: string, score: number, points: number, at: number }

local ExpoService = {}
-- Лучшая игра каждого игрока за текущий раунд
local best: { [Player]: Entry } = {}
local leader: Entry? = nil

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

local function recomputeLeader()
	local top: Entry? = nil
	for _, entry in best do
		if better(entry, top) then
			top = entry
		end
	end
	leader = top
end

local function publishLeader()
	ReplicatedStorage:SetAttribute("ExpoLeaderPlayer", if leader then leader.player.DisplayName else nil)
	ReplicatedStorage:SetAttribute("ExpoLeaderGame", if leader then leader.game else nil)
	ReplicatedStorage:SetAttribute("ExpoLeaderScore", if leader then leader.score else nil)
end

-- name уже отфильтрован TextService в DevelopmentService (его видят все игроки)
function ExpoService.onGameReleased(player: Player, info: { name: string, score: number, points: number })
	local entry: Entry =
		{ player = player, game = info.name, score = info.score, points = info.points, at = os.clock() }
	if better(entry, best[player]) then
		best[player] = entry
		recomputeLeader()
		publishLeader()
	end
end

local function finishRound()
	local winner = leader
	table.clear(best)
	leader = nil
	publishLeader()
	if winner and winner.player.Parent and DataService.get(winner.player) then
		DataService.addCash(winner.player, Expo.prize)
		ExpoRemotes.ExpoResult:FireAllClients({
			winner = winner.player.DisplayName,
			winnerId = winner.player.UserId,
			game = winner.game,
			score = winner.score,
			prize = Expo.prize,
		})
	else
		-- Никто не выпустил игру (или победитель вышел) — приз не разыгран
		ExpoRemotes.ExpoResult:FireAllClients({ prize = Expo.prize })
	end
end

function ExpoService.start()
	local interval = if RunService:IsStudio() then Expo.studioIntervalSeconds else Expo.intervalSeconds
	Players.PlayerRemoving:Connect(function(player)
		-- Ушедший игрок выбывает: лидером становится следующий
		if best[player] then
			best[player] = nil
			recomputeLeader()
			publishLeader()
		end
	end)
	task.spawn(function()
		while true do
			local endsAt = os.time() + interval
			ReplicatedStorage:SetAttribute("ExpoEndsAt", endsAt)
			task.wait(interval)
			finishRound()
		end
	end)
end

return ExpoService
