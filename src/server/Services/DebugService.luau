--!strict
-- Тестовые деньги в Studio, чтобы проверять покупки без разработки игр.
-- На живых серверах выключено.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Debug = require(ReplicatedStorage.Shared.Config.Debug)
local DataService = require(script.Parent.DataService)

local DebugService = {}

local function onPlayerAdded(player: Player)
	-- Профиль грузится асинхронно в DataService
	local profile = DataService.get(player)
	while not profile and player.Parent do
		task.wait(0.2)
		profile = DataService.get(player)
	end
	if profile and profile.cash < Debug.studioStartCash then
		DataService.addCash(player, Debug.studioStartCash - profile.cash)
		warn("[DebugService] Studio: выдано $" .. Debug.studioStartCash .. " для теста")
	end
end

function DebugService.start()
	if not RunService:IsStudio() or Debug.studioStartCash <= 0 then
		return
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DebugService
