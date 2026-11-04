--!strict
-- Платформы игр и своя консоль (волна 2; Config/Platforms, Config/Console).
-- Платформа выбирается в окне «Создать игру»; DevelopmentService спрашивает здесь:
--   platformFor(player, raw)              — открытая платформа или "pc"
--   scoreBonus(platformId)                — прибавка к оценке до округления
--   revenueMultiplier(player, id, genre)  — множитель дохода (жанр × доля рынка своей консоли)
--   onGameReleased(player, info)          — прогресс этапа консоли и доля рынка
-- Консоль: profile.console = { stage, started, progress, share, earned } — этапов пройдено,
-- оплачен ли текущий, игр с его старта, доля рынка %, заработано роялти. Rebirth не сбрасывает.
-- Состояние окна (ConsoleState) включает и стримера (StreamerService.stateFor).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Console = require(Shared.Config.Console)
local Platforms = require(Shared.Config.Platforms)
local Debug = require(Shared.Config.Debug)
local ConsoleRemotes = require(Shared.ConsoleRemotes)
local DataService = require(script.Parent.DataService)

type Data = { stage: number, started: boolean, progress: number, share: number, earned: number }

local REQUEST_COOLDOWN = 0.5
local STAGE_COUNT = #Console.stages

-- Только Studio: консоль открыта на любом этапе студии, этапу хватает stageGames игр
local isStudio = RunService:IsStudio()
local forceUnlock = isStudio and (Debug :: any).consoleForceUnlock == true
local debugStageGames = if isStudio then tonumber((Debug :: any).consoleStageGames) else nil

local ConsoleService = {}
local lastRequest: { [Player]: number } = {}
local lastStage: { [Player]: number } = {}

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

local function logEvent(player: Player, key: string, value: number, field: string)
	local analytics = optional("AnalyticsService")
	if analytics and type(analytics.logLiveOps) == "function" then
		pcall(analytics.logLiveOps, player, key, value, field)
	end
end

local function num(value: any, default: number): number
	local n = tonumber(value)
	return if n and n == n and n > -math.huge and n < math.huge then n else default
end

-- Поле профиля в порядке: старые сохранения без него и мусор
local function data(profile: DataService.Profile): Data
	local raw = (profile :: any).console
	if type(raw) ~= "table" then
		raw = {}
	end
	local fixed: Data = {
		stage = math.clamp(math.floor(num(raw.stage, 0)), 0, STAGE_COUNT),
		started = raw.started == true,
		progress = math.max(math.floor(num(raw.progress, 0)), 0),
		share = math.clamp(num(raw.share, 0), 0, Console.shareMax),
		earned = math.max(num(raw.earned, 0), 0),
	}
	if fixed.stage >= STAGE_COUNT then
		fixed.started = false
		fixed.share = math.max(fixed.share, Console.shareBase)
	end
	(profile :: any).console = fixed
	return fixed
end

local function launched(d: Data): boolean
	return d.stage >= STAGE_COUNT
end

local function consoleUnlocked(profile: DataService.Profile): boolean
	return forceUnlock or profile.studioLevel >= Console.minStudioLevel
end

local function stageGames(index: number): number
	local stage = Console.stages[index]
	if debugStageGames and debugStageGames > 0 then
		return math.floor(debugStageGames)
	end
	return if stage then stage.games else 0
end

-- Открыта ли платформа игроку
local function platformOpen(profile: DataService.Profile, platform: Platforms.Platform): boolean
	if platform.needsConsole then
		return launched(data(profile))
	end
	return profile.studioLevel >= platform.minStudioLevel
end

-- Доход студии в минуту (ShopService.incomePerMinute), без модуля — 0
function ConsoleService.incomePerMinute(player: Player, profile: DataService.Profile): number
	local shop = optional("ShopService")
	if not shop then
		return 0
	end
	local ok, value = pcall(shop.incomePerMinute, player, profile)
	return if ok and type(value) == "number" and value == value then math.max(value, 0) else 0
end

local function royaltyPerMinute(player: Player, profile: DataService.Profile, d: Data): number
	if not launched(d) then
		return 0
	end
	return math.floor(ConsoleService.incomePerMinute(player, profile) * d.share * Console.royaltyPerShare)
end

function ConsoleService.pushState(player: Player)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	local d = data(profile)
	local platforms = {}
	for id, platform in Platforms.list do
		if platformOpen(profile, platform) then
			platforms[id] = true
		end
	end
	local royalty = royaltyPerMinute(player, profile, d)
	local streamer = optional("StreamerService")
	local streamerState = nil
	if streamer then
		local ok, value = pcall(streamer.stateFor, player, profile)
		streamerState = if ok then value else nil
	end
	ConsoleRemotes.ConsoleState:FireClient(player, {
		platforms = platforms,
		console = {
			unlocked = consoleUnlocked(profile),
			stage = d.stage,
			started = d.started,
			progress = d.progress,
			need = stageGames(d.stage + 1),
			launched = launched(d),
			share = d.share,
			royaltyPerMinute = royalty,
			licensePerMinute = math.floor(royalty * Console.licenseShare),
			earned = math.floor(d.earned),
		},
		streamer = streamerState,
	})
end

-- Платформа новой игры: открытая — как просили, иначе ПК (старый клиент без выбора тоже ПК)
function ConsoleService.platformFor(player: Player, raw: any): string
	local profile = DataService.get(player)
	local platform = Platforms.get(raw)
	if profile and platform and platformOpen(profile, platform) then
		return platform.id
	end
	return "pc"
end

function ConsoleService.scoreBonus(platformId: any): number
	local platform = Platforms.get(platformId)
	return if platform then platform.scoreBonus else 0
end

function ConsoleService.revenueMultiplier(player: Player, platformId: any, genreId: string): number
	local platform = Platforms.get(platformId)
	if not platform then
		return 1
	end
	local multiplier = Platforms.genreMultiplier(platform, genreId)
	if platform.needsConsole then
		local profile = DataService.get(player)
		local share = if profile then data(profile).share else 0
		multiplier *= 1 + share * Console.shareRevenueBonus
	end
	return multiplier
end

-- Хук DevelopmentService после релиза: { platform, score, genreId }
function ConsoleService.onGameReleased(player: Player, info: any)
	local profile = DataService.get(player)
	if not profile or type(info) ~= "table" then
		return
	end
	local d = data(profile)
	local platform = if type(info.platform) == "string" then info.platform else "pc"
	local score = num(info.score, 0)
	logEvent(player, "platform", score, platform)
	-- Этап консоли: считаем игры, вышедшие на 3-м этаже
	if d.started and consoleUnlocked(profile) then
		d.progress += 1
		if d.progress >= stageGames(d.stage + 1) then
			d.stage += 1
			d.started = false
			d.progress = 0
			local stage = Console.stages[d.stage]
			logEvent(player, "console", d.stage, (if stage then stage.id else "?") .. "_done")
			if launched(d) then
				d.share = math.max(d.share, Console.shareBase)
				ConsoleRemotes.ConsoleNotice:FireClient(player, { kind = "launched" })
			else
				ConsoleRemotes.ConsoleNotice:FireClient(player, { kind = "stageDone", stage = d.stage })
			end
		end
	end
	if launched(d) and platform == "console" and score >= Console.hitScore then
		d.share = math.min(d.share + Console.shareHit, Console.shareMax)
	end
	ConsoleService.pushState(player)
end

-- Начать следующий этап: оплата сразу, дальше — игры
local function onStage(player: Player)
	local now = os.clock()
	if (lastStage[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastStage[player] = now
	local profile = DataService.get(player)
	if not profile or not consoleUnlocked(profile) then
		return
	end
	local d = data(profile)
	if d.started or launched(d) then
		return
	end
	local stage = Console.stages[d.stage + 1]
	local cost = if forceUnlock then 0 else stage.cost
	if not DataService.trySpend(player, cost) then
		return
	end
	d.started = true
	d.progress = 0
	logEvent(player, "console", d.stage + 1, stage.id .. "_started")
	ConsoleService.pushState(player)
end

local function onRequest(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	ConsoleService.pushState(player)
end

-- Роялти и таяние доли рынка (пока игрок в игре)
local function tick(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local d = data(profile)
	if not launched(d) then
		return
	end
	local minutes = Console.tickSeconds / 60
	d.share = math.max(d.share - Console.shareDecayPerMinute * minutes, Console.shareBase)
	local amount = math.floor(royaltyPerMinute(player, profile, d) * minutes)
	if amount > 0 then
		DataService.addCash(player, amount)
		d.earned += amount
	end
	ConsoleService.pushState(player)
end

function ConsoleService.start()
	ConsoleRemotes.ConsoleRequest.OnServerEvent:Connect(onRequest)
	ConsoleRemotes.ConsoleStage.OnServerEvent:Connect(onStage)
	-- Строке платформ в окне «Создать игру» снимок нужен сразу после входа
	DataService.onProfileLoaded(function(player)
		task.defer(ConsoleService.pushState, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		lastStage[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Console.tickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tick, player)
				if not ok then
					warn("[ConsoleService] Tick failed for", player.Name, err)
				end
			end
		end
	end)
end

return ConsoleService
