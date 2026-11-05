--!strict
-- «События дня» (Config/DailyEvents, роадмап 7.15): раз в час в hh:30 UTC одно хорошее событие
-- на 15 минут, раз в день «Золотой час». Расписание считается по os.time одинаково на всех серверах.
-- Клиенту — атрибуты ReplicatedStorage (DailyEventBanner рисует плашку и расписание):
--   DailyEventId / DailyEventStartsAt / DailyEventEndsAt / DailyEventAnnounce / DailyEventGenre /
--   DailyEventTopic — текущий или следующий слот; DailyEventActive — событие идёт (ставит сервер);
--   DailyGoldenStartsAt / DailyGoldenEndsAt / DailyGoldenAnnounce / DailyGoldenMultiplier /
--   DailyGoldenActive — золотой час.
-- Таблица события (жуки, инвестор, блиц-джем) — DailyEventRemotes.DailyEventBoard, тосты — DailyEventToast
-- (за 2 минуты до начала — пинг со звуком тем, кто видел окно уведомлений, NotifyService.wantsPings).
-- Эффекты — маленькими хуками в чужих сервисах (они сами спрашивают здесь, без модуля — как обычно):
--   DevelopmentService: devSpeed (кофе-раш), revenueMultiplier (золотой час), reviewBonus (критики),
--     onGameReleased (блиц-джем); MascotService.bonusFor: mascotMultiplier (парад);
--   StartParkService: pawnMultiplier, setCartridgeRush (картриджепад); StaffLife: noBreaks (пицца);
--   StaffService: talentStar (охота за талантами); Decor/FurnitureStyle: DailyEvents.cashPrice (распродажа);
--   ShopWindow (клиент): кофе — скидочная копия «Сделки дня» (кофе-раш).
-- Свои объекты в мире: жуки (workspace.DailyBugs) и NPC-инвестор у фонтана (workspace.DailyInvestor).
-- Титул победителя блиц-джема на сутки — общий временный титул blitz_champion (TitleService.grant
-- с untilAt, одна табличка над головой). Старое поле (profile :: any).dailyTitle = { key, untilAt }
-- переносится в TitleService при входе и удаляется.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local DailyEvents = require(Shared.Config.DailyEvents)
local DailyEventRemotes = require(Shared.DailyEventRemotes)
local Employees = require(Shared.Config.Employees)
local Images = require(Shared.Config.Images)
local Mascots = require(Shared.Config.Mascots)
local Mood = require(Shared.Config.Mood)
local Texts = require(Shared.Config.Texts)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local StaffAppearance = require(script.Parent.StaffAppearance)

type Entry = { name: string, score: number, revenue: number }
type BoardRow = { name: string, value: number }

local REQUEST_COOLDOWN = 1
local BUG_FOLDER = "DailyBugs"
local INVESTOR_NAME = "DailyInvestor"
local SPARKLES_NAME = "DailyParadeSparkles"
local PET_FOLDER = "Mascots" -- питомцы MascotService в Workspace

local DailyEventService = {}

local current: DailyEvents.Slot? = nil -- событие идёт (begin уже был)
local announcedIndex: number? = nil
local goldenActive = false
local goldenAnnounced = 0
local boardDirty = false
local rng = Random.new()

-- Охота на баги
local bugs: { [Model]: boolean } = {}
local catches: { [Player]: number } = {}
local lastCatch: { [Player]: number } = {}
-- Оплаченные жуки за охоту по UserId (лимит bugHunt.maxCatchesPerPlayer; перезаход не сбрасывает)
local paidByUser: { [number]: number } = {}
local limitToasted: { [number]: boolean } = {}
-- Час инвесторов: кто уже получил грант (по UserId — перезаход не помогает)
local investorGranted: { [number]: boolean } = {}
local investorCount = 0
-- Блиц-джем: лучшая заявка по UserId
local blitz: { [number]: Entry } = {}
-- Пицца-пати: кому уже подняли настроение в этом слоте
local pizzaFor: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
-- Охота за талантами: звезда игрока в этом слоте (id = nil — нанимать было некого)
local stars: { [Player]: { index: number, id: string? } } = {}

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end

-- Вызвать функцию другого сервиса; ошибка не должна ломать событие
local function call(name: string, fnName: string, ...: any): any
	local module = optional(name)
	local fn = module and module[fnName]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn("[DailyEventService] " .. name .. "." .. fnName .. " failed:", result)
		return nil
	end
	return result
end

local function log(player: Player, field: string, value: number?)
	call("AnalyticsService", "logLiveOps", player, "dailyEvent", value or 1, field)
end

local function toast(player: Player, key: string, vars: { [string]: any }?, extra: { [string]: any }?)
	local payload: { [string]: any } = { key = key, vars = vars or {} }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	DailyEventRemotes.DailyEventToast:FireClient(player, payload)
end

local function toastAll(key: string, vars: { [string]: any }?, extra: { [string]: any }?)
	for _, player in Players:GetPlayers() do
		toast(player, key, vars, extra)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isOn(id: DailyEvents.EventId): boolean
	local slot = current
	return slot ~= nil and slot.id == id
end

-- ===== Хуки для других сервисов =====

function DailyEventService.isActive(id: DailyEvents.EventId): boolean
	return isOn(id)
end

-- Скорость разработки с учётом хакатона: кофе-раш +25%, вместе не выше maxDevSpeed
-- (если хакатон уже выше лимита — остаётся как есть)
function DailyEventService.devSpeed(hackathon: number): number
	if not isOn("coffeeRush") then
		return hackathon
	end
	local cap = math.max(hackathon, DailyEvents.maxDevSpeed)
	return math.min(hackathon * DailyEvents.coffeeRush.devSpeed, cap)
end

-- Множитель дохода релиза поверх праздничного (holiday): золотой час ×2, но праздник × золотой час
-- не выше maxRevenueMultiplier; праздник уже выше лимита — 1
function DailyEventService.revenueMultiplier(holiday: number): number
	if not goldenActive or holiday <= 0 then
		return 1
	end
	local cap = math.max(holiday, DailyEvents.maxRevenueMultiplier)
	return math.min(holiday * DailyEvents.golden.revenueMultiplier, cap) / holiday
end

-- «Критики в городе»: прибавка к оценке игр жанра дня
function DailyEventService.reviewBonus(genreId: string): number
	local slot = current
	if slot and slot.id == "critics" and slot.genreId == genreId then
		return DailyEvents.critics.reviewBonus
	end
	return 0
end

function DailyEventService.mascotMultiplier(): number
	return if isOn("mascotParade") then DailyEvents.mascotParade.bonusMultiplier else 1
end

function DailyEventService.pawnMultiplier(): number
	return if isOn("cartridgeRush") then DailyEvents.cartridgeRush.pawnMultiplier else 1
end

function DailyEventService.noBreaks(): boolean
	return isOn("pizza")
end

-- «Охота за талантами»: самый сильный ещё не нанятый обычный сотрудник, доступный по этапу,
-- и его цена со скидкой. Звезда одна на событие: выбирается при первом вопросе и запоминается;
-- наняли её — скидки больше нет. nil — события нет или нанимать некого
function DailyEventService.talentStar(player: Player): (string?, number?)
	local slot = current
	if not slot or slot.id ~= "talentHunt" then
		return nil, nil
	end
	local profile = DataService.get(player)
	if not profile then
		return nil, nil
	end
	local hired = call("StaffService", "hired", profile)
	local staff = if type(hired) == "table" then hired else {}
	local chosen = stars[player]
	if chosen and chosen.index == slot.index then
		local starId = chosen.id
		local employee = if starId then Employees.get(starId) else nil
		if not starId or not employee or staff[starId] ~= nil then
			return nil, nil
		end
		local discount = math.clamp(DailyEvents.talentHunt.discount, 0, 0.9)
		return starId, math.floor(employee.cost * (1 - discount))
	end
	local best: Employees.Employee? = nil
	for _, employee in Employees.list do
		if employee.legendary or employee.stage > profile.studioLevel or staff[employee.id] ~= nil then
			continue
		end
		if
			not best
			or employee.stage > best.stage
			or (employee.stage == best.stage and employee.cost > best.cost)
			or (employee.stage == best.stage and employee.cost == best.cost and employee.id < best.id)
		then
			best = employee
		end
	end
	stars[player] = { index = slot.index, id = if best then best.id else nil }
	if not best then
		return nil, nil
	end
	local discount = math.clamp(DailyEvents.talentHunt.discount, 0, 0.9)
	return best.id, math.floor(best.cost * (1 - discount))
end

-- ===== Таблица события =====

local function topOf(source: { [any]: number }, nameOf: (any) -> string?, size: number): { BoardRow }
	local rows: { BoardRow } = {}
	for key, value in source do
		local name = nameOf(key)
		if name and value > 0 then
			table.insert(rows, { name = name, value = value })
		end
	end
	table.sort(rows, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.name < b.name
	end)
	while #rows > size do
		table.remove(rows)
	end
	return rows
end

local function boardFor(player: Player): { [string]: any }
	local slot = current
	if not slot then
		return { id = nil }
	end
	if slot.id == "bugHunt" then
		return {
			id = slot.id,
			top = topOf(catches :: any, function(p: Player)
				return if p.Parent then p.DisplayName else nil
			end, 3),
			mine = catches[player] or 0,
		}
	elseif slot.id == "investors" then
		return { id = slot.id, left = math.max(DailyEvents.investors.grants - investorCount, 0) }
	elseif slot.id == "blitzJam" then
		local scores: { [number]: number } = {}
		for userId, entry in blitz do
			scores[userId] = entry.score
		end
		local mine = blitz[player.UserId]
		return {
			id = slot.id,
			top = topOf(scores :: any, function(userId: number)
				local entry = blitz[userId]
				return if entry then entry.name else nil
			end, DailyEvents.blitzJam.boardSize),
			mine = if mine then mine.score else 0,
		}
	end
	return { id = slot.id }
end

local function pushBoard(player: Player)
	DailyEventRemotes.DailyEventBoard:FireClient(player, boardFor(player))
end

local function pushBoardAll()
	boardDirty = false
	for _, player in Players:GetPlayers() do
		pushBoard(player)
	end
end

local function onRequest(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	pushBoard(player)
end

-- ===== Мир: точки на земле =====

local function parkCenter(): Vector3
	local spawnPoint = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	return if spawnPoint then spawnPoint.Position else Vector3.zero
end

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for _, name in { BUG_FOLDER, INVESTOR_NAME, PET_FOLDER } do
		local item = workspace:FindFirstChild(name)
		if item then
			table.insert(ignore, item)
		end
	end
	params.FilterDescendantsInstances = ignore
	return params
end

-- Земля под точкой (x, z) около высоты baseY: nil — крыша, дерево или пусто
local function groundAt(x: number, z: number, baseY: number, params: RaycastParams): Vector3?
	local hit = workspace:Raycast(Vector3.new(x, baseY + 30, z), Vector3.new(0, -60, 0), params)
	if hit and hit.Normal.Y > 0.7 and math.abs(hit.Position.Y - baseY) < 6 then
		return hit.Position
	end
	return nil
end

local function parkPoint(params: RaycastParams): Vector3?
	local cfg = DailyEvents.bugHunt
	local center = parkCenter()
	for _ = 1, 20 do
		local radius = math.sqrt(rng:NextNumber(cfg.parkRadiusMin ^ 2, cfg.parkRadiusMax ^ 2))
		local angle = rng:NextNumber(0, 2 * math.pi)
		local point = groundAt(
			center.X + math.cos(angle) * radius,
			center.Z + math.sin(angle) * radius,
			center.Y,
			params
		)
		if point then
			return point
		end
	end
	return nil
end

-- Перед участком (там, где кнопки): внутри зданий жуков не видно
local function plotPoint(params: RaycastParams): Vector3?
	local plots = workspace:FindFirstChild("Plots")
	local list: { BasePart } = {}
	for _, plot in if plots then plots:GetChildren() else {} do
		if plot:IsA("BasePart") then
			table.insert(list, plot)
		end
	end
	if #list == 0 then
		return nil
	end
	local plot = list[rng:NextInteger(1, #list)]
	local x = rng:NextNumber(-0.4, 0.4) * plot.Size.X
	local z = plot.Size.Z / 2 + rng:NextNumber(2, 7)
	local world = (plot.CFrame * CFrame.new(x, plot.Size.Y / 2, z)).Position
	return groundAt(world.X, world.Z, world.Y, params) or world
end

-- Модель без скриптов: корень закреплён, остальное приварено; клики проходят (CanQuery)
local function prepareModel(model: Model, root: BasePart)
	for _, item in model:GetDescendants() do
		if item:IsA("Script") or item:IsA("LocalScript") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.CanCollide = false
			item.CanTouch = false
			item.Massless = true
			item.CastShadow = false
			if item ~= root then
				item.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = item
				weld.Parent = item
			end
		end
	end
	root.Anchored = true
	model.PrimaryPart = root
	model.WorldPivot = CFrame.new(root.Position)
end

local function part(
	model: Model,
	name: string,
	size: Vector3,
	color: Color3,
	cframe: CFrame,
	ball: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CFrame = cframe
	p.Anchored = true
	if ball then
		p.Shape = Enum.PartType.Ball
	end
	p.Parent = model
	return p
end

-- Низ модели от корня: чтобы поставить на землю, а не утопить
local function liftOf(model: Model, root: BasePart): number
	local cf, size = model:GetBoundingBox()
	return root.Position.Y - (cf.Position.Y - size.Y / 2)
end

-- ===== Охота на баги =====

local function bugPlaceholder(): (Model, BasePart)
	local model = Instance.new("Model")
	local shell = Color3.fromRGB(60, 170, 90)
	local dark = Color3.fromRGB(25, 30, 35)
	-- Шар у Roblox всегда круглый: панцирь — шар, голова — шар поменьше спереди (лицо к +Z)
	local body = part(model, "Body", Vector3.new(1.4, 1.4, 1.4), shell, CFrame.new(0, 0.7, 0), true)
	body.Material = Enum.Material.Glass
	part(model, "Head", Vector3.new(0.7, 0.7, 0.7), dark, CFrame.new(0, 0.5, 0.8), true)
	part(
		model,
		"EyeLeft",
		Vector3.new(0.22, 0.22, 0.22),
		Color3.new(1, 1, 1),
		CFrame.new(-0.18, 0.65, 1.1),
		true
	)
	part(
		model,
		"EyeRight",
		Vector3.new(0.22, 0.22, 0.22),
		Color3.new(1, 1, 1),
		CFrame.new(0.18, 0.65, 1.1),
		true
	)
	part(model, "Stripe", Vector3.new(0.08, 1.42, 1.0), dark, CFrame.new(0, 0.72, -0.1))
	return model, body
end

local function buildBug(): (Model, BasePart)
	local cfg = DailyEvents.bugHunt
	local source = ServerStorage:FindFirstChild(Mascots.folder)
	local template = source and source:FindFirstChild("Mascot_" .. cfg.mascotId)
	if template and template:IsA("Model") then
		local model = template:Clone()
		local root = model:FindFirstChild("Body", true)
		if not root or not root:IsA("BasePart") then
			root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		end
		if root and root:IsA("BasePart") then
			pcall(function()
				model:ScaleTo(model:GetScale() * cfg.modelScale)
			end)
			return model, root
		end
		model:Destroy()
	end
	return bugPlaceholder()
end

local spawnBug: (slotIndex: number) -> ()

local function onCatch(player: Player, model: Model, root: BasePart, slotIndex: number)
	local slot = current
	if not bugs[model] or not slot or slot.id ~= "bugHunt" or slot.index ~= slotIndex then
		return
	end
	local cfg = DailyEvents.bugHunt
	local now = os.clock()
	if (lastCatch[player] or 0) + cfg.catchCooldown > now then
		return
	end
	local character = rootOf(player)
	local profile = DataService.get(player)
	if not character or not profile or (character.Position - root.Position).Magnitude > cfg.catchDistance then
		return
	end
	lastCatch[player] = now
	bugs[model] = nil
	model:Destroy()
	catches[player] = (catches[player] or 0) + 1
	-- Деньги — только за первые maxCatchesPerPlayer жуков охоты, дальше — только зачёт топа
	local paid = paidByUser[player.UserId] or 0
	if paid < cfg.maxCatchesPerPlayer then
		paidByUser[player.UserId] = paid + 1
		local amount = RewardService.incomeForMinutes(player, profile, cfg.incomeMinutes)
		RewardService.grant(player, { incomeMinutes = cfg.incomeMinutes })
		toast(player, "devent_bug_caught", { money = Texts.money(amount), count = catches[player] })
	elseif not limitToasted[player.UserId] then
		limitToasted[player.UserId] = true
		toast(player, "devent_bug_limit", { count = cfg.maxCatchesPerPlayer })
	end
	call("AchievementService", "note", player, "bugsCaught", 1)
	boardDirty = true
	task.delay(cfg.respawnSeconds, spawnBug, slotIndex)
end

-- Жук ползает около места появления: короткий твин корня (остальное приварено)
local function crawl(model: Model, root: BasePart, home: Vector3)
	local cfg = DailyEvents.bugHunt
	task.spawn(function()
		while bugs[model] and model.Parent do
			local offset = Vector3.new(
				rng:NextNumber(-cfg.crawlStep, cfg.crawlStep),
				0,
				rng:NextNumber(-cfg.crawlStep, cfg.crawlStep)
			)
			local target = Vector3.new(home.X + offset.X, root.Position.Y, home.Z + offset.Z)
			local flat = target - root.Position
			if flat.Magnitude > 0.1 then
				-- Лицо к +Z (как у маскотов): lookAt смотрит -Z, разворачиваем
				local goal = CFrame.lookAt(root.Position, root.Position + flat) * CFrame.Angles(0, math.pi, 0)
					+ flat
				TweenService:Create(root, TweenInfo.new(cfg.crawlSeconds * 0.8, Enum.EasingStyle.Linear), {
					CFrame = goal,
				}):Play()
			end
			task.wait(cfg.crawlSeconds + rng:NextNumber(0, 0.5))
		end
	end)
end

spawnBug = function(slotIndex: number)
	local slot = current
	if not slot or slot.id ~= "bugHunt" or slot.index ~= slotIndex then
		return
	end
	local cfg = DailyEvents.bugHunt
	local alive = 0
	for _ in bugs do
		alive += 1
	end
	if alive >= cfg.count then
		return
	end
	local folder = workspace:FindFirstChild(BUG_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = BUG_FOLDER
		folder.Parent = workspace
	end
	local params = rayParams()
	local point = if rng:NextNumber() < cfg.plotShare then plotPoint(params) else nil
	point = point or parkPoint(params)
	if not point then
		return
	end
	local model, root = buildBug()
	model.Name = "Bug"
	prepareModel(model, root)
	local lift = liftOf(model, root)
	model:PivotTo(
		CFrame.new(point + Vector3.new(0, lift, 0)) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
	)
	local detector = Instance.new("ClickDetector")
	detector.MaxActivationDistance = 32
	detector.Parent = root
	detector.MouseClick:Connect(function(player: Player)
		onCatch(player, model, root, slotIndex)
	end)
	bugs[model] = true
	model.Parent = folder
	crawl(model, root, point)
end

local function clearBugs()
	for model in bugs do
		model:Destroy()
	end
	table.clear(bugs)
	local folder = workspace:FindFirstChild(BUG_FOLDER)
	if folder then
		folder:Destroy()
	end
end

local function finishBugHunt()
	clearBugs()
	local cfg = DailyEvents.bugHunt
	local top = {}
	for player, count in catches do
		if player.Parent and count > 0 then
			table.insert(top, { player = player, count = count })
		end
		log(player, "bugHunt_caught", count)
	end
	table.sort(top, function(a, b)
		return a.count > b.count
	end)
	for rank, row in top do
		local minutes = cfg.topBonusMinutes[rank]
		if not minutes then
			break
		end
		local profile = DataService.get(row.player)
		if profile then
			local amount = RewardService.incomeForMinutes(row.player, profile, minutes)
			RewardService.grant(row.player, { incomeMinutes = minutes })
			toast(row.player, "devent_bug_top", { rank = rank, money = Texts.money(amount) })
		end
	end
	table.clear(catches)
	table.clear(lastCatch)
	table.clear(paidByUser)
	table.clear(limitToasted)
end

-- ===== Час инвесторов =====

local function investorPlaceholder(): (Model, BasePart)
	local model = Instance.new("Model")
	local suit = Color3.fromRGB(40, 45, 70)
	local skin = Color3.fromRGB(234, 184, 146)
	local root = part(model, "Body", Vector3.new(2, 2, 1), suit, CFrame.new(0, 3, 0))
	part(model, "Legs", Vector3.new(2, 2, 1), Color3.fromRGB(30, 30, 40), CFrame.new(0, 1, 0))
	part(model, "Head", Vector3.new(1.2, 1.2, 1.2), skin, CFrame.new(0, 4.6, 0), true)
	part(model, "Tie", Vector3.new(0.3, 1.2, 0.05), Color3.fromRGB(200, 40, 50), CFrame.new(0, 3.2, 0.53))
	local case =
		part(model, "Case", Vector3.new(1.4, 1, 0.4), Color3.fromRGB(110, 70, 40), CFrame.new(1.4, 1.6, 0))
	local coins = Instance.new("Sparkles")
	coins.SparkleColor = Color3.fromRGB(255, 210, 60)
	coins.Parent = case
	return model, root
end

-- Модель инвестора: ServerStorage.DailyEvents.Investor (Config/DailyEvents) или InvestorNPC Астры
-- (V27: ServerStorage.Upgrades / ServerStorage / ServerStorage.DailyEvents)
local function investorSource(name: string, folderName: string?): Instance?
	local folders: { string } = if folderName then { folderName } else { "Upgrades", "DailyEvents", "" }
	for _, folder in folders do
		-- "" — сам ServerStorage
		local parent = if folder == "" then ServerStorage else ServerStorage:FindFirstChild(folder)
		local found = parent and parent:FindFirstChild(name)
		if found then
			return found
		end
	end
	return nil
end

-- Одежда Астры (Images.investor, шаблоны 585×559) и кейс-аксессуар InvestorCase на NPC с Humanoid.
-- Своя одежда / свой аксессуар в модели не трогаем
local function dressInvestor(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	if Images.investor.shirt > 0 and not model:FindFirstChildOfClass("Shirt") then
		local shirt = Instance.new("Shirt")
		shirt.ShirtTemplate = "rbxassetid://" .. Images.investor.shirt
		shirt.Parent = model
	end
	if Images.investor.pants > 0 and not model:FindFirstChildOfClass("Pants") then
		local pants = Instance.new("Pants")
		pants.PantsTemplate = "rbxassetid://" .. Images.investor.pants
		pants.Parent = model
	end
	local case = investorSource("InvestorCase")
	if case and case:IsA("Accessory") and not model:FindFirstChildOfClass("Accessory") then
		StaffAppearance.addAccessory(model, humanoid, case)
	end
end

-- Нет модели, но есть одежда Астры — R15-NPC в её костюме (как пристав, BailiffService)
local function investorRig(): Model?
	if Images.investor.shirt <= 0 and Images.investor.pants <= 0 then
		return nil
	end
	local description = Instance.new("HumanoidDescription")
	local skin = Color3.fromRGB(234, 184, 146)
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = skin
	description.LeftLegColor = skin
	description.RightLegColor = skin
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("Model") then
		warn("[DailyEventService] Investor NPC build failed:", result)
		return nil
	end
	return result
end

local function buildInvestor(): (Model, BasePart)
	local cfg = DailyEvents.investors
	local template = investorSource(cfg.modelName, cfg.modelFolder) or investorSource("InvestorNPC")
	local model: Model? = nil
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = investorRig()
	end
	if model then
		dressInvestor(model)
		local root = model:FindFirstChild("HumanoidRootPart", true)
			or model.PrimaryPart
			or model:FindFirstChildWhichIsA("BasePart", true)
		if root and root:IsA("BasePart") then
			return model, root
		end
		model:Destroy()
	end
	return investorPlaceholder()
end

local function removeInvestor()
	local model = workspace:FindFirstChild(INVESTOR_NAME)
	if model then
		model:Destroy()
	end
end

local function onInvestor(player: Player, root: BasePart, slotIndex: number)
	local slot = current
	if not slot or slot.id ~= "investors" or slot.index ~= slotIndex then
		return
	end
	local cfg = DailyEvents.investors
	local character = rootOf(player)
	local profile = DataService.get(player)
	if not character or not profile or (character.Position - root.Position).Magnitude > cfg.reachDistance then
		return
	end
	if investorGranted[player.UserId] then
		toast(player, "devent_investor_already")
		return
	end
	if investorCount >= cfg.grants then
		toast(player, "devent_investor_late")
		return
	end
	investorGranted[player.UserId] = true
	investorCount += 1
	local amount = RewardService.incomeForMinutes(player, profile, cfg.incomeMinutes)
	RewardService.grant(player, { incomeMinutes = cfg.incomeMinutes })
	toast(
		player,
		"devent_investor_got",
		{ money = Texts.money(amount), rank = investorCount, max = cfg.grants }
	)
	log(player, "investors_grant", investorCount)
	boardDirty = true
	if investorCount >= cfg.grants then
		-- Гранты кончились: инвестор уходит
		task.delay(2, removeInvestor)
	end
end

local function spawnInvestor(slotIndex: number)
	removeInvestor()
	local model, root = buildInvestor()
	model.Name = INVESTOR_NAME
	prepareModel(model, root)
	-- У фонтана (его ставит WorldService), иначе у спавна
	local center = parkCenter()
	local radius = 8
	local fountain = workspace:FindFirstChild("Fountain", true)
	local size: Vector3? = nil
	if fountain and fountain:IsA("Model") then
		local cf, box = fountain:GetBoundingBox()
		center, size = cf.Position, box
	elseif fountain and fountain:IsA("BasePart") then
		center, size = fountain.Position, fountain.Size
	end
	if size then
		radius = math.max(size.X, size.Z) / 2 + 3
	end
	local spot = center + Vector3.new(radius, 0, 0)
	local ground = groundAt(spot.X, spot.Z, center.Y, rayParams()) or spot
	local lift = liftOf(model, root)
	model:PivotTo(
		CFrame.lookAt(ground + Vector3.new(0, lift, 0), Vector3.new(center.X, ground.Y + lift, center.Z))
	)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Получить грант"
	prompt.ObjectText = "Инвестор"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	-- Клиент переводит по ключам (StartParkController.relabel)
	prompt:SetAttribute("ActionKey", "devent_investor_prompt")
	prompt:SetAttribute("ObjectKey", "devent_investor_name")
	prompt.Triggered:Connect(function(player: Player)
		onInvestor(player, root, slotIndex)
	end)
	prompt.Parent = root
	model.Parent = workspace
end

-- ===== Блиц-джем =====

function DailyEventService.onGameReleased(player: Player, info: any)
	local slot = current
	if not slot or slot.id ~= "blitzJam" or type(info) ~= "table" then
		return
	end
	if info.genreId ~= slot.genreId or info.topicId ~= slot.topicId then
		return
	end
	local score = tonumber(info.score) or 0
	local revenue = tonumber(info.revenue) or 0
	local best = blitz[player.UserId]
	if best and (best.score > score or (best.score == score and best.revenue >= revenue)) then
		toast(player, "devent_blitz_entry", { score = score, best = best.score })
		return
	end
	blitz[player.UserId] = { name = player.DisplayName, score = score, revenue = revenue }
	toast(player, "devent_blitz_entry", { score = score, best = score })
	boardDirty = true
end

-- Старый формат (до общих титулов): действующий титул блиц-джема → TitleService, поле удаляем
local function migrateTitle(player: Player, profile: DataService.Profile)
	local raw = (profile :: any).dailyTitle
	if raw == nil then
		return
	end
	(profile :: any).dailyTitle = nil
	local untilAt = type(raw) == "table" and tonumber(raw.untilAt)
	if untilAt and untilAt > os.time() then
		call("TitleService", "grant", player, DailyEvents.blitzJam.titleId, untilAt)
	end
end

local function finishBlitz()
	local cfg = DailyEvents.blitzJam
	-- Победитель — лучший из тех, кто ещё на сервере (оценка, при равенстве — доход)
	local winner: Player? = nil
	local winnerEntry: Entry? = nil
	for userId, entry in blitz do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			continue
		end
		local best = winnerEntry
		if
			not best
			or entry.score > best.score
			or (entry.score == best.score and entry.revenue > best.revenue)
		then
			winner, winnerEntry = player, entry
		end
	end
	table.clear(blitz)
	if not winner or not winnerEntry then
		return
	end
	local profile = DataService.get(winner)
	if not profile then
		return
	end
	RewardService.grant(winner, { trophy = cfg.trophy, incomeMinutes = cfg.winnerIncomeMinutes })
	call("TitleService", "grant", winner, cfg.titleId, os.time() + cfg.titleSeconds)
	call("AchievementService", "note", winner, "blitzWins", 1)
	-- Кубок Trophy_Blitz на полке хитов (если Dev 1 импортировал модель)
	call("HitService", "refreshShelf", winner)
	log(winner, "blitzJam_win", winnerEntry.score)
	for _, player in Players:GetPlayers() do
		if player == winner then
			toast(player, "devent_blitz_win", { score = winnerEntry.score })
		else
			toast(player, "devent_blitz_result", { name = winnerEntry.name, score = winnerEntry.score })
		end
	end
	task.spawn(DataService.save, winner)
end

-- ===== Пицца-пати и парад маскотов =====

local function applyPizza(player: Player)
	local slot = current
	if not slot or slot.id ~= "pizza" or pizzaFor[player] == slot.index then
		return
	end
	local left = slot.endsAt - os.time()
	if left <= 0 or not DataService.get(player) then
		return
	end
	pizzaFor[player] = slot.index
	-- Поправка цели на весь остаток события: настроение сразу на максимум и держится
	call("MoodService", "addTemporary", player, DailyEvents.pizza.moodKey, Mood.max, left)
end

local function petBodies(): { BasePart }
	local list: { BasePart } = {}
	local folder = workspace:FindFirstChild(PET_FOLDER)
	for _, pet in if folder then folder:GetChildren() else {} do
		if pet:IsA("Model") then
			local body = pet:FindFirstChild("Body", true) or pet.PrimaryPart
			if body and body:IsA("BasePart") then
				table.insert(list, body)
			end
		end
	end
	return list
end

-- Искры у всех питомцев (новый питомец получит их на следующем тике)
local function paradeSparkles(on: boolean)
	for _, body in petBodies() do
		local sparkles = body:FindFirstChild(SPARKLES_NAME)
		if on and not sparkles then
			local s = Instance.new("Sparkles")
			s.Name = SPARKLES_NAME
			s.SparkleColor = Color3.fromRGB(255, 220, 90)
			s.Parent = body
		elseif not on and sparkles then
			sparkles:Destroy()
		end
	end
end

local function refreshStaffAll()
	for _, player in Players:GetPlayers() do
		call("StaffService", "refreshStaff", player)
	end
end

-- ===== Начало и конец события =====

local function begin(slot: DailyEvents.Slot)
	current = slot
	ReplicatedStorage:SetAttribute("DailyEventActive", true)
	local id = slot.id
	if id == "bugHunt" then
		table.clear(catches)
		table.clear(paidByUser)
		table.clear(limitToasted)
		for _ = 1, DailyEvents.bugHunt.count do
			spawnBug(slot.index)
		end
	elseif id == "investors" then
		table.clear(investorGranted)
		investorCount = 0
		spawnInvestor(slot.index)
	elseif id == "cartridgeRush" then
		call("StartParkService", "setCartridgeRush", DailyEvents.cartridgeRush.cartridgeMultiplier)
	elseif id == "blitzJam" then
		table.clear(blitz)
	elseif id == "pizza" then
		for _, player in Players:GetPlayers() do
			applyPizza(player)
		end
	elseif id == "talentHunt" then
		refreshStaffAll()
	elseif id == "mascotParade" then
		paradeSparkles(true)
	end
	for _, player in Players:GetPlayers() do
		log(player, id .. "_start")
	end
	toastAll("devent_started", nil, { eventId = id })
	pushBoardAll()
end

local function finish(slot: DailyEvents.Slot)
	current = nil
	ReplicatedStorage:SetAttribute("DailyEventActive", false)
	local id = slot.id
	if id == "bugHunt" then
		finishBugHunt()
	elseif id == "investors" then
		removeInvestor()
	elseif id == "cartridgeRush" then
		call("StartParkService", "setCartridgeRush", 1)
	elseif id == "blitzJam" then
		finishBlitz()
	elseif id == "talentHunt" then
		refreshStaffAll()
	elseif id == "mascotParade" then
		paradeSparkles(false)
	end
	table.clear(pizzaFor)
	pushBoardAll()
end

-- За 2 минуты: пинг со звуком тем, кто видел окно уведомлений (остальным — только плашка)
local function announce(slot: DailyEvents.Slot)
	announcedIndex = slot.index
	for _, player in Players:GetPlayers() do
		if call("NotifyService", "wantsPings", player) == true then
			toast(player, "devent_ping", nil, { eventId = slot.id, ping = true })
		end
	end
end

local function setSlotAttributes(slot: DailyEvents.Slot)
	ReplicatedStorage:SetAttribute("DailyEventId", slot.id)
	ReplicatedStorage:SetAttribute("DailyEventStartsAt", slot.startsAt)
	ReplicatedStorage:SetAttribute("DailyEventEndsAt", slot.endsAt)
	ReplicatedStorage:SetAttribute("DailyEventAnnounce", slot.announceSeconds)
	ReplicatedStorage:SetAttribute("DailyEventGenre", slot.genreId)
	ReplicatedStorage:SetAttribute("DailyEventTopic", slot.topicId)
end

local function tickEvents(now: number)
	local slot = DailyEvents.slot(now)
	local running = current
	local inWindow = now >= slot.startsAt and now < slot.endsAt
	-- Окно кончилось или слот сменился (в Studio поменяли Debug) — сначала закрываем старое
	if running and (not inWindow or running.index ~= slot.index or running.id ~= slot.id) then
		finish(running)
	end
	setSlotAttributes(slot)
	if inWindow and not current then
		begin(slot)
	elseif not inWindow and now < slot.startsAt and slot.startsAt - now <= slot.announceSeconds then
		if announcedIndex ~= slot.index then
			announce(slot)
		end
	end
	if isOn("mascotParade") then
		paradeSparkles(true)
	end
	-- Жуков меньше нужного (не нашлось места, поймали быстрее респавна) — добавляем по одному
	local bugSlot = current
	if bugSlot and bugSlot.id == "bugHunt" then
		spawnBug(bugSlot.index)
	end
end

local function tickGolden(now: number)
	local window = DailyEvents.goldenWindow(now)
	ReplicatedStorage:SetAttribute("DailyGoldenStartsAt", window.startsAt)
	ReplicatedStorage:SetAttribute("DailyGoldenEndsAt", window.endsAt)
	ReplicatedStorage:SetAttribute("DailyGoldenAnnounce", window.announceSeconds)
	ReplicatedStorage:SetAttribute("DailyGoldenMultiplier", DailyEvents.golden.revenueMultiplier)
	local active = now >= window.startsAt and now < window.endsAt
	if active ~= goldenActive then
		goldenActive = active
		ReplicatedStorage:SetAttribute("DailyGoldenActive", active)
		if active then
			for _, player in Players:GetPlayers() do
				log(player, "golden_start")
			end
			toastAll("devent_golden_started", { x = DailyEvents.golden.revenueMultiplier })
		end
	end
	if not active and now < window.startsAt and window.startsAt - now <= window.announceSeconds then
		if goldenAnnounced ~= window.startsAt then
			goldenAnnounced = window.startsAt
			for _, player in Players:GetPlayers() do
				if call("NotifyService", "wantsPings", player) == true then
					toast(
						player,
						"devent_golden_ping",
						{ x = DailyEvents.golden.revenueMultiplier },
						{ ping = true }
					)
				end
			end
		end
	end
end

function DailyEventService.start()
	ReplicatedStorage:SetAttribute("DailyEventActive", false)
	ReplicatedStorage:SetAttribute("DailyGoldenActive", false)
	DailyEventRemotes.RequestDailyEvent.OnServerEvent:Connect(onRequest)
	DataService.onProfileLoaded(function(player: Player, profile: DataService.Profile)
		migrateTitle(player, profile)
		applyPizza(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		catches[player] = nil
		lastCatch[player] = nil
		pizzaFor[player] = nil
		lastRequest[player] = nil
		stars[player] = nil
	end)
	task.spawn(function()
		while true do
			local now = os.time()
			local ok, err = pcall(tickEvents, now)
			if not ok then
				warn("[DailyEventService] tick failed:", err)
			end
			local okGolden, errGolden = pcall(tickGolden, now)
			if not okGolden then
				warn("[DailyEventService] golden tick failed:", errGolden)
			end
			if boardDirty then
				pushBoardAll()
			end
			task.wait(1)
		end
	end)
end

return DailyEventService
