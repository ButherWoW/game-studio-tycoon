--!strict
-- Маскоты студии (Config/Mascots): покупка, выбор, бонус и питомец в мире.
-- За $ — BuyMascot; за Robux — квитанцию принимает MonetizationService и зовёт grantProduct
-- (сохраняет MonetizationService до PurchaseGranted). За достижение и группу маскот открыт сам,
-- как только есть достижение / награда группы (ничего не хранить). Сезон и прочее — grant().
-- Бонус даёт только надетый маскот: bonus(player, kind) читают DevelopmentService (скорость,
-- доход, оценка), MoodService (часть «Маскот»), QuickEventService (окно «Отлично»).
-- В мире: модель надетого маскота ходит за владельцем (сервер, раз в Mascots.follow.tickSeconds
-- твин детали Body к точке сзади-слева, с подскоком). Сидит за ПК — маскот рядом со стулом.
-- Модель ServerStorage.Mascots.Mascot_<id>; нет — заглушка из шаров.
-- Данные: profile.mascots = { owned = { [id]: true }, equipped = id? }. Rebirth не трогает.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Mascots = require(Shared.Config.Mascots)
local ContentDrops = require(Shared.Config.ContentDrops)
local MascotRemotes = require(Shared.MascotRemotes)
local DataService = require(script.Parent.DataService)

local BUY_COOLDOWN = 0.25
local EQUIP_COOLDOWN = 1
local STATE_REQUEST_COOLDOWN = 1
local FOLDER_NAME = "Mascots" -- папка моделей в Workspace

type MascotData = { owned: { [string]: boolean }, equipped: string? }
type Pet = { model: Model, body: BasePart, offset: CFrame, id: string, hop: boolean, tween: Tween? }

local MascotService = {}

-- Для каких маскотов уже писали про отсутствие модели (раз на id)
local missingWarned: { [string]: boolean } = {}
local pets: { [Player]: Pet } = {}
local lastBuy: { [Player]: number } = {}
local lastEquip: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
local worldFolder: Folder? = nil

local function data(profile: DataService.Profile): MascotData
	local p = profile :: any
	local raw = p.mascots
	if type(raw) ~= "table" then
		raw = {}
	end
	local owned: { [string]: boolean } = {}
	if type(raw.owned) == "table" then
		for id, value in raw.owned do
			-- Неизвестные id тоже храним: предмет переименовали или временно убрали из Config —
			-- купленное за Robux не должно пропасть из сохранения. Интерфейс и обмен смотрят по Config
			if value == true and type(id) == "string" and #id <= 64 then
				owned[id] = true
			end
		end
	end
	local clean: MascotData = { owned = owned, equipped = nil }
	if type(raw.equipped) == "string" and Mascots.get(raw.equipped) then
		clean.equipped = raw.equipped
	end
	p.mascots = clean
	return clean
end

-- Открыт ли маскот: куплен/выдан или условие (достижение, группа) уже выполнено
local function ownsIn(
	profile: DataService.Profile,
	mascot: Mascots.Mascot,
	owned: { [string]: boolean }
): boolean
	if owned[mascot.id] then
		return true
	end
	local p = profile :: any
	if mascot.how == "achievement" and mascot.achievement then
		local achievements = p.achievements
		local done = type(achievements) == "table" and achievements.done
		return type(done) == "table" and done[mascot.achievement] ~= nil
	elseif mascot.how == "group" then
		return type(p.social) == "table" and p.social.groupRewarded == true
	end
	return false
end

local function ownedSet(profile: DataService.Profile): { [string]: boolean }
	local d = data(profile)
	local result: { [string]: boolean } = {}
	for _, mascot in Mascots.list do
		if ownsIn(profile, mascot, d.owned) then
			result[mascot.id] = true
		end
	end
	return result
end

function MascotService.owns(profile: DataService.Profile, mascotId: string): boolean
	local mascot = Mascots.get(mascotId)
	return mascot ~= nil and ownsIn(profile, mascot, data(profile).owned)
end

-- Надетый маскот (только если всё ещё открыт)
function MascotService.equippedOf(profile: DataService.Profile): Mascots.Mascot?
	local d = data(profile)
	local mascot = Mascots.get(d.equipped)
	if mascot and ownsIn(profile, mascot, d.owned) then
		return mascot
	end
	return nil
end

-- «Парад маскотов» (DailyEventService): множитель бонуса; без модуля или при ошибке — 1
local function paradeMultiplier(): number
	local module = script.Parent:FindFirstChild("DailyEventService")
	if not module or not module:IsA("ModuleScript") then
		return 1
	end
	local ok, value = pcall(function()
		return (require(module) :: any).mascotMultiplier()
	end)
	return if ok and type(value) == "number" and value >= 1 and value <= 10 then value else 1
end

-- Бонус надетого маскота вида kind (0 — нет такого)
function MascotService.bonusFor(profile: DataService.Profile, kind: Mascots.BonusKind): number
	local mascot = MascotService.equippedOf(profile)
	return if mascot and mascot.bonus.kind == kind then mascot.bonus.value * paradeMultiplier() else 0
end

function MascotService.bonus(player: Player, kind: Mascots.BonusKind): number
	local profile = DataService.get(player)
	return if profile then MascotService.bonusFor(profile, kind) else 0
end

local function pushState(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local equipped = MascotService.equippedOf(profile)
	MascotRemotes.MascotState:FireClient(
		player,
		{ owned = ownedSet(profile), equipped = if equipped then equipped.id else nil }
	)
end

local function logMascot(player: Player, mascotId: string, how: string)
	local analytics = script.Parent:FindFirstChild("AnalyticsService")
	if analytics and analytics:IsA("ModuleScript") then
		pcall((require(analytics) :: any).logMascot, player, mascotId, how)
	end
end

-- ===== Модель в мире =====

local function folder(): Folder
	if worldFolder and worldFolder.Parent then
		return worldFolder
	end
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	f.Parent = workspace
	worldFolder = f
	return f
end

local function ball(model: Model, name: string, size: Vector3, color: Color3, at: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = at
	part.Parent = model
	return part
end

-- Заглушка, пока Астра не сдала модель: шар-тело, уши и глаза (лицо к +Z, низ на Y = 0)
local function placeholder(mascot: Mascots.Mascot): Model
	local model = Instance.new("Model")
	local body = ball(model, "Body", Vector3.new(1.8, 1.8, 1.8), mascot.color, CFrame.new(0, 0.9, 0))
	ball(model, "EarLeft", Vector3.new(0.6, 0.6, 0.6), mascot.color, CFrame.new(-0.55, 1.8, 0))
	ball(model, "EarRight", Vector3.new(0.6, 0.6, 0.6), mascot.color, CFrame.new(0.55, 1.8, 0))
	local white = Color3.new(1, 1, 1)
	local black = Color3.fromRGB(20, 20, 30)
	ball(model, "EyeLeft", Vector3.new(0.45, 0.45, 0.45), white, CFrame.new(-0.35, 1.1, 0.75))
	ball(model, "EyeRight", Vector3.new(0.45, 0.45, 0.45), white, CFrame.new(0.35, 1.1, 0.75))
	ball(model, "PupilLeft", Vector3.new(0.22, 0.22, 0.22), black, CFrame.new(-0.35, 1.1, 0.95))
	ball(model, "PupilRight", Vector3.new(0.22, 0.22, 0.22), black, CFrame.new(0.35, 1.1, 0.95))
	-- Редкие светятся (V16: Neon только у редких)
	if mascot.rarity == "epic" or mascot.rarity == "legendary" then
		body.Material = Enum.Material.Neon
	end
	model.PrimaryPart = body
	model.WorldPivot = CFrame.new()
	return model
end

local function buildModel(mascot: Mascots.Mascot): (Model, BasePart)
	local source = ServerStorage:FindFirstChild(Mascots.folder)
	local template = source and source:FindFirstChild("Mascot_" .. mascot.id)
	-- Нет модели Астры — запасной вариант из шаров (владелец 07.11: «бегает какое-то убожище»): пишем в
	-- лог, какой именно маскот остался заглушкой, чтобы Dev 1 импортировал assets/models/astra-mascots
	if not (template and template:IsA("Model")) and not missingWarned[mascot.id] then
		missingWarned[mascot.id] = true
		warn(
			"[MascotService] нет модели ServerStorage."
				.. Mascots.folder
				.. ".Mascot_"
				.. mascot.id
				.. " — заглушка из шаров"
		)
	end
	local model = if template and template:IsA("Model") then template:Clone() else placeholder(mascot)
	local body = model:FindFirstChild("Body", true)
	if not body or not body:IsA("BasePart") then
		body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not body or not body:IsA("BasePart") then
		model:Destroy()
		model = placeholder(mascot)
		body = model:FindFirstChild("Body") :: BasePart
	end
	local root = body :: BasePart
	-- Скрипты в модели не нужны; детали — призраки: не мешают ходить и кликать
	for _, item in model:GetDescendants() do
		if item:IsA("Script") or item:IsA("LocalScript") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
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
	return model, root
end

local function removePet(player: Player)
	local pet = pets[player]
	pets[player] = nil
	if pet then
		if pet.tween then
			pet.tween:Cancel()
		end
		pet.model:Destroy()
	end
end

-- Модель под надетого маскота (или убрать). Ставится на место при следующем тике
local function refreshPet(player: Player)
	local profile = DataService.get(player)
	local mascot = profile and MascotService.equippedOf(profile)
	local current = pets[player]
	if current and mascot and current.id == mascot.id then
		return
	end
	removePet(player)
	if not mascot then
		return
	end
	local model, body = buildModel(mascot)
	model.Name = "Mascot_" .. player.UserId
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("MascotId", mascot.id)
	local offset = model:GetPivot():ToObjectSpace(body.CFrame)
	-- Прячем под карту до первого тика (персонаж мог ещё не появиться). Двигаем всю модель:
	-- WeldConstraint включаются при входе в workspace и запоминают ТЕКУЩЕЕ смещение — если сдвинуть
	-- только Body, остальные детали остаются у шаблона (в 500 studs), видно один кубик туловища
	model:PivotTo(CFrame.new(0, -500, 0))
	model.Parent = folder()
	pets[player] = { model = model, body = body, offset = offset, id = mascot.id, hop = false }
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Пол под точкой (nil — не нашли)
local function floorY(at: Vector3, character: Model): number?
	rayParams.FilterDescendantsInstances = { folder(), character }
	local hit = workspace:Raycast(at + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), rayParams)
	return if hit then hit.Position.Y else nil
end

local function step(player: Player, pet: Pet)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local cfg = Mascots.follow
	local seat = humanoid.SeatPart
	local anchor: CFrame
	if seat then
		-- Сидит за ПК (или на диване): маскот на полу сбоку от стула
		anchor = seat.CFrame * CFrame.new(2.5, 0, 0.5)
	else
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		local yaw = if flat.Magnitude > 0.01
			then CFrame.lookAt(root.Position, root.Position + flat)
			else CFrame.new(root.Position)
		anchor = yaw * CFrame.new(cfg.side, 0, cfg.behind)
	end
	local position = anchor.Position
	local standY = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
	local y = floorY(position, character) or standY
	-- Пол сильно ниже ног (край этажа, лестница): держимся уровня ног
	if math.abs(y - standY) > 4 and not seat then
		y = standY
	end
	local ground = Vector3.new(position.X, y, position.Z)
	local current = pet.body.CFrame * pet.offset:Inverse()
	local moved = (Vector3.new(current.X, 0, current.Z) - Vector3.new(ground.X, 0, ground.Z)).Magnitude
	-- Подскок на ходу: каждый второй тик вверх
	pet.hop = moved > 0.3 and not pet.hop
	local lift = if pet.hop then cfg.hopHeight else 0
	local facing = Vector3.new(root.Position.X, ground.Y, root.Position.Z)
	local at = ground + Vector3.new(0, lift, 0)
	-- Лицо маскота к +Z: lookAt смотрит -Z, разворачиваем
	local target = (
		if (facing - at).Magnitude > 0.1
			then CFrame.lookAt(at, Vector3.new(facing.X, at.Y, facing.Z)) * CFrame.Angles(0, math.pi, 0)
			else CFrame.new(at)
	) * pet.offset
	-- Стоит на месте: новый твин не нужен (каждый серверный твин реплицирует CFrame всем клиентам)
	local body = pet.body.CFrame
	if
		(body.Position - target.Position).Magnitude < 0.05
		and body.LookVector:Dot(target.LookVector) > 0.999
	then
		return
	end
	if pet.tween then
		pet.tween:Cancel()
		pet.tween = nil
	end
	if moved > cfg.maxStep or math.abs(current.Y - ground.Y) > cfg.maxStep then
		-- Телепорт, респаун, лифт: сразу на место
		pet.body.CFrame = target
		return
	end
	local tween = TweenService:Create(
		pet.body,
		TweenInfo.new(cfg.tickSeconds, Enum.EasingStyle.Linear),
		{ CFrame = target }
	)
	pet.tween = tween
	tween:Play()
end

-- ===== Выдача и покупка =====

-- Выдать маскота (достижения, группа, сезон, подарок). false — такого нет или уже открыт
function MascotService.grant(player: Player, mascotId: string): boolean
	local profile = DataService.get(player)
	local mascot = Mascots.get(mascotId)
	if not profile or not mascot or MascotService.owns(profile, mascot.id) then
		return false
	end
	data(profile).owned[mascot.id] = true
	pushState(player)
	return true
end

-- Подарок (GiftService): выдать в профиль получателя
function MascotService.grantMascot(player: Player, profile: DataService.Profile, mascotId: string): boolean
	local mascot = Mascots.get(mascotId)
	if not mascot or MascotService.owns(profile, mascot.id) then
		return false
	end
	data(profile).owned[mascot.id] = true
	pushState(player)
	return true
end

-- Забрать маскота (обмен, TradeService): только купленного/выданного (owned), не за достижение
-- или группу. Был надет — снимаем. false — его и не было
function MascotService.revokeMascot(player: Player, profile: DataService.Profile, mascotId: string): boolean
	local d = data(profile)
	if not d.owned[mascotId] then
		return false
	end
	d.owned[mascotId] = nil
	-- data() каждый раз собирает новую таблицу: после owns() берём её заново
	if not MascotService.owns(profile, mascotId) then
		local fresh = data(profile)
		if fresh.equipped == mascotId then
			fresh.equipped = nil
		end
	end
	refreshPet(player)
	pushState(player)
	return true
end

-- Маскот за Robux (зовёт MonetizationService.ProcessReceipt). false — это не маскот.
-- Повторная выдача безопасна: маскот просто остаётся открытым
function MascotService.grantProduct(player: Player, profile: DataService.Profile, productId: number): boolean
	local mascot = Mascots.findByProduct(productId)
	if not mascot then
		return false
	end
	data(profile).owned[mascot.id] = true
	pushState(player)
	logMascot(player, mascot.id, "robux")
	return true
end

local function throttled(map: { [Player]: number }, player: Player, cooldown: number): boolean
	local now = os.clock()
	if (map[player] or 0) + cooldown > now then
		return true
	end
	map[player] = now
	return false
end

local function onBuy(player: Player, mascotId: any)
	if throttled(lastBuy, player, BUY_COOLDOWN) then
		return
	end
	local mascot = Mascots.get(mascotId)
	local profile = DataService.get(player)
	if not mascot or not profile or mascot.how ~= "cash" then
		return
	end
	-- График контента (Config/ContentDrops): до выхода не продаём
	if not ContentDrops.isReleased("mascot", mascot.id) then
		return
	end
	local cost = mascot.cost
	if type(cost) ~= "number" or cost < 0 or MascotService.owns(profile, mascot.id) then
		return
	end
	if DataService.trySpend(player, cost) then
		data(profile).owned[mascot.id] = true
		-- Первый маскот — сразу с собой
		if data(profile).equipped == nil then
			data(profile).equipped = mascot.id
			refreshPet(player)
		end
		pushState(player)
		logMascot(player, mascot.id, "cash")
	end
end

local function onEquip(player: Player, mascotId: any)
	if mascotId ~= nil and type(mascotId) ~= "string" then
		return
	end
	if throttled(lastEquip, player, EQUIP_COOLDOWN) then
		pushState(player)
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if mascotId ~= nil and not MascotService.owns(profile, mascotId) then
		return
	end
	data(profile).equipped = mascotId
	refreshPet(player)
	pushState(player)
end

local function onStateRequest(player: Player)
	if throttled(lastRequest, player, STATE_REQUEST_COOLDOWN) then
		return
	end
	pushState(player)
	-- Маскот за достижение мог открыться только что: модель — если он уже надет
	refreshPet(player)
end

function MascotService.start()
	MascotRemotes.BuyMascot.OnServerEvent:Connect(onBuy)
	MascotRemotes.EquipMascot.OnServerEvent:Connect(onEquip)
	MascotRemotes.MascotStateRequest.OnServerEvent:Connect(onStateRequest)
	DataService.onProfileLoaded(function(player: Player, _: DataService.Profile)
		pushState(player)
		refreshPet(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		removePet(player)
		lastBuy[player] = nil
		lastEquip[player] = nil
		lastRequest[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Mascots.follow.tickSeconds)
			for player, pet in pets do
				if not player.Parent then
					removePet(player)
				elseif pet.model.Parent then
					local ok, err = pcall(step, player, pet)
					if not ok then
						warn("[MascotService] Follow failed:", err)
					end
				end
			end
		end
	end)
end

return MascotService
