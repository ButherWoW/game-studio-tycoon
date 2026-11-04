--!strict
-- Скины сотрудников (Config/Skins): покупка, кто что носит, наряд NPC.
-- Обычные — за $ (BuySkin), премиум — за Robux: квитанцию принимает MonetizationService
-- и зовёт grantProduct (эффект в профиле, сохраняет MonetizationService до PurchaseGranted).
-- Купленный скин — открытый стиль: его можно надеть на сколько угодно нанятых сотрудников.
-- NPC строит StaffService и для каждого зовёт decorate (одежда, цвета, аксессуары);
-- смена скина — StaffService.refreshNpcs. Косметика: бонусов нет.
-- Данные: profile.skins = { owned = { [skinId]: true }, assigned = { [employeeId]: skinId } }.
-- Rebirth: owned остаётся, assigned — только у тех, кто всё ещё нанят (чистит data()).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local Skins = require(Shared.Config.Skins)
local Images = require(Shared.Config.Images)
local SkinRemotes = require(Shared.SkinRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StaffService = require(script.Parent.StaffService)

local ACTION_COOLDOWN = 0.25 -- покупка не чаще
local ASSIGN_COOLDOWN = 1 -- смена скина перестраивает NPC: не чаще раза в секунду
local STATE_REQUEST_COOLDOWN = 1

-- Детали R15, которые красим запасными цветами (кисти, ступни и голова остаются цвета кожи)
local SHIRT_PARTS = {
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"RightUpperArm",
	"RightLowerArm",
}
local PANTS_PARTS =
	{ "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }

local SkinService = {}
local lastAction: { [Player]: number } = {}
local lastAssign: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}

type SkinData = { owned: { [string]: boolean }, assigned: { [string]: string } }

-- Поле профиля в порядке: старые сохранения без него, мусор, уволенные (Rebirth) сотрудники
local function data(profile: DataService.Profile): SkinData
	local raw = (profile :: any).skins
	if type(raw) ~= "table" then
		raw = {}
	end
	local owned: { [string]: boolean } = {}
	if type(raw.owned) == "table" then
		for id, value in raw.owned do
			if value == true and Skins.get(id) then
				owned[id] = true
			end
		end
	end
	local assigned: { [string]: string } = {}
	if type(raw.assigned) == "table" then
		local staff = StaffService.hired(profile)
		for employeeId, skinId in raw.assigned do
			if
				type(employeeId) == "string"
				and staff[employeeId] ~= nil
				and type(skinId) == "string"
				and owned[skinId]
			then
				assigned[employeeId] = skinId
			end
		end
	end
	local clean = { owned = owned, assigned = assigned }
	profile.skins = clean
	return clean
end

local function pushState(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local skins = data(profile)
	SkinRemotes.SkinState:FireClient(player, { owned = skins.owned, assigned = skins.assigned })
end

local function paint(model: Model, names: { string }, color: Color3)
	for _, name in names do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = color
		end
	end
end

-- Одежда из картинок Config/Images.skins (0 — не загружена: остаются только цвета)
local function clothing(model: Model, shirtId: number, pantsId: number)
	if shirtId > 0 then
		local shirt = model:FindFirstChildOfClass("Shirt") or Instance.new("Shirt")
		shirt.ShirtTemplate = "rbxassetid://" .. shirtId
		shirt.Parent = model
	end
	if pantsId > 0 then
		local pants = model:FindFirstChildOfClass("Pants") or Instance.new("Pants")
		pants.PantsTemplate = "rbxassetid://" .. pantsId
		pants.Parent = model
	end
end

-- Ручное крепление, если AddAccessory не сварил (модель ещё не в Workspace)
local function weldByAttachment(model: Model, accessory: Accessory)
	local handle = accessory:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") or handle:FindFirstChild("AccessoryWeld") then
		return
	end
	local own = handle:FindFirstChildOfClass("Attachment")
	if not own then
		return
	end
	for _, part in model:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local target = part:FindFirstChild(own.Name)
		if target and target:IsA("Attachment") then
			handle.CFrame = target.WorldCFrame * own.CFrame:Inverse()
			local weld = Instance.new("WeldConstraint")
			weld.Name = "AccessoryWeld"
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = handle
			return
		end
	end
end

-- Аксессуары скина из ServerStorage.Skins: модель с Accessory внутри (как сдала Астра)
local function accessories(model: Model, humanoid: Humanoid, skin: Skins.Skin)
	local folder = ServerStorage:FindFirstChild(Skins.folder)
	local source = folder
		and (folder:FindFirstChild(skin.model) or folder:FindFirstChild("skin_" .. skin.id .. "_acc"))
	if not source then
		return
	end
	local list = if source:IsA("Accessory") then { source } else source:GetChildren()
	for _, child in list do
		if child:IsA("Accessory") then
			local clone = child:Clone()
			local ok = pcall(function()
				humanoid:AddAccessory(clone)
			end)
			if not ok then
				clone.Parent = model
			end
			weldByAttachment(model, clone)
		end
	end
end

-- Какой скин носит сотрудник (nil — свой вид из «Внешности»)
function SkinService.skinOf(profile: DataService.Profile, employeeId: string): string?
	return data(profile).assigned[employeeId]
end

-- Нарядить NPC (StaffService.rebuildNpcs, до рассадки: аксессуары поедут вместе с моделью)
function SkinService.decorate(model: Model, employeeId: string, profile: DataService.Profile)
	local skin = Skins.get(data(profile).assigned[employeeId])
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not skin or not humanoid then
		return
	end
	-- Цвета всегда: под прозрачными местами шаблона и пока картинки не загружены
	paint(model, SHIRT_PARTS, skin.shirt)
	paint(model, PANTS_PARTS, skin.pants)
	local colors = model:FindFirstChildOfClass("BodyColors")
	if colors then
		colors.TorsoColor3 = skin.shirt
		colors.LeftArmColor3 = skin.shirt
		colors.RightArmColor3 = skin.shirt
		colors.LeftLegColor3 = skin.pants
		colors.RightLegColor3 = skin.pants
	end
	local images = Images.skins[skin.id]
	if images then
		clothing(model, images.shirt, images.pants)
	end
	accessories(model, humanoid, skin)
end

-- Сотрудника уволили (StaffService.onFire): при повторном найме он придёт в своём виде
function SkinService.forget(player: Player, profile: DataService.Profile, employeeId: string)
	data(profile).assigned[employeeId] = nil
	pushState(player)
end

local function grant(player: Player, profile: DataService.Profile, skin: Skins.Skin)
	data(profile).owned[skin.id] = true
	pushState(player)
end

-- Премиум-скин за Robux (зовёт MonetizationService.ProcessReceipt). false — это не скин.
-- Повторная выдача безопасна: скин просто остаётся открытым
function SkinService.grantProduct(player: Player, profile: DataService.Profile, productId: number): boolean
	local skin = Skins.findByProduct(productId)
	if not skin then
		return false
	end
	grant(player, profile, skin)
	return true
end

-- Открыт ли скин у игрока (подарки: не дарить то, что уже есть)
function SkinService.owns(profile: DataService.Profile, skinId: string): boolean
	return data(profile).owned[skinId] == true
end

-- Выдать скин по id (стартовый набор, сделка дня). false — уже был открыт или такого нет
function SkinService.grantSkin(player: Player, profile: DataService.Profile, skinId: string): boolean
	local skin = Skins.get(skinId)
	if not skin or data(profile).owned[skin.id] then
		return false
	end
	grant(player, profile, skin)
	return true
end

function SkinService.ownsSkin(profile: DataService.Profile, skinId: string): boolean
	return data(profile).owned[skinId] == true
end

-- Забрать скин (обмен, TradeService): снять со всех сотрудников. false — его и не было
function SkinService.revokeSkin(player: Player, profile: DataService.Profile, skinId: string): boolean
	local skins = data(profile)
	if not skins.owned[skinId] then
		return false
	end
	skins.owned[skinId] = nil
	local worn = false
	for employeeId, id in skins.assigned do
		if id == skinId then
			skins.assigned[employeeId] = nil
			worn = true
		end
	end
	pushState(player)
	if worn then
		StaffService.refreshNpcs(player)
	end
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

local function onBuy(player: Player, skinId: any)
	if throttled(lastAction, player, ACTION_COOLDOWN) then
		return
	end
	local skin = Skins.get(skinId)
	local profile = DataService.get(player)
	-- Премиум за $ не продаётся; открытый второй раз не продаём
	if not skin or skin.premium or not profile then
		return
	end
	local cost = skin.cost
	if type(cost) ~= "number" or cost < 0 or data(profile).owned[skin.id] then
		return
	end
	if DataService.trySpend(player, cost) then
		grant(player, profile, skin)
	end
end

local function onAssign(player: Player, employeeId: any, skinId: any)
	if type(employeeId) ~= "string" or (skinId ~= nil and type(skinId) ~= "string") then
		return
	end
	if throttled(lastAssign, player, ASSIGN_COOLDOWN) then
		-- Клиент мог уже перерисовать выбор: вернём правду
		pushState(player)
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local skins = data(profile)
	if StaffService.hired(profile)[employeeId] == nil then
		return
	end
	if skinId ~= nil and not skins.owned[skinId] then
		return
	end
	if skins.assigned[employeeId] == skinId then
		return
	end
	skins.assigned[employeeId] = skinId
	pushState(player)
	StaffService.refreshNpcs(player)
end

local function onStateRequest(player: Player)
	if throttled(lastRequest, player, STATE_REQUEST_COOLDOWN) then
		return
	end
	pushState(player)
end

function SkinService.start()
	SkinRemotes.BuySkin.OnServerEvent:Connect(onBuy)
	SkinRemotes.AssignSkin.OnServerEvent:Connect(onAssign)
	SkinRemotes.SkinStateRequest.OnServerEvent:Connect(onStateRequest)
	DataService.onProfileLoaded(function(player: Player, _: DataService.Profile)
		pushState(player)
	end)
	-- Rebirth, переезд: команда могла разойтись — data() в pushState чистит assigned сразу,
	-- иначе после Rebirth заново нанятый сотрудник пришёл бы в старом скине
	PlotService.plotChanged:Connect(pushState)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		lastAssign[player] = nil
		lastRequest[player] = nil
	end)
end

return SkinService
