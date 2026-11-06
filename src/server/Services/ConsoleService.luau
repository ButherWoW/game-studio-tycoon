--!strict
-- Платформы игр и своя консоль (волна 2; Config/Platforms, Config/Console).
-- Платформа выбирается в окне «Создать игру»; DevelopmentService спрашивает здесь:
--   platformFor(player, raw)              — открытая платформа или "pc"
--   scoreBonus(platformId)                — прибавка к оценке до округления
--   revenueMultiplier(player, id, genre)  — множитель дохода (жанр × доля рынка своей консоли)
--   onGameReleased(player, info)          — доля рынка своей консоли
-- Консоль — цепочка этапов Console.stages: оборудование (купить в окне консоли) + сотрудник
-- с навыком (StaffService.skillLevels) + оплата -> таймер на os.time (идёт и офлайн).
-- profile.console = { v = 2, stage, endsAt, duration, worker, equipment, credit, skips, share,
-- earned }: этапов пройдено, конец таймера идущего этапа (0 — не идёт), его длина, кто ведёт,
-- купленное оборудование, накопленное ускорение (сек) и «завершить этап» (шт.) за Robux,
-- доля рынка %, заработано роялти. Rebirth не сбрасывает. Старый формат (3 этапа по играм) —
-- migrate() по Console.legacyStageMap.
-- Robux: grantProduct (MonetizationService) — consoleSpeed5 / consoleSpeed30 / consoleSkip.
-- Обновления по средам (Config/Features): строка платформ (ПК, телефоны) — с запуска; своя
-- консоль ("console") и её платформа ("platforms") — обновлением «Своя консоль». До выхода:
-- этапы/оборудование не принимаются, таймер и роялти стоят, модель не ставится, ускорение
-- за Robux выдаётся деньгами; данные profile.console лежат до выхода.
-- Модель консоли (stage.model, V23) и оборудование (V30) ставятся на 3-й этаж при сборке
-- участка (PlotService.plotChanged) и пересобираются при смене этапа / покупке;
-- нет модели консоли — ничего, нет модели оборудования — заглушка из деталей.
-- Состояние окна (ConsoleState) включает и стримера (StreamerService.stateFor).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local Console = require(Shared.Config.Console)
local Platforms = require(Shared.Config.Platforms)
local Debug = require(Shared.Config.Debug)
local ConsoleRemotes = require(Shared.ConsoleRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StudioLayout = require(Shared.StudioLayout)
local UnlockRules = require(Shared.UnlockRules)
local Features = require(Shared.Config.Features)
local FeatureReleaseService = require(script.Parent.FeatureReleaseService)

type Data = {
	v: number,
	stage: number,
	endsAt: number,
	duration: number,
	worker: string,
	equipment: { [string]: boolean },
	credit: number,
	skips: number,
	share: number,
	earned: number,
}

local DATA_VERSION = 2
local REQUEST_COOLDOWN = 0.5
local MODEL_NAME = "OwnConsole"
local EQUIPMENT_FOLDER = "ConsoleEquipment"
local STAGE_COUNT = #Console.stages
-- Robux за ускорение после запуска (гонка двух окон): отдаём деньгами, как SeasonService
local LATE_PURCHASE_MINUTES = 10

-- Только Studio: консоль открыта на любом этапе студии, этапы и оборудование бесплатные,
-- этап идёт stageSeconds секунд, навыки можно не требовать
local isStudio = RunService:IsStudio()
local forceUnlock = isStudio and (Debug :: any).consoleForceUnlock == true
local debugStageSeconds = if isStudio then tonumber((Debug :: any).consoleStageSeconds) else nil
local skipSkills = isStudio and (Debug :: any).consoleSkipSkills == true

local ConsoleService = {}
local lastRequest: { [Player]: number } = {}
local lastStage: { [Player]: number } = {}

local equipmentById: { [string]: Console.ConsoleEquipment } = {}
for _, item in Console.equipment do
	equipmentById[item.id] = item
end

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

-- Старый формат (до цепочки): { stage 0..3, started, progress } — этапы «проект/прототип/запуск»
-- по числу игр. Пройденные -> Console.legacyStageMap; оплаченный незаконченный — пройденным
-- (деньги списаны, игры частично выпущены — не отнимаем). Оборудование пройденных этапов — даром
local function migrate(raw: { [string]: any }): { [string]: any }
	local old = math.clamp(math.floor(num(raw.stage, 0)), 0, 3)
	if raw.started == true and old < 3 then
		old += 1
	end
	local stage = Console.legacyStageMap[old] or 0
	local equipment = {}
	for i = 1, math.min(stage, STAGE_COUNT) do
		for _, id in Console.stages[i].equipment do
			equipment[id] = true
		end
	end
	return {
		v = DATA_VERSION,
		stage = stage,
		equipment = equipment,
		share = raw.share,
		earned = raw.earned,
	}
end

-- Поле профиля в порядке: старые сохранения без него и мусор
local function data(profile: DataService.Profile): Data
	local raw = (profile :: any).console
	if type(raw) ~= "table" then
		raw = {}
	end
	if raw.v ~= DATA_VERSION then
		raw = migrate(raw)
	end
	local equipment = {}
	if type(raw.equipment) == "table" then
		for id, owned in raw.equipment do
			if owned == true and type(id) == "string" and equipmentById[id] then
				equipment[id] = true
			end
		end
	end
	local fixed: Data = {
		v = DATA_VERSION,
		stage = math.clamp(math.floor(num(raw.stage, 0)), 0, STAGE_COUNT),
		endsAt = math.max(math.floor(num(raw.endsAt, 0)), 0),
		duration = math.max(math.floor(num(raw.duration, 0)), 0),
		worker = if type(raw.worker) == "string" then raw.worker else "",
		equipment = equipment,
		credit = math.max(math.floor(num(raw.credit, 0)), 0),
		skips = math.max(math.floor(num(raw.skips, 0)), 0),
		share = math.clamp(num(raw.share, 0), 0, Console.shareMax),
		earned = math.max(num(raw.earned, 0), 0),
	}
	if fixed.stage >= STAGE_COUNT then
		fixed.endsAt = 0
		fixed.worker = ""
		fixed.share = math.max(fixed.share, Console.shareBase)
	end
	-- Чиним на месте: кто держит ссылку из прошлого data() (finishStage -> renderModel),
	-- видит те же поля, правки не теряются
	local target = (profile :: any).console
	if type(target) ~= "table" then
		target = {};
		(profile :: any).console = target
	end
	table.clear(target)
	for key, value in fixed :: any do
		target[key] = value
	end
	return target :: Data
end

local function launched(d: Data): boolean
	return d.stage >= STAGE_COUNT
end

local function running(d: Data): boolean
	return d.endsAt > 0 and not launched(d)
end

local function released(): boolean
	return Features.isReleased("console")
end

local function consoleUnlocked(profile: DataService.Profile): boolean
	return released() and (forceUnlock or profile.studioLevel >= Console.minStudioLevel)
end

local function stageSeconds(index: number): number
	local stage = Console.stages[index]
	if debugStageSeconds and debugStageSeconds > 0 then
		return math.floor(debugStageSeconds)
	end
	return if stage then math.floor(stage.minutes * 60) else 0
end

-- Открыта ли платформа игроку
local function platformOpen(profile: DataService.Profile, platform: Platforms.Platform): boolean
	if platform.needsConsole then
		return released() and Features.isReleased("platforms") and launched(data(profile))
	end
	local ok = UnlockRules.check({ requires = platform.requires } :: any, profile)
	return ok
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

-- ===== Требования этапа =====

-- Лучший сотрудник по навыку: (id, уровень); при равенстве — по id (стабильно)
local function bestBySkill(profile: DataService.Profile, skill: string): (string?, number)
	local staff = optional("StaffService")
	if not staff or type(staff.skillLevels) ~= "function" then
		return nil, 0
	end
	local ok, levels = pcall(staff.skillLevels, profile)
	if not ok or type(levels) ~= "table" then
		return nil, 0
	end
	local bestId: string? = nil
	local bestLevel = -1
	for employeeId, skills in levels do
		local level = num(skills[skill], 0)
		if level > bestLevel or (level == bestLevel and bestId ~= nil and employeeId < bestId) then
			bestId, bestLevel = employeeId, level
		end
	end
	return bestId, math.max(bestLevel, 0)
end

-- Что мешает начать этап (окно консоли показывает чек-лист)
type Check = {
	missingEquipment: { string },
	skill: string?,
	level: number,
	workerId: string?, -- кто ведёт этап (навык ≥ level)
	bestId: string?, -- лучший по навыку, если не дотягивает
	bestLevel: number,
	skillOk: boolean,
	ready: boolean, -- всё, кроме денег
}

local function check(profile: DataService.Profile, d: Data, index: number): Check?
	local stage = Console.stages[index]
	if not stage then
		return nil
	end
	local missing = {}
	for _, id in stage.equipment do
		if not d.equipment[id] then
			table.insert(missing, id)
		end
	end
	local workerId: string? = nil
	local bestId: string? = nil
	local bestLevel = 0
	local skillOk = true
	local skill = stage.skill
	if skill then
		bestId, bestLevel = bestBySkill(profile, skill)
		local enough = bestId ~= nil and bestLevel >= stage.level
		skillOk = skipSkills or enough
		workerId = if enough then bestId else nil
	end
	return {
		missingEquipment = missing,
		skill = skill,
		level = stage.level,
		workerId = workerId,
		bestId = bestId,
		bestLevel = bestLevel,
		skillOk = skillOk,
		ready = #missing == 0 and skillOk,
	}
end

-- ===== Модели на 3-м этаже =====

local function floorFrame(plot: BasePart, position: Vector3, rotation: number): CFrame
	local floorY = StudioLayout.floorY(StudioLayout.FLOOR_COUNT)
	return plot.CFrame
		* CFrame.new(position + Vector3.new(0, floorY, 0))
		* CFrame.Angles(0, math.rad(rotation), 0)
end

local function cleanClone(template: Instance, name: string): Model
	local model = template:Clone() :: Model
	model.Name = name
	for _, item in model:GetDescendants() do
		if item:IsA("BaseScript") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
		end
	end
	return model
end

-- Модель консоли: идёт этап — его, иначе последний пройденный; ничего не начато — ничего
local function shownModel(d: Data): string?
	local index = if running(d) then d.stage + 1 else d.stage
	local stage = Console.stages[math.min(index, STAGE_COUNT)]
	return if stage and index > 0 then stage.model else nil
end

-- Заглушка оборудования, пока нет модели Астры (V30): корпус + светящаяся панель спереди (+Z)
local function placeholder(item: Console.ConsoleEquipment): Model
	local model = Instance.new("Model")
	local base = Instance.new("Part")
	base.Name = "Body"
	base.Anchored = true
	base.Size = item.size
	base.Color = item.color
	base.Material = Enum.Material.SmoothPlastic
	base.CFrame = CFrame.new(0, item.size.Y / 2, 0)
	base.Parent = model
	local panel = Instance.new("Part")
	panel.Name = "Panel"
	panel.Anchored = true
	panel.CanCollide = false
	panel.Size = Vector3.new(item.size.X * 0.7, item.size.Y * 0.4, 0.2)
	panel.Color = Color3.fromRGB(230, 240, 255)
	panel.Material = Enum.Material.Neon
	panel.CFrame = CFrame.new(0, item.size.Y * 0.65, item.size.Z / 2 + 0.1)
	panel.Parent = model
	model.PrimaryPart = base
	model.WorldPivot = CFrame.new()
	return model
end

local function renderEquipment(plot: BasePart, d: Data, show: boolean)
	local folder = plot:FindFirstChild(EQUIPMENT_FOLDER)
	if not show then
		if folder then
			folder:Destroy()
		end
		return
	end
	if not folder then
		local created = Instance.new("Folder")
		created.Name = EQUIPMENT_FOLDER
		created.Parent = plot
		folder = created
	end
	local container = folder :: Instance
	local templates = ServerStorage:FindFirstChild("Upgrades")
	for _, item in Console.equipment do
		local existing = container:FindFirstChild(item.id)
		if not d.equipment[item.id] then
			if existing then
				existing:Destroy()
			end
			continue
		end
		if existing then
			continue
		end
		local template = templates and templates:FindFirstChild(item.model)
		local model = if template and template:IsA("Model")
			then cleanClone(template, item.id)
			else placeholder(item)
		model.Name = item.id
		model:PivotTo(floorFrame(plot, item.position, item.rotation))
		model.Parent = container
	end
end

local function renderModel(player: Player)
	local plot = PlotService.getPlot(player)
	local profile = DataService.get(player)
	if not plot or not profile then
		return
	end
	local d = data(profile)
	-- До выхода консоли модели и оборудования нет (данные не трогаем)
	local onFloor = released() and profile.studioLevel >= Console.minStudioLevel
	renderEquipment(plot, d, onFloor)
	local name = if onFloor then shownModel(d) else nil
	local old = plot:FindFirstChild(MODEL_NAME)
	if old and name and old:GetAttribute("ConsoleModel") == name then
		return
	end
	if old then
		old:Destroy()
	end
	local folder = ServerStorage:FindFirstChild("Upgrades")
	local template = name and folder and folder:FindFirstChild(name)
	if not (template and template:IsA("Model")) then
		return
	end
	local model = cleanClone(template, MODEL_NAME)
	model:SetAttribute("ConsoleModel", name)
	model:PivotTo(floorFrame(plot, Console.modelPosition, Console.modelRotation))
	model.Parent = plot
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
	local streamer = if Features.isReleased("streamer") then optional("StreamerService") else nil
	local streamerState = nil
	if streamer then
		local ok, value = pcall(streamer.stateFor, player, profile)
		streamerState = if ok then value else nil
	end
	local nextCheck = if launched(d) or running(d) then nil else check(profile, d, d.stage + 1)
	ConsoleRemotes.ConsoleState:FireClient(player, {
		platforms = platforms,
		console = {
			unlocked = consoleUnlocked(profile),
			free = forceUnlock,
			stage = d.stage,
			running = running(d),
			endsAt = d.endsAt,
			duration = d.duration,
			now = os.time(),
			worker = if d.worker ~= "" then d.worker else nil,
			equipment = d.equipment,
			credit = d.credit,
			skips = d.skips,
			nextStage = nextCheck,
			launched = launched(d),
			share = d.share,
			royaltyPerMinute = royalty,
			licensePerMinute = math.floor(royalty * Console.licenseShare),
			earned = math.floor(d.earned),
		},
		streamer = streamerState,
	})
end

-- Этап готов: следующий ждёт игрока (требования и оплата — снова). how — done / skip
local function finishStage(player: Player, d: Data, how: string)
	local index = d.stage + 1
	local stage = Console.stages[index]
	d.stage = math.min(index, STAGE_COUNT)
	d.endsAt = 0
	d.duration = 0
	d.worker = ""
	logEvent(player, "console", d.stage, (if stage then stage.id else "?") .. "_" .. how)
	renderModel(player)
	if launched(d) then
		d.share = math.max(d.share, Console.shareBase)
		ConsoleRemotes.ConsoleNotice:FireClient(player, { kind = "launched" })
	else
		ConsoleRemotes.ConsoleNotice:FireClient(player, { kind = "stageDone", stage = d.stage })
	end
end

-- Накопленное ускорение на только что начатый этап: сначала «завершить», потом секунды
local function applyCredit(player: Player, d: Data, now: number)
	if not running(d) then
		return
	end
	if d.skips > 0 then
		d.skips -= 1
		finishStage(player, d, "skip")
		return
	end
	if d.credit > 0 then
		local used = math.min(d.credit, math.max(d.endsAt - now, 0))
		d.credit -= used
		d.endsAt -= used
		if d.endsAt <= now then
			finishStage(player, d, "done")
		end
	end
end

-- Таймер вышел (в игре или офлайн — проверяем при входе и каждые tickSeconds)
local function checkTimer(player: Player, d: Data): boolean
	if running(d) and os.time() >= d.endsAt then
		finishStage(player, d, "done")
		return true
	end
	return false
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
	if not released() then
		-- Консоли ещё нет, но число игр выросло: строка платформ (телефоны) могла открыться
		ConsoleService.pushState(player)
		return
	end
	checkTimer(player, d)
	if launched(d) and platform == "console" and score >= Console.hitScore then
		d.share = math.min(d.share + Console.shareHit, Console.shareMax)
	end
	ConsoleService.pushState(player)
end

local function throttled(player: Player): boolean
	local now = os.clock()
	if (lastStage[player] or 0) + REQUEST_COOLDOWN > now then
		return true
	end
	lastStage[player] = now
	return false
end

-- Начать следующий этап: оборудование и сотрудник есть — оплата, дальше таймер
local function onStage(player: Player)
	if throttled(player) then
		return
	end
	local profile = DataService.get(player)
	if not profile or not consoleUnlocked(profile) then
		return
	end
	local d = data(profile)
	if running(d) or launched(d) then
		return
	end
	local index = d.stage + 1
	local stage = Console.stages[index]
	local status = check(profile, d, index)
	if not stage or not status or not status.ready then
		ConsoleService.pushState(player)
		return
	end
	if not DataService.trySpend(player, if forceUnlock then 0 else stage.cost) then
		return
	end
	local seconds = stageSeconds(index)
	local t = os.time()
	d.endsAt = t + seconds
	d.duration = seconds
	d.worker = status.workerId or ""
	logEvent(player, "console", index, stage.id .. "_started")
	renderModel(player)
	applyCredit(player, d, t)
	ConsoleService.pushState(player)
end

-- Купить оборудование консоли (id из Console.equipment)
local function onEquip(player: Player, id: any)
	if type(id) ~= "string" or throttled(player) then
		return
	end
	local item = equipmentById[id]
	local profile = DataService.get(player)
	if not item or not profile or not consoleUnlocked(profile) then
		return
	end
	local d = data(profile)
	if d.equipment[id] then
		return
	end
	if not DataService.trySpend(player, if forceUnlock then 0 else item.cost) then
		return
	end
	d.equipment[id] = true
	logEvent(player, "console", item.cost, "equip_" .. id)
	renderModel(player)
	ConsoleService.pushState(player)
end

-- Robux-ускорение этапа (MonetizationService, ProcessReceipt). Повтор квитанции отсекает
-- MonetizationService (processedReceipts). Robux не пропадают: без идущего этапа и остаток
-- сверх таймера — в запас (credit / skips) на следующий этап; после запуска — деньгами
function ConsoleService.grantProduct(player: Player, profile: DataService.Profile, productId: number): boolean
	if productId == 0 then
		return false
	end
	local product: Console.ConsoleSpeedup? = nil
	for _, item in Console.speedups do
		if item.productId ~= 0 and item.productId == productId then
			product = item
			break
		end
	end
	if not product then
		return false
	end
	local d = data(profile)
	logEvent(player, "console", d.stage + 1, "speed_" .. product.id)
	-- Консоль ещё не вышла (кнопок нет, но чек мог прийти) или уже запущена — деньгами
	if launched(d) or not released() then
		local rewards = optional("RewardService")
		if rewards then
			-- Минуты — по цене товара, как у пакета «10 минут дохода» (49 R$): не дешёвый пакет денег
			local minutes = math.max(1, math.floor((product.robuxPrice or 49) * LATE_PURCHASE_MINUTES / 49))
			rewards.grant(player, { incomeMinutes = minutes })
		end
		return true
	end
	local seconds = product.seconds
	if seconds == nil then
		if running(d) then
			finishStage(player, d, "skip")
		else
			d.skips += 1
		end
	elseif running(d) then
		local left = math.max(d.endsAt - os.time(), 0)
		if seconds >= left then
			d.credit += seconds - left
			finishStage(player, d, "done")
		else
			d.endsAt -= seconds
		end
	else
		d.credit += seconds
	end
	task.defer(ConsoleService.pushState, player)
	return true
end

local function onRequest(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	ConsoleService.pushState(player)
end

-- Таймер этапа, роялти и таяние доли рынка (пока игрок в игре)
local function tick(player: Player)
	local profile = DataService.get(player)
	if not profile or not released() then
		return
	end
	local d = data(profile)
	if checkTimer(player, d) then
		ConsoleService.pushState(player)
	end
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
	ConsoleRemotes.ConsoleEquip.OnServerEvent:Connect(onEquip)
	-- Участок собран (вход, переезд, Rebirth): модель консоли и оборудование на 3-м этаже
	PlotService.plotChanged:Connect(renderModel)
	-- Строке платформ в окне «Создать игру» снимок нужен сразу после входа; таймер этапа
	-- мог выйти офлайн — завершаем сразу
	DataService.onProfileLoaded(function(player)
		local profile = DataService.get(player)
		if profile and released() then
			checkTimer(player, data(profile))
		end
		task.defer(ConsoleService.pushState, player)
	end)
	-- Консоль вышла, пока сервер работает: модели, таймеры и окно — всем в игре
	if not released() then
		FeatureReleaseService.whenReleased("console", "ConsoleService", function()
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile then
					pcall(checkTimer, player, data(profile))
					pcall(renderModel, player)
					ConsoleService.pushState(player)
				end
			end
		end)
	end
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
