--!strict
-- Стройка следующего этапа (V29, Config/Construction): площадка и строители на участке, таймер,
-- ускорения за Robux. Состояние (profile.construction) ведёт PlotService: он начинает стройку при
-- покупке офиса/этажа и переносит студию в finishConstruction. Здесь — то, что видно и тикает:
--   • площадка в папке ConstructionSite участка (не модель: PlotService.rebuild её не сносит):
--     леса по трём сторонам здания, забор, кран, доски и кирпичи, табличка с прогрессом, пыль;
--     модели Астры из ServerStorage.Upgrades (Construction_*), без них — из деталей;
--   • 3–4 строителя (R15, оранжевая форма, жёлтая каска): прибегают с улицы, потом ходят по
--     дорожке между лесами и забором, носят доски, «стучат молотком». Ходьба — StaffLife.walkTo
--     (тот же шаг PivotTo и общий лимит идущих NPC), руки машут на клиенте (ConstructionController) по
--     атрибуту Work — сервер не шлёт кадров анимации;
--   • раз в секунду: время вышло — PlotService.finishConstruction (и для вошедшего после офлайна).
-- Всё снаружи участка 60×60: внутри стоит гараж/офис, где игрок продолжает работать; лифт
-- (X −23..−17, Z 21..27) не задет. Спереди (+Z) площадка открыта — там вход, кнопки и тропинка.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Construction = require(ReplicatedStorage.Shared.Config.Construction)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local StudioLayout = require(ReplicatedStorage.Shared.StudioLayout)
local ConstructionRemotes = require(ReplicatedStorage.Shared.ConstructionRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StaffLife = require(script.Parent.StaffLife)

local SITE_NAME = "ConstructionSite"
-- Раскладка снаружи участка (studs от края 30): леса 0.8..3.0, дорожка строителей ~4.6, забор 6.2.
-- Боковые стороны кончаются у Z = SIDE_FRONT: ближе к фасаду соседние участки (12 на сервере)
-- почти касаются углами — дальше 3 studs за край там выходить нельзя
local SCAFFOLD_IN = 0.8
local SCAFFOLD_DEPTH = 2.2
local LANE = 4.6
local FENCE = 6.2
local SIDE_FRONT = 12
local LANE_FRONT = 13 -- конец дорожки у штабелей (Z)
local PILE_Z = 16
local SCAFFOLD_SECTION = 10.5 -- шаг стоек
local SCAFFOLD_TIER = 7 -- шаг настилов
local FENCE_HEIGHT = 3.4
local CRANE_OFFSET = 4 -- кран за углом забора
local CRANE_OVER = 12 -- мачта выше здания
local SIGN_POS = Vector2.new(13, 3.5) -- X и Z за передним краем
local SPAWN_Z = 8 -- строители прибегают с тропинки: столько studs перед участком
local SPAWN_STAGGER = 0.7
local BUILDER_SPACING = 6 -- минимум между точками работы строителей (по дорожке)
local WORK_MARGIN = 4 -- точки работы не ближе к концам дорожки
-- Сколько строителей на всём сервере идут одновременно: у StaffLife общий лимит идущих NPC (24),
-- строители занимают не больше половины — сотрудники на перерыв ходить не перестанут
local MAX_WALKING_BUILDERS = 12

local COLOR_PIPE = Color3.fromRGB(150, 155, 165)
local COLOR_DECK = Color3.fromRGB(176, 128, 74)
local COLOR_FENCE = Color3.fromRGB(255, 120, 30)
local COLOR_STRIPE = Color3.fromRGB(245, 245, 245)
local COLOR_CRANE = Color3.fromRGB(255, 196, 30)
local COLOR_DARK = Color3.fromRGB(45, 48, 58)
local COLOR_PLANK = Color3.fromRGB(196, 150, 92)
local COLOR_BRICK = Color3.fromRGB(170, 82, 60)
local COLOR_VEST = Color3.fromRGB(255, 120, 20)
local COLOR_PANTS = Color3.fromRGB(45, 60, 95)
local COLOR_HAT = Color3.fromRGB(255, 205, 30)
local SKINS = {
	Color3.fromRGB(255, 220, 180),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(198, 140, 100),
	Color3.fromRGB(141, 95, 66),
}

type Builder = {
	model: Model,
	plank: BasePart?,
	s: number, -- место на дорожке (длина вдоль U-образной дорожки)
	busyUntil: number,
	walking: boolean,
	carrying: boolean,
	ready: boolean, -- добежал до площадки
}

type Site = {
	folder: Folder,
	plot: BasePart,
	stage: number,
	builders: { Builder },
	screen: BasePart?,
}

local ConstructionService = {}
local sites: { [Player]: Site } = {}
local rng = Random.new()

local function analytics(player: Player, value: number, field: string)
	local module = script.Parent:FindFirstChild("AnalyticsService")
	if module and module:IsA("ModuleScript") then
		pcall(function()
			(require(module) :: any).logLiveOps(player, "construction", value, field)
		end)
	end
end

local function stageKey(stage: number): string
	local info = Stages[stage]
	return if info then info.id else tostring(stage)
end

-- ===== Детали =====

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Декор из модели Астры: всё закреплено, без коллизий, касаний, запросов и теней
local function quiet(model: Instance)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.CastShadow = false
		elseif item:IsA("Script") or item:IsA("LocalScript") then
			item:Destroy()
		end
	end
end

local function template(name: string): Model?
	local folder = ServerStorage:FindFirstChild("Upgrades")
	local found = folder and folder:FindFirstChild(name)
	return if found and found:IsA("Model") then found else nil
end

local function placeTemplate(source: Model, parent: Instance, cframe: CFrame): Model
	local model = source:Clone()
	quiet(model)
	model:PivotTo(cframe)
	model.Parent = parent
	return model
end

-- Точка на земле рядом с участком: x/z от центра участка, y — над землёй (низ участка)
local function ground(plot: BasePart, x: number, y: number, z: number): CFrame
	return plot.CFrame * CFrame.new(x, -plot.Size.Y / 2 + y, z)
end

-- Высота верха строящегося этажа над землёй
local function buildingTop(plot: BasePart, stage: number): number
	local floor = math.max(stage - 1, 1)
	return plot.Size.Y + StudioLayout.floorY(floor) + StudioLayout.FLOOR_HEIGHT
end

-- Сторона площадки: центр на расстоянии distance от центра участка, LookVector — к зданию,
-- локальная X — вдоль стороны. Левая и правая — от задней стены до SIDE_FRONT, задняя — во всю ширину
type Side = { cframe: CFrame, length: number }
local function sides(plot: BasePart, distance: number, rearInset: number?): { Side }
	local zMin, zMax = -distance + (rearInset or 0), SIDE_FRONT
	local sideLength = zMax - zMin
	local zMid = (zMin + zMax) / 2
	local result: { Side } = {}
	for _, spec in
		{
			{ pos = Vector3.new(-distance, 0, zMid), look = Vector3.new(1, 0, 0), length = sideLength },
			{ pos = Vector3.new(distance, 0, zMid), look = Vector3.new(-1, 0, 0), length = sideLength },
			{ pos = Vector3.new(0, 0, -distance), look = Vector3.new(0, 0, 1), length = 2 * distance },
		}
	do
		local base = ground(plot, spec.pos.X, 0, spec.pos.Z)
		table.insert(result, {
			cframe = CFrame.lookAt(base.Position, base.Position + plot.CFrame:VectorToWorldSpace(spec.look)),
			length = spec.length,
		})
	end
	return result
end

-- ===== Площадка =====

local function buildScaffold(folder: Folder, plot: BasePart, stage: number)
	local model = Instance.new("Model")
	model.Name = "Scaffold"
	local top = buildingTop(plot, stage)
	local half = plot.Size.X / 2
	local source = template("Construction_Scaffold")
	local center = half + SCAFFOLD_IN + SCAFFOLD_DEPTH / 2
	local rearInset = if source then source:GetExtentsSize().Z / 2 + 0.1 else 0
	for _, side in sides(plot, center, rearInset) do
		if source then
			-- Секции Астры: ширина и высота — по самой модели, лицевая сторона (−Z) к зданию
			local size = source:GetExtentsSize()
			local count = math.max(1, math.floor(side.length / math.max(size.X, 1) + 0.5))
			local width = side.length / count
			local tiers = math.max(1, math.ceil(top / math.max(size.Y, 1)))
			for i = 1, count do
				for tier = 0, tiers - 1 do
					local x = -side.length / 2 + (i - 0.5) * width
					placeTemplate(source, model, side.cframe * CFrame.new(x, tier * size.Y, 0))
				end
			end
		else
			-- Стойки в два ряда, настилы и перила на каждом ярусе — во всю длину стороны
			local count = math.max(1, math.floor(side.length / SCAFFOLD_SECTION + 0.5))
			for i = 0, count do
				local x = -side.length / 2 + i * side.length / count
				for _, z in { -SCAFFOLD_DEPTH / 2, SCAFFOLD_DEPTH / 2 } do
					part(
						model,
						"Pole",
						Vector3.new(0.3, top, 0.3),
						side.cframe * CFrame.new(x, top / 2, z),
						COLOR_PIPE,
						Enum.Material.Metal
					)
				end
			end
			local tier = SCAFFOLD_TIER
			while tier < top do
				part(
					model,
					"Deck",
					Vector3.new(side.length, 0.25, SCAFFOLD_DEPTH),
					side.cframe * CFrame.new(0, tier, 0),
					COLOR_DECK,
					Enum.Material.WoodPlanks
				)
				part(
					model,
					"Rail",
					Vector3.new(side.length, 0.2, 0.2),
					side.cframe * CFrame.new(0, tier + 1.6, SCAFFOLD_DEPTH / 2),
					COLOR_PIPE,
					Enum.Material.Metal
				)
				tier += SCAFFOLD_TIER
			end
		end
	end
	model.Parent = folder
end

local function buildFence(folder: Folder, plot: BasePart)
	local model = Instance.new("Model")
	model.Name = "Fence"
	local source = template("Construction_Fence")
	local rearInset = if source then source:GetExtentsSize().Z / 2 + 0.05 else 0
	for _, side in sides(plot, plot.Size.X / 2 + FENCE, rearInset) do
		if source then
			local size = source:GetExtentsSize()
			local count = math.max(1, math.floor(side.length / math.max(size.X, 1) + 0.5))
			local width = side.length / count
			for i = 1, count do
				placeTemplate(
					source,
					model,
					side.cframe * CFrame.new(-side.length / 2 + (i - 0.5) * width, 0, 0)
				)
			end
		else
			local panel = part(
				model,
				"Panel",
				Vector3.new(side.length, FENCE_HEIGHT, 0.25),
				side.cframe * CFrame.new(0, FENCE_HEIGHT / 2, 0),
				COLOR_FENCE
			)
			panel.Transparency = 0.1
			part(
				model,
				"Stripe",
				Vector3.new(side.length, 0.5, 0.3),
				side.cframe * CFrame.new(0, FENCE_HEIGHT - 0.8, 0),
				COLOR_STRIPE
			)
		end
	end
	model.Parent = folder
end

-- Кран за задним левым углом, стрела смотрит в центр участка
local function buildCrane(folder: Folder, plot: BasePart, stage: number)
	local corner = plot.Size.X / 2 + FENCE + CRANE_OFFSET
	local base = ground(plot, -corner, 0, -corner)
	local centre = ground(plot, 0, 0, 0)
	local frame = CFrame.lookAt(base.Position, Vector3.new(centre.X, base.Y, centre.Z))
	local source = template("Construction_Crane")
	if source then
		placeTemplate(source, folder, frame).Name = "Crane"
		return
	end
	local model = Instance.new("Model")
	model.Name = "Crane"
	local height = buildingTop(plot, stage) + CRANE_OVER
	local reach = corner * math.sqrt(2) - 8
	part(
		model,
		"Base",
		Vector3.new(6, 1, 6),
		frame * CFrame.new(0, 0.5, 0),
		COLOR_DARK,
		Enum.Material.Concrete
	)
	part(
		model,
		"Mast",
		Vector3.new(2.2, height, 2.2),
		frame * CFrame.new(0, height / 2, 0),
		COLOR_CRANE,
		Enum.Material.Metal
	)
	part(model, "Cab", Vector3.new(2.8, 2.6, 2.8), frame * CFrame.new(0, height - 1.3, -1.6), COLOR_DARK)
	part(
		model,
		"Jib",
		Vector3.new(1.6, 1.4, reach),
		frame * CFrame.new(0, height + 0.7, -reach / 2),
		COLOR_CRANE,
		Enum.Material.Metal
	)
	part(
		model,
		"CounterJib",
		Vector3.new(1.6, 1.4, 10),
		frame * CFrame.new(0, height + 0.7, 5),
		COLOR_CRANE,
		Enum.Material.Metal
	)
	part(model, "Counterweight", Vector3.new(3, 3, 3), frame * CFrame.new(0, height - 0.8, 9), COLOR_DARK)
	local cable = 9
	part(
		model,
		"Cable",
		Vector3.new(0.15, cable, 0.15),
		frame * CFrame.new(0, height - cable / 2, -reach + 6),
		COLOR_DARK
	)
	part(
		model,
		"Load",
		Vector3.new(4, 1.2, 1.2),
		frame * CFrame.new(0, height - cable - 0.6, -reach + 6),
		COLOR_PLANK,
		Enum.Material.WoodPlanks
	)
	model.Parent = folder
end

-- Штабель досок слева и поддоны кирпича справа — у концов дорожки строителей
local function buildPiles(folder: Folder, plot: BasePart)
	local model = Instance.new("Model")
	model.Name = "Materials"
	local x = plot.Size.X / 2 + LANE
	for i = 0, 2 do
		part(
			model,
			"Planks",
			Vector3.new(2.4, 0.4, 6),
			ground(plot, -x + (i % 2) * 0.2, 0.2 + i * 0.42, PILE_Z) * CFrame.Angles(0, math.rad(i * 4), 0),
			COLOR_PLANK,
			Enum.Material.WoodPlanks
		)
	end
	for _, dz in { -1.6, 1.6 } do
		part(model, "Pallet", Vector3.new(2.8, 0.35, 2.8), ground(plot, x, 0.18, PILE_Z + dz), COLOR_DECK)
		part(
			model,
			"Bricks",
			Vector3.new(2.4, 1.6, 2.4),
			ground(plot, x, 0.35 + 0.8, PILE_Z + dz),
			COLOR_BRICK,
			Enum.Material.Brick
		)
	end
	model.Parent = folder
end

-- Пыль у лесов: эмиттер выключен; клиент включает, если не «Меньше эффектов» (ConstructionController)
local function buildDust(folder: Folder, plot: BasePart)
	local half = plot.Size.X / 2
	for i, point in { Vector3.new(0, 0, -(half + LANE)), Vector3.new(-(half + LANE), 0, -10) } do
		local holder =
			part(folder, "Dust" .. i, Vector3.new(4, 0.2, 4), ground(plot, point.X, 0.1, point.Z), COLOR_DECK)
		holder.Transparency = 1
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "BuildDust"
		emitter.Enabled = false
		emitter.Rate = 3
		emitter.Lifetime = NumberRange.new(1.8, 2.6)
		emitter.Speed = NumberRange.new(0.8, 1.6)
		emitter.SpreadAngle = Vector2.new(60, 60)
		emitter.Color = ColorSequence.new(Color3.fromRGB(205, 190, 165))
		emitter.Size =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3) })
		emitter.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		emitter.LightInfluence = 1
		emitter.Parent = holder
	end
end

-- Табличка у входа: «🏗️ Офис», полоса прогресса и сколько осталось. Текст и полосу клиент
-- (ConstructionController) обновляет сам по атрибутам BuildStage / BuildStart / BuildEnd детали Screen
local function buildSign(folder: Folder, plot: BasePart, stage: number): BasePart?
	local pos = ground(plot, SIGN_POS.X, 0, plot.Size.Z / 2 + SIGN_POS.Y) * CFrame.Angles(0, math.pi, 0)
	local screen: BasePart? = nil
	local source = template("Construction_Sign")
	if source then
		local model = placeTemplate(source, folder, pos)
		model.Name = "Sign"
		local found = model:FindFirstChild("Screen", true)
		if found and found:IsA("BasePart") then
			screen = found
		end
	end
	if not screen then
		local model = Instance.new("Model")
		model.Name = "Sign"
		for _, x in { -3, 3 } do
			part(
				model,
				"Post",
				Vector3.new(0.35, 5.4, 0.35),
				pos * CFrame.new(x, 2.7, 0.2),
				COLOR_PIPE,
				Enum.Material.Metal
			)
		end
		screen = part(model, "Screen", Vector3.new(7.4, 4.2, 0.3), pos * CFrame.new(0, 3.6, 0), COLOR_DARK)
		model.Parent = folder
	end
	local board = screen :: BasePart
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BuildSign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Parent = board
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.05, 0.06)
	title.Size = UDim2.fromScale(0.9, 0.36)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = COLOR_HAT
	title.Text = "🏗️ " .. Texts.format("ru", "build_sign_title", { stage = Stages[stage].name })
	title.Parent = gui
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromScale(0.08, 0.5)
	bar.Size = UDim2.fromScale(0.84, 0.16)
	bar.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(61, 220, 132)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "Time"
	timeLabel.BackgroundTransparency = 1
	timeLabel.Position = UDim2.fromScale(0.05, 0.7)
	timeLabel.Size = UDim2.fromScale(0.9, 0.24)
	timeLabel.Font = Enum.Font.GothamBold
	timeLabel.TextScaled = true
	timeLabel.TextColor3 = Color3.new(1, 1, 1)
	timeLabel.Text = ""
	timeLabel.Parent = gui
	return board
end

-- ===== Строители =====

-- Дорожка строителей — буква П вокруг здания: от штабеля досок (левый передний конец) вдоль левой
-- стороны, задней и правой до кирпичей. s — длина вдоль дорожки
local function laneCorners(plot: BasePart): { Vector3 }
	local d = plot.Size.X / 2 + LANE
	local y = -plot.Size.Y / 2
	return {
		Vector3.new(-d, y, LANE_FRONT),
		Vector3.new(-d, y, -d),
		Vector3.new(d, y, -d),
		Vector3.new(d, y, LANE_FRONT),
	}
end

local function laneLength(plot: BasePart): number
	local corners = laneCorners(plot)
	local total = 0
	for i = 2, #corners do
		total += (corners[i] - corners[i - 1]).Magnitude
	end
	return total
end

-- Точка дорожки и куда смотреть, работая (к зданию)
local function lanePoint(plot: BasePart, s: number): (Vector3, Vector3)
	local corners = laneCorners(plot)
	local left = math.clamp(s, 0, laneLength(plot))
	for i = 2, #corners do
		local a, b = corners[i - 1], corners[i]
		local length = (b - a).Magnitude
		if left <= length or i == #corners then
			local point = a + (b - a).Unit * math.min(left, length)
			-- Лицом к стене: по нормали своей стороны, а не в центр участка
			local face = if i == 3 then Vector3.new(0, 0, 1) else Vector3.new(-math.sign(point.X), 0, 0)
			return point, point + face
		end
		left -= length
	end
	return corners[1], corners[1] + Vector3.new(1, 0, 0)
end

-- Путь по дорожке от sFrom до sTo (через углы)
local function lanePath(plot: BasePart, sFrom: number, sTo: number): { Vector3 }
	local corners = laneCorners(plot)
	local marks = {}
	local acc = 0
	for i = 2, #corners - 1 do
		acc += (corners[i] - corners[i - 1]).Magnitude
		marks[i] = acc
	end
	local path = {}
	if sTo >= sFrom then
		for i = 2, #corners - 1 do
			if marks[i] > sFrom and marks[i] < sTo then
				table.insert(path, corners[i])
			end
		end
	else
		for i = #corners - 1, 2, -1 do
			if marks[i] < sFrom and marks[i] > sTo then
				table.insert(path, corners[i])
			end
		end
	end
	local target = lanePoint(plot, sTo)
	table.insert(path, target)
	return path
end

local function standAt(model: Model, plot: BasePart, pos: Vector3, toward: Vector3)
	local height = tonumber(model:GetAttribute("StandHeight")) or 3
	local look = Vector3.new(toward.X, pos.Y, toward.Z) - pos
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	model:PivotTo(plot.CFrame * (CFrame.lookAt(pos, pos + look.Unit) + Vector3.new(0, height, 0)))
end

local function weldTo(target: BasePart, item: BasePart)
	item.Anchored = false
	item.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = target
	weld.Part1 = item
	weld.Parent = item
end

-- Каска, светоотражающая полоса, молоток и доска на плече (доска видна, только пока несёт)
-- custom — модель Астры BuilderNPC: жилет уже на одежде, полосу не добавляем
local function dressBuilder(model: Model, custom: boolean): BasePart?
	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso")
	local hand = model:FindFirstChild("RightHand")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local upgrades = ServerStorage:FindFirstChild("Upgrades")
	local accessory = upgrades and upgrades:FindFirstChild("BuilderHat")
	if accessory and accessory:IsA("Accessory") and humanoid then
		local clone = accessory:Clone()
		for _, item in clone:GetDescendants() do
			if item:IsA("BasePart") then
				item.CanCollide = false
				item.CanTouch = false
				item.CanQuery = false
				item.CastShadow = false
				item.Massless = true
			end
		end
		humanoid:AddAccessory(clone)
	elseif head and head:IsA("BasePart") then
		local size = head.Size
		local dome = part(
			model,
			"HardHat",
			Vector3.new(size.X * 1.15, size.Y * 0.75, size.Z * 1.15),
			head.CFrame * CFrame.new(0, size.Y * 0.38, 0),
			COLOR_HAT,
			nil,
			Enum.PartType.Ball
		)
		weldTo(head, dome)
		local brim = part(
			model,
			"HardHatBrim",
			Vector3.new(0.12, size.X * 1.35, size.X * 1.35),
			head.CFrame * CFrame.new(0, size.Y * 0.32, -0.08) * CFrame.Angles(0, 0, math.rad(90)),
			COLOR_HAT,
			nil,
			Enum.PartType.Cylinder
		)
		weldTo(head, brim)
	end
	local plank: BasePart? = nil
	if torso and torso:IsA("BasePart") then
		local size = torso.Size
		if not custom then
			local band = part(
				model,
				"VestStripe",
				Vector3.new(size.X + 0.06, 0.22, size.Z + 0.06),
				torso.CFrame * CFrame.new(0, -size.Y * 0.15, 0),
				Color3.fromRGB(230, 235, 240),
				Enum.Material.Neon
			)
			weldTo(torso, band)
		end
		local board = part(
			model,
			"CarryPlank",
			Vector3.new(0.45, 0.3, 6),
			torso.CFrame * CFrame.new(size.X / 2 + 0.1, size.Y / 2 + 0.25, -0.4),
			COLOR_PLANK,
			Enum.Material.WoodPlanks
		)
		board.Transparency = 1
		weldTo(torso, board)
		plank = board
	end
	if hand and hand:IsA("BasePart") then
		local handle = part(
			model,
			"HammerHandle",
			Vector3.new(0.18, 1.2, 0.18),
			hand.CFrame * CFrame.new(0, -0.4, -0.1),
			COLOR_DECK,
			Enum.Material.Wood
		)
		weldTo(hand, handle)
		local headPart = part(
			model,
			"HammerHead",
			Vector3.new(0.3, 0.3, 0.6),
			hand.CFrame * CFrame.new(0, -0.95, -0.2),
			COLOR_PIPE,
			Enum.Material.Metal
		)
		weldTo(hand, headPart)
	end
	return plank
end

-- R15 строителя: модель Астры BuilderNPC или HumanoidDescription (оранжевый верх, синие штаны).
-- Корень закреплён, остальное — на суставах (ConstructionController на клиенте поворачивает плечи)
local function makeBuilder(index: number): Model?
	local source = template("BuilderNPC")
	local model: Model
	if source and source:FindFirstChildOfClass("Humanoid") then
		model = source:Clone()
	else
		local description = Instance.new("HumanoidDescription")
		local skin = SKINS[rng:NextInteger(1, #SKINS)]
		description.HeadColor = skin
		description.LeftArmColor = skin
		description.RightArmColor = skin
		description.TorsoColor = COLOR_VEST
		description.LeftLegColor = COLOR_PANTS
		description.RightLegColor = COLOR_PANTS
		local ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
		if not ok or not result then
			warn("[ConstructionService] Builder build failed:", result)
			return nil
		end
		model = result :: Model
	end
	model.Name = "Builder" .. index
	-- Одежда Астры V29 (builder_shirt/pants, Images.builder): поверх цветов и пустых шаблонов модели
	local clothes = Images.builder
	if clothes and clothes.shirt > 0 then
		local shirt = model:FindFirstChildOfClass("Shirt") or Instance.new("Shirt")
		shirt.ShirtTemplate = "rbxassetid://" .. clothes.shirt
		shirt.Parent = model
	end
	if clothes and clothes.pants > 0 then
		local pants = model:FindFirstChildOfClass("Pants") or Instance.new("Pants")
		pants.PantsTemplate = "rbxassetid://" .. clothes.pants
		pants.Parent = model
	end
	for _, item in model:GetDescendants() do
		if item:IsA("Script") or item:IsA("LocalScript") then
			item:Destroy()
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = item == root
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Massless = true
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local height = 3
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		humanoid.EvaluateStateMachine = false
		local rootPart = model.PrimaryPart
		height = humanoid.HipHeight + (if rootPart then rootPart.Size.Y / 2 else 1)
	end
	model:SetAttribute("StandHeight", height)
	model:SetAttribute("Builder", true)
	model:SetAttribute("Work", "walk")
	return model
end

local function setWork(builder: Builder, work: string)
	builder.model:SetAttribute("Work", work)
end

local function setCarrying(builder: Builder, on: boolean)
	builder.carrying = on
	local plank = builder.plank
	if plank then
		plank.Transparency = if on then 0 else 1
	end
end

-- Свободная точка работы на дорожке: не ближе BUILDER_SPACING к другим строителям
local function pickWorkPoint(site: Site, self: Builder): number
	local length = laneLength(site.plot)
	local best = rng:NextNumber(WORK_MARGIN, length - WORK_MARGIN)
	for _ = 1, 6 do
		local candidate = rng:NextNumber(WORK_MARGIN, length - WORK_MARGIN)
		local free = true
		for _, other in site.builders do
			if other ~= self and math.abs(other.s - candidate) < BUILDER_SPACING then
				free = false
				break
			end
		end
		if free then
			return candidate
		end
		best = candidate
	end
	return best
end

local function hammer(builder: Builder)
	setWork(builder, "hammer")
	local range = Construction.hammerSeconds
	builder.busyUntil = os.clock() + rng:NextNumber(range[1], range[2])
end

local function walkingBuilders(): number
	local count = 0
	for _, site in sites do
		for _, builder in site.builders do
			if builder.walking then
				count += 1
			end
		end
	end
	return count
end

-- Пройти по дорожке к sTo; лимит идущих NPC исчерпан — остаёмся и работаем на месте
local function goTo(
	player: Player,
	site: Site,
	builder: Builder,
	sTo: number,
	work: string,
	onArrive: () -> ()
)
	if walkingBuilders() >= MAX_WALKING_BUILDERS then
		hammer(builder)
		return
	end
	local path = lanePath(site.plot, builder.s, sTo)
	setWork(builder, work)
	local started = StaffLife.walkTo(
		player,
		builder.model,
		site.plot,
		path,
		Construction.walkSpeed,
		function()
			builder.walking = false
			builder.s = sTo
			local point, face = lanePoint(site.plot, sTo)
			standAt(builder.model, site.plot, point, face)
			onArrive()
		end
	)
	if started then
		builder.walking = true
	else
		hammer(builder)
	end
end

-- Следующее дело строителя: отнести доску, сходить за доской или перейти к другим лесам
local function nextTask(player: Player, site: Site, builder: Builder)
	if builder.carrying then
		goTo(player, site, builder, pickWorkPoint(site, builder), "carry", function()
			setCarrying(builder, false)
			hammer(builder)
		end)
	elseif rng:NextNumber() < 0.35 then
		-- Доски — у левого конца дорожки (s = 0)
		goTo(player, site, builder, 0, "walk", function()
			local point = lanePoint(site.plot, 0)
			standAt(builder.model, site.plot, point, point + Vector3.new(0, 0, 1))
			setCarrying(builder, true)
			setWork(builder, "carry")
			builder.busyUntil = os.clock() + 1
		end)
	else
		goTo(player, site, builder, pickWorkPoint(site, builder), "walk", function()
			hammer(builder)
		end)
	end
end

-- Строители по одному (CreateHumanoidModelFromDescription уступает поток) прибегают с тропинки
local function spawnBuilders(player: Player, site: Site)
	local plot = site.plot
	local folder = Instance.new("Folder")
	folder.Name = "Builders"
	folder.Parent = site.folder
	for i = 1, Construction.builders do
		local model = makeBuilder(i)
		if sites[player] ~= site or not site.folder.Parent then
			if model then
				model:Destroy()
			end
			return
		end
		if not model then
			-- Не вышло собрать одного строителя — остальные всё равно прибегут
			continue
		end
		-- Стук молотка слышен рядом (SoundController: тег SoundEmitter, пауза 0.6–1.5 с)
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			root:SetAttribute("SoundKey", "construction_hammer")
			CollectionService:AddTag(root, "SoundEmitter")
		end
		local builder: Builder = {
			model = model,
			plank = dressBuilder(model, template("BuilderNPC") ~= nil),
			s = 0,
			busyUntil = math.huge,
			walking = false,
			carrying = false,
			ready = false,
		}
		local sideSign = if i % 2 == 0 then 1 else -1
		local half = plot.Size.X / 2
		local y = -plot.Size.Y / 2
		local start = Vector3.new(sideSign * (2 + i), y, half + SPAWN_Z)
		local target = pickWorkPoint(site, builder)
		builder.s = target
		local point, face = lanePoint(plot, target)
		-- Бегом вдоль фасада к своей стороне, потом по дорожке к точке работы
		local entry = if sideSign < 0 then 0 else laneLength(plot)
		local path = {
			Vector3.new(sideSign * (half + 1.5), y, half + 1.5),
			(laneCorners(plot))[if sideSign < 0 then 1 else 4],
		}
		for _, p in lanePath(plot, entry, target) do
			table.insert(path, p)
		end
		standAt(model, plot, start, start + Vector3.new(0, 0, -1))
		model.Parent = folder
		table.insert(site.builders, builder)
		setWork(builder, "run")
		local running = walkingBuilders() < MAX_WALKING_BUILDERS
			and StaffLife.walkTo(player, model, plot, path, Construction.runSpeed, function()
				builder.walking = false
				builder.ready = true
				standAt(model, plot, point, face)
				hammer(builder)
			end)
		if running then
			builder.walking = true
		else
			builder.ready = true
			standAt(model, plot, point, face)
			hammer(builder)
		end
		task.wait(SPAWN_STAGGER)
	end
end

-- ===== Площадка целиком =====

local function clearSite(player: Player)
	local site = sites[player]
	if not site then
		return
	end
	sites[player] = nil
	for _, builder in site.builders do
		StaffLife.stopWalking(builder.model)
	end
	site.folder:Destroy()
end

local function updateSign(
	player: Player,
	site: Site,
	construction: { stage: number, startedAt: number, endsAt: number }
)
	local screen = site.screen
	if screen then
		-- Чей участок: у своей таблички клиент показывает кнопку «Ускорить» (ConstructionController)
		screen:SetAttribute("BuildOwner", player.UserId)
		screen:SetAttribute("BuildStage", construction.stage)
		screen:SetAttribute("BuildStart", construction.startedAt)
		screen:SetAttribute("BuildEnd", construction.endsAt)
	end
end

local function buildSite(
	player: Player,
	plot: BasePart,
	construction: { stage: number, startedAt: number, endsAt: number }
)
	clearSite(player)
	local old = plot:FindFirstChild(SITE_NAME)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = SITE_NAME
	folder:SetAttribute("Stage", construction.stage)
	local site: Site = {
		folder = folder,
		plot = plot,
		stage = construction.stage,
		builders = {},
		screen = nil,
	}
	buildScaffold(folder, plot, construction.stage)
	buildFence(folder, plot)
	buildCrane(folder, plot, construction.stage)
	buildPiles(folder, plot)
	buildDust(folder, plot)
	site.screen = buildSign(folder, plot, construction.stage)
	updateSign(player, site, construction)
	folder.Parent = plot
	sites[player] = site
	task.spawn(spawnBuilders, player, site)
end

-- Привести площадку к состоянию профиля: нет стройки — снести, стройка готова — достроить,
-- идёт — поставить (или обновить табличку). Зовётся на любые изменения участка
local function sync(player: Player)
	local construction = PlotService.construction(player)
	local plot = PlotService.getPlot(player)
	if not construction or not plot then
		clearSite(player)
		return
	end
	if construction.endsAt <= os.time() then
		clearSite(player)
		PlotService.finishConstruction(player)
		return
	end
	local site = sites[player]
	if site and site.stage == construction.stage and site.plot == plot and site.folder.Parent == plot then
		updateSign(player, site, construction)
		return
	end
	buildSite(player, plot, construction)
end
ConstructionService.sync = sync

-- ===== Ускорения за Robux =====

-- Запасной доход за долю fraction (0..1) цены ускорения: Robux не пропадают, если ускорять нечего
local function fallbackIncome(
	player: Player,
	profile: DataService.Profile,
	speedup: Construction.Speedup,
	fraction: number
): number
	if fraction <= 0 then
		return 0
	end
	local shop = script.Parent:FindFirstChild("ShopService")
	if not shop or not shop:IsA("ModuleScript") then
		return 0
	end
	local service = require(shop) :: any
	local minutes = speedup.robuxPrice * Construction.fallbackMinutesPerRobux * fraction
	local amount = math.max(0, math.floor(service.incomePerMinute(player, profile) * minutes))
	if amount > 0 then
		DataService.addCash(player, amount)
		local reward = script.Parent:FindFirstChild("RewardService")
		if reward and reward:IsA("ModuleScript") then
			pcall((require(reward) :: any).noteNonEarned, player, amount)
		end
	end
	return amount
end

-- Developer Product «Ускорить стройку» (MonetizationService, после проверки квитанции).
-- Стройки уже нет (закончилась, пока шла покупка) — Robux не пропадают: доход за N минут.
-- Порог minLeftSeconds и остаток проверяются здесь, в момент выдачи (а не только в окне клиента):
-- «−N мин» срезает не больше, чем осталось, а неиспользованная доля уходит доходом
function ConstructionService.grantProduct(
	player: Player,
	profile: DataService.Profile,
	productId: number
): boolean
	local speedup = Construction.speedupByProduct(productId)
	if not speedup then
		return false
	end
	local construction = PlotService.construction(player)
	local now = os.time()
	if not construction or construction.endsAt <= now then
		local amount = fallbackIncome(player, profile, speedup, 1)
		ConstructionRemotes.BuildEvent:FireClient(player, { kind = "fallback", amount = amount })
		analytics(player, amount, speedup.id .. "_fallback")
		if construction then
			task.defer(sync, player)
		end
		return true
	end
	local left = construction.endsAt - now
	local amount = 0
	local usedSeconds = left
	if speedup.kind == "minutes" then
		local fullSeconds = (speedup.minutes or 0) * 60
		usedSeconds = math.min(fullSeconds, left)
		-- Остаток стройки ниже порога — ускорение не применяем: весь товар уходит доходом
		if speedup.minLeftSeconds and left <= speedup.minLeftSeconds then
			usedSeconds = 0
		end
		construction.endsAt = now + left - usedSeconds
		if fullSeconds > 0 and usedSeconds < fullSeconds then
			amount = fallbackIncome(player, profile, speedup, 1 - usedSeconds / fullSeconds)
		end
	else
		construction.endsAt = now
	end
	analytics(player, left, stageKey(construction.stage) .. "_" .. speedup.id)
	DataService.replicate(player)
	ConstructionRemotes.BuildEvent:FireClient(player, {
		kind = "speed",
		minutes = math.floor(usedSeconds / 60 + 0.5),
		skip = speedup.kind == "skip",
		amount = amount,
	})
	-- Квитанцию с новым временем сохраняет MonetizationService; переезд — следующим кадром
	task.defer(sync, player)
	return true
end

-- ===== Цикл =====

local function tickBuilders(player: Player, site: Site)
	local now = os.clock()
	for _, builder in site.builders do
		if builder.ready and not builder.walking and builder.busyUntil <= now and builder.model.Parent then
			nextTask(player, site, builder)
		end
	end
end

function ConstructionService.start()
	PlotService.plotChanged:Connect(function(player: Player)
		task.defer(sync, player)
	end)
	PlotService.constructionChanged:Connect(function(player: Player, kind: string, stage: number)
		analytics(player, Construction.duration(stage), stageKey(stage) .. "_" .. kind)
		if kind == "finish" then
			ConstructionRemotes.BuildEvent:FireClient(player, { kind = "done", stage = stage })
		end
		task.defer(sync, player)
	end)
	Players.PlayerRemoving:Connect(clearSite)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile and profile.construction then
					local ok, err = pcall(sync, player)
					if not ok then
						warn("[ConstructionService] sync failed:", err)
					end
				end
				local site = sites[player]
				if site then
					local ok, err = pcall(tickBuilders, player, site)
					if not ok then
						warn("[ConstructionService] builders failed:", err)
					end
				end
			end
		end
	end)
end

return ConstructionService
