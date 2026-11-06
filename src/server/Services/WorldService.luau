--!strict
-- Создаёт мир, если его нет в плейсе: пол, точку спавна, участки и модели-заглушки апгрейдов.
-- Всё, что уже построено в Studio, не трогаем — создаём только недостающее.
-- Благодаря этому плейс можно пересобирать из build.rbxl и ничего не теряется.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local ModelFactory = require(script.Parent.ModelFactory)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)
local StartPark = require(ReplicatedStorage.Shared.Config.StartPark)
local World = require(ReplicatedStorage.Shared.Config.World)

-- Участок каждому игроку, но не больше 12: при MaxPlayers = 60 кольцо уходило на ~760 studs,
-- за край земли (отчёт #2, п. 1). Лишние игроки ждут освободившийся участок (PlotService)
local PLOT_COUNT = math.clamp(game:GetService("Players").MaxPlayers, 6, 12)
local PLOT_SIZE = 60
local PLOT_THICKNESS = 1
-- Расстояние от спавна до центра участка: растёт с числом участков, чтобы они не налезали
-- Не ближе 102: иначе при 6–7 участках они налезают на парк Астры (Ø140, assets/models/astra-park)
local PLOT_RING_RADIUS = math.max(102, PLOT_COUNT * 80 / (2 * math.pi))
-- Земля с запасом за дальним краем участков (полудиагональ участка ≈ 0.71 · PLOT_SIZE)
-- 07.11 (владелец): карта меньше. Раньше минимум 512 (при 12 игроках ~465 от колец участков), теперь
-- ровно кольцо участков + небольшой запас; Baseplate из Studio сжимается до этого размера, по краю
-- стоят невидимые стены (ensureBoundaryWalls), чтобы никто не выпал с карты
local GROUND_SIZE = 2 * (PLOT_RING_RADIUS + PLOT_SIZE * 0.75 + 20)
local WALL_HEIGHT = World.boundary.height
local WALL_THICKNESS = World.boundary.thickness
local FOUNTAIN_SCALE = World.fountainScale
-- Тропинки от спавна к передним краям участков, чтобы было видно, куда идти
local PATH_WIDTH = 6
-- Начинаются за скамейками парка, чтобы не идти под ними (при 12 участках тропинки на углах скамеек)
local PATH_START = StartPark.benchRadius + 6
local PATH_COLOR = Color3.fromRGB(176, 150, 112)
-- Парк Астры (модель Park в ServerStorage): свои дорожки до радиуса 69.25, дальше — наши, его цветом
local LANDSCAPE_NAME = "Park"
local LANDSCAPE_OBSTACLES = "LandscapeObstacles"
local LANDSCAPE_PATH_START = 69
local LANDSCAPE_PATH_COLOR = Color3.fromRGB(217, 201, 163)
local PLOT_COLOR = Color3.fromRGB(106, 190, 48)

-- Заглушки: размер и цвет по имени модели. Неизвестные модели — серый куб.
local PLACEHOLDERS: { [string]: { size: Vector3, color: Color3 } } = {
	Desk1 = { size = Vector3.new(6, 3, 3), color = Color3.fromRGB(150, 105, 60) },
	PC1 = { size = Vector3.new(2, 2, 1), color = Color3.fromRGB(60, 60, 70) },
	GarageWalls = { size = Vector3.new(14, 8, 1), color = Color3.fromRGB(200, 190, 170) },
	Chair = { size = Vector3.new(2, 4, 2), color = Color3.fromRGB(200, 40, 60) },
	Desk2 = { size = Vector3.new(6, 3, 3), color = Color3.fromRGB(170, 120, 70) },
	Coffee = { size = Vector3.new(2, 3, 2), color = Color3.fromRGB(90, 60, 40) },
	Posters = { size = Vector3.new(8, 4, 0.5), color = Color3.fromRGB(255, 80, 200) },
	PCPro = { size = Vector3.new(3, 3, 2), color = Color3.fromRGB(40, 160, 255) },
	Office = { size = Vector3.new(12, 10, 12), color = Color3.fromRGB(220, 230, 240) },
	Floor = { size = Vector3.new(12, 16, 12), color = Color3.fromRGB(70, 110, 200) },
	Skyscraper = { size = Vector3.new(10, 40, 10), color = Color3.fromRGB(40, 40, 70) },
}
local DEFAULT_PLACEHOLDER = { size = Vector3.new(3, 3, 3), color = Color3.fromRGB(150, 150, 150) }

local WorldService = {}

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function ensureGround()
	local existing = workspace:FindFirstChild("Baseplate")
	if not existing then
		local base = makePart(
			"Baseplate",
			Vector3.new(GROUND_SIZE, 2, GROUND_SIZE),
			CFrame.new(0, -1, 0),
			Color3.fromRGB(90, 90, 95),
			workspace
		)
		base.Locked = true
	elseif existing:IsA("BasePart") then
		-- Baseplate из Studio приводим к размеру карты: меньше — расширяем (иначе участки висят над
		-- пустотой), больше — сжимаем (карту уменьшили, лишняя земля ни к чему). Центр и высота те же
		local cf = existing.CFrame
		existing.Size = Vector3.new(GROUND_SIZE, existing.Size.Y, GROUND_SIZE)
		existing.CFrame = cf
	end
	local ground = workspace:FindFirstChild("Baseplate")
	if ground and ground:IsA("BasePart") and not workspace:FindFirstChild("MapBoundary") then
		-- Невидимые стены по краю земли: четыре плиты, прозрачные, но с коллизией
		local boundary = Instance.new("Folder")
		boundary.Name = "MapBoundary"
		local half = ground.Size.X / 2
		local top = ground.Position.Y + ground.Size.Y / 2
		for _, spec in
			{
				{
					Vector3.new(ground.Size.X + 2 * WALL_THICKNESS, WALL_HEIGHT, WALL_THICKNESS),
					Vector3.new(0, 0, half + WALL_THICKNESS / 2),
				},
				{
					Vector3.new(ground.Size.X + 2 * WALL_THICKNESS, WALL_HEIGHT, WALL_THICKNESS),
					Vector3.new(0, 0, -half - WALL_THICKNESS / 2),
				},
				{
					Vector3.new(WALL_THICKNESS, WALL_HEIGHT, ground.Size.Z),
					Vector3.new(half + WALL_THICKNESS / 2, 0, 0),
				},
				{
					Vector3.new(WALL_THICKNESS, WALL_HEIGHT, ground.Size.Z),
					Vector3.new(-half - WALL_THICKNESS / 2, 0, 0),
				},
			}
		do
			local wall = Instance.new("Part")
			wall.Name = "Wall"
			wall.Anchored = true
			wall.CanCollide = true
			wall.CanQuery = false
			wall.CanTouch = false
			wall.CastShadow = false
			wall.Transparency = 1
			wall.Size = spec[1]
			wall.Position = Vector3.new(
				ground.Position.X + spec[2].X,
				top + WALL_HEIGHT / 2,
				ground.Position.Z + spec[2].Z
			)
			wall.Parent = boundary
		end
		boundary.Parent = workspace
	end
	if not workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "SpawnLocation"
		spawn.Anchored = true
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.CFrame = CFrame.new(0, 0.5, 0)
		spawn.Duration = 0
		spawn.Parent = workspace
	end
end

local function ensurePlots()
	local folder = workspace:FindFirstChild("Plots")
	if folder and #folder:GetChildren() > 0 then
		return
	end
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Plots"
		newFolder.Parent = workspace
		folder = newFolder
	end
	for i = 1, PLOT_COUNT do
		local angle = (i - 1) * (2 * math.pi / PLOT_COUNT)
		local pos = Vector3.new(
			math.cos(angle) * PLOT_RING_RADIUS,
			PLOT_THICKNESS / 2,
			math.sin(angle) * PLOT_RING_RADIUS
		)
		-- Передний край участка (+Z, там кнопки покупки) смотрит на спавн.
		-- lookAt направляет к центру -Z, поэтому разворачиваем на 180°.
		local cf = CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)) * CFrame.Angles(0, math.pi, 0)
		makePart(
			"Plot" .. i,
			Vector3.new(PLOT_SIZE, PLOT_THICKNESS, PLOT_SIZE),
			cf,
			PLOT_COLOR,
			folder :: Instance
		)
	end
end

-- Тропинки от спавна к передним краям участков (по фактическим участкам, в т. ч. собранным в Studio).
-- Только визуальные: CanCollide = false, игрок идёт по земле под ними
-- Шаблон из ServerStorage или ServerStorage.Upgrades (как импортирует Dev 1)
local function landscapeTemplate(name: string): Instance?
	local direct = ServerStorage:FindFirstChild(name)
	if direct then
		return direct
	end
	local upgrades = ServerStorage:FindFirstChild("Upgrades")
	return upgrades and upgrades:FindFirstChild(name)
end

local function hasLandscape(): boolean
	local park = landscapeTemplate(LANDSCAPE_NAME)
	return park ~= nil and park:IsA("Model")
end

-- Площадка появления (модель SpawnPad из ServerStorage.Upgrades): ставится центром в X/Z SpawnLocation,
-- низом на землю. Сам SpawnLocation остаётся невидимым (Duration = 0), вписывается в габарит площадки
-- и теряет коллизию: опора — модель, второй ступеньки над рисунком нет. Нет модели, она пустая или
-- это заглушка Generated — SpawnLocation остаётся как был (8×1×8, видимый)
local function ensureSpawnPad()
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local template = landscapeTemplate(StartPark.spawnPadName)
	if
		not spawn
		or workspace:FindFirstChild(StartPark.spawnPadName)
		or not template
		or not template:IsA("Model")
		or template:GetAttribute("Generated") == true
		or not template:FindFirstChildWhichIsA("BasePart", true)
	then
		return
	end
	local ground = workspace:FindFirstChild("Baseplate")
	local groundY = if ground and ground:IsA("BasePart") then ground.Position.Y + ground.Size.Y / 2 else 0
	local rotation = spawn.CFrame.Rotation
	local pad = template:Clone()
	pad.Name = StartPark.spawnPadName
	pad:PivotTo(CFrame.new(spawn.Position.X, groundY, spawn.Position.Z) * rotation)
	-- Низ модели строго на земле, даже если pivot импортирован не в основании
	local box, size = pad:GetBoundingBox()
	pad:PivotTo(pad:GetPivot() + Vector3.new(0, groundY - (box.Position.Y - size.Y / 2), 0))
	box, size = pad:GetBoundingBox()
	pad.Parent = workspace

	spawn.Size = size
	spawn.CFrame = CFrame.new(box.Position) * rotation
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Duration = 0
end

local function ensurePaths()
	if workspace:FindFirstChild("PlotPaths") then
		return
	end
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return
	end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local center = if spawn and spawn:IsA("BasePart")
		then Vector3.new(spawn.Position.X, 0, spawn.Position.Z)
		else Vector3.zero
	local folder = Instance.new("Folder")
	folder.Name = "PlotPaths"
	for _, plot in plots:GetChildren() do
		if plot:IsA("BasePart") then
			-- Передний край участка — локальная +Z (там вход и кнопки)
			local front = (plot.CFrame * CFrame.new(0, 0, plot.Size.Z / 2)).Position
			local target = Vector3.new(front.X, 0, front.Z)
			local offset = target - center
			local start = if hasLandscape() then LANDSCAPE_PATH_START else PATH_START
			local length = offset.Magnitude - start
			if length > 1 then
				local dir = offset.Unit
				local from = center + dir * start
				local mid = from + dir * (length / 2) + Vector3.new(0, 0.05, 0)
				local path = makePart(
					"Path_" .. plot.Name,
					Vector3.new(PATH_WIDTH, 0.1, length),
					CFrame.lookAt(mid, mid + dir),
					if hasLandscape() then LANDSCAPE_PATH_COLOR else PATH_COLOR,
					folder
				)
				path.Material = Enum.Material.Ground
				path.CanCollide = false
				path.CanQuery = false
				path.CanTouch = false
			end
		end
	end
	folder.Parent = workspace
end

-- Заглушки строятся центром основания в (0,0,0): место на участке задаёт
-- position/rotation в Config/Upgrades (PlotService). Без position — старая сетка.
local function ensureUpgradeModels()
	local folder = ServerStorage:FindFirstChild("Upgrades")
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Upgrades"
		newFolder.Parent = ServerStorage
		folder = newFolder
	end
	local spacing = 16
	-- Модели этапов (Config/Stages) ставятся как апгрейды с position
	local entries: { { model: string, position: Vector3? } } = {}
	for _, upgrade in Upgrades do
		table.insert(entries, { model = upgrade.model, position = upgrade.position })
	end
	for _, stage in Stages do
		if stage.model then
			table.insert(entries, { model = stage.model, position = stage.position })
		end
	end
	for index, upgrade in entries do
		-- Импортированная в Studio модель важнее; иначе — модель из деталей (ModelFactory)
		local built = if (folder :: Instance):FindFirstChild(upgrade.model)
			then nil
			else ModelFactory.build(upgrade.model)
		if built then
			-- Метка «собрано кодом»: PlotService отличает её от импортированной модели
			built:SetAttribute("Generated", true)
			built.Parent = folder
		elseif not (folder :: Instance):FindFirstChild(upgrade.model) then
			local spec = PLACEHOLDERS[upgrade.model] or DEFAULT_PLACEHOLDER
			-- Сетка 3×3 на участке, чтобы заглушки не налезали друг на друга
			local model = Instance.new("Model")
			model.Name = upgrade.model
			local cframe
			if upgrade.position then
				cframe = CFrame.new(0, spec.size.Y / 2, 0)
			else
				local col = (index - 1) % 3 - 1
				local row = math.floor((index - 1) / 3) - 1
				cframe = CFrame.new(col * spacing, PLOT_THICKNESS / 2 + spec.size.Y / 2, row * spacing)
			end
			local part = makePart("Main", spec.size, cframe, spec.color, model)
			model.PrimaryPart = part
			if upgrade.position then
				-- С PrimaryPart pivot модели берётся из детали: опускаем его к основанию
				part.PivotOffset = CFrame.new(0, -spec.size.Y / 2, 0)
			end
			model.Parent = folder
		end
	end
end

-- Парк «Инди в парке» вокруг спавна: скамейки с ноутбуками, доска заказов, ломбард и точки
-- картриджей (поведение — StartParkService). Участки начинаются в 60 studs от спавна,
-- тропинки к ним идут по углам 0°, 60°…, поэтому скамейки и киоски стоят между тропинками.
local function ensureStartPark()
	if workspace:FindFirstChild("StartPark") then
		return
	end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local center = if spawn and spawn:IsA("BasePart")
		then Vector3.new(spawn.Position.X, 0, spawn.Position.Z)
		else Vector3.zero
	local folder = Instance.new("Folder")
	folder.Name = "StartPark"

	-- Поставить модель на землю в точке angle/radius; lookAt разворачивает −Z модели к спавну
	local function place(model: Model, angleDeg: number, radius: number, faceSpawnWithFront: boolean)
		local angle = math.rad(angleDeg)
		local pos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local cf = CFrame.lookAt(pos, center)
		if faceSpawnWithFront then
			-- «Лицо» моделей ModelFactory — +Z, разворачиваем к спавну
			cf *= CFrame.Angles(0, math.pi, 0)
		end
		model:PivotTo(cf)
		model.Parent = folder
	end

	-- Модели Астры (assets/models/astra-park-objects) из ServerStorage важнее собранных кодом
	local function parkModel(name: string): (Model?, boolean)
		local template = landscapeTemplate(name)
		if template and template:IsA("Model") then
			return template:Clone(), true
		end
		return ModelFactory.build(name), false
	end
	-- Поставить по точке и повороту из раскладки Астры (лицо модели — +Z)
	local function placeAt(model: Model, spot: { position: Vector3, yaw: number })
		model:PivotTo(CFrame.new(center + spot.position) * CFrame.Angles(0, math.rad(spot.yaw), 0))
		model.Parent = folder
	end
	-- Надпись на табличке импортированной модели (у Астры текста нет): лицо +Z — грань Back
	local function addSign(model: Model, partName: string, key: string, text: string, color: Color3)
		local part = model:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			ModelFactory.signText(part, Enum.NormalId.Back, key, text, color)
		end
	end
	local landscape = hasLandscape()

	-- Сидящий на скамейке смотрит на −Z (к спавну), столик с ноутбуком перед ним
	for i = 1, StartPark.benchCount do
		local bench = parkModel("ParkBench")
		if bench then
			bench.Name = "Bench" .. i
			-- Ноутбук в парке — общий: атрибут Public на PcSeat (у импортированной модели может не быть)
			for _, seat in bench:GetDescendants() do
				if seat:IsA("Seat") and seat.Name == "PcSeat" then
					seat:SetAttribute("Public", true)
				end
			end
			place(bench, 30 + (i - 1) * 360 / StartPark.benchCount, StartPark.benchRadius, false)
		end
	end
	local board, boardImported = parkModel("JobBoard")
	if board then
		if landscape then
			placeAt(board, StartPark.landscapeBoard)
		else
			place(board, 90, StartPark.boardRadius, true)
		end
		if boardImported then
			addSign(board, "Header", "park_board_sign", "📋 ЗАКАЗЫ", Color3.fromRGB(255, 255, 255))
		end
	end
	local pawn, pawnImported = parkModel("Pawnshop")
	if pawn then
		if landscape then
			placeAt(pawn, StartPark.landscapePawnshop)
		else
			place(pawn, 270, StartPark.boardRadius, true)
		end
		if pawnImported then
			addSign(pawn, "SignPanel", "park_pawn_sign", "📦 ЛОМБАРД", Color3.fromRGB(255, 201, 60))
		end
	end
	-- Фонтан Астры — только вместе с её парком (место в парке под него оставлено)
	if landscape then
		local fountain = landscapeTemplate("Fountain")
		if fountain and fountain:IsA("Model") then
			local copy = fountain:Clone()
			copy.Name = "Fountain"
			-- Фонтан крупнее (владелец 07.11): масштаб вокруг центра основания, место в парке под него есть
			copy:ScaleTo(FOUNTAIN_SCALE)
			placeAt(copy, StartPark.landscapeFountain)
		end
	end

	-- Точки картриджей — на тропинках к участкам: игрок проходит мимо
	local spots = Instance.new("Folder")
	spots.Name = "CartridgeSpots"
	spots.Parent = folder
	for i = 1, StartPark.cartridgeSpots do
		local angle = math.rad((i - 1) * 360 / StartPark.cartridgeSpots)
		local pos = center
			+ Vector3.new(
				math.cos(angle) * StartPark.cartridgeRadius,
				0.1,
				math.sin(angle) * StartPark.cartridgeRadius
			)
		local spot =
			makePart("Spot" .. i, Vector3.new(3, 0.2, 3), CFrame.new(pos), Color3.fromRGB(80, 70, 60), spots)
		spot.Shape = Enum.PartType.Cylinder
		spot.Size = Vector3.new(0.2, 3, 3)
		spot.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
		spot.CanCollide = false
		spot.Material = Enum.Material.Ground
	end
	folder.Parent = workspace
end

-- Свет гаража тусклее (просьба владельца). Касается и модели, импортированной в Studio
-- (Garage из Creator Store): её лампы ослабляем один раз при старте сервера.
-- Отчёт #2, п. 16: при 0.5 лампы всё ещё давали пересвеченные пятна на полу — режем сильнее,
-- ограничиваем яркость и дальность и включаем тени, чтобы свет не пробивал всё насквозь
-- 06.11 (владелец): «2-й этаж слишком много света, очень ярко» — оболочки 2-го этажа (Floor и три
-- платные отделки) ослабляем так же, чуть мягче гаража: этаж большой, в нём не должно быть темно
type LightLimit = { scale: number, maxBrightness: number, maxRange: number }
local GARAGE_LIGHT: LightLimit = { scale = 0.3, maxBrightness = 0.4, maxRange = 16 }
local FLOOR_LIGHT: LightLimit = { scale = 0.35, maxBrightness = 0.5, maxRange = 20 }
local DIMMED_MODELS: { [string]: LightLimit } = {
	Garage = GARAGE_LIGHT,
	Floor = FLOOR_LIGHT,
	Floor_Aurora = FLOOR_LIGHT,
	Floor_Sakura = FLOOR_LIGHT,
	Floor_ObsidianGold = FLOOR_LIGHT,
}

-- Уютный стиль мебели слишком яркий (владелец 07.11): свет моделей *_Cozy в два раза темнее
local COZY_SUFFIX = "_Cozy"
local COZY_LIGHT_SCALE = 0.5

local function dimImportedLights()
	local folder = ServerStorage:FindFirstChild("Upgrades")
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		if model.Name:sub(-#COZY_SUFFIX) == COZY_SUFFIX and not model:GetAttribute("LightsDimmed") then
			model:SetAttribute("LightsDimmed", true)
			for _, d in model:GetDescendants() do
				if d:IsA("Light") then
					d.Brightness *= COZY_LIGHT_SCALE
				end
			end
		end
	end
	for name, limit in DIMMED_MODELS do
		local model = folder:FindFirstChild(name)
		if model and not model:GetAttribute("LightsDimmed") then
			model:SetAttribute("LightsDimmed", true)
			for _, d in model:GetDescendants() do
				if d:IsA("Light") then
					d.Brightness = math.min(d.Brightness * limit.scale, limit.maxBrightness)
					d.Shadows = true
					if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
						d.Range = math.min(d.Range, limit.maxRange)
					end
				end
			end
		end
	end
end

-- Трава с настоящей текстурой (материал Grass) по всему парку: земля вокруг и газон парка Астры
-- (MeadowGround #6BBF59, был гладкий пластик). Узнаём газон по цвету и имени
local function grassify(part: BasePart)
	part.Material = Enum.Material.Grass
end

local function isMeadow(part: BasePart): boolean
	if part.Name == "MeadowGround" then
		return true
	end
	local c = part.Color
	return math.abs(c.R * 255 - 107) < 12 and math.abs(c.G * 255 - 191) < 12 and math.abs(c.B * 255 - 89) < 12
end

-- Парк Астры вокруг спавна: модель — рядом со StartPark (не внутри: StartParkService посчитал бы
-- весь парк одним препятствием), невидимые прокси деревьев/пруда — внутрь StartPark, чтобы
-- картриджи не появлялись в стволах и в пруду. Pivot парка — центр основания, прокси сдвигаем
-- на тот же XZ, что и парк
local function ensureLandscape()
	local template = landscapeTemplate(LANDSCAPE_NAME)
	if not template or not template:IsA("Model") or workspace:FindFirstChild(LANDSCAPE_NAME) then
		return
	end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local center = if spawn and spawn:IsA("BasePart")
		then Vector3.new(spawn.Position.X, 0, spawn.Position.Z)
		else Vector3.zero
	local park = template:Clone()
	park:PivotTo(CFrame.new(center))
	for _, item in park:GetDescendants() do
		if item:IsA("BasePart") and isMeadow(item) then
			grassify(item)
		end
	end
	park.Parent = workspace
	local startPark = workspace:FindFirstChild("StartPark")
	local proxies = landscapeTemplate(LANDSCAPE_OBSTACLES)
	if
		startPark
		and proxies
		and proxies:IsA("Folder")
		and not startPark:FindFirstChild(LANDSCAPE_OBSTACLES)
	then
		local copy = proxies:Clone()
		for _, part in copy:GetDescendants() do
			if part:IsA("BasePart") then
				part.CFrame = CFrame.new(center) * part.CFrame
			end
		end
		copy.Parent = startPark
	end
end

-- Пустая земля вокруг парка и между участками: трава + деревья, кусты, клумбы, камни, изгороди,
-- заборчики и скамейки Астры (отдельные модели из astra-park и astra-landscape в ServerStorage). Раскладка случайная, но одна и та же
-- на каждом сервере (свой seed); обходим парк, участки с запасом под кнопки и тропинки
local OUTER_NAME = "OuterPark"
-- Как газон парка Астры (MeadowGround #6BBF59, SmoothPlastic): трава везде одинаковая (просьба владельца)
local OUTER_GROUND_COLOR = Color3.fromRGB(107, 191, 89)
local OUTER_SEED = 4242
local OUTER_CELL = 13 -- шаг сетки: в каждой клетке не больше одного предмета
local OUTER_PARK_CLEAR = 74 -- радиус парка Астры (70) + запас
local OUTER_PLOT_MARGIN = 8 -- запас вокруг участка 60×60
local OUTER_PLOT_FRONT = 14 -- спереди (+Z) — кнопки покупки и табличка гаража
local OUTER_PATH_CLEAR = 7 -- от оси тропинки
local OUTER_EDGE = 10 -- от края земли
-- Что сажаем: имя модели, вес, разброс масштаба
local OUTER_PROPS = {
	{ name = "TreeBroadleaf", weight = 5, scale = { 0.85, 1.3 } },
	{ name = "TreePine", weight = 4, scale = { 0.85, 1.4 } },
	{ name = "TreeBirch", weight = 3, scale = { 0.85, 1.2 } },
	{ name = "Bush", weight = 4, scale = { 0.8, 1.4 } },
	{ name = "Flowerbed", weight = 1, scale = { 1, 1 } },
	-- Набор Астры для разнообразия (assets/models/astra-landscape)
	{ name = "RockSmall", weight = 2, scale = { 0.8, 1.3 } },
	{ name = "RockMedium", weight = 1.5, scale = { 0.8, 1.2 } },
	{ name = "RockLarge", weight = 0.7, scale = { 0.9, 1.1 } },
	-- Заборы и изгороди убраны (владелец 06.11: стояли ни к чему, смысла не имеют)
	{ name = "StreetBench", weight = 0.8, scale = { 1, 1 } },
}
local OUTER_FILL = 0.55 -- доля клеток с предметом

local function outerBlocked(point: Vector3, center: Vector3): boolean
	local flat = Vector3.new(point.X - center.X, 0, point.Z - center.Z)
	if flat.Magnitude < OUTER_PARK_CLEAR then
		return true
	end
	local plots = workspace:FindFirstChild("Plots")
	if plots then
		for _, plot in plots:GetChildren() do
			if plot:IsA("BasePart") then
				local here = plot.CFrame:PointToObjectSpace(point)
				local half = plot.Size / 2
				if
					math.abs(here.X) < half.X + OUTER_PLOT_MARGIN
					and here.Z > -half.Z - OUTER_PLOT_MARGIN
					and here.Z < half.Z + OUTER_PLOT_FRONT
				then
					return true
				end
			end
		end
	end
	local paths = workspace:FindFirstChild("PlotPaths")
	if paths then
		for _, path in paths:GetChildren() do
			if path:IsA("BasePart") then
				local here = path.CFrame:PointToObjectSpace(point)
				if
					math.abs(here.X) < OUTER_PATH_CLEAR
					and math.abs(here.Z) < path.Size.Z / 2 + OUTER_PATH_CLEAR
				then
					return true
				end
			end
		end
	end
	return false
end

local function ensureOuterLandscape()
	if workspace:FindFirstChild(OUTER_NAME) or not hasLandscape() then
		return
	end
	local base = workspace:FindFirstChild("Baseplate")
	if base and base:IsA("BasePart") then
		base.Color = OUTER_GROUND_COLOR
		grassify(base)
	end
	local templates = {}
	local total = 0
	for _, prop in OUTER_PROPS do
		local template = landscapeTemplate(prop.name)
		if template and template:IsA("Model") then
			table.insert(templates, { model = template, weight = prop.weight, scale = prop.scale })
			total += prop.weight
		end
	end
	if total <= 0 then
		return
	end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local center = if spawn and spawn:IsA("BasePart")
		then Vector3.new(spawn.Position.X, 0, spawn.Position.Z)
		else Vector3.zero
	local groundY = if base and base:IsA("BasePart") then base.Position.Y + base.Size.Y / 2 else 0
	local half = (if base and base:IsA("BasePart") then math.min(base.Size.X, base.Size.Z) else GROUND_SIZE)
			/ 2
		- OUTER_EDGE
	local random = Random.new(OUTER_SEED)
	local folder = Instance.new("Folder")
	folder.Name = OUTER_NAME
	local cells = math.floor(half / OUTER_CELL)
	for ix = -cells, cells - 1 do
		for iz = -cells, cells - 1 do
			-- random вызываем всегда одинаково — раскладка не зависит от того, что клетка занята
			local fill = random:NextNumber()
			local pick = random:NextNumber() * total
			local jitterX, jitterZ = random:NextNumber(0.15, 0.85), random:NextNumber(0.15, 0.85)
			local yaw, scaleRoll = random:NextNumber(0, 2 * math.pi), random:NextNumber()
			local point = Vector3.new(
				center.X + (ix + jitterX) * OUTER_CELL,
				groundY,
				center.Z + (iz + jitterZ) * OUTER_CELL
			)
			if fill < OUTER_FILL and not outerBlocked(point, center) then
				local chosen = templates[#templates]
				for _, entry in templates do
					pick -= entry.weight
					if pick <= 0 then
						chosen = entry
						break
					end
				end
				local model = chosen.model:Clone()
				local scale = chosen.scale[1] + (chosen.scale[2] - chosen.scale[1]) * scaleRoll
				if scale ~= 1 then
					model:ScaleTo(scale)
				end
				model:PivotTo(CFrame.new(point) * CFrame.Angles(0, yaw, 0))
				model.Parent = folder
			end
		end
	end
	folder.Parent = workspace
end

-- Вызывать до PlotService.start()
-- Импортированные модели апгрейдов (ServerStorage.Upgrades) клонируются на каждый участок:
-- касания у декора не нужны (Touched — только у кнопок покупки), Seat оставляем
local function untouchUpgradeModels()
	local folder = ServerStorage:FindFirstChild("Upgrades")
	if not folder then
		return
	end
	for _, item in folder:GetDescendants() do
		if item:IsA("BasePart") and not item:IsA("Seat") and not item:IsA("VehicleSeat") then
			item.CanTouch = false
		end
	end
end

-- Спасение от падения (владелец 07.11): упал ниже FALL_Y (прыжок с 3-го этажа, баг лифта, дыра в карте) —
-- сразу на свой участок или к спавну, без смерти и потери прогресса
local FALL_Y = World.fallY
local FALL_CHECK = World.fallCheckSeconds

local function rescueFallen()
	for _, player in game:GetService("Players"):GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and root.Position.Y < FALL_Y then
			local plots = workspace:FindFirstChild("Plots")
			local plot = plots and plots:FindFirstChild(tostring(player:GetAttribute("PlotName")))
			local target: CFrame
			if plot and plot:IsA("BasePart") then
				target = plot.CFrame * CFrame.new(0, plot.Size.Y / 2 + 6, plot.Size.Z / 2 + 10)
			else
				local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
				target = CFrame.new(
					if spawn and spawn:IsA("BasePart")
						then spawn.Position + Vector3.new(0, 6, 0)
						else Vector3.new(0, 10, 0)
				)
			end
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = target
		end
	end
end

function WorldService.start()
	task.spawn(function()
		while true do
			task.wait(FALL_CHECK)
			local ok, err = pcall(rescueFallen)
			if not ok then
				warn("[WorldService] rescueFallen failed:", err)
			end
		end
	end)
	ensureGround()
	ensurePlots()
	ensureSpawnPad()
	ensurePaths()
	ensureUpgradeModels()
	ensureStartPark()
	ensureLandscape()
	ensureOuterLandscape()
	dimImportedLights()
	untouchUpgradeModels()
end

return WorldService
