--!strict
-- Долг и приставы (Config/Bailiffs). Долг — это минус на балансе: ExpensesService списывает аренду
-- и зарплату в минус до лимита овердрафта (DataService.charge). Здесь раз в секунду:
--   • атрибуты игрока BailiffDebt (сколько в минусе), BailiffLimit, BailiffsActive — для плашки;
--   • пока в минусе — офис «разваливается»: трещины и пыль на полу верхнего этажа, свет мигает
--     и тускнеет (детали на сервере — видно и гостям); −настроение считает MoodService;
--   • баланс упёрся в лимит — (profile :: any).bailiffs = true (переживает перезаход): раз в
--     seizeSeconds пристав (NPC в тёмном костюме) идёт к предмету, предмет растворяется в пыли,
--     продаётся за sellShare цены, выручка гасит минус; тост владельцу;
--   • баланс снова ≥ 0 — приставы уходят, офис чинится, забастовка снимается сразу.
-- Что забирают и что нет — pickItem и шапка Config/Bailiffs. Офлайн ничего не происходит.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Bailiffs = require(Shared.Config.Bailiffs)
local Debug = require(Shared.Config.Debug)
local Decor = require(Shared.Config.Decor)
local Stages = require(Shared.Config.Stages)
local Upgrades = require(Shared.Config.Upgrades)
local StudioLayout = require(Shared.StudioLayout)
local BailiffRemotes = require(Shared.BailiffRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local ExpensesService = require(script.Parent.ExpensesService)

local CHECK_INTERVAL = 1
local LIGHT_RESCAN = 5 -- пересобрать список ламп участка не реже (модели пересобираются)
local WALK_SPEED = 10 -- studs/с
local WALK_MAX = 3 -- секунд на дорогу, не больше
local FADE_SECONDS = 1.2
local STAND_OFF = 3.5 -- пристав встаёт рядом с предметом, а не в нём
local ROOT_HEIGHT = 3 -- центр HumanoidRootPart над полом (R15)
local FLOOR_LEVEL = 0.5 -- пол участка над его центром
local DEBUG_DELAY = 5
local SUIT = Color3.fromRGB(28, 28, 34)
local SHIRT = Color3.fromRGB(235, 235, 240)
local SKIN = Color3.fromRGB(234, 184, 146)
local CRACK = Color3.fromRGB(38, 34, 30)
local DUST = Color3.fromRGB(150, 140, 125)

-- kind: "upgrade" | "decor"; floor — этап, на полу которого стоит предмет
type Candidate = { kind: string, id: string, key: string, floor: number, cost: number }
type Decay = { folder: Folder, level: number, lights: { Light }, scannedAt: number }

local BailiffService = {}
local joinedAt: { [Player]: number } = {}
local lastSeize: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
local decays: { [Player]: Decay } = {}
local debugForced: { [Player]: boolean } = {}
local root: Folder? = nil

local function container(): Folder
	local existing = root
	if existing and existing.Parent then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Bailiffs"
	folder.Parent = workspace
	root = folder
	return folder
end

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			return result
		end
	end
	return nil
end

-- Долг = минус баланса (целыми долларами вверх)
local function debtOf(profile: DataService.Profile): number
	return if profile.cash < 0 then math.ceil(-profile.cash) else 0
end

-- Пол этажа (высота над полом участка): гараж и 1-й этаж — 0
local function floorYOf(stage: number): number
	local data = Stages[stage]
	return if data then data.floorY else 0
end

-- ===== «Офис разваливается» =====

local function makePart(parent: Instance, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Slate
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function dustEmitter(parent: Instance, rate: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(DUST)
	emitter.LightEmission = 0
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 3.5) })
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(2.5, 4)
	emitter.Speed = NumberRange.new(0.5, 2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -0.5, 0)
	emitter.Rate = rate
	emitter.Parent = parent
	return emitter
end

local function scanLights(plot: BasePart): { Light }
	local lights = {}
	for _, item in plot:GetDescendants() do
		if item:IsA("Light") then
			table.insert(lights, item)
		end
	end
	return lights
end

local function restoreLights(lights: { Light })
	for _, light in lights do
		local base = light:GetAttribute("BailiffBrightness")
		if type(base) == "number" and light.Parent then
			light.Brightness = base
			light:SetAttribute("BailiffBrightness", nil)
		end
	end
end

local function clearDecay(player: Player)
	local decay = decays[player]
	if not decay then
		return
	end
	decays[player] = nil
	decay.folder:Destroy()
	restoreLights(decay.lights)
	local plot = PlotService.getPlot(player)
	if plot then
		restoreLights(scanLights(plot))
	end
end

-- Трещины и пыль на полу верхнего открытого этажа (раскладка постоянная для игрока)
local function buildDecay(player: Player, plot: BasePart, level: number): Decay
	local folder = Instance.new("Folder")
	folder.Name = "Decay_" .. player.UserId
	local y = FLOOR_LEVEL + floorYOf(level) + 0.03
	local random = Random.new(player.UserId + level)
	for _ = 1, Bailiffs.cracks do
		local x, z = random:NextNumber(-24, 22), random:NextNumber(-24, 18)
		local angle = random:NextNumber(0, math.pi)
		local base = plot.CFrame * CFrame.new(x, y, z) * CFrame.Angles(0, angle, 0)
		local length = random:NextNumber(3, 7)
		makePart(folder, Vector3.new(length, 0.05, random:NextNumber(0.15, 0.35)), base, CRACK)
		-- Ответвление трещины
		local branch = random:NextNumber(1.5, 3)
		makePart(
			folder,
			Vector3.new(branch, 0.05, 0.15),
			base
				* CFrame.new(length * 0.25, 0, 0)
				* CFrame.Angles(0, random:NextNumber(0.5, 1.1), 0)
				* CFrame.new(branch / 2, 0, 0),
			CRACK
		)
	end
	for _ = 1, Bailiffs.dustClouds do
		local x, z = random:NextNumber(-20, 18), random:NextNumber(-20, 14)
		local holder = makePart(folder, Vector3.new(6, 1, 6), plot.CFrame * CFrame.new(x, y + 6, z), DUST)
		holder.Transparency = 1
		dustEmitter(holder, 3)
	end
	folder.Parent = container()
	return { folder = folder, level = level, lights = scanLights(plot), scannedAt = os.clock() }
end

local function ensureDecay(player: Player, profile: DataService.Profile)
	local plot = PlotService.getPlot(player)
	if not plot or not PlotService.ownsGarage(player) then
		clearDecay(player)
		return
	end
	local decay = decays[player]
	if decay and decay.level ~= profile.studioLevel then
		clearDecay(player)
		decay = nil
	end
	if not decay then
		decays[player] = buildDecay(player, plot, profile.studioLevel)
	end
end

-- Мигание: лампы участка тускнеют, иногда почти гаснут
local function flicker()
	for player, decay in decays do
		local plot = PlotService.getPlot(player)
		if not plot then
			continue
		end
		if os.clock() - decay.scannedAt > LIGHT_RESCAN then
			decay.lights = scanLights(plot)
			decay.scannedAt = os.clock()
		end
		for _, light in decay.lights do
			if not light.Parent then
				continue
			end
			local base = light:GetAttribute("BailiffBrightness")
			if type(base) ~= "number" then
				base = light.Brightness
				light:SetAttribute("BailiffBrightness", base)
			end
			local off = math.random() < 0.2
			light.Brightness = (base :: number) * (if off then 0.05 else Bailiffs.dimFactor)
		end
	end
end

-- ===== Что забрать =====

-- Можно ли сейчас забирать: новичок, только что вошёл, нет участка — нет
local function canSeize(player: Player, profile: DataService.Profile): boolean
	if not PlotService.getPlot(player) or not PlotService.ownsGarage(player) then
		return false
	end
	if os.clock() - (joinedAt[player] or os.clock()) < Bailiffs.joinGraceSeconds then
		return false
	end
	if debugForced[player] then
		return true
	end
	local offers = (profile :: any).offers
	local firstJoin = type(offers) == "table" and tonumber(offers.firstJoin) or os.time()
	return os.time() - firstJoin >= Bailiffs.newPlayerSeconds
end

-- Всё, что можно забрать: декор на виду; интерьер, который не нужен ни одному купленному предмету
-- и ни одному этапу (requires / requiresUpgrade), виден на участке и куплен за $
local function candidates(profile: DataService.Profile): ({ Candidate }, { Candidate })
	local decor: { Candidate } = {}
	local raw = (profile :: any).decor
	local owned = if type(raw) == "table" and type(raw.owned) == "table" then raw.owned else {}
	for _, entry in Decor.placed(owned, profile.studioLevel) do
		local cost = Decor.cost(entry.item, entry.floor)
		if cost > 0 then
			table.insert(decor, {
				kind = "decor",
				id = entry.item.id,
				key = Decor.key(entry.item.id, entry.floor),
				floor = entry.stage,
				cost = cost,
			})
		end
	end
	local needed: { [string]: boolean } = {}
	for _, upgrade in Upgrades do
		if upgrade.requires and profile.upgrades[upgrade.id] then
			needed[upgrade.requires] = true
		end
	end
	for _, stage in Stages do
		if stage.requiresUpgrade then
			needed[stage.requiresUpgrade] = true
		end
	end
	local interior: { Candidate } = {}
	for _, upgrade in Upgrades do
		if
			profile.upgrades[upgrade.id]
			and upgrade.cost > 0
			and not upgrade.move
			and not Bailiffs.protected[upgrade.id]
			and not needed[upgrade.id]
			and StudioLayout.isVisible(upgrade, profile.studioLevel)
		then
			table.insert(interior, {
				kind = "upgrade",
				id = upgrade.id,
				key = upgrade.id,
				floor = upgrade.stage or 1,
				cost = upgrade.cost,
			})
		end
	end
	return decor, interior
end

-- Сначала декор, потом интерьер. Из группы — самый дешёвый предмет, которого хватит закрыть долг;
-- не хватит ни одного — самый дорогой (меньше вещей уйдёт)
local function pickItem(profile: DataService.Profile, debt: number): Candidate?
	local decor, interior = candidates(profile)
	local group = if #decor > 0 then decor else interior
	local best: Candidate? = nil
	local priciest: Candidate? = nil
	for _, candidate in group do
		local sale = Bailiffs.saleFor(candidate.cost)
		if sale >= debt and (best == nil or candidate.cost < best.cost) then
			best = candidate
		end
		if priciest == nil or candidate.cost > priciest.cost then
			priciest = candidate
		end
	end
	return best or priciest
end

-- ===== Пристав и анимация =====

local function buildBailiff(): Model?
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = SKIN
	description.LeftArmColor = SUIT
	description.RightArmColor = SUIT
	description.TorsoColor = SUIT
	description.LeftLegColor = SUIT
	description.RightLegColor = SUIT
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn("[BailiffService] NPC build failed:", result)
		return nil
	end
	local model = result :: Model
	model.Name = "Bailiff"
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	-- Белая рубашка под пиджаком и табличка над головой — видно издалека и гостям
	local torso = model:FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") then
		local shirt = Instance.new("Part")
		shirt.Name = "Shirt"
		shirt.Anchored = true
		shirt.CanCollide = false
		shirt.CanQuery = false
		shirt.Size = Vector3.new(0.6, 1.2, 0.1)
		shirt.Color = SHIRT
		shirt.Material = Enum.Material.SmoothPlastic
		shirt.CFrame = torso.CFrame * CFrame.new(0, 0.1, -torso.Size.Z / 2 - 0.03)
		shirt.Parent = model
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local board = Instance.new("BillboardGui")
		board.Size = UDim2.fromOffset(60, 40)
		board.StudsOffset = Vector3.new(0, 2.2, 0)
		board.AlwaysOnTop = true
		board.MaxDistance = 120
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "⚖️"
		label.TextScaled = true
		label.Parent = board
		board.Parent = head
	end
	return model
end

-- Модель предмета на участке (одинаковые модели — по ближайшему месту из Config)
local function findTarget(plot: BasePart, candidate: Candidate): Model?
	if candidate.kind == "decor" then
		local decor = plot:FindFirstChild("PlayerDecor")
		local _, floor = Decor.parseKey(candidate.key)
		local model = decor and floor and decor:FindFirstChild(candidate.id .. "_" .. floor)
		return if model and model:IsA("Model") then model else nil
	end
	local upgrade = StudioLayout.get(candidate.id)
	if not upgrade then
		return nil
	end
	local expected = plot.CFrame * (upgrade.position or Vector3.zero)
	local best: Model? = nil
	local bestDistance = math.huge
	for _, child in plot:GetChildren() do
		if child:IsA("Model") and child.Name == upgrade.model then
			local distance = (child:GetPivot().Position - expected).Magnitude
			if distance < bestDistance then
				best, bestDistance = child, distance
			end
		end
	end
	return best
end

local function walk(model: Model, from: CFrame, to: CFrame)
	local seconds = math.min((to.Position - from.Position).Magnitude / WALK_SPEED, WALK_MAX)
	local alpha = Instance.new("NumberValue")
	alpha.Changed:Connect(function(value: number)
		if model.Parent then
			model:PivotTo(from:Lerp(to, value))
		end
	end)
	local tween = TweenService:Create(alpha, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Value = 1 })
	tween:Play()
	tween.Completed:Wait()
	alpha:Destroy()
end

local function fadeOut(model: Model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") or part:IsA("Decal") then
			TweenService:Create(part, TweenInfo.new(FADE_SECONDS), { Transparency = 1 }):Play()
		end
	end
end

-- Пристав выходит из лифта (в гараже — от ворот), идёт к предмету, предмет тает в пыли
local function animate(player: Player, candidate: Candidate, sale: number)
	local plot = PlotService.getPlot(player)
	if not plot then
		return
	end
	local floorY = FLOOR_LEVEL + floorYOf(candidate.floor)
	local target = findTarget(plot, candidate)
	local targetPos = if target then target:GetPivot().Position else plot.CFrame * Vector3.new(0, floorY, 0)
	local startLocal = if candidate.floor <= 1
		then Vector3.new(0, floorY + ROOT_HEIGHT, 26)
		else Vector3.new(StudioLayout.ELEVATOR.X, floorY + ROOT_HEIGHT, StudioLayout.ELEVATOR.Z)
	local start = plot.CFrame * CFrame.new(startLocal)
	local localTarget = plot.CFrame:PointToObjectSpace(targetPos)
	local flat = Vector3.new(localTarget.X, floorY + ROOT_HEIGHT, localTarget.Z)
	local direction = Vector3.new(startLocal.X - flat.X, 0, startLocal.Z - flat.Z)
	local stand = flat
		+ (if direction.Magnitude > 0.1 then direction.Unit * STAND_OFF else Vector3.new(0, 0, STAND_OFF))
	local standWorld = plot.CFrame * stand
	local face = Vector3.new(targetPos.X, standWorld.Y, targetPos.Z)
	local endCFrame = if (face - standWorld).Magnitude > 0.1
		then CFrame.lookAt(standWorld, face)
		else CFrame.new(standWorld)
	local startCFrame =
		CFrame.lookAt(start.Position, Vector3.new(standWorld.X, start.Position.Y, standWorld.Z))

	local npc = buildBailiff()
	if npc then
		npc:PivotTo(startCFrame)
		npc.Parent = container()
		walk(npc, startCFrame, endCFrame)
	end
	-- Пыль и сумма над предметом
	local puff =
		makePart(container(), Vector3.new(4, 1, 4), CFrame.new(targetPos + Vector3.new(0, 2, 0)), DUST)
	puff.Transparency = 1
	dustEmitter(puff, 0):Emit(40)
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(160, 40)
	board.StudsOffset = Vector3.new(0, 4, 0)
	board.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 90, 90)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Text = "⚖️ +" .. sale
	label.Parent = board
	board.Parent = puff
	if target then
		fadeOut(target)
	end
	task.wait(FADE_SECONDS + 0.2)
	-- Модели участка пересобираем: предмета уже нет в профиле (кнопка покупки вернётся)
	if player.Parent then
		PlotService.rebuild(player)
	end
	task.delay(3, function()
		puff:Destroy()
	end)
	if npc then
		walk(npc, endCFrame, startCFrame)
		npc:Destroy()
	end
end

-- Забрать предмет: сразу из профиля и деньги в счёт долга, потом анимация и пересборка участка
local function seize(player: Player, profile: DataService.Profile, candidate: Candidate)
	if candidate.kind == "decor" then
		local raw = (profile :: any).decor
		if type(raw) ~= "table" or type(raw.owned) ~= "table" or not raw.owned[candidate.key] then
			return
		end
		raw.owned[candidate.key] = nil
	else
		if not profile.upgrades[candidate.id] then
			return
		end
		profile.upgrades[candidate.id] = nil
	end
	local sale = Bailiffs.saleFor(candidate.cost)
	if sale > 0 then
		DataService.addCash(player, sale)
		-- Выручка приставов — не «заработок» для заданий
		local reward = optional("RewardService")
		if reward then
			pcall(reward.noteNonEarned, player, sale)
		end
	end
	DataService.replicate(player)
	BailiffRemotes.BailiffSeized:FireClient(
		player,
		{ kind = candidate.kind, id = candidate.id, amount = sale }
	)
	local analytics = optional("AnalyticsService")
	if analytics and analytics.logSeizure then
		pcall(analytics.logSeizure, player, candidate.key, sale)
	end
	busy[player] = true
	task.spawn(function()
		local ok, err = pcall(animate, player, candidate, sale)
		if not ok then
			warn("[BailiffService] animation failed:", err)
			if player.Parent then
				PlotService.rebuild(player)
			end
		end
		busy[player] = nil
	end)
end

-- ===== Цикл =====

local function setAttr(player: Player, name: string, value: any)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

local function check(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local p = profile :: any
	local debt = debtOf(profile)
	local limit = Bailiffs.limitFor(profile.studioLevel)
	setAttr(player, "BailiffDebt", debt)
	setAttr(player, "BailiffLimit", limit)
	if debt <= 0 then
		if p.bailiffs then
			p.bailiffs = nil
			BailiffRemotes.BailiffSeized:FireClient(player, { left = true })
		end
		setAttr(player, "BailiffsActive", false)
		clearDecay(player)
		ExpensesService.syncStrike(player)
		return
	end
	ensureDecay(player, profile)
	if debt >= limit and PlotService.ownsGarage(player) then
		p.bailiffs = true
	end
	setAttr(player, "BailiffsActive", p.bailiffs == true)
	if p.bailiffs ~= true or busy[player] or not canSeize(player, profile) then
		return
	end
	local now = os.clock()
	if now - (lastSeize[player] or 0) < Bailiffs.seizeSeconds then
		return
	end
	local candidate = pickItem(profile, debt)
	if candidate then
		lastSeize[player] = now
		seize(player, profile, candidate)
	end
end

-- Studio: Config/Debug.bailiffsDebt — сразу в минус, чтобы проверить плашку и приставов
local function debugDebt(player: Player)
	if not RunService:IsStudio() or (Debug.bailiffsDebt or 0) <= 0 then
		return
	end
	task.delay(DEBUG_DELAY, function()
		local profile = DataService.get(player)
		if not profile or not player.Parent then
			return
		end
		profile.cash = -math.min(Debug.bailiffsDebt, Bailiffs.maxLimit())
		debugForced[player] = true
		-- Без задержки после входа: она уже прошла, пока ждали
		joinedAt[player] = os.clock() - Bailiffs.joinGraceSeconds
		DataService.replicate(player)
		warn(
			"[BailiffService] Studio: баланс "
				.. profile.cash
				.. " для теста приставов"
		)
	end)
end

function BailiffService.start()
	DataService.onProfileLoaded(function(player: Player)
		joinedAt[player] = os.clock()
		debugDebt(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		clearDecay(player)
		joinedAt[player] = nil
		lastSeize[player] = nil
		busy[player] = nil
		debugForced[player] = nil
	end)
	-- Участок пересобран (переезд, покупка) — лампы новые, пересканировать
	PlotService.plotChanged:Connect(function(player: Player)
		local decay = decays[player]
		if decay then
			decay.scannedAt = 0
		end
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(check, player)
				if not ok then
					warn("[BailiffService] check failed:", err)
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Bailiffs.flickerSeconds)
			local ok, err = pcall(flicker)
			if not ok then
				warn("[BailiffService] flicker failed:", err)
			end
		end
	end)
end

return BailiffService
