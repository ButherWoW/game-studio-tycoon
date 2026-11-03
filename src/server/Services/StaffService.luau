--!strict
-- Найм сотрудников (issue #7) и NPC за столами (без подписей — имена видны в окне «Команда»).
-- Данные — (profile :: any).staff = { [employeeId]: deskUpgradeId }. Стол — купленный апгрейд
-- с desk = true (Config/Upgrades); за одним столом один сотрудник.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Employees = require(ReplicatedStorage.Shared.Config.Employees)
local StaffRemotes = require(ReplicatedStorage.Shared.StaffRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local SEAT_DISTANCE = 3.5 -- насколько перед столом стоит NPC
local SEAT_MIN_GAP = 2.5 -- столы стоят тесно (стол, ПК, кресло): раздвигаем NPC вбок
local SEAT_SIDE_SHIFTS = { 0, -3, 3, -6, 6, -9, 9 }
local SKIN = Color3.fromRGB(234, 184, 146)
local PANTS = Color3.fromRGB(45, 50, 70)

local StaffService = {}
local npcFolders: { [Player]: Folder } = {}
local refreshGeneration: { [Player]: number } = {}

-- Нанятые сотрудники игрока; из сохранения берём только то, что сходится с конфигом
local function getStaff(profile: DataService.Profile): { [string]: string }
	local raw = (profile :: any).staff
	if type(raw) ~= "table" then
		raw = {};
		(profile :: any).staff = raw
	end
	local usedDesks: { [string]: boolean } = {}
	for employeeId, deskId in raw do
		local valid = type(employeeId) == "string"
			and type(deskId) == "string"
			and Employees.get(employeeId) ~= nil
			and profile.upgrades[deskId] == true
			and not usedDesks[deskId]
		if valid then
			usedDesks[deskId] = true
		else
			raw[employeeId] = nil
		end
	end
	return raw
end

local function isDesk(upgrade: Upgrades.Upgrade): boolean
	return upgrade.desk == true
end

local function freeDesk(profile: DataService.Profile, staff: { [string]: string }): Upgrades.Upgrade?
	local taken: { [string]: boolean } = {}
	for _, deskId in staff do
		taken[deskId] = true
	end
	for _, upgrade in Upgrades do
		if isDesk(upgrade) and profile.upgrades[upgrade.id] and not taken[upgrade.id] then
			return upgrade
		end
	end
	return nil
end

-- deskUpgradeId -> сотрудник за этим столом (для DevelopmentService)
function StaffService.employeesByDesk(player: Player): { [string]: Employees.Employee }
	local result = {}
	local profile = DataService.get(player)
	if not profile then
		return result
	end
	for employeeId, deskId in getStaff(profile) do
		local employee = Employees.get(employeeId)
		if employee then
			result[deskId] = employee
		end
	end
	return result
end

local function sendStaff(player: Player)
	local profile = DataService.get(player)
	if profile then
		StaffRemotes.StaffChanged:FireClient(player, getStaff(profile))
	end
end

local function buildNpc(employee: Employees.Employee): Model?
	local description = Instance.new("HumanoidDescription")
	local shirt = Employees.shirtColors[employee.specialization or "all"]
	description.HeadColor = SKIN
	description.LeftArmColor = SKIN
	description.RightArmColor = SKIN
	description.TorsoColor = shirt
	description.LeftLegColor = PANTS
	description.RightLegColor = PANTS
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn("[StaffService] NPC build failed:", result)
		return nil
	end
	local model = result :: Model
	model.Name = "Staff_" .. employee.id
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	return model
end

-- Поставить NPC перед столом лицом к нему. used — уже занятые точки (в координатах участка).
local function seatNpc(model: Model, plot: BasePart, desk: Upgrades.Upgrade, used: { Vector3 })
	local position = desk.position or Vector3.zero
	local floorY = plot.Size.Y / 2
	local rotation = CFrame.Angles(0, math.rad(desk.rotation or 0), 0)
	local deskPoint = Vector3.new(position.X, floorY, position.Z)

	local seat = deskPoint + rotation:VectorToWorldSpace(Vector3.new(0, 0, SEAT_DISTANCE))
	for _, shift in SEAT_SIDE_SHIFTS do
		local candidate = deskPoint + rotation:VectorToWorldSpace(Vector3.new(shift, 0, SEAT_DISTANCE))
		local free = true
		for _, other in used do
			if (other - candidate).Magnitude < SEAT_MIN_GAP then
				free = false
				break
			end
		end
		if free then
			seat = candidate
			break
		end
	end
	table.insert(used, seat)

	-- Pivot R15 — HumanoidRootPart: поднимаем на высоту бёдер над полом
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	local height = (if humanoid then humanoid.HipHeight else 2) + (if root then root.Size.Y / 2 else 1)
	-- Смотрит на стол: стол «лицом» к +Z, значит NPC смотрит в -Z стола
	local facing = seat - rotation:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local placement = CFrame.lookAt(seat, facing) + Vector3.new(0, height, 0)
	model:PivotTo(plot.CFrame * placement)
end

-- Пересадить всех NPC игрока (вход, найм, новый стол, переезд)
local function refreshNpcs(player: Player)
	-- Сборка NPC уступает поток; актуальна только последняя запущенная пересадка
	local generation = (refreshGeneration[player] or 0) + 1
	refreshGeneration[player] = generation
	local plot = PlotService.getPlot(player)
	local profile = DataService.get(player)
	if not plot or not profile then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Staff"

	local byDesk = StaffService.employeesByDesk(player)
	local used: { Vector3 } = {}
	for _, upgrade in Upgrades do
		local employee = byDesk[upgrade.id]
		if employee then
			local npc = buildNpc(employee)
			if npc then
				seatNpc(npc, plot, upgrade, used)
				npc.Parent = folder
			end
		end
	end
	-- Пока строили, игрок мог уйти или запустить новую пересадку
	if refreshGeneration[player] ~= generation or PlotService.getPlot(player) ~= plot then
		folder:Destroy()
		return
	end
	local old = npcFolders[player]
	if old then
		old:Destroy()
	end
	folder.Parent = plot
	npcFolders[player] = folder
end

local function onHire(player: Player, employeeId: any)
	if type(employeeId) ~= "string" then
		return
	end
	local employee = Employees.get(employeeId)
	local profile = DataService.get(player)
	if not employee or not profile then
		return
	end
	-- TODO(#7, #8, #11): легендарные — после исследований, квестов и геймпасса
	if employee.legendary or profile.studioLevel < employee.stage then
		return
	end
	local staff = getStaff(profile)
	if staff[employee.id] then
		return
	end
	local desk = freeDesk(profile, staff)
	if not desk then
		return
	end
	if DataService.trySpend(player, employee.cost) then
		staff[employee.id] = desk.id
		sendStaff(player)
		task.spawn(refreshNpcs, player)
		-- Задания «найми сотрудника» из ветки заданий, если она уже в игре
		local questModule = script.Parent:FindFirstChild("QuestService")
		if questModule and questModule:IsA("ModuleScript") then
			local count = 0
			for _ in staff do
				count += 1
			end
			(require(questModule) :: any).onEmployeesChanged(player, count)
		end
	end
end

function StaffService.start()
	StaffRemotes.HireEmployee.OnServerEvent:Connect(onHire)
	PlotService.plotChanged:Connect(function(player: Player)
		sendStaff(player)
		task.spawn(refreshNpcs, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local folder = npcFolders[player]
		if folder then
			folder:Destroy()
		end
		npcFolders[player] = nil
		refreshGeneration[player] = nil
	end)
end

return StaffService
