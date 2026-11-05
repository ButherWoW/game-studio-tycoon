--!strict
-- Звуки и фоновая музыка (5.6). Ключи и громкость — Config/Sounds; id = 0 — молчим.
-- Подключено к событиям без правки чужих окон: релиз, разработка, покупки, клики по кнопкам,
-- окна (Ui.windowEvent); остальные игровые моменты слушает SoundEvents (remotes и атрибуты).
-- Громкость из настроек (Config/Settings): музыка (looped) — SoundGroup «Music», остальное — «Effects».
--
-- API для других контроллеров:
--   SoundController.play(key)            — 2D-звук (антиспам по Sounds.throttle)
--   SoundController.playAt(key, where)   — 3D у детали/аттачмента/точки (слышно до Sounds.rollOffMax,
--                                          дальше Sounds.hearDistance от игрока — не играем)
--   SoundController.stop(key)
-- Кнопка с атрибутом SoundKey = "tab_switch" (или любой ключ) звучит этим ключом вместо click.
-- Сервер может повесить на деталь тег «SoundEmitter» + атрибут SoundKey (и SoundMin/SoundMax, сек):
-- клиент сам стучит этим звуком со случайной паузой, пока игрок ближе Sounds.hearDistance
-- (так звучат строители: SoundKey = "construction_hammer").
-- Музыка меняется по месту игрока: парк/чужие участки — music_park, свой участок — гараж или этаж
-- офиса (music_office / music_floor2 / music_floor3), в Золотой час — music_golden; с затуханием.

local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Critics = require(ReplicatedStorage.Shared.Config.Critics)
local StudioLayout = require(ReplicatedStorage.Shared.StudioLayout)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientSettings = require(script.Parent.Parent.ClientSettings)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local SoundController = {}

local folder: Folder? = nil
local cache: { [string]: Sound } = {}
local groups: { [string]: SoundGroup } = {}
local lastPlayed: { [string]: number } = {}

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

-- Антиспам: true — можно играть (и запоминаем время)
local function allowed(key: string): boolean
	local now = os.clock()
	local gap = Sounds.throttle[key] or Sounds.defaultThrottle
	local last = lastPlayed[key]
	if last and now - last < gap then
		return false
	end
	lastPlayed[key] = now
	return true
end

function SoundController.play(key: string)
	if not allowed(key) then
		return
	end
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

-- ===== 3D-звуки =====

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function positionOf(where: Instance | Vector3): Vector3?
	if typeof(where) == "Vector3" then
		return where :: Vector3
	elseif typeof(where) == "Instance" then
		local instance = where :: Instance
		if instance:IsA("BasePart") then
			return instance.Position
		elseif instance:IsA("Attachment") then
			return instance.WorldPosition
		elseif instance:IsA("Model") then
			return instance:GetPivot().Position
		end
	end
	return nil
end

-- Игрок достаточно близко, чтобы услышать
local function nearby(position: Vector3): boolean
	local here = rootPosition()
	return here ~= nil and (here - position).Magnitude <= Sounds.hearDistance
end

-- Без антиспама: его делает вызывающий (playAt — по ключу, эмиттеры — своей паузой)
local function spawn3d(key: string, where: Instance | Vector3)
	local config = Sounds.list[key]
	if not config or config.id == 0 then
		return
	end
	local position = positionOf(where)
	if not position or not nearby(position) then
		return
	end
	local parent: Instance
	local holder: Attachment? = nil
	if
		typeof(where) == "Instance"
		and ((where :: Instance):IsA("BasePart") or (where :: Instance):IsA("Attachment"))
	then
		parent = where :: Instance
	else
		local a = Instance.new("Attachment")
		a.Name = "SoundAt"
		a.WorldPosition = position
		a.Parent = workspace.Terrain
		holder = a
		parent = a
	end
	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. key
	sound.SoundId = "rbxassetid://" .. config.id
	sound.Volume = config.volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Sounds.rollOffMin
	sound.RollOffMaxDistance = Sounds.rollOffMax
	sound.SoundGroup = getGroup("Effects")
	sound.Parent = parent
	local function cleanup()
		if holder then
			holder:Destroy()
		else
			sound:Destroy()
		end
	end
	sound.Ended:Once(cleanup)
	-- Если звук не загрузился и Ended не придёт
	task.delay(20, function()
		if sound.Parent then
			cleanup()
		end
	end)
	sound:Play()
end

function SoundController.playAt(key: string, where: Instance | Vector3)
	if allowed(key) then
		spawn3d(key, where)
	end
end

-- Эмиттеры: деталь с тегом SoundEmitter стучит своим SoundKey, пока она в мире и игрок рядом
local function watchEmitter(instance: Instance)
	task.spawn(function()
		local random = Random.new()
		while instance.Parent and instance:HasTag(Sounds.emitterTag) do
			local low = tonumber(instance:GetAttribute("SoundMin")) or Sounds.emitterMin
			local high = tonumber(instance:GetAttribute("SoundMax")) or Sounds.emitterMax
			task.wait(random:NextNumber(low, math.max(high, low)))
			local key = instance:GetAttribute("SoundKey")
			if type(key) == "string" and instance.Parent then
				spawn3d(key, instance)
			end
		end
	end)
end

-- ===== Музыка =====

local FLOOR_MUSIC = { "music_office", "music_floor2", "music_floor3" }

local currentMusic: string? = nil
local musicTweens: { [string]: Tween } = {}

local function ownPlot(): BasePart?
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild(tostring(player:GetAttribute("PlotName")))
	return if plot and plot:IsA("BasePart") then plot else nil
end

-- Какой трек должен играть сейчас
local function wantedMusic(): string
	if ReplicatedStorage:GetAttribute("DailyGoldenActive") == true then
		return "music_golden"
	end
	local plot = ownPlot()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not plot or not root or not root:IsA("BasePart") then
		return "music_park"
	end
	local here = plot.CFrame:PointToObjectSpace(root.Position)
	if math.abs(here.X) > plot.Size.X / 2 or math.abs(here.Z) > plot.Size.Z / 2 then
		return "music_park"
	end
	local data = ClientState.data
	local level = if data then tonumber(data.studioLevel) or 1 else 1
	if level <= 1 then
		return "music_garage"
	end
	local floor = math.min(StudioLayout.floorAt(here.Y - plot.Size.Y / 2), StudioLayout.floorsUnlocked(level))
	return FLOOR_MUSIC[floor] or "music_office"
end

local function fade(key: string, sound: Sound, target: number, onDone: (() -> ())?)
	local old = musicTweens[key]
	if old then
		old:Cancel()
	end
	local tween = TweenService:Create(sound, TweenInfo.new(Sounds.musicFade), { Volume = target })
	musicTweens[key] = tween
	tween.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and onDone then
			onDone()
		end
	end)
	tween:Play()
end

local function setMusic(key: string)
	if key == currentMusic then
		return
	end
	local sound = getSound(key)
	if not sound then
		-- У трека нет id — оставляем текущий (или гаражный, если ничего не играет)
		if currentMusic or key == "music_garage" then
			return
		end
		key = "music_garage"
		sound = getSound(key)
		if not sound then
			return
		end
	end
	local previousKey = currentMusic
	currentMusic = key
	if previousKey then
		local previous = cache[previousKey]
		if previous then
			fade(previousKey, previous, 0, function()
				if currentMusic ~= previousKey then
					previous:Pause()
				end
			end)
		end
	end
	local config = Sounds.list[key]
	local volume = if config then config.volume else 0
	local s = sound :: Sound
	if not s.IsPlaying then
		s.Volume = 0
		if s.TimePosition > 0 then
			s:Resume()
		else
			s:Play()
		end
	end
	fade(key, s, volume)
end

-- Сменился ли трек (для «Двери»: вошёл на свой участок / вышел)
local onMusicChanged: ((string?, string) -> ())? = nil

function SoundController.onMusicChanged(callback: (string?, string) -> ())
	onMusicChanged = callback
end

local function updateMusic()
	local key = wantedMusic()
	local before = currentMusic
	setMusic(key)
	if before ~= currentMusic and onMusicChanged then
		(onMusicChanged :: (string?, string) -> ())(before, key)
	end
end

-- ===== Релиз игры =====

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

	-- Музыка по месту игрока: проверяем раз в секунду и сразу при смене Золотого часа
	updateMusic()
	task.spawn(function()
		while true do
			task.wait(Sounds.musicCheckInterval)
			updateMusic()
		end
	end)
	ReplicatedStorage:GetAttributeChangedSignal("DailyGoldenActive"):Connect(updateMusic)

	-- Короткие звуки подгружаем заранее, чтобы первый раз не было задержки
	task.spawn(function()
		local list: { Instance } = {}
		for key, config in Sounds.list do
			if not config.looped then
				local sound = getSound(key)
				if sound then
					table.insert(list, sound)
				end
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)

	-- Эмиттеры в мире (строители и т. п.)
	for _, instance in CollectionService:GetTagged(Sounds.emitterTag) do
		watchEmitter(instance)
	end
	CollectionService:GetInstanceAddedSignal(Sounds.emitterTag):Connect(watchEmitter)

	-- Окна: открытие заглушает клик кнопки, которая его открыла
	Ui.windowEvent:Connect(function(opened: boolean)
		if opened then
			SoundController.stop("click")
			SoundController.stop("window_close")
			SoundController.play("window_open")
		else
			SoundController.play("window_close")
		end
	end)

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

	-- Клик по любой кнопке нашего интерфейса (атрибут SoundKey — свой звук, например tab_switch)
	local playerGui = player:WaitForChild("PlayerGui")
	local function hook(object: Instance)
		if object:IsA("GuiButton") then
			object.Activated:Connect(function()
				local key = object:GetAttribute("SoundKey")
				SoundController.play(if type(key) == "string" then key else "click")
			end)
		end
	end
	for _, object in playerGui:GetDescendants() do
		hook(object)
	end
	playerGui.DescendantAdded:Connect(hook)
end

return SoundController
