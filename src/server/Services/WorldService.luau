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

-- Участок каждому игроку, но не больше 12: при MaxPlayers = 60 кольцо уходило на ~760 studs,
-- за край земли (отчёт #2, п. 1). Лишние игроки ждут освободившийся участок (PlotService)
local PLOT_COUNT = math.clamp(game:GetService("Players").MaxPlayers, 6, 12)
local PLOT_SIZE = 60
local PLOT_THICKNESS = 1
-- Расстояние от спавна до центра участка: растёт с числом участков, чтобы они не налезали
-- Не ближе 102: иначе при 6–7 участках они налезают на парк Астры (Ø140, assets/models/astra-park)
local PLOT_RING_RADIUS = math.max(102, PLOT_COUNT * 80 / (2 * math.pi))
-- Земля с запасом за дальним краем участков (полудиагональ участка ≈ 0.71 · PLOT_SIZE)
local GROUND_SIZE = math.max(512, 2 * (PLOT_RING_RADIUS + PLOT_SIZE) + 40)
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
	elseif existing:IsA("BasePart") and (existing.Size.X < GROUND_SIZE or existing.Size.Z < GROUND_SIZE) then
		-- Baseplate из Studio меньше кольца участков: расширяем, иначе участки висят над пустотой
		local cf = existing.CFrame
		existing.Size = Vector3.new(
			math.max(existing.Size.X, GROUND_SIZE),
			existing.Size.Y,
			math.max(existing.Size.Z, GROUND_SIZE)
		)
		existing.CFrame = cf
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
local GARAGE_LIGHT_SCALE = 0.3
local GARAGE_LIGHT_MAX_BRIGHTNESS = 0.4
local GARAGE_LIGHT_MAX_RANGE = 16
local DIMMED_MODELS = { "Garage" }

local function dimImportedLights()
	local folder = ServerStorage:FindFirstChild("Upgrades")
	if not folder then
		return
	end
	for _, name in DIMMED_MODELS do
		local model = folder:FindFirstChild(name)
		if model and not model:GetAttribute("LightsDimmed") then
			model:SetAttribute("LightsDimmed", true)
			for _, d in model:GetDescendants() do
				if d:IsA("Light") then
					d.Brightness = math.min(d.Brightness * GARAGE_LIGHT_SCALE, GARAGE_LIGHT_MAX_BRIGHTNESS)
					d.Shadows = true
					if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
						d.Range = math.min(d.Range, GARAGE_LIGHT_MAX_RANGE)
					end
				end
			end
		end
	end
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
	{ name = "Hedge", weight = 1.5, scale = { 1, 1 } },
	{ name = "FenceSection", weight = 0.8, scale = { 1, 1 } },
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
		base.Material = Enum.Material.SmoothPlastic
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

function WorldService.start()
	ensureGround()
	ensurePlots()
	ensurePaths()
	ensureUpgradeModels()
	ensureStartPark()
	ensureLandscape()
	ensureOuterLandscape()
	dimImportedLights()
	untouchUpgradeModels()
end

return WorldService
