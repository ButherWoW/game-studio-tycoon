--!strict
-- Участки и тайкун-апгрейды.
-- В Workspace нужна папка Plots с частями Plot1..PlotN (точка привязки участка),
-- в ServerStorage — папка Upgrades с моделями (имена из Config/Upgrades).
-- Если их нет в плейсе, WorldService создаёт их сам при старте сервера.
-- Кнопки-апгрейды на полу создаются из кода: наступил — купил.
-- Здесь же этапы студии (Config/Stages): studioLevel, переезд и модель этапа на участке.
-- После гаража — трёхэтажный офис: оболочки всех этажей стоят сразу, «переезд» открывает
-- следующий этаж, интерьер нижних остаётся (лифты и замки этажей — OfficeFloors).
-- Покупка офиса или этажа начинает стройку (Config/Construction, V29): деньги списаны, этап
-- наступает, когда выйдет время (profile.construction). Площадку и строителей ставит
-- ConstructionService по сигналам plotChanged / constructionChanged; до конца стройки
-- studioLevel и upgrades — прежние, поэтому все проверки этапа видят текущую студию.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)
local Construction = require(ReplicatedStorage.Shared.Config.Construction)
local StaffRemotes = require(ReplicatedStorage.Shared.StaffRemotes)
local StartPark = require(ReplicatedStorage.Shared.Config.StartPark)
local StartRemotes = require(ReplicatedStorage.Shared.StartRemotes)
local StudioLayout = require(ReplicatedStorage.Shared.StudioLayout)
local Features = require(ReplicatedStorage.Shared.Config.Features)
local DataService = require(script.Parent.DataService)
local FeatureReleaseService = require(script.Parent.FeatureReleaseService)
local OfficeFloors = require(script.Parent.OfficeFloors)
local StyleModels = require(script.Parent.StyleModels)

local BUTTON_SIZE = Vector3.new(5, 0.4, 5)
local BUTTON_SPACING = 7
local BUTTON_EDGE_OFFSET = 5 -- от переднего края участка
local TOUCH_COOLDOWN = 0.5
-- Новая кнопка срабатывает только после того, как игрок отошёл от неё дальше этого
local ARM_DISTANCE = 4.5
-- «Стоит на кнопке»: запас по краям и высота HumanoidRootPart над кнопкой (studs)
local STAND_MARGIN = 0.5
local STAND_HEIGHT = 6
local COLOR_REFRESH = 0.5
local COLOR_AFFORDABLE = Color3.fromRGB(61, 220, 132)
local COLOR_EXPENSIVE = Color3.fromRGB(70, 72, 90)
-- Кнопка переезда крупнее и золотая, чтобы не путать с интерьером
local MOVE_BUTTON_SIZE = Vector3.new(8, 0.5, 8)
local COLOR_MOVE = Color3.fromRGB(255, 201, 60)
-- Табличка «Гараж продаётся» — кнопка Buy_garage (не апгрейд из Config, а покупка самого гаража)
local GARAGE_ID = "garage"
-- Серая кнопка на месте переезда, пока идёт стройка (PlotLabels переводит Buy_building)
local BUILDING_ID = "building"
-- Серая кнопка «🔒 Скоро» на месте переезда на этаж, который ещё не вышел (Config/Features.stages)
local SOON_PREFIX = "soon_"
-- Точка появления владельца гаража: снаружи перед воротами (передний край участка +Z), лицом внутрь
local HOME_OUTSIDE = 4 -- studs за передним краем участка
local HOME_HEIGHT = 3.5 -- над верхом участка: HumanoidRootPart стоящего персонажа
-- Кнопка 🏠: не чаще раза в HOME_COOLDOWN секунд
local HOME_COOLDOWN = 2
-- Лифт между этажами: не чаще раза в LIFT_COOLDOWN секунд, пульт не дальше LIFT_DISTANCE
local LIFT_COOLDOWN = 1
local LIFT_DISTANCE = 14
local CHARACTER_WAIT = 5

local PlotService = {}
local owners: { [BasePart]: Player } = {}
local buttons: { [Player]: { [BasePart]: Upgrades.Upgrade } } = {}
local lastTouch: { [Player]: number } = {}
local lastHome: { [Player]: number } = {}
local lastLift: { [Player]: number } = {}
-- Игроки без участка (все заняты): получат первый освободившийся
local waiting: { Player } = {}

-- Участок собран заново (вход игрока, переезд): StaffService пересаживает NPC
local plotChanged = Instance.new("BindableEvent")
PlotService.plotChanged = plotChanged.Event
-- Стройка началась / закончилась / отменена: (player, kind: "start" | "finish" | "cancel", stage)
local constructionChanged = Instance.new("BindableEvent")
PlotService.constructionChanged = constructionChanged.Event

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
	-- Стиль мебели владельца (V15): Desk1_Neon вместо Desk1, если такая модель импортирована;
	-- у оболочек этапов — отделка владельца (Office_Sakura, для Garage — GarageWalls_Sakura)
	local owner = owners[plot]
	local template = StyleModels.find(folder, modelName, if owner then DataService.get(owner) else nil)
	if not template or not template:IsA("Model") then
		warn("[PlotService] Missing model", modelName)
		return
	end
	local model = template:Clone()
	-- Имя — классическое: по нему модель ищут StaffService, VipService, BailiffService и placeUpgrade
	model.Name = modelName
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

-- Кодовая оболочка этапа → купленная модель, которая её заменяет, если импортирована из Studio
-- (стены гаража Астры #61 уже с полом и стенами: вторые стены мерцали бы)
local SUPERSEDED_BY = { Garage = "GarageWalls" }

-- Смотрим на поставленный клон, а не на классический шаблон: при отделке на участке может стоять
-- GarageWalls_<suffix> (импортирован) при заглушке GarageWalls — гараж всё равно не ставим второй.
-- Клон несёт атрибут Generated своего шаблона
local function supersededOnPlot(plot: BasePart, modelName: string): boolean
	local replacement = SUPERSEDED_BY[modelName]
	local placed = replacement and plot:FindFirstChild(replacement)
	return placed ~= nil and placed:GetAttribute("Generated") ~= true
end

local function placeUpgrade(plot: BasePart, upgrade: Upgrades.Upgrade)
	placeModel(plot, upgrade.model, upgrade.position, upgrade.rotation)
	-- Купили импортированные стены гаража (GarageWalls или GarageWalls_<отделка>) — это полная оболочка:
	-- старый Garage убираем, как это делает buildPlot (supersededOnPlot). Заглушка Generated — только декор,
	-- базовый Garage остаётся
	local oldShell = plot:FindFirstChild("Garage")
	if oldShell and supersededOnPlot(plot, "Garage") then
		oldShell:Destroy()
	end
	-- Купили кресло (или стол при уже стоящем кресле) — табурет у первого стола больше не нужен: место
	-- игрока теперь в кресле. Шаблон Desk1 мог не загрузиться (placeModel только warn) — тогда убирать нечего
	if upgrade.id == "chair" or (upgrade.id == "desk1" and plot:FindFirstChild("Chair")) then
		local desk = plot:FindFirstChild("Desk1")
		local stool = desk and desk:FindFirstChild("PcSeat")
		if stool then
			stool:Destroy()
		end
	end
end

-- Есть ли у игрока гараж (начало «Инди в парке»). Флаг (profile :: any).ownsGarage ставится
-- один раз при первом обращении: старые сохранения (стол или выпущенные игры) — уже владельцы.
-- Rebirth флаг не сбрасывает: студия возвращается в гараж, а не в парк.
local function profileOwnsGarage(profile: DataService.Profile): boolean
	local p = profile :: any
	if p.ownsGarage == nil then
		p.ownsGarage = profile.upgrades.desk1 == true or profile.gamesReleased > 0
	end
	return p.ownsGarage == true
end

function PlotService.ownsGarage(player: Player): boolean
	local profile = DataService.get(player)
	return profile ~= nil and profileOwnsGarage(profile)
end

-- Игрок сидит за своим компьютером (Seat «PcSeat» на своём участке).
-- Пока гаража нет, компьютер — любой общий ноутбук в парке (PcSeat с атрибутом Public).
function PlotService.isAtPc(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat or seat.Name ~= "PcSeat" then
		return false
	end
	if seat:GetAttribute("Public") == true then
		return not PlotService.ownsGarage(player)
	end
	local plot = getPlot(player)
	return plot ~= nil and seat:IsDescendantOf(plot)
end

-- Можно ли переехать на этап stage (без проверки денег и того, что это следующий этап)
local function stageRequirementsMet(profile: DataService.Profile, stage: Stages.Stage): boolean
	-- 3-й этаж выходит обновлением по средам (Config/Features): до выхода переезда нет
	if not Features.stageReleased(stage.level) then
		return false
	end
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

-- Стройка, которая ведёт на следующий этап; другая (мусор, этап уже сменился) — не считается
local function activeConstruction(profile: DataService.Profile)
	local construction = profile.construction
	if construction and construction.stage == profile.studioLevel + 1 then
		return construction
	end
	return nil
end

function PlotService.construction(player: Player)
	local profile = DataService.get(player)
	return if profile then activeConstruction(profile) else nil
end

-- Стройка не ведёт на следующий этап (Rebirth, отладка, старое сохранение) — снимаем. true — сняли
local function dropStaleConstruction(player: Player, profile: DataService.Profile): boolean
	local construction = profile.construction
	if construction and not activeConstruction(profile) then
		profile.construction = nil
		constructionChanged:Fire(player, "cancel", construction.stage)
		return true
	end
	return false
end

-- Начинка прошлых этапов (гаражные стеллажи, офисные стены) после переезда не нужна,
-- интерьер следующих этапов появляется только после переезда (Upgrade.stage)
local function isVisible(upgrade: Upgrades.Upgrade, profile: DataService.Profile): boolean
	return StudioLayout.isVisible(upgrade, profile.studioLevel)
end

local onLift: OfficeFloors.LiftHandler

-- Поставить всё купленное и модели этапа: в гараже — гараж, в офисе — все три этажа
-- (некупленные закрыты, OfficeFloors)
local function buildPlot(plot: BasePart, profile: DataService.Profile)
	-- Участок без гаража пустой: только табличка «Гараж продаётся» (refreshButtons)
	if not profileOwnsGarage(profile) then
		return
	end
	for _, upgrade in Upgrades do
		if profile.upgrades[upgrade.id] and isVisible(upgrade, profile) then
			placeUpgrade(plot, upgrade)
		end
	end
	local level = profile.studioLevel
	for _, stage in Stages do
		local shown = if stage.level == 1 then level == 1 else level >= 2
		if shown and stage.model and not supersededOnPlot(plot, stage.model) then
			placeModel(plot, stage.model, stage.position, 0)
		end
	end
	-- Потолок этажей (низ перекрытий) — в цвете отделки владельца; классика — как раньше
	local finish = StyleModels.finish(profile)
	local ceiling: OfficeFloors.Ceiling? = if finish and finish.ceilingColor
		then { color = finish.ceilingColor, material = finish.ceilingMaterial or Enum.Material.SmoothPlastic }
		else nil
	OfficeFloors.build(plot, level, onLift, ceiling)
end

local refreshButtons: (player: Player) -> ()

-- Пересобрать участок: снести модели и поставить заново (купленное + модель этапа).
-- NPC сотрудников лежат в папке, а не моделью, — их пересаживает StaffService по plotChanged.
function PlotService.rebuild(player: Player)
	local plot = getPlot(player)
	local profile = DataService.get(player)
	if not plot or not profile then
		return
	end
	-- После Rebirth офиса больше нет: студия снова в гараже
	if not profile.upgrades.office then
		profile.studioLevel = 1
	end
	normalizeStage(profile)
	dropStaleConstruction(player, profile)
	for _, child in plot:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
	buildPlot(plot, profile)
	refreshButtons(player)
	DataService.replicate(player)
	plotChanged:Fire(player)
end

local function formatPrice(cost: number): string
	return if cost <= 0 then "Бесплатно" else Texts.money(cost)
end

-- Весь интерьер текущего этапа куплен (всё, кроме переездов и начинки прошлых этапов)
local function interiorComplete(profile: DataService.Profile): boolean
	for _, upgrade in Upgrades do
		if not upgrade.move and isVisible(upgrade, profile) and not profile.upgrades[upgrade.id] then
			return false
		end
	end
	return true
end

-- За каждым купленным столом текущего (верхнего открытого) этажа сидит сотрудник. Рассадку
-- (staff: сотрудник -> стол, "" — ждёт стол) ведёт StaffService; столы нижних этажей не считаются
local function staffFull(profile: DataService.Profile): boolean
	local desks = {}
	for _, desk in StudioLayout.visibleDesks(profile.upgrades, profile.studioLevel) do
		if StudioLayout.deskStage(desk) == profile.studioLevel then
			table.insert(desks, desk)
		end
	end
	if #desks == 0 then
		return false
	end
	local staff = (profile :: any).staff
	local seated: { [string]: boolean } = {}
	if type(staff) == "table" then
		for _, deskId in staff do
			if type(deskId) == "string" then
				seated[deskId] = true
			end
		end
	end
	for _, desk in desks do
		if not seated[desk.id] then
			return false
		end
	end
	return true
end

local function readyToMove(profile: DataService.Profile): boolean
	return interiorComplete(profile) and staffFull(profile)
end

-- Переезд на этаж и в небоскрёб — тоже кнопкой на участке (офис — апгрейд office)
local function stageMoveButton(profile: DataService.Profile): Upgrades.Upgrade?
	local nextStage = Stages[profile.studioLevel + 1]
	if not nextStage or nextStage.cost <= 0 or not stageRequirementsMet(profile, nextStage) then
		return nil
	end
	return {
		id = "stage_" .. nextStage.id,
		name = "Переезд: " .. nextStage.name,
		cost = nextStage.cost,
		model = "",
		move = true,
	}
end

local function availableUpgrades(profile: DataService.Profile): { Upgrades.Upgrade }
	local result = {}
	-- Пока идёт стройка, кнопки переезда нет: вместо неё серая «🏗️ Строится…» (refreshButtons)
	local canMove = readyToMove(profile) and activeConstruction(profile) == nil
	for _, upgrade in Upgrades do
		local unlocked = not upgrade.requires or profile.upgrades[upgrade.requires]
		if not profile.upgrades[upgrade.id] and unlocked and isVisible(upgrade, profile) then
			if not upgrade.move or canMove then
				table.insert(result, upgrade)
			end
		end
	end
	local stageMove = if canMove then stageMoveButton(profile) else nil
	if stageMove then
		table.insert(result, stageMove)
	end
	return result
end

-- Стоит ли персонаж на кнопке (по горизонтали над ней и невысоко)
local function isStandingOn(root: BasePart, button: BasePart): boolean
	local offset = button.CFrame:PointToObjectSpace(root.Position)
	return math.abs(offset.X) <= button.Size.X / 2 + STAND_MARGIN
		and math.abs(offset.Z) <= button.Size.Z / 2 + STAND_MARGIN
		and offset.Y >= -1
		and offset.Y <= STAND_HEIGHT
end

-- Дорогие кнопки переезда (офис, этажи) покупаются только подтверждением на ProximityPrompt:
-- «наступил — купил» для них не работает (деньги на порядки больше, стройка необратима).
-- Гараж и серые кнопки (cost 0) остаются как были
local function needsConfirm(upgrade: Upgrades.Upgrade): boolean
	return upgrade.move == true and upgrade.cost > 0 and upgrade.id ~= GARAGE_ID
end

-- Сколько секунд строится этап, который открывает кнопка переезда (0 — переезд сразу)
local function moveBuildSeconds(upgrade: Upgrades.Upgrade): number
	for _, stage in Stages do
		local byStageButton = "stage_" .. stage.id == upgrade.id
		local byUpgrade = stage.requiresUpgrade == upgrade.id
		if byStageButton or byUpgrade then
			return Construction.duration(stage.level)
		end
	end
	return 0
end

local tryBuy: (player: Player, upgradeId: string) -> ()
local onMoveStudio: (player: Player) -> ()
local startConstruction: (player: Player, profile: DataService.Profile, stage: number, cost: number) -> ()

local function createButton(
	player: Player,
	plot: BasePart,
	upgrade: Upgrades.Upgrade,
	index: number,
	count: number,
	floor: number
): BasePart
	local x = (index - (count + 1) / 2) * BUTTON_SPACING
	local z = plot.Size.Z / 2 - BUTTON_EDGE_OFFSET
	-- Ряд кнопок у входа на своём этаже
	local y = plot.Size.Y / 2 + BUTTON_SIZE.Y / 2 + StudioLayout.floorY(floor)

	local button = Instance.new("Part")
	button.Name = "Buy_" .. upgrade.id
	button.Size = if upgrade.move then MOVE_BUTTON_SIZE else BUTTON_SIZE
	button.Anchored = true
	button.CanCollide = false
	button.Material = Enum.Material.Neon
	button.Color = COLOR_EXPENSIVE
	button.CFrame = plot.CFrame * CFrame.new(x, y, z)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(200, 60)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	-- Сквозь перекрытия видно только кнопки 1-го этажа (у входа), иначе надписи верхних висят в воздухе
	billboard.AlwaysOnTop = floor == 1
	billboard.MaxDistance = 60
	billboard.Parent = button

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = (if upgrade.move and upgrade.id ~= GARAGE_ID then "🏢 " else "")
		.. upgrade.name
		.. "\n"
		.. formatPrice(upgrade.cost)
	if needsConfirm(upgrade) then
		local minutes = moveBuildSeconds(upgrade) // 60
		label.Text ..= "\n" .. Texts.format("ru", "move_hint", { minutes = minutes })
	end
	label.Parent = billboard

	-- Новая кнопка появляется там, где стоит игрок: пока он не отойдёт, она «не взведена»,
	-- иначе стоя на месте покупались подряд компьютер, кресло и стены (отчёт #42)
	button:SetAttribute("Armed", false)
	if needsConfirm(upgrade) then
		-- Подтверждение: окно подсказки с ценой и сроком (тексты на языке игрока ставит PlotLabels).
		-- Оплату и все условия по-прежнему проверяет tryBuy на сервере
		local minutes = moveBuildSeconds(upgrade) // 60
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "MovePrompt"
		prompt.ActionText = Texts.format("ru", "move_prompt_action")
		prompt.ObjectText =
			Texts.format("ru", "move_prompt_object", { price = formatPrice(upgrade.cost), minutes = minutes })
		prompt.HoldDuration = Construction.confirmHoldSeconds
		prompt.MaxActivationDistance = Construction.confirmDistance
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt:SetAttribute("MoveCost", upgrade.cost)
		prompt:SetAttribute("MoveMinutes", minutes)
		prompt.Parent = button
		prompt.Triggered:Connect(function(who: Player)
			if who == player then
				tryBuy(player, upgrade.id)
			end
		end)
		return button
	end
	button.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character or Players:GetPlayerFromCharacter(character) ~= player then
			return
		end
		if button:GetAttribute("Armed") ~= true then
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
refreshButtons = function(player: Player)
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

	-- Без гаража на участке одна кнопка — покупка гаража: крупная, золотая, у самого входа
	local list = if profileOwnsGarage(profile)
		then availableUpgrades(profile)
		else {
			{
				id = GARAGE_ID,
				name = "🏠 Гараж продаётся",
				cost = StartPark.garagePrice,
				model = "",
				move = true,
			} :: Upgrades.Upgrade,
		}
	-- Кнопки интерьера — на этаже предмета, кнопка открытия следующего этажа — на верхнем открытом
	local topFloor = StudioLayout.floorsUnlocked(profile.studioLevel)
	local byFloor: { [number]: { Upgrades.Upgrade } } = {}
	for _, upgrade in list do
		local floor = if upgrade.id:sub(1, 6) == "stage_"
			then topFloor
			else math.min(StudioLayout.upgradeFloor(upgrade), topFloor)
		byFloor[floor] = byFloor[floor] or {}
		table.insert(byFloor[floor], upgrade)
	end
	-- Идёт стройка: на месте кнопки переезда — серая «🏗️ Строится…». В playerButtons её нет:
	-- общий цикл её не перекрашивает и не «покупает» (Buy_building не апгрейд — tryBuy её пропустит)
	local building: Upgrades.Upgrade? = nil
	if activeConstruction(profile) then
		local placeholder = {
			id = BUILDING_ID,
			name = "🏗️ Строится…",
			cost = 0,
			model = "",
			move = true,
		} :: Upgrades.Upgrade
		building = placeholder
		byFloor[topFloor] = byFloor[topFloor] or {}
		table.insert(byFloor[topFloor], placeholder)
	end
	-- Интерьер и команда готовы, а следующий этаж ещё не вышел: серая «🔒 Скоро» (подпись и
	-- дни — PlotLabels на языке игрока). Тоже не апгрейд: tryBuy её пропустит
	local nextStage = Stages[profile.studioLevel + 1]
	if
		not building
		and profileOwnsGarage(profile)
		and nextStage
		and nextStage.cost > 0
		and not Features.stageReleased(nextStage.level)
		and readyToMove(profile)
	then
		local soon = {
			id = SOON_PREFIX .. nextStage.id,
			name = "🔒 " .. nextStage.name .. ": скоро",
			cost = 0,
			model = "",
			move = true,
		} :: Upgrades.Upgrade
		building = soon
		byFloor[topFloor] = byFloor[topFloor] or {}
		table.insert(byFloor[topFloor], soon)
	end
	-- Для табличек этажей (PlotLabels): какой этап сейчас строится (0 — никакой)
	local constructionNow = activeConstruction(profile)
	plot:SetAttribute("BuildingStage", if constructionNow then constructionNow.stage else 0)
	local playerButtons = {}
	for floor, floorList in byFloor do
		for i, upgrade in floorList do
			local button = createButton(player, plot, upgrade, i, #floorList, floor)
			button.Parent = newFolder
			if upgrade == building then
				button.Color = COLOR_EXPENSIVE
				local gui = button:FindFirstChildWhichIsA("BillboardGui")
				local label = gui and gui:FindFirstChildWhichIsA("TextLabel")
				if label then
					label.Text = upgrade.name
				end
			else
				playerButtons[button] = upgrade
			end
		end
	end
	newFolder.Parent = plot
	buttons[player] = playerButtons
end

-- Купить гараж: помещение этапа 1 и бесплатный стол сразу
local function buyGarage(player: Player)
	local profile = DataService.get(player)
	if not profile or not getPlot(player) or profileOwnsGarage(profile) then
		return
	end
	if not DataService.trySpend(player, StartPark.garagePrice) then
		return
	end
	(profile :: any).ownsGarage = true
	profile.upgrades.desk1 = true
	player:SetAttribute("OwnsGarage", true)
	PlotService.rebuild(player)
	StartRemotes.GarageBought:FireClient(player)
	-- Крупная покупка — сохраняем сразу, не ждём автосейва
	task.spawn(DataService.save, player)
end

tryBuy = function(player: Player, upgradeId: string)
	if upgradeId == GARAGE_ID then
		buyGarage(player)
		return
	end
	-- Без гаража апгрейдов нет (кнопок тоже, но BuyUpgrade может прийти с клиента)
	if not PlotService.ownsGarage(player) then
		return
	end
	-- Кнопка переезда на этаж или в небоскрёб
	if upgradeId:sub(1, 6) == "stage_" then
		onMoveStudio(player)
		return
	end
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
			-- Интерьер другого этапа (BuyUpgrade может прийти с клиента в обход кнопок)
			if not isVisible(upgrade, profile) then
				return
			end
			if upgrade.move and (not readyToMove(profile) or activeConstruction(profile)) then
				return
			end
			-- Переезд в офис — через стройку (Config/Construction): апгрейд office появится в конце
			local nextStage = Stages[profile.studioLevel + 1]
			if
				upgrade.move
				and nextStage
				and nextStage.requiresUpgrade == upgrade.id
				and Construction.duration(nextStage.level) > 0
			then
				if DataService.trySpend(player, upgrade.cost) then
					startConstruction(player, profile, nextStage.level, upgrade.cost)
				end
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

-- Во время кражи хита домой не переносим: жертва мгновенно вставала у ворот на пути вора
-- (ловила его без погони) — и кнопкой 🏠, и через Reset; вор телепортом сбивал проверку скорости.
-- HitService требует PlotService, поэтому берём его лениво, как другие сервисы
local function inChase(player: Player): boolean
	local hits = script.Parent:FindFirstChild("HitService")
	if hits and hits:IsA("ModuleScript") then
		local ok, busy = pcall((require(hits) :: any).inChase, player)
		return ok and busy == true
	end
	return false
end

-- Поставить персонажа в точку cframe (мировые координаты)
local function teleport(player: Player, cframe: CFrame)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	-- Сидящего сначала поднимаем: иначе SeatWeld тянет персонажа обратно к стулу
	local seat = humanoid.SeatPart
	if seat then
		humanoid.Sit = false
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	character:PivotTo(cframe)
end

-- Перенести персонажа к воротам своего гаража (появление, Rebirth, кнопка 🏠) — 1-й этаж
local function sendHome(player: Player)
	if inChase(player) then
		return
	end
	local plot = getPlot(player)
	if not plot then
		return
	end
	-- CFrame участка смотрит на −Z (внутрь), поэтому персонаж сразу стоит лицом к воротам
	local offset = CFrame.new(0, plot.Size.Y / 2 + HOME_HEIGHT, plot.Size.Z / 2 + HOME_OUTSIDE)
	teleport(player, plot.CFrame * offset)
end

-- Лифт: только свой участок, только открытый этаж, только стоя у пульта
onLift = function(player: Player, prompt: ProximityPrompt, floor: number)
	local plot = getPlot(player)
	local profile = DataService.get(player)
	if not plot or not profile or not prompt:IsDescendantOf(plot) or inChase(player) then
		return
	end
	if floor < 1 or floor > StudioLayout.floorsUnlocked(profile.studioLevel) or profile.studioLevel < 2 then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local panel = prompt.Parent
	if not root or not panel or not panel:IsA("BasePart") then
		return
	end
	if (root.Position - panel.Position).Magnitude > LIFT_DISTANCE then
		return
	end
	local now = os.clock()
	if (lastLift[player] or 0) + LIFT_COOLDOWN > now then
		return
	end
	lastLift[player] = now
	teleport(player, OfficeFloors.arrival(plot, floor))
end

-- Новый персонаж владельца гаража появляется у своего гаража, а не в парке
local function onCharacterAdded(player: Player, character: Model)
	if not character:WaitForChild("HumanoidRootPart", CHARACTER_WAIT) then
		return
	end
	-- Ждём кадр: SpawnLocation ставит персонажа на себя уже после CharacterAdded
	task.wait()
	if player.Character == character and PlotService.ownsGarage(player) then
		sendHome(player)
	end
end

local function onGoHome(player: Player)
	local now = os.clock()
	if (lastHome[player] or 0) + HOME_COOLDOWN > now then
		return
	end
	lastHome[player] = now
	-- Без гаража тоже ведём к своему участку: новичок находит табличку «Гараж продаётся» (отчёт #3, P1-1)
	sendHome(player)
end

-- Очередь за участком видна клиенту: атрибут PlotWaiting = место в очереди (nil — не ждёт)
local function refreshWaiting()
	for index, waiter in waiting do
		waiter:SetAttribute("PlotWaiting", index)
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
			player:SetAttribute("PlotWaiting", nil)
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
				dropStaleConstruction(player, profile)
				player:SetAttribute("OwnsGarage", profileOwnsGarage(profile))
				buildPlot(plot, profile)
				DataService.replicate(player)
				refreshButtons(player)
				plotChanged:Fire(player)
				-- Персонаж появился раньше, чем загрузился профиль: переносим к гаражу сейчас
				if profileOwnsGarage(profile) then
					sendHome(player)
				end
			end)
			return
		end
	end
	-- Участков меньше, чем мест на сервере (WorldService): ждём, пока кто-нибудь выйдет
	warn("[PlotService] No free plots, player waits:", player.Name)
	if not table.find(waiting, player) then
		table.insert(waiting, player)
	end
	refreshWaiting()
end

onMoveStudio = function(player: Player)
	local profile = DataService.get(player)
	if not profile or not getPlot(player) or activeConstruction(profile) then
		return
	end
	local nextStage = Stages[profile.studioLevel + 1]
	if not nextStage or not stageRequirementsMet(profile, nextStage) or not readyToMove(profile) then
		return
	end
	-- Офис (cost 0) покупается апгрейдом office, а не здесь: иначе переезд бесплатно
	if nextStage.cost <= 0 then
		return
	end
	if DataService.trySpend(player, nextStage.cost) then
		if Construction.duration(nextStage.level) > 0 then
			startConstruction(player, profile, nextStage.level, nextStage.cost)
			return
		end
		profile.studioLevel = nextStage.level
		PlotService.rebuild(player)
		DataService.replicate(player)
	end
end

-- Начать стройку этапа stage (деньги уже списаны)
startConstruction = function(player: Player, profile: DataService.Profile, stage: number, cost: number)
	local now = os.time()
	profile.construction = {
		stage = stage,
		startedAt = now,
		endsAt = now + Construction.duration(stage),
		cost = cost,
	}
	refreshButtons(player)
	DataService.replicate(player)
	constructionChanged:Fire(player, "start", stage)
	-- Крупная покупка — сохраняем сразу, не ждём автосейва
	task.spawn(DataService.save, player)
end

-- Стройка закончилась (время вышло или ускорение за Robux): этап наступает, участок пересобирается.
-- Офис — это апгрейд office (Stages[2].requiresUpgrade), этажи — studioLevel. true — переехали
function PlotService.finishConstruction(player: Player): boolean
	local profile = DataService.get(player)
	local construction = profile and profile.construction
	if not profile or not construction then
		return false
	end
	if dropStaleConstruction(player, profile) then
		return false
	end
	profile.construction = nil
	local stage = Stages[construction.stage]
	if stage.requiresUpgrade and stage.cost <= 0 then
		profile.upgrades[stage.requiresUpgrade] = true
	end
	profile.studioLevel = math.max(profile.studioLevel, construction.stage)
	if getPlot(player) then
		PlotService.rebuild(player)
	else
		normalizeStage(profile)
		DataService.replicate(player)
	end
	constructionChanged:Fire(player, "finish", construction.stage)
	task.spawn(DataService.save, player)
	return true
end

-- Нанят сотрудник — может появиться кнопка переезда
function PlotService.refreshButtons(player: Player)
	refreshButtons(player)
end

-- Окно «Студия» (DecorService): некупленный интерьер открытых этажей и переезд с причиной замка.
-- Покупка из окна — тот же BuyUpgrade -> tryBuy, что у кнопок на полу (те же проверки)
export type Offer = {
	id: string,
	cost: number,
	floor: number,
	move: boolean?,
	stage: number?, -- переезд на этап (кнопка stage_<id>)
	lock: string?, -- ключ текста причины; nil — можно купить
	lockVars: { [string]: any }?,
}

local function moveLock(profile: DataService.Profile): (string?, { [string]: any }?)
	if activeConstruction(profile) then
		return "build_lock_building", nil
	elseif not interiorComplete(profile) then
		return "studio_lock_interior", nil
	elseif not staffFull(profile) then
		return "studio_lock_staff", nil
	end
	return nil, nil
end

function PlotService.studioOffers(player: Player): { Offer }
	local result: { Offer } = {}
	local profile = DataService.get(player)
	if not profile or not getPlot(player) or not profileOwnsGarage(profile) then
		return result
	end
	local topFloor = StudioLayout.floorsUnlocked(profile.studioLevel)
	for _, upgrade in Upgrades do
		if profile.upgrades[upgrade.id] or not isVisible(upgrade, profile) then
			continue
		end
		local offer: Offer = {
			id = upgrade.id,
			cost = upgrade.cost,
			floor = math.min(StudioLayout.upgradeFloor(upgrade), topFloor),
			move = upgrade.move,
		}
		if upgrade.requires and not profile.upgrades[upgrade.requires] then
			offer.lock, offer.lockVars = "studio_lock_requires", { id = upgrade.requires }
		elseif upgrade.move then
			offer.lock, offer.lockVars = moveLock(profile)
		end
		table.insert(result, offer)
	end
	local nextStage = Stages[profile.studioLevel + 1]
	if nextStage and nextStage.cost > 0 then
		local offer: Offer = {
			id = "stage_" .. nextStage.id,
			cost = nextStage.cost,
			floor = topFloor,
			move = true,
			stage = nextStage.level,
		}
		if not Features.stageReleased(nextStage.level) then
			-- Этаж выходит обновлением по средам (Config/Features)
			offer.lock, offer.lockVars =
				"upd_soon", { days = Features.daysUntil(Features.stages[nextStage.level]) }
		elseif nextStage.requiresUpgrade and not profile.upgrades[nextStage.requiresUpgrade] then
			offer.lock, offer.lockVars = "studio_lock_requires", { id = nextStage.requiresUpgrade }
		elseif profile.gamesReleased < nextStage.gamesRequired then
			offer.lock, offer.lockVars =
				"studio_lock_games", { have = profile.gamesReleased, need = nextStage.gamesRequired }
		else
			offer.lock, offer.lockVars = moveLock(profile)
		end
		table.insert(result, offer)
	end
	return result
end

local function onBuyUpgrade(player: Player, upgradeId: any)
	if type(upgradeId) ~= "string" then
		return
	end
	tryBuy(player, upgradeId)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	assignPlot(player)
end

function PlotService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		buttons[player] = nil
		lastTouch[player] = nil
		lastHome[player] = nil
		lastLift[player] = nil
		local index = table.find(waiting, player)
		if index then
			table.remove(waiting, index)
		end
		local plot = getPlot(player)
		if plot then
			owners[plot] = nil
			for _, child in plot:GetChildren() do
				if child:IsA("Model") or child.Name == "Buttons" then
					child:Destroy()
				end
			end
			-- Освободившийся участок — первому из очереди
			local nextPlayer = table.remove(waiting, 1)
			if nextPlayer and nextPlayer.Parent then
				assignPlot(nextPlayer)
			end
		end
		refreshWaiting()
	end)
	Remotes.BuyUpgrade.OnServerEvent:Connect(onBuyUpgrade)
	StartRemotes.GoHome.OnServerEvent:Connect(onGoHome)
	-- Этаж вышел, пока сервер работает (Config/Features.stages): «🔒 Скоро» -> кнопка переезда
	for _, id in Features.stages do
		FeatureReleaseService.whenReleased(id, "PlotService", function()
			for player in buttons do
				if player.Parent then
					refreshButtons(player)
				end
			end
		end)
	end
	StaffRemotes.MoveStudio.OnServerEvent:Connect(onMoveStudio)

	-- Один общий цикл: зелёная кнопка — денег хватает, серая — нет
	task.spawn(function()
		while true do
			task.wait(COLOR_REFRESH)
			for player, playerButtons in buttons do
				local profile = DataService.get(player)
				if profile then
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
					for button, upgrade in playerButtons do
						-- Взводим кнопку, когда игрок отошёл от неё (или его нет рядом)
						if button:GetAttribute("Armed") ~= true then
							local offset = if root then root.Position - button.Position else nil
							if not offset or Vector3.new(offset.X, 0, offset.Z).Magnitude > ARM_DISTANCE then
								button:SetAttribute("Armed", true)
							end
						end
						local ready = if upgrade.move then COLOR_MOVE else COLOR_AFFORDABLE
						local affordable = profile.cash >= upgrade.cost
						button.Color = if affordable then ready else COLOR_EXPENSIVE
						-- Игрок уже стоит на взведённой кнопке, а деньги появились только сейчас:
						-- Touched не повторится, пока он не сойдёт, — покупаем сами (отчёт #3, P1-2)
						if
							affordable
							and not needsConfirm(upgrade)
							and root
							and button:GetAttribute("Armed") == true
							and isStandingOn(root, button)
							and (lastTouch[player] or 0) + TOUCH_COOLDOWN <= os.clock()
						then
							lastTouch[player] = os.clock()
							-- В своём потоке: ошибка или ожидание покупки не остановит общий цикл
							task.spawn(tryBuy, player, upgrade.id)
							-- Кнопки сейчас пересоздадутся — остальные этого игрока не трогаем
							break
						end
					end
				end
			end
		end
	end)
end

return PlotService
