--!strict
-- Звуки и фоновая музыка (5.6). Ключи и громкость — Config/Sounds; id = 0 — молчим.
-- Подключено к событиям без правки чужих окон: релиз, разработка, покупки, клики по кнопкам.
-- Другие контроллеры могут звать SoundController.play(key) сами.
-- Громкость из настроек (Config/Settings): музыка (looped) — SoundGroup «Music», остальное — «Effects».

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Critics = require(ReplicatedStorage.Shared.Config.Critics)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientSettings = require(script.Parent.Parent.ClientSettings)

local SoundController = {}

local folder: Folder? = nil
local cache: { [string]: Sound } = {}
local groups: { [string]: SoundGroup } = {}

-- Группа громкости: "Music" или "Effects" (Volume = множитель из настроек)
local function getGroup(name: string): SoundGroup
	local group = groups[name]
	if not group then
		local g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = if name == "Music"
			then ClientSettings.values.musicVolume
			else ClientSettings.values.sfxVolume
		g.Parent = SoundService
		groups[name] = g
		group = g
	end
	return group
end

local function getFolder(): Folder
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "GameSounds"
		f.Parent = SoundService
		folder = f
	end
	return folder :: Folder
end

local function getSound(key: string): Sound?
	local config = Sounds.list[key]
	if not config or config.id == 0 then
		return nil
	end
	local sound = cache[key]
	if not sound then
		local s = Instance.new("Sound")
		s.Name = key
		s.SoundId = "rbxassetid://" .. config.id
		s.Volume = config.volume
		s.Looped = config.looped == true
		s.SoundGroup = getGroup(if config.looped then "Music" else "Effects")
		s.Parent = getFolder()
		cache[key] = s
		sound = s
	end
	return sound
end

function SoundController.play(key: string)
	local sound = getSound(key)
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

function SoundController.stop(key: string)
	local sound = cache[key]
	if sound then
		sound:Stop()
	end
end

local function scoreKey(score: number): string
	if score <= Sounds.scoreLowMax then
		return "score_low"
	elseif score <= Sounds.scoreMidMax then
		return "score_mid"
	end
	return "score_high"
end

-- Повторяем тайминг анимации ReleaseWindow: критики по очереди, потом итог и деньги
local function onGameReleased(info: any)
	if type(info) ~= "table" or type(info.score) ~= "number" then
		return
	end
	task.spawn(function()
		for _ = 1, #Critics do
			task.wait(Sounds.criticRevealDelay)
			SoundController.play("critic_reveal")
		end
		task.wait(Sounds.criticRevealDelay)
		SoundController.play(scoreKey(info.score))
		task.wait(Sounds.moneyDelay)
		SoundController.play(if info.isRecord then "record" else "money")
	end)
end

local function countKeys(set: any): number
	local n = 0
	if type(set) == "table" then
		for _ in set do
			n += 1
		end
	end
	return n
end

function SoundController.start()
	ClientSettings.changed:Connect(function(key: string)
		if key == "musicVolume" then
			getGroup("Music").Volume = ClientSettings.values.musicVolume
		elseif key == "sfxVolume" then
			getGroup("Effects").Volume = ClientSettings.values.sfxVolume
		end
	end)
	SoundController.play("music_garage")

	-- Разработка: первый тик — dev_start, дальше тихий dev_tick раз в несколько секунд
	local developing = false
	local lastTick = 0
	Remotes.DevelopmentProgress.OnClientEvent:Connect(function()
		local now = os.clock()
		if not developing then
			developing = true
			lastTick = now
			SoundController.play("dev_start")
		elseif now - lastTick >= Sounds.devTickInterval then
			lastTick = now
			SoundController.play("dev_tick")
		end
	end)
	Remotes.GameReleased.OnClientEvent:Connect(function(info)
		developing = false
		onGameReleased(info)
	end)

	-- Покупки: сравниваем снимки данных; первый снимок (загрузка профиля) не звучит
	local known: { [string]: boolean }? = nil
	local unlockedCount = 0
	local function onChanged()
		local data = ClientState.data
		if not data or type(data.upgrades) ~= "table" then
			return
		end
		local unlocked = countKeys(data.unlockedGenres) + countKeys(data.unlockedTopics)
		if known then
			for id in data.upgrades do
				if not known[id] then
					SoundController.play(if id == "office" then "move_office" else "buy")
				end
			end
			if unlocked > unlockedCount then
				SoundController.play("unlock")
			end
		end
		known = table.clone(data.upgrades)
		unlockedCount = unlocked
	end
	ClientState.changed:Connect(onChanged)
	onChanged()

	-- Клик по любой кнопке нашего интерфейса
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function hook(object: Instance)
		if object:IsA("GuiButton") then
			object.Activated:Connect(function()
				SoundController.play("click")
			end)
		end
	end
	for _, object in playerGui:GetDescendants() do
		hook(object)
	end
	playerGui.DescendantAdded:Connect(hook)
end

return SoundController
