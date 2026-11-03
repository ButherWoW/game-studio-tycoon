--!strict
-- Туториал: прогресс шагов живёт на клиенте, факт завершения и награда — здесь.
-- Флаг в профиле: (profile :: any).tutorialDone. Клиенту — атрибут игрока TutorialActive.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialRemotes = require(ReplicatedStorage.Shared.TutorialRemotes)
local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local DataService = require(script.Parent.DataService)

local PROFILE_WAIT = 0.2

local TutorialService = {}

-- Ленивая инициализация: у старых профилей поля нет. Кто уже выпускал игры — туториал не нужен
local function isDone(profile: DataService.Profile): boolean
	local p = profile :: any
	if p.tutorialDone == nil then
		p.tutorialDone = profile.gamesReleased > 0
	end
	return p.tutorialDone == true
end

local function onPlayerAdded(player: Player)
	local profile
	repeat
		profile = DataService.get(player)
		if not profile then
			task.wait(PROFILE_WAIT)
		end
	until profile or not player.Parent
	if not profile then
		return
	end
	player:SetAttribute("TutorialActive", not isDone(profile))
end

local function onFinish(player: Player, completed: any)
	if type(completed) ~= "boolean" then
		return
	end
	local profile = DataService.get(player)
	if not profile or isDone(profile) then
		return
	end
	(profile :: any).tutorialDone = true
	player:SetAttribute("TutorialActive", false)
	-- Награда только за прохождение: в туториале игрок выпускает первую игру
	if completed and profile.gamesReleased > 0 then
		DataService.addCash(player, Tutorial.reward)
	end
end

function TutorialService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	TutorialRemotes.TutorialFinish.OnServerEvent:Connect(onFinish)
end

return TutorialService
