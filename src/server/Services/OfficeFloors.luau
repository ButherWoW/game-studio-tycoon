--!strict
-- Этажи офиса (решение владельца): после гаража студия — одно трёхэтажное здание на участке.
-- Оболочки этажей ставит PlotService сразу после покупки office; здесь — то, что строится кодом
-- поверх любой модели оболочки: лифт на каждом открытом этаже, стекло в проёме верхних этажей
-- и «закрытый» этаж (тёмная обёртка со всех сторон и табличка 🔒 с ценой и условиями).
-- Всё лежит в моделях OfficeFloorN на участке: PlotService.rebuild сносит их вместе с остальным.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StudioLayout = require(ReplicatedStorage.Shared.StudioLayout)

local OfficeFloors = {}

-- Деталей мало (12 участков): лифт — 2, стекло — 1, закрытый этаж — 5
local PAD_SIZE = Vector3.new(6, 0.1, 6)
local PANEL_SIZE = Vector3.new(1, 7, 3)
local PAD_COLOR = Color3.fromRGB(95, 100, 115)
local PANEL_COLOR = Color3.fromRGB(55, 60, 75)
local GLASS_SIZE = Vector3.new(24, 9, 0.4) -- проём передней стены оболочки (ModelFactory.shell)
local WRAP_COLOR = Color3.fromRGB(45, 50, 65)
local WRAP_THICKNESS = 0.3
local PLOT_HALF = 30 -- участок 60×60
-- Перекрытие между этажами: пол этажей Астры — лист 0.02 stud, сквозь него снизу была видна мебель
-- этажа выше, а между верхом стен (13) и полом следующего (14) оставалась щель (тест владельца)
local SLAB_THICKNESS = 0.98
local SLAB_COLOR = Color3.fromRGB(235, 236, 240) -- потолок снизу светлый
local PROMPT_DISTANCE = 8
-- Клавиши подсказок по номеру целевого этажа: подсказки видны все сразу
local PROMPT_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }
local PROMPT_PAD_KEYS = { Enum.KeyCode.DPadDown, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadUp }

export type LiftHandler = (player: Player, prompt: ProximityPrompt, floor: number) -> ()

local function makePart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- Точка на участке: x/z от центра, y — над полом участка
local function at(plot: BasePart, x: number, y: number, z: number): CFrame
	return plot.CFrame * CFrame.new(x, plot.Size.Y / 2 + y, z)
end

-- Куда ставить персонажа, приехавшего на этаж (HumanoidRootPart стоящего — 3.5 над полом)
function OfficeFloors.arrival(plot: BasePart, floor: number): CFrame
	local e = StudioLayout.ELEVATOR
	return at(plot, e.X + 1, StudioLayout.floorY(floor) + 3.5, e.Z)
end

local function label(parent: Instance, text: string): TextLabel
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextStrokeTransparency = 0.4
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.TextScaled = true
	textLabel.Text = text
	textLabel.Parent = parent
	return textLabel
end

-- Лифт этажа: площадка 6×6 и пульт с подсказками на другие этажи (закрытый — 🔒, не едет)
local function buildElevator(
	model: Model,
	plot: BasePart,
	floor: number,
	unlocked: number,
	onLift: LiftHandler
)
	local e = StudioLayout.ELEVATOR
	local y = StudioLayout.floorY(floor)
	local pad = makePart(model, "LiftPad", PAD_SIZE, at(plot, e.X, y + 0.16, e.Z), PAD_COLOR)
	pad.Material = Enum.Material.DiamondPlate
	pad.CanCollide = false
	local panel = makePart(
		model,
		"LiftPanel",
		PANEL_SIZE,
		at(plot, e.X - PAD_SIZE.X / 2 + PANEL_SIZE.X / 2, y + PANEL_SIZE.Y / 2, e.Z),
		PANEL_COLOR
	)
	panel.Material = Enum.Material.Metal

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(160, 40)
	billboard.StudsOffset = Vector3.new(0, PANEL_SIZE.Y / 2 + 1, 0)
	billboard.MaxDistance = 40
	billboard.Parent = panel
	local sign = label(billboard, "🛗 " .. StudioLayout.floorName("ru", floor))
	sign:SetAttribute("FloorLift", floor)

	-- Открытые этажи и первый закрытый над ними
	for target = 1, math.min(unlocked + 1, StudioLayout.FLOOR_COUNT) do
		if target ~= floor then
			local arrow = if target > unlocked then "🔒" elseif target > floor then "⬆" else "⬇"
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "Lift" .. target
			prompt.ActionText = arrow .. " " .. StudioLayout.floorName("ru", target)
			prompt.ObjectText = "🛗"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = PROMPT_DISTANCE
			prompt.RequiresLineOfSight = false
			prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
			prompt.KeyboardKeyCode = PROMPT_KEYS[target] or Enum.KeyCode.E
			prompt.GamepadKeyCode = PROMPT_PAD_KEYS[target] or Enum.KeyCode.ButtonX
			prompt:SetAttribute("FloorTarget", target)
			prompt:SetAttribute("FloorArrow", arrow)
			prompt.Parent = panel
			prompt.Triggered:Connect(function(player: Player)
				onLift(player, prompt, target)
			end)
		end
	end
end

-- Плотное перекрытие под этажом 2 и 3: верх чуть ниже пола оболочки (без мерцания), низ — над стенами
local function buildSlab(model: Model, plot: BasePart, floor: number)
	local y = StudioLayout.floorY(floor)
	local slab = makePart(
		model,
		"FloorSlab",
		Vector3.new(PLOT_HALF * 2, SLAB_THICKNESS, PLOT_HALF * 2),
		at(plot, 0, y - 0.01 - SLAB_THICKNESS / 2, 0),
		SLAB_COLOR
	)
	slab.Material = Enum.Material.Concrete
end

-- Открытый верхний этаж: стекло в проёме передней стены, чтобы не выпасть на улицу
local function buildGlass(model: Model, plot: BasePart, floor: number)
	local y = StudioLayout.floorY(floor)
	local glass = makePart(
		model,
		"FrontGlass",
		GLASS_SIZE,
		at(plot, 0, y + 0.1 + GLASS_SIZE.Y / 2, PLOT_HALF - 0.5),
		Color3.fromRGB(170, 210, 240)
	)
	glass.Material = Enum.Material.Glass
	glass.Transparency = 0.6
end

-- Закрытый этаж: тёмная обёртка со всех сторон и сверху (внутрь не попасть) и табличка на фасаде
local function buildLock(model: Model, plot: BasePart, floor: number)
	local y = StudioLayout.floorY(floor)
	local height = StudioLayout.FLOOR_HEIGHT - 0.5
	local side = PLOT_HALF + WRAP_THICKNESS / 2
	local width = 2 * PLOT_HALF + 2 * WRAP_THICKNESS
	local center = y + height / 2
	local front = makePart(
		model,
		"LockFront",
		Vector3.new(width, height, WRAP_THICKNESS),
		at(plot, 0, center, side),
		WRAP_COLOR
	)
	makePart(
		model,
		"LockBack",
		Vector3.new(width, height, WRAP_THICKNESS),
		at(plot, 0, center, -side),
		WRAP_COLOR
	)
	makePart(
		model,
		"LockLeft",
		Vector3.new(WRAP_THICKNESS, height, 2 * PLOT_HALF),
		at(plot, -side, center, 0),
		WRAP_COLOR
	)
	makePart(
		model,
		"LockRight",
		Vector3.new(WRAP_THICKNESS, height, 2 * PLOT_HALF),
		at(plot, side, center, 0),
		WRAP_COLOR
	)
	makePart(
		model,
		"LockTop",
		Vector3.new(width, WRAP_THICKNESS, width),
		at(plot, 0, y + height - WRAP_THICKNESS / 2, 0),
		WRAP_COLOR
	)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name:sub(1, 4) == "Lock" then
			part.Transparency = 0.1
		end
	end

	-- Табличка на фасаде (+Z участка — грань Back детали)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = front
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromScale(0.45, 0.7)
	box.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
	box.BackgroundTransparency = 0.2
	box.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.08, 0)
	corner.Parent = box
	local text = label(box, StudioLayout.floorSign("ru", floor))
	text.Size = UDim2.fromScale(0.9, 0.85)
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text:SetAttribute("FloorSign", floor)
end

-- Поставить лифты, стёкла и замки этажей на участок. До офиса (гараж) — ничего
function OfficeFloors.build(plot: BasePart, studioLevel: number, onLift: LiftHandler)
	if studioLevel < 2 then
		return
	end
	local unlocked = StudioLayout.floorsUnlocked(studioLevel)
	for floor = 1, StudioLayout.FLOOR_COUNT do
		local model = Instance.new("Model")
		model.Name = "OfficeFloor" .. floor
		model:SetAttribute("Floor", floor)
		if floor > 1 then
			buildSlab(model, plot, floor)
		end
		if floor <= unlocked then
			buildElevator(model, plot, floor, unlocked, onLift)
			if floor > 1 then
				buildGlass(model, plot, floor)
			end
		else
			buildLock(model, plot, floor)
		end
		model.Parent = plot
	end
end

return OfficeFloors
