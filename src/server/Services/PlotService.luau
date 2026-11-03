--!strict
-- Участки и тайкун-апгрейды.
-- В Workspace нужна папка Plots с частями Plot1..PlotN (точка привязки участка),
-- в ServerStorage — папка Upgrades с моделями (имена из Config/Upgrades).
-- Если их нет в плейсе, WorldService создаёт их сам при старте сервера.
-- Кнопки-апгрейды на полу создаются из кода: наступил — купил.
-- Здесь же этапы студии (Config/Stages): studioLevel, переезд и модель этапа на участке.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)
local StaffRemotes = require(ReplicatedStorage.Shared.StaffRemotes)
local DataService = require(script.Parent.DataService)

local BUTTON_SIZE = Vector3.new(5, 0.4, 5)
local BUTTON_SPACING = 7
local BUTTON_EDGE_OFFSET = 5 -- от переднего края участка
local TOUCH_COOLDOWN = 0.5
local COLOR_REFRESH = 0.5
local COLOR_AFFORDABLE = Color3.fromRGB(61, 220, 132)
local COLOR_EXPENSIVE = Color3.fromRGB(70, 72, 90)

local PlotService = {}
local owners: { [BasePart]: Player } = {}
local buttons: { [Player]: { [BasePart]: Upgrades.Upgrade } } = {}
local lastTouch: { [Player]: number } = {}

-- Участок собран заново (вход игрока, переезд): StaffService пересаживает NPC
local plotChanged = Instance.new("BindableEvent")
PlotService.plotChanged = plotChanged.Event

local function getPlot(player: Player): BasePart?
	for plot, owner in owners do
		if owner == player then
			return plot
		end
	end
	return nil
end
PlotService.getPlot = getPlot

local function placeModel(plot: BasePart, modelName: string, position: Vector3?, rotationDeg: number?)
	local folder = ServerStorage:FindFirstChild("Upgrades")
	local template = folder and folder:FindFirstChild(modelName)
	if not template or not template:IsA("Model") then
		warn("[PlotService] Missing model", modelName)
		return
	end
	local model = template:Clone()
	if position then
		-- Раскладка из Config: pivot модели — центр её основания
		local rotation = math.rad(rotationDeg or 0)
		model:PivotTo(plot.CFrame * CFrame.new(position) * CFrame.Angles(0, rotation, 0))
	else
		-- Модель уже собрана на своём месте относительно центра участка
		model:PivotTo(plot.CFrame * model:GetPivot())
	end
	model.Parent = plot
end

local function placeUpgrade(plot: BasePart, upgrade: Upgrades.Upgrade)
	placeModel(plot, upgrade.model, upgrade.position, upgrade.rotation)
end

-- Можно ли переехать на этап stage (без проверки денег и того, что это следующий этап)
local function stageRequirementsMet(profile: DataService.Profile, stage: Stages.Stage): boolean
	if stage.requiresUpgrade and not profile.upgrades[stage.requiresUpgrade] then
		return false
	end
	return profile.gamesReleased >= stage.gamesRequired
end

-- studioLevel из сохранения может быть мусором; бесплатные этапы (офис после апгрейда office)
-- наступают сами. Возвращает true, если уровень изменился.
local function normalizeStage(profile: DataService.Profile): boolean
	local old = profile.studioLevel
	local level = tonumber(old) or 1
	level = math.clamp(math.floor(level), 1, #Stages)
	while level < #Stages do
		local nextStage = Stages[level + 1]
		if nextStage.cost > 0 or not stageRequirementsMet(profile, nextStage) then
			break
		end
		level += 1
	end
	profile.studioLevel = level
	return level ~= old
end

-- Поставить всё купленное и модель текущего этапа
local function buildPlot(plot: BasePart, profile: DataService.Profile)
	for _, upgrade in Upgrades do
		if profile.upgrades[upgrade.id] then
			placeUpgrade(plot, upgrade)
		end
	end
	local stage = Stages[profile.studioLevel]
	if stage and stage.model then
		placeModel(plot, stage.model, stage.position, 0)
	end
end

-- Пересобрать участок: снести модели и поставить заново (купленное + модель этапа).
-- NPC сотрудников лежат в папке, а не моделью, — их пересаживает StaffService по plotChanged.
function PlotService.rebuild(player: Player)
	local plot = getPlot(player)
	local profile = DataService.get(player)
	if not plot or not profile then
		return
	end
	for _, child in plot:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
	buildPlot(plot, profile)
	plotChanged:Fire(player)
end

local function formatPrice(cost: number): string
	return if cost <= 0 then "Бесплатно" else Texts.money(cost)
end

local function availableUpgrades(profile: DataService.Profile): { Upgrades.Upgrade }
	local result = {}
	for _, upgrade in Upgrades do
		local unlocked = not upgrade.requires or profile.upgrades[upgrade.requires]
		if not profile.upgrades[upgrade.id] and unlocked then
			table.insert(result, upgrade)
		end
	end
	return result
end

local tryBuy: (player: Player, upgradeId: string) -> ()

local function createButton(
	player: Player,
	plot: BasePart,
	upgrade: Upgrades.Upgrade,
	index: number,
	count: number
): BasePart
	local x = (index - (count + 1) / 2) * BUTTON_SPACING
	local z = plot.Size.Z / 2 - BUTTON_EDGE_OFFSET
	local y = plot.Size.Y / 2 + BUTTON_SIZE.Y / 2

	local button = Instance.new("Part")
	button.Name = "Buy_" .. upgrade.id
	button.Size = BUTTON_SIZE
	button.Anchored = true
	button.CanCollide = false
	button.Material = Enum.Material.Neon
	button.Color = COLOR_EXPENSIVE
	button.CFrame = plot.CFrame * CFrame.new(x, y, z)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(200, 60)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 60
	billboard.Parent = button

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = upgrade.name .. "\n" .. formatPrice(upgrade.cost)
	label.Parent = billboard

	button.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character or Players:GetPlayerFromCharacter(character) ~= player then
			return
		end
		local now = os.clock()
		if (lastTouch[player] or 0) + TOUCH_COOLDOWN > now then
			return
		end
		lastTouch[player] = now
		tryBuy(player, upgrade.id)
	end)

	return button
end

-- Пересоздать кнопки: по одной на каждый доступный, но ещё не купленный апгрейд
local function refreshButtons(player: Player)
	local plot = getPlot(player)
	local profile = DataService.get(player)
	if not plot or not profile then
		return
	end

	local folder = plot:FindFirstChild("Buttons")
	if folder then
		folder:Destroy()
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "Buttons"

	local list = availableUpgrades(profile)
	local playerButtons = {}
	for i, upgrade in list do
		local button = createButton(player, plot, upgrade, i, #list)
		button.Parent = newFolder
		playerButtons[button] = upgrade
	end
	newFolder.Parent = plot
	buttons[player] = playerButtons
end

tryBuy = function(player: Player, upgradeId: string)
	local profile = DataService.get(player)
	local plot = getPlot(player)
	if not profile or not plot then
		return
	end
	for _, upgrade in Upgrades do
		if upgrade.id == upgradeId then
			if profile.upgrades[upgrade.id] then
				return
			end
			if upgrade.requires and not profile.upgrades[upgrade.requires] then
				return
			end
			if DataService.trySpend(player, upgrade.cost) then
				profile.upgrades[upgrade.id] = true
				placeUpgrade(plot, upgrade)
				if normalizeStage(profile) then
					PlotService.rebuild(player)
				end
				DataService.replicate(player)
				refreshButtons(player)
				-- Новый стол — StaffService может посадить за него сотрудника
				plotChanged:Fire(player)
			end
			return
		end
	end
end

local function assignPlot(player: Player)
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then
		warn("[PlotService] workspace.Plots not found")
		return
	end
	for _, plot in plotsFolder:GetChildren() do
		if plot:IsA("BasePart") and not owners[plot] then
			owners[plot] = player
			player:SetAttribute("PlotName", plot.Name)
			-- Восстанавливаем купленное, потом ставим кнопки
			task.spawn(function()
				local profile
				repeat
					profile = DataService.get(player)
					task.wait(0.2)
				until profile or not player.Parent
				if not profile or owners[plot] ~= player then
					return
				end
				normalizeStage(profile)
				buildPlot(plot, profile)
				DataService.replicate(player)
				refreshButtons(player)
				plotChanged:Fire(player)
			end)
			return
		end
	end
	warn("[PlotService] No free plots")
end

local function onMoveStudio(player: Player)
	local profile = DataService.get(player)
	if not profile or not getPlot(player) then
		return
	end
	local nextStage = Stages[profile.studioLevel + 1]
	if not nextStage or not stageRequirementsMet(profile, nextStage) then
		return
	end
	if DataService.trySpend(player, nextStage.cost) then
		profile.studioLevel = nextStage.level
		PlotService.rebuild(player)
		DataService.replicate(player)
	end
end

local function onBuyUpgrade(player: Player, upgradeId: any)
	if type(upgradeId) ~= "string" then
		return
	end
	tryBuy(player, upgradeId)
end

function PlotService.start()
	Players.PlayerAdded:Connect(assignPlot)
	for _, player in Players:GetPlayers() do
		assignPlot(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		buttons[player] = nil
		lastTouch[player] = nil
		local plot = getPlot(player)
		if plot then
			owners[plot] = nil
			for _, child in plot:GetChildren() do
				if child:IsA("Model") or child.Name == "Buttons" then
					child:Destroy()
				end
			end
		end
	end)
	Remotes.BuyUpgrade.OnServerEvent:Connect(onBuyUpgrade)
	StaffRemotes.MoveStudio.OnServerEvent:Connect(onMoveStudio)

	-- Один общий цикл: зелёная кнопка — денег хватает, серая — нет
	task.spawn(function()
		while true do
			task.wait(COLOR_REFRESH)
			for player, playerButtons in buttons do
				local profile = DataService.get(player)
				if profile then
					for button, upgrade in playerButtons do
						button.Color = if profile.cash >= upgrade.cost
							then COLOR_AFFORDABLE
							else COLOR_EXPENSIVE
					end
				end
			end
		end
	end)
end

return PlotService
