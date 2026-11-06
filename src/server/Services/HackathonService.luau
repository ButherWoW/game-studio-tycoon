--!strict
-- Ночь хакатона (Config/Hackathon): раз в час на 10 минут разработка на сервере ×2 быстрее.
-- Окно считается по os.time одинаково везде; клиенту — атрибуты ReplicatedStorage
-- HackathonStartsAt / HackathonEndsAt (плашка с отсчётом и объявление за минуту).
-- DevelopmentService в каждом тике спрашивает speedMultiplier().

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hackathon = require(ReplicatedStorage.Shared.Config.Hackathon)
local FeatureReleaseService = require(script.Parent.FeatureReleaseService)

local HackathonService = {}

-- Во сколько раз быстрее идёт разработка прямо сейчас (1 — хакатона нет)
function HackathonService.speedMultiplier(): number
	return if Hackathon.active() then Hackathon.speedMultiplier else 1
end

local function logStart()
	local module = script.Parent:FindFirstChild("AnalyticsService")
	if not module or not module:IsA("ModuleScript") then
		return
	end
	local analytics = require(module) :: any
	if type(analytics.logLiveOps) ~= "function" then
		return
	end
	-- Событие на каждого игрока в игре: сколько людей застали хакатон
	for _, player in Players:GetPlayers() do
		pcall(analytics.logLiveOps, player, "hackathon", 1, "start")
	end
end

local function startNow()
	task.spawn(function()
		local announcedStart = 0
		while true do
			local window = Hackathon.window()
			ReplicatedStorage:SetAttribute("HackathonStartsAt", window.startsAt)
			ReplicatedStorage:SetAttribute("HackathonEndsAt", window.endsAt)
			ReplicatedStorage:SetAttribute("HackathonMultiplier", Hackathon.speedMultiplier)
			ReplicatedStorage:SetAttribute("HackathonAnnounceSeconds", window.announceSeconds)
			local now = os.time()
			if now >= window.startsAt and now < window.endsAt and announcedStart ~= window.startsAt then
				announcedStart = window.startsAt
				pcall(logStart)
			end
			task.wait(1)
		end
	end)
end

-- Обновления по средам (Config/Features): до выхода системы «hackathon» сервис спит — remotes
-- заглушены, циклы и обработчики не запущены; вышла (в т. ч. пока сервер работает) — startNow()
function HackathonService.start()
	FeatureReleaseService.whenReleased("hackathon", "HackathonService", startNow)
end

return HackathonService
