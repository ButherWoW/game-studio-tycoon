--!strict
-- «Инди в парке»: доска заказов (мини-игры), ретро-картриджи и ломбард у спавна,
-- а ещё название студии после покупки гаража (вывеска на постерах и табличка у входа).
-- Парк строит WorldService (папка workspace.StartPark), здесь — поведение.
-- Данные: (profile :: any).cartridges, .jobReadyAt { [jobId]: os.time() }, .studioName.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local StartPark = require(ReplicatedStorage.Shared.Config.StartPark)
local StartRemotes = require(ReplicatedStorage.Shared.StartRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local TextSafe = require(ReplicatedStorage.Shared.TextSafe)
local WordFilter = require(ReplicatedStorage.Shared.WordFilter)

local PROFILE_WAIT = 0.2
local REQUEST_COOLDOWN = 0.3 -- секунд между запросами заказов одного игрока
local NAME_COOLDOWN = 1
local PROMPT_DISTANCE = 10
local PICKUP_DISTANCE = 14 -- запас к PROMPT_DISTANCE на лаги
local EARLY_TOLERANCE = 1 -- результат раньше jobDuration минус это — враньё клиента

type ActiveJob = { id: string, startedAt: number }

local StartParkService = {}
-- Ставит VipService: украсить готовую вывеску игрока (модель StudioSign и доска с названием)
StartParkService.decorateSign = nil :: ((Player, Model, BasePart) -> ())?
-- Остальные украшения вывески (PremiumService: ⭐ перед названием) — после VIP, по порядку
StartParkService.signDecorators = {} :: { (Player, Model, BasePart) -> () }
local activeJobs: { [Player]: ActiveJob } = {}
local lastRequest: { [Player]: number } = {}
local lastNameRequest: { [Player]: number } = {}
local naming: { [Player]: boolean } = {}

local jobsById: { [string]: StartPark.Job } = {}
for _, job in StartPark.jobs do
	jobsById[job.id] = job
end

local function park(): Instance?
	return workspace:FindFirstChild("StartPark")
end

local function rootPart(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isSeated(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

local function near(player: Player, target: BasePart, distance: number): boolean
	local root = rootPart(player)
	return root ~= nil and (root.Position - target.Position).Magnitude <= distance
end

-- Деталь модели парка для ProximityPrompt (JobBoard.Board, Pawnshop.Counter)
local function promptPart(modelName: string, partName: string): BasePart?
	local folder = park()
	local model = folder and folder:FindFirstChild(modelName)
	local p = model
		and (model:FindFirstChild(partName, true) or model:FindFirstChildWhichIsA("BasePart", true))
	return if p and p:IsA("BasePart") then p else nil
end

-- Текст подсказки по-русски; клиент переводит по атрибутам ActionKey/ObjectKey
local function makePrompt(
	parent: BasePart,
	action: string,
	actionKey: string,
	object: string,
	objectKey: string
)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("ActionKey", actionKey)
	prompt:SetAttribute("ObjectKey", objectKey)
	prompt.Parent = parent
	return prompt
end

-- ===== Профиль =====

local function cartridgesOf(profile: DataService.Profile): number
	local p = profile :: any
	local count = tonumber(p.cartridges)
	if not count or count ~= count or count < 0 then
		count = 0
	end
	p.cartridges = math.floor(count :: number)
	return p.cartridges
end

local function jobReadyAt(profile: DataService.Profile): { [string]: number }
	local p = profile :: any
	if type(p.jobReadyAt) ~= "table" then
		p.jobReadyAt = {}
	end
	return p.jobReadyAt
end

local function studioNameOf(player: Player, profile: DataService.Profile): string
	local name = (profile :: any).studioName
	return if type(name) == "string" and name ~= "" then name else "Studio " .. player.DisplayName
end

local function hasStudioName(profile: DataService.Profile): boolean
	local name = (profile :: any).studioName
	return type(name) == "string" and name ~= ""
end

-- ===== Доска заказов =====

local board: BasePart? = nil

local function jobBoardState(profile: DataService.Profile): { [string]: number }
	local readyAt = jobReadyAt(profile)
	local now = os.time()
	local state = {}
	for _, job in StartPark.jobs do
		state[job.id] = math.max((tonumber(readyAt[job.id]) or 0) - now, 0)
	end
	return state
end

local function onBoardTriggered(player: Player)
	local profile = DataService.get(player)
	if profile then
		StartRemotes.JobBoardOpen:FireClient(player, jobBoardState(profile))
	end
end

local function rateLimited(player: Player): boolean
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return true
	end
	lastRequest[player] = now
	return false
end

-- Заказ без результата дольше срока — снимаем, перезарядка всё равно идёт
local function dropExpired(player: Player, profile: DataService.Profile)
	local active = activeJobs[player]
	if active and os.clock() - active.startedAt > StartPark.jobDuration + StartPark.jobGrace then
		activeJobs[player] = nil
		jobReadyAt(profile)[active.id] = os.time() + StartPark.jobCooldown
	end
end

local function onJobStart(player: Player, jobId: any)
	if rateLimited(player) or type(jobId) ~= "string" or not jobsById[jobId] then
		return
	end
	local profile = DataService.get(player)
	if not profile or not board then
		return
	end
	dropExpired(player, profile)
	if activeJobs[player] then
		return
	end
	-- Подработки — только для тех, кто копит на первый гараж (иначе это вечный AFK-фарм)
	if PlotService.ownsGarage(player) then
		StartRemotes.JobResult:FireClient(player, { id = jobId, ok = false, pay = 0, reason = "garage" })
		return
	end
	if (tonumber(jobReadyAt(profile)[jobId]) or 0) > os.time() then
		return
	end
	-- Заказ берут у доски и стоя: за ноутбуком параллельно не поработаешь
	if isSeated(player) or not near(player, board :: BasePart, StartPark.jobMaxDistance) then
		return
	end
	activeJobs[player] = { id = jobId, startedAt = os.clock() }
	StartRemotes.JobStarted:FireClient(player, { id = jobId, duration = StartPark.jobDuration })
end

local function onJobFinish(player: Player, jobId: any, rawScore: any)
	if rateLimited(player) or type(jobId) ~= "string" then
		return
	end
	local active = activeJobs[player]
	local profile = DataService.get(player)
	if not active or active.id ~= jobId or not profile then
		return
	end
	local job = jobsById[jobId]
	activeJobs[player] = nil
	jobReadyAt(profile)[jobId] = os.time() + StartPark.jobCooldown

	local elapsed = os.clock() - active.startedAt
	local inTime = elapsed >= StartPark.jobDuration - EARLY_TOLERANCE
		and elapsed <= StartPark.jobDuration + StartPark.jobGrace
	local inPlace = board ~= nil
		and not isSeated(player)
		and near(player, board :: BasePart, StartPark.jobMaxDistance)
	local score = tonumber(rawScore)
	if not inTime or not inPlace or not score or score ~= score then
		StartRemotes.JobResult:FireClient(player, { id = jobId, ok = false, pay = 0 })
		return
	end
	-- Счёт клиента не больше физически возможного за 15 с
	score = math.clamp(math.floor(score :: number), 0, job.maxScore)
	local share = math.clamp(score / job.target, 0, 1)
	local pay = math.floor(job.minPay + (job.maxPay - job.minPay) * share)
	DataService.addCash(player, pay)
	StartRemotes.JobResult:FireClient(player, { id = jobId, ok = true, pay = pay })
end

-- ===== Картриджи и ломбард =====

local CARTRIDGE_COLORS = {
	Color3.fromRGB(255, 90, 95),
	Color3.fromRGB(61, 123, 255),
	Color3.fromRGB(61, 220, 132),
	Color3.fromRGB(255, 201, 60),
	Color3.fromRGB(190, 90, 255),
}
local rng = Random.new()

local spawnCartridge: (spot: BasePart) -> ()

-- Картриджи разбросаны по всему парку, а не стоят кольцом: точка (деталь из CartridgeSpots)
-- перед каждым появлением переезжает в случайное место. Препятствия считаются один раз в start
type Obstacle = { position: Vector3, radius: number }
local parkCenter = Vector3.zero
local groundY = 0 -- высота земли парка (по точкам из плейса), чтобы не лечь на крышу
local obstacles: { Obstacle } = {}

local function addObstacle(target: Instance)
	if target:IsA("Model") then
		local cf, size = target:GetBoundingBox()
		table.insert(obstacles, { position = cf.Position, radius = math.max(size.X, size.Z) / 2 })
	elseif target:IsA("BasePart") then
		table.insert(
			obstacles,
			{ position = target.Position, radius = math.max(target.Size.X, target.Size.Z) / 2 }
		)
	end
end

-- Модель, появившаяся в парке после старта (щиты и Зал славы выходят обновлением по средам,
-- BillboardService / HallOfFameService): картриджи больше не падают внутрь неё
function StartParkService.addObstacle(target: Instance)
	addObstacle(target)
end

-- Скамейки, доска, ломбард и прочие модели парка, фонтан и спавн
local function collectObstacles(folder: Instance, spots: Instance?)
	obstacles = {}
	for _, child in folder:GetChildren() do
		if child == spots then
			continue
		end
		if child:IsA("Folder") then
			for _, inner in child:GetChildren() do
				addObstacle(inner)
			end
		else
			addObstacle(child)
		end
	end
	-- Деревья, камни и скамейки вокруг парка (WorldService.ensureOuterLandscape)
	local outer = workspace:FindFirstChild("OuterPark")
	for _, prop in if outer then outer:GetChildren() else {} do
		addObstacle(prop)
	end
	local fountain = workspace:FindFirstChild("Fountain", true)
	if fountain then
		addObstacle(fountain)
	end
	local spawnPoint = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnPoint then
		addObstacle(spawnPoint)
		parkCenter = Vector3.new(spawnPoint.Position.X, 0, spawnPoint.Position.Z)
	end
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Место свободно: в стороне от препятствий и от других картриджей
-- Точка на участке игрока, у его кнопок или на тропинке к нему (туда картриджи не кладём)
local function onPlotOrPath(position: Vector3): boolean
	local plots = workspace:FindFirstChild("Plots")
	for _, plot in if plots then plots:GetChildren() else {} do
		if plot:IsA("BasePart") then
			local here = plot.CFrame:PointToObjectSpace(position)
			local margin = StartPark.cartridgePlotMargin
			if
				math.abs(here.X) < plot.Size.X / 2 + margin
				and here.Z > -plot.Size.Z / 2 - margin
				and here.Z < plot.Size.Z / 2 + margin + 8
			then
				return true
			end
		end
	end
	local paths = workspace:FindFirstChild("PlotPaths")
	for _, path in if paths then paths:GetChildren() else {} do
		if path:IsA("BasePart") then
			local here = path.CFrame:PointToObjectSpace(position)
			if math.abs(here.X) < StartPark.cartridgePathClear and math.abs(here.Z) < path.Size.Z / 2 then
				return true
			end
		end
	end
	return false
end

local function spotFree(position: Vector3, spot: BasePart): boolean
	if onPlotOrPath(position) then
		return false
	end
	for _, obstacle in obstacles do
		if flatDistance(position, obstacle.position) < obstacle.radius + StartPark.cartridgeClearance then
			return false
		end
	end
	local spots = spot.Parent
	for _, other in if spots then spots:GetChildren() else {} do
		if
			other ~= spot
			and other:IsA("BasePart")
			and other:FindFirstChild("Cartridge")
			and flatDistance(position, other.Position) < StartPark.cartridgeSpacing
		then
			return false
		end
	end
	return true
end

-- Случайная точка на земле парка (луч вниз); nil — за cartridgeTries попыток не нашлось
local function randomSpotPosition(spot: BasePart): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { spot.Parent or spot }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local minR, maxR = StartPark.cartridgeAreaMin, StartPark.cartridgeAreaMax
	for _ = 1, StartPark.cartridgeTries do
		-- Равномерно по площади кольца
		local radius = math.sqrt(rng:NextNumber(minR * minR, maxR * maxR))
		local angle = rng:NextNumber(0, 2 * math.pi)
		local flat = parkCenter + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		if spotFree(flat, spot) then
			local hit =
				workspace:Raycast(Vector3.new(flat.X, groundY + 60, flat.Z), Vector3.new(0, -120, 0), params)
			if hit and hit.Normal.Y > 0.7 and math.abs(hit.Position.Y - groundY) < 4 then
				return hit.Position
			end
		end
	end
	return nil
end

-- Переставить точку (вместе с её «пятном» на земле), сохранив поворот детали
local function relocateSpot(spot: BasePart)
	local position = randomSpotPosition(spot)
	if position then
		spot.CFrame = (spot.CFrame - spot.Position) + position + Vector3.new(0, 0.1, 0)
	end
end

local function onPickup(player: Player, spot: BasePart, cartridge: BasePart)
	-- Два игрока нажали одновременно: второй уже не найдёт картридж на месте
	if cartridge.Parent ~= spot then
		return
	end
	local profile = DataService.get(player)
	if not profile or not near(player, cartridge, PICKUP_DISTANCE) then
		return
	end
	local count = cartridgesOf(profile)
	if count >= StartPark.maxCartridges then
		StartRemotes.ParkNotice:FireClient(player, { kind = "full", count = count })
		return
	end
	cartridge:Destroy()
	count += 1
	(profile :: any).cartridges = count
	player:SetAttribute("Cartridges", count)
	StartRemotes.ParkNotice:FireClient(player, { kind = "cartridge", count = count })
	task.delay(StartPark.cartridgeRespawn, spawnCartridge, spot)
end

spawnCartridge = function(spot: BasePart)
	if not spot.Parent or spot:FindFirstChild("Cartridge") then
		return
	end
	relocateSpot(spot)
	-- Старая дискета (06.11, владелец «перерисуй»): квадратный корпус, металлическая шторка сверху,
	-- белая этикетка снизу, вырез защиты записи. Корпус — корневая деталь (Anchored, на ней подсказка
	-- «Подобрать»), остальное приварено и едет вместе с ней: клиент крутит и качает дискету
	-- (Controllers/CartridgeAnimator, тег ParkCartridge), опираясь на атрибуты BasePos и BaseYaw
	local cartridge = Instance.new("Part")
	cartridge.Name = "Cartridge"
	cartridge.Anchored = true
	cartridge.CanCollide = false
	cartridge.Size = Vector3.new(1.7, 1.7, 0.16)
	cartridge.Color = CARTRIDGE_COLORS[rng:NextInteger(1, #CARTRIDGE_COLORS)]
	cartridge.Material = Enum.Material.SmoothPlastic
	local basePosition = spot.Position + Vector3.new(0, 2.2, 0)
	local baseYaw = rng:NextNumber(0, 2 * math.pi)
	cartridge.CFrame = CFrame.new(basePosition) * CFrame.Angles(0, baseYaw, 0)
	cartridge:SetAttribute("BasePos", basePosition)
	cartridge:SetAttribute("BaseYaw", baseYaw)
	local function detail(
		name: string,
		size: Vector3,
		offset: Vector3,
		color: Color3,
		material: Enum.Material
	)
		local piece = Instance.new("Part")
		piece.Name = name
		piece.Anchored = false
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.Massless = true
		piece.Size = size
		piece.Color = color
		piece.Material = material
		piece.CFrame = cartridge.CFrame * CFrame.new(offset)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = cartridge
		weld.Part1 = piece
		weld.Parent = piece
		piece.Parent = cartridge
		return piece
	end
	-- Металлическая шторка сверху и квадратное окошко в ней
	detail(
		"Shutter",
		Vector3.new(0.9, 0.6, 0.2),
		Vector3.new(0.12, 0.55, 0),
		Color3.fromRGB(196, 200, 208),
		Enum.Material.Metal
	)
	detail(
		"ShutterWindow",
		Vector3.new(0.22, 0.4, 0.22),
		Vector3.new(0.3, 0.55, 0),
		Color3.fromRGB(40, 42, 48),
		Enum.Material.SmoothPlastic
	)
	-- Белая этикетка снизу (две стороны одной деталью-пластиной) и цветная полоска на ней
	detail(
		"Label",
		Vector3.new(1.3, 0.85, 0.2),
		Vector3.new(0, -0.35, 0),
		Color3.fromRGB(242, 240, 230),
		Enum.Material.SmoothPlastic
	)
	detail(
		"LabelStripe",
		Vector3.new(1.3, 0.16, 0.22),
		Vector3.new(0, -0.08, 0),
		cartridge.Color,
		Enum.Material.SmoothPlastic
	)
	-- Вырез защиты записи в углу
	detail(
		"Notch",
		Vector3.new(0.16, 0.16, 0.2),
		Vector3.new(-0.72, -0.72, 0),
		Color3.fromRGB(30, 30, 34),
		Enum.Material.SmoothPlastic
	)
	CollectionService:AddTag(cartridge, "ParkCartridge")
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = cartridge.Color
	sparkle.Parent = cartridge
	local prompt = makePrompt(
		cartridge,
		"Подобрать",
		"park_cartridge_prompt",
		"Ретро-картридж",
		"park_cartridge"
	)
	prompt.Triggered:Connect(function(player: Player)
		onPickup(player, spot, cartridge)
	end)
	cartridge.Parent = spot
end

-- Множитель ломбарда от «Событий дня»; без модуля или при ошибке — 1
local function dailyPawnMultiplier(): number
	local module = script.Parent:FindFirstChild("DailyEventService")
	if not module or not module:IsA("ModuleScript") then
		return 1
	end
	local ok, value = pcall(function()
		return (require(module) :: any).pawnMultiplier()
	end)
	return if ok and type(value) == "number" and value >= 1 and value <= 10 then value else 1
end

-- «Картриджепад»: multiplier > 1 — в CartridgeSpots добавляются временные точки RushSpot*
-- (всего точек в multiplier раз больше), 1 — временные точки убираются вместе с картриджами
function StartParkService.setCartridgeRush(multiplier: number)
	local folder = park()
	local spots = folder and folder:FindFirstChild("CartridgeSpots")
	if not spots then
		return
	end
	local base: { BasePart } = {}
	for _, spot in spots:GetChildren() do
		if spot:IsA("BasePart") then
			if spot:GetAttribute("DailyRush") then
				if multiplier <= 1 then
					spot:Destroy()
				end
			else
				table.insert(base, spot)
			end
		end
	end
	if multiplier <= 1 then
		spots:SetAttribute("RushActive", nil)
		return
	end
	-- Уже добавлены (повторный вызов в том же событии)
	if #base == 0 or spots:GetAttribute("RushActive") then
		return
	end
	spots:SetAttribute("RushActive", true)
	local extra = math.floor(#base * (multiplier - 1))
	for i = 1, extra do
		local spot = base[(i - 1) % #base + 1]:Clone()
		for _, child in spot:GetChildren() do
			child:Destroy()
		end
		spot.Name = "RushSpot" .. i
		spot:SetAttribute("DailyRush", true)
		spot.Parent = spots
		spawnCartridge(spot)
	end
end

local function onPawn(player: Player)
	local profile = DataService.get(player)
	local counter = promptPart("Pawnshop", "Counter")
	if not profile or not counter or not near(player, counter, PICKUP_DISTANCE) then
		return
	end
	local count = cartridgesOf(profile)
	if count <= 0 then
		StartRemotes.ParkNotice:FireClient(player, { kind = "pawn", count = 0, pay = 0 })
		return
	end
	-- «Картриджепад» (DailyEventService): ломбард платит больше
	local pay = math.floor(count * StartPark.cartridgePrice * dailyPawnMultiplier());
	(profile :: any).cartridges = 0
	player:SetAttribute("Cartridges", 0)
	DataService.addCash(player, pay)
	StartRemotes.ParkNotice:FireClient(player, { kind = "pawn", count = count, pay = pay })
end

-- ===== Название студии =====

-- Над воротами гаража (передняя стена z = 29.5, высота 12). Отчёт #2, п. 15: доска 22×3.2 на 13.5
-- закрывала обзор у передней кнопки — теперь меньше и выше, на двух стойках над стеной
local SIGN_OFFSET = CFrame.new(0, 17, 29.5)
local SIGN_SIZE = Vector2.new(14, 2.2)
local SIGN_WALL_TOP = 12

-- Вывеска на постерах и табличка у входа на участке игрока. Табличка — модель, поэтому
-- PlotService.rebuild её сносит, а plotChanged ставит заново
local function applyStudioSigns(player: Player)
	local plot = PlotService.getPlot(player)
	local profile = DataService.get(player)
	if not plot or not profile then
		return
	end
	local old = plot:FindFirstChild("StudioSign")
	if old then
		old:Destroy()
	end
	if not PlotService.ownsGarage(player) then
		return
	end
	local name = studioNameOf(player, profile)
	local posters = plot:FindFirstChild("Posters")
	local neon = posters and posters:FindFirstChild("StudioName", true)
	if neon and neon:IsA("TextLabel") then
		neon.Text = name
	end

	-- Настоящая вывеска над воротами: тёмная доска с неоновой рамкой и названием с обеих сторон
	local model = Instance.new("Model")
	model.Name = "StudioSign"
	local signBoard = Instance.new("Part")
	signBoard.Name = "Board"
	signBoard.Anchored = true
	signBoard.CanCollide = false
	signBoard.CanQuery = false
	signBoard.CanTouch = false
	signBoard.Size = Vector3.new(SIGN_SIZE.X, SIGN_SIZE.Y, 0.4)
	signBoard.Color = Color3.fromRGB(28, 26, 40)
	signBoard.Material = Enum.Material.SmoothPlastic
	signBoard.CFrame = plot.CFrame * SIGN_OFFSET
	signBoard.Parent = model
	for _, y in { SIGN_SIZE.Y / 2 + 0.1, -SIGN_SIZE.Y / 2 - 0.1 } do
		local strip = Instance.new("Part")
		strip.Anchored = true
		strip.CanCollide = false
		strip.CanQuery = false
		strip.CanTouch = false
		strip.Size = Vector3.new(SIGN_SIZE.X + 0.3, 0.2, 0.5)
		strip.Color = Color3.fromRGB(255, 201, 60)
		strip.Material = Enum.Material.Neon
		strip.CFrame = signBoard.CFrame * CFrame.new(0, y, 0)
		strip.Parent = model
	end
	-- Стойки от верха стены до низа доски
	local postHeight = SIGN_OFFSET.Position.Y - SIGN_SIZE.Y / 2 - SIGN_WALL_TOP
	for _, x in { -SIGN_SIZE.X / 2 + 1.5, SIGN_SIZE.X / 2 - 1.5 } do
		local post = Instance.new("Part")
		post.Anchored = true
		post.CanCollide = false
		post.CanQuery = false
		post.CanTouch = false
		post.Size = Vector3.new(0.3, postHeight, 0.3)
		post.Color = Color3.fromRGB(60, 60, 65)
		post.Material = Enum.Material.Metal
		post.CFrame = signBoard.CFrame * CFrame.new(x, -SIGN_SIZE.Y / 2 - postHeight / 2, 0)
		post.Parent = model
	end
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = signBoard
		local label = Instance.new("TextLabel")
		label.Name = "StudioName"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(255, 201, 60)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = name
		label.Parent = gui
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 201, 60)
	glow.Range = 10
	glow.Brightness = 0.6
	glow.Parent = signBoard
	model.Parent = plot
	-- VIP: золотая рамка, 👑 и искры (VipService)
	local decorate = StartParkService.decorateSign
	if decorate then
		local ok, err = pcall(decorate, player, model, signBoard)
		if not ok then
			warn("[StartParkService] VIP sign failed:", err)
		end
	end
	for _, extra in StartParkService.signDecorators do
		local ok, err = pcall(extra, player, model, signBoard)
		if not ok then
			warn("[StartParkService] Sign decorator failed:", err)
		end
	end
end

-- Перестроить вывеску (VipService, PremiumService: статус появился или пропал)
StartParkService.refreshSigns = applyStudioSigns

local function refreshNaming(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	-- Окно открывает клиент по атрибуту: и новым владельцам гаража, и старым игрокам без названия
	player:SetAttribute("NeedsStudioName", PlotService.ownsGarage(player) and not hasStudioName(profile))
end

local function onSetStudioName(player: Player, raw: any)
	if type(raw) ~= "string" or #raw > 200 or naming[player] then
		return
	end
	local now = os.clock()
	if (lastNameRequest[player] or 0) + NAME_COOLDOWN > now then
		return
	end
	lastNameRequest[player] = now
	local profile = DataService.get(player)
	if not profile or not PlotService.ownsGarage(player) or hasStudioName(profile) then
		return
	end
	-- Убираем невидимые символы, «Zalgo» и экзотические пробелы; видимых должно быть не меньше минимума
	local name = TextSafe.clean(raw)
	local length = name and utf8.len(name)
	if
		not name
		or not length
		or TextSafe.visibleLength(name) < StartPark.studioNameMin
		or length > StartPark.studioNameMax
	then
		StartRemotes.StudioNameResult:FireClient(player, { ok = false, reason = "length" })
		return
	end
	-- Свой фильтр мата: отвечаем как на фильтр Roblox — «придумай другое название»
	if not WordFilter.isClean(name) then
		StartRemotes.StudioNameResult:FireClient(player, { ok = false, reason = "filtered" })
		return
	end

	-- Фильтр уступает поток: второй запрос в это время не пройдёт
	naming[player] = true
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(name, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	naming[player] = nil
	if not player.Parent or DataService.get(player) ~= profile or hasStudioName(profile) then
		return
	end
	if not ok or type(result) ~= "string" then
		warn("[StartParkService] Text filter failed:", result)
		StartRemotes.StudioNameResult:FireClient(player, { ok = false, reason = "error" })
		return
	end
	-- Фильтр заменил слова решётками — просим другое название, а не сохраняем «####»
	if result ~= name then
		StartRemotes.StudioNameResult:FireClient(player, { ok = false, reason = "filtered" })
		return
	end
	(profile :: any).studioName = result
	refreshNaming(player)
	applyStudioSigns(player)
	StartRemotes.StudioNameResult:FireClient(player, { ok = true, name = result })
	task.spawn(DataService.save, player)
end

-- ===== Старт =====

local function onPlayerAdded(player: Player)
	local profile = DataService.get(player)
	while not profile and player.Parent do
		task.wait(PROFILE_WAIT)
		profile = DataService.get(player)
	end
	if profile then
		player:SetAttribute("Cartridges", cartridgesOf(profile))
	end
end

-- Общие ноутбуки — для тех, кто копит на гараж: владельца гаража со скамейки поднимаем,
-- иначе альты и старички занимают все места и новичкам негде делать игры
local function guardPublicSeat(seat: Instance)
	if not seat:IsA("Seat") or seat.Name ~= "PcSeat" or seat:GetAttribute("Public") ~= true then
		return
	end
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = seat.Occupant
		local player = humanoid and Players:GetPlayerFromCharacter(humanoid.Parent)
		if player and humanoid and PlotService.ownsGarage(player) then
			humanoid.Sit = false
			StartRemotes.JobResult:FireClient(
				player,
				{ id = "", ok = false, pay = 0, reason = "garage_seat" }
			)
		end
	end)
end

function StartParkService.start()
	for _, d in workspace:GetDescendants() do
		guardPublicSeat(d)
	end
	workspace.DescendantAdded:Connect(guardPublicSeat)
	local folder = park()
	if not folder then
		warn("[StartParkService] workspace.StartPark not found: park is disabled")
	else
		board = promptPart("JobBoard", "Board")
		if board then
			local prompt = makePrompt(
				board,
				"Взять заказ",
				"park_board_prompt",
				"Доска заказов",
				"park_board"
			)
			prompt.Triggered:Connect(onBoardTriggered)
		end
		local counter = promptPart("Pawnshop", "Counter")
		if counter then
			local prompt = makePrompt(
				counter,
				"Сдать картриджи",
				"park_pawn_prompt",
				"Ломбард",
				"park_pawn"
			)
			prompt.Triggered:Connect(onPawn)
		end
		local spots = folder:FindFirstChild("CartridgeSpots")
		collectObstacles(folder, spots)
		if spots then
			-- Высота земли — по самой низкой точке из плейса
			local lowest = math.huge
			for _, spot in spots:GetChildren() do
				if spot:IsA("BasePart") then
					lowest = math.min(lowest, spot.Position.Y)
				end
			end
			groundY = if lowest < math.huge then lowest - 0.1 else 0
			for _, spot in spots:GetChildren() do
				if spot:IsA("BasePart") then
					spawnCartridge(spot)
				end
			end
		end
	end

	StartRemotes.JobStart.OnServerEvent:Connect(onJobStart)
	StartRemotes.JobFinish.OnServerEvent:Connect(onJobFinish)
	StartRemotes.SetStudioName.OnServerEvent:Connect(onSetStudioName)
	-- Участок собран (вход, покупка гаража, апгрейд, переезд): вывески и окно названия
	PlotService.plotChanged:Connect(function(player: Player)
		applyStudioSigns(player)
		refreshNaming(player)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		activeJobs[player] = nil
		lastRequest[player] = nil
		lastNameRequest[player] = nil
		naming[player] = nil
	end)
end

return StartParkService
