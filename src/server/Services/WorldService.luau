--!strict
-- Создаёт мир, если его нет в плейсе: пол, точку спавна, участки и модели-заглушки апгрейдов.
-- Всё, что уже построено в Studio, не трогаем — создаём только недостающее.
-- Благодаря этому плейс можно пересобирать из build.rbxl и ничего не теряется.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)

local PLOT_COUNT = 6
local PLOT_SIZE = 60
local PLOT_THICKNESS = 1
local PLOT_RING_RADIUS = 90 -- расстояние от спавна до центра участка
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
	if not workspace:FindFirstChild("Baseplate") then
		local base = makePart(
			"Baseplate",
			Vector3.new(512, 2, 512),
			CFrame.new(0, -1, 0),
			Color3.fromRGB(90, 90, 95),
			workspace
		)
		base.Locked = true
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
	local entries: { { model: string, name: string, position: Vector3? } } = {}
	for _, upgrade in Upgrades do
		table.insert(entries, { model = upgrade.model, name = upgrade.name, position = upgrade.position })
	end
	for _, stage in Stages do
		if stage.model then
			table.insert(entries, { model = stage.model, name = stage.name, position = stage.position })
		end
	end
	for index, upgrade in entries do
		if not (folder :: Instance):FindFirstChild(upgrade.model) then
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

-- Вызывать до PlotService.start()
function WorldService.start()
	ensureGround()
	ensurePlots()
	ensureUpgradeModels()
end

return WorldService
