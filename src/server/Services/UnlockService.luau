--!strict
-- Покупка жанров и тем за игровую валюту. Цены — Config/Genres и Config/Topics.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local DataService = require(script.Parent.DataService)

local UnlockService = {}

local function onUnlock(player: Player, kind: any, id: any)
	if type(kind) ~= "string" or type(id) ~= "string" then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local cost: number
	local unlocked: { [string]: boolean }
	if kind == "genre" and Genres[id] then
		cost, unlocked = Genres[id].unlockCost, profile.unlockedGenres
	elseif kind == "topic" and Topics[id] then
		cost, unlocked = Topics[id].unlockCost, profile.unlockedTopics
	else
		return
	end

	if unlocked[id] then
		return
	end
	if DataService.trySpend(player, cost) then
		unlocked[id] = true
		DataService.replicate(player)
	end
end

function UnlockService.start()
	Remotes.UnlockContent.OnServerEvent:Connect(onUnlock)
end

return UnlockService
