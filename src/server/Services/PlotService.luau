--!strict
-- Участки и тайкун-апгрейды.
-- В Workspace нужна папка Plots с частями Plot1..PlotN (точка привязки участка),
-- в ServerStorage — папка Upgrades с моделями (имена из Config/Upgrades).
-- Если их нет в плейсе, WorldService создаёт их сам при старте сервера.
-- Кнопки-апгрейды на полу создаются из кода: наступил — купил.
-- Здесь же этапы студии (Config/Stages): studioLevel, переезд и модель этапа на участке.
-- После гаража — трёхэтажный офис: оболочки всех этажей стоят сразу, «переезд» открывает
-- следующий этаж, интерьер нижних остаётся (лифты и замки этажей — OfficeFloors).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)
local StaffRemotes = require(ReplicatedStorage.Shared.StaffRemotes)
local StartPark = require(ReplicatedStorage.Shared.Config.StartPark)
local StartRemotes = require(ReplicatedStorage.Shared.StartRemotes)
local StudioLayout = require(ReplicatedStorage.Shared.StudioLayout)
local DataService = require(script.Parent.DataService)
local OfficeFloors = require(script.Parent.OfficeFloors)

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
	-- Купили кресло — табурет у первого стола больше не нужен: место игрока теперь в кресле
	if upgrade.id == "chair" then
		local desk = plot:FindFirstChild("Desk1")
		local stool = desk and desk:FindFirstChild("PcSeat")
		if stool then
			stool:Destroy()
		end
	elseif upgrade.id == "desk1" and plot:FindFirstChild("Chair") then
		local stool = (plot:FindFirstChild("Desk1") :: Instance):FindFirstChild("PcSeat")
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

-- Начинка прошлых этапов (гаражные стеллажи, офисные стены) после переезда не нужна,
-- интерьер следующих этапов появляется только после переезда (Upgrade.stage)
local function isVisible(upgrade: Upgrades.Upgrade, profile: DataService.Profile): boolean
	return StudioLayout.isVisible(upgrade, profile.studioLevel)
end

-- Кодовая оболочка этапа → купленная модель, которая её заменяет, если импортирована из Studio
-- (стены гаража Астры #61 уже с полом и стенами: вторые стены мерцали бы)
local SUPERSEDED_BY = { Garage = "GarageWalls" }

local function supersededOnPlot(plot: BasePart, modelName: string): boolean
	local replacement = SUPERSEDED_BY[modelName]
	if not replacement or not plot:FindFirstChild(replacement) then
		return false
	end
	local folder = ServerStorage:FindFirstChild("Upgrades")
	local template = folder and folder:FindFirstChild(replacement)
	return template ~= nil and template:GetAttribute("Generated") ~= true
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
	OfficeFloors.build(plot, level, onLift)
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
	for _, upgrade in Upgrades do
		local unlocked = not upgrade.requires or profile.upgrades[upgrade.requires]
		if not profile.upgrades[upgrade.id] and unlocked and isVisible(upgrade, profile) then
			if not upgrade.move or readyToMove(profile) then
				table.insert(result, upgrade)
			end
		end
	end
	local stageMove = if readyToMove(profile) then stageMoveButton(profile) else nil
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

local tryBuy: (player: Player, upgradeId: string) -> ()
local onMoveStudio: (player: Player) -> ()

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
	label.Parent = billboard

	-- Новая кнопка появляется там, где стоит игрок: пока он не отойдёт, она «не взведена»,
	-- иначе стоя на месте покупались подряд компьютер, кресло и стены (отчёт #42)
	button:SetAttribute("Armed", false)
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
	local playerButtons = {}
	for floor, floorList in byFloor do
		for i, upgrade in floorList do
			local button = createButton(player, plot, upgrade, i, #floorList, floor)
			button.Parent = newFolder
			playerButtons[button] = upgrade
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
			if upgrade.move and not readyToMove(profile) then
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
end

onMoveStudio = function(player: Player)
	local profile = DataService.get(player)
	if not profile or not getPlot(player) then
		return
	end
	local nextStage = Stages[profile.studioLevel + 1]
	if not nextStage or not stageRequirementsMet(profile, nextStage) or not readyToMove(profile) then
		return
	end
	if DataService.trySpend(player, nextStage.cost) then
		profile.studioLevel = nextStage.level
		PlotService.rebuild(player)
		DataService.replicate(player)
	end
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
	if not interiorComplete(profile) then
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
		if nextStage.requiresUpgrade and not profile.upgrades[nextStage.requiresUpgrade] then
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
	end)
	Remotes.BuyUpgrade.OnServerEvent:Connect(onBuyUpgrade)
	StartRemotes.GoHome.OnServerEvent:Connect(onGoHome)
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
