--!strict
-- Охранник студии (Config/HitCartridges.guard): когда вор уносит картридж с полки хозяина, от полки
-- бежит охранник и пытается его схватить. Ловит НЕ со 100%-й вероятностью (владелец 07.11): у вора
-- есть шанс вырваться, а если вор убежал далеко от полки, охранник отстаёт.
-- Охранник — виртуальный бегун (позиция считается здесь, модель R15 с закреплённым корнем двигается
-- PivotTo, как ходоки StaffLife); ноги и руки качает клиент (Controllers/NpcWalkAnimator, тег NpcWalker).
-- HitService создаёт охранника на каждую кражу (spawn), каждый тик зовёт step и убирает его (destroy).
-- step возвращает событие: "chase" — выбежал, "catch" — схватил (попытка удалась), "slipped" — вор
-- вырвался (охранник споткнулся), "lost" — охранник сдался или отстал.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HitCartridges = require(ReplicatedStorage.Shared.Config.HitCartridges)

export type Guard = {
	home: Vector3, -- полка хозяина (мир)
	pos: Vector3, -- где охранник сейчас (мир, XZ; высоту берём с пола)
	startedAt: number, -- os.clock() начала кражи
	last: number, -- os.clock() прошлого шага
	spawned: boolean,
	done: boolean,
	attempts: number,
	stunnedUntil: number,
	giveUp: boolean, -- после оглушения сдаётся (попытки кончились)
	model: Model?,
	building: boolean,
}

local GuardService = {}

local rng = Random.new()
local WALK_TAG = "NpcWalker"
local HIP_HEIGHT = 3 -- корень R15 над полом

local NAVY = Color3.fromRGB(28, 44, 92)
local SKIN = Color3.fromRGB(224, 172, 126)

local function setWalking(model: Model?, speed: number?)
	if model then
		model:SetAttribute("WalkSpeed", speed or 0)
		model:SetAttribute("Walking", speed ~= nil)
		if speed ~= nil then
			CollectionService:AddTag(model, WALK_TAG)
		end
	end
end

-- Модель охранника: форма тёмно-синяя, фуражка и значок 🛡 над головой
local function build(guard: Guard)
	if guard.building or guard.model then
		return
	end
	guard.building = true
	task.spawn(function()
		local description = Instance.new("HumanoidDescription")
		description.HeadColor = SKIN
		description.LeftArmColor = NAVY
		description.RightArmColor = NAVY
		description.TorsoColor = NAVY
		description.LeftLegColor = Color3.fromRGB(20, 30, 62)
		description.RightLegColor = Color3.fromRGB(20, 30, 62)
		local ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
		guard.building = false
		if not ok or not result or guard.done then
			return
		end
		local model = result :: Model
		model.Name = "SecurityGuard"
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		local head = model:FindFirstChild("Head")
		local root = model:FindFirstChild("HumanoidRootPart")
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = part == root
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
		if head and head:IsA("BasePart") then
			local cap = Instance.new("Part")
			cap.Name = "GuardCap"
			cap.Size = Vector3.new(1.35, 0.4, 1.35)
			cap.Color = NAVY
			cap.Material = Enum.Material.Fabric
			cap.CanCollide = false
			cap.CanQuery = false
			cap.CanTouch = false
			cap.Massless = true
			cap.CFrame = head.CFrame * CFrame.new(0, 0.62, 0)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = cap
			weld.Parent = cap
			cap.Parent = model
			local gui = Instance.new("BillboardGui")
			gui.Name = "GuardBadge"
			gui.Size = UDim2.fromScale(2, 1.2)
			gui.StudsOffset = Vector3.new(0, 2.4, 0)
			gui.MaxDistance = 100
			gui.Adornee = head
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Text = "🛡"
			label.Parent = gui
			gui.Parent = head
		end
		model:PivotTo(CFrame.new(guard.pos + Vector3.new(0, HIP_HEIGHT, 0)))
		model.Parent = workspace
		guard.model = model
	end)
end

function GuardService.spawn(home: Vector3, now: number): Guard
	return {
		home = home,
		pos = Vector3.new(home.X, home.Y, home.Z),
		startedAt = now,
		last = now,
		spawned = false,
		done = false,
		attempts = 0,
		stunnedUntil = 0,
		giveUp = false,
		model = nil,
		building = false,
	}
end

function GuardService.destroy(guard: Guard?)
	if not guard then
		return
	end
	guard.done = true
	local model = guard.model
	guard.model = nil
	if model then
		model:Destroy()
	end
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Одна итерация (HitService зовёт каждый CARRY_TICK): thiefPosition — корень вора. Возвращает событие
function GuardService.step(guard: Guard?, thiefPosition: Vector3, now: number): string?
	local config = HitCartridges.guard
	if not guard or guard.done or not config.enabled then
		return nil
	end
	local dt = math.clamp(now - guard.last, 0, 0.5)
	guard.last = now
	if now - guard.startedAt < config.reactionSeconds then
		return nil
	end
	if not guard.spawned then
		guard.spawned = true
		build(guard)
		return "chase"
	end
	-- Споткнулся: стоит, вор уходит
	if guard.stunnedUntil > now then
		setWalking(guard.model, nil)
		return nil
	end
	if guard.stunnedUntil > 0 and guard.giveUp then
		GuardService.destroy(guard)
		return "lost"
	end
	-- Далеко от полки: охранник отстал
	if (flat(guard.pos) - flat(guard.home)).Magnitude > config.leashDistance then
		GuardService.destroy(guard)
		return "lost"
	end
	local gap = flat(thiefPosition) - flat(guard.pos)
	if
		gap.Magnitude <= config.catchDistance
		and math.abs(thiefPosition.Y - guard.pos.Y) <= HitCartridges.catchHeight
	then
		guard.attempts += 1
		if rng:NextNumber() < config.catchChance then
			return "catch"
		end
		guard.stunnedUntil = now + config.stunSeconds
		guard.giveUp = guard.attempts >= config.maxAttempts
		setWalking(guard.model, nil)
		return "slipped"
	end
	-- Бежит к вору по земле
	local direction = if gap.Magnitude > 0.01 then gap.Unit else Vector3.new(0, 0, 1)
	local move = math.min(config.speed * dt, gap.Magnitude)
	local nextPos = guard.pos + direction * move
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if guard.model then
		table.insert(ignore, guard.model)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(
		Vector3.new(nextPos.X, thiefPosition.Y + 4, nextPos.Z),
		Vector3.new(0, -40, 0),
		params
	)
	local groundY = if hit then hit.Position.Y else thiefPosition.Y - HIP_HEIGHT
	guard.pos = Vector3.new(nextPos.X, groundY, nextPos.Z)
	local model = guard.model
	if model then
		model:PivotTo(
			CFrame.lookAt(
				guard.pos + Vector3.new(0, HIP_HEIGHT, 0),
				guard.pos + Vector3.new(direction.X, HIP_HEIGHT, direction.Z)
			)
		)
		setWalking(model, config.speed)
	end
	return nil
end

return GuardService
