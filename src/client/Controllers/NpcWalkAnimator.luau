--!strict
-- Ходьба NPC (сотрудники на перерыве, строители): раньше модель просто скользила и подпрыгивала.
-- Сервер (StaffLife) ставит на идущую модель тег NpcWalker и атрибуты Walking / WalkSpeed; здесь на
-- клиенте качаем суставы R15 в такт шагу: бёдра и колени, плечи и локти (руки навстречу ногам),
-- лёгкий наклон корпуса. Transform суставов клиентский: ничего не реплицируется и сервер не нагружен.
-- Дальше VIEW_DISTANCE от камеры не анимируем. Остановился — суставы возвращаются в нейтраль.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "NpcWalker"
local SIT_TAG = "NpcSitter"
local VIEW_DISTANCE = 120
local STEP_PER_SPEED = 1.15 -- рад/с фазы шага на 1 stud/с скорости: при скорости 7 ~ 2 шага в секунду
local HIP_SWING = 0.62
local KNEE_BEND = 1.05
local ARM_SWING = 0.5
local ELBOW_BEND = 0.2
local LEAN = 0.07

type PoseJoint = Motor6D | AnimationConstraint

type Joints = {
	leftHip: PoseJoint?,
	rightHip: PoseJoint?,
	leftKnee: PoseJoint?,
	rightKnee: PoseJoint?,
	leftAnkle: PoseJoint?,
	rightAnkle: PoseJoint?,
	leftShoulder: PoseJoint?,
	rightShoulder: PoseJoint?,
	leftElbow: PoseJoint?,
	rightElbow: PoseJoint?,
	waist: PoseJoint?,
}

type Tracked = { joints: Joints, phase: number, walking: boolean }

local NpcWalkAnimator = {}

local tracked: { [Model]: Tracked } = {}
-- Сидящие за столом (StaffService.poseSitting: тег NpcSitter, атрибут Sitting): ноги согнуты, руки к столу
local sitters: { [Model]: any } = {}

local function motor(model: Model, name: string): PoseJoint?
	local legacy: Motor6D? = nil
	for _, item in model:GetDescendants() do
		if item:IsA("AnimationConstraint") then
			local attachment = item.Attachment0
			if
				item.Name == name
				or item.Name == name .. "AnimationConstraint"
				or (attachment and attachment.Name == name .. "RigAttachment")
			then
				return item
			end
		elseif item:IsA("Motor6D") and item.Name == name then
			legacy = item
		end
	end
	return legacy
end

local function collect(model: Model): Joints
	return {
		leftHip = motor(model, "LeftHip"),
		rightHip = motor(model, "RightHip"),
		leftKnee = motor(model, "LeftKnee"),
		rightKnee = motor(model, "RightKnee"),
		leftAnkle = motor(model, "LeftAnkle"),
		rightAnkle = motor(model, "RightAnkle"),
		leftShoulder = motor(model, "LeftShoulder"),
		rightShoulder = motor(model, "RightShoulder"),
		leftElbow = motor(model, "LeftElbow"),
		rightElbow = motor(model, "RightElbow"),
		waist = motor(model, "Waist"),
	}
end

-- A streamed-out joint reference can remain non-nil; recollect it on return.
local function needsCollect(model: Model, joints: Joints): boolean
	local required = {
		joints.leftHip,
		joints.rightHip,
		joints.leftKnee,
		joints.rightKnee,
		joints.leftAnkle,
		joints.rightAnkle,
		joints.leftShoulder,
		joints.rightShoulder,
		joints.leftElbow,
		joints.rightElbow,
		joints.waist,
	}
	-- Do not iterate this sparse list with ipairs: a missing first entry is meaningful.
	for index = 1, 11 do
		local joint = required[index]
		if not joint or not joint:IsDescendantOf(model) then
			return true
		end
	end
	return false
end

local function setAngle(joint: PoseJoint?, angle: number)
	if joint and joint.Parent then
		joint.Transform = CFrame.Angles(angle, 0, 0)
	end
end

-- PR #311 guard: posed is metadata, not a joint. Both avatar joint types are reset.
local function relax(joints: Joints)
	for _, joint in joints :: any do
		if typeof(joint) == "Instance" and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
			joint.Transform = CFrame.identity
		end
	end
end

local function track(item: Instance)
	if item:IsA("Model") and tracked[item] == nil then
		tracked[item] = { joints = collect(item), phase = 0, walking = false }
	end
end

local function trackSitter(item: Instance)
	if item:IsA("Model") and sitters[item] == nil then
		sitters[item] = collect(item) :: any
	end
end

local function applySitting(model: Model, joints: any)
	if needsCollect(model, joints) then
		local fresh = collect(model) :: any
		fresh.posed = joints.posed
		sitters[model] = fresh
		joints = fresh
	end
	local sitting = model:GetAttribute("Sitting") == true
	if sitting then
		-- Бёдра вперёд на 90°, колени вниз, плечи вперёд к клавиатуре, локти согнуты
		setAngle(joints.leftHip, math.rad(90))
		setAngle(joints.rightHip, math.rad(90))
		setAngle(joints.leftKnee, math.rad(-90))
		setAngle(joints.rightKnee, math.rad(-90))
		setAngle(joints.leftAnkle, 0)
		setAngle(joints.rightAnkle, 0)
		setAngle(joints.leftShoulder, math.rad(50))
		setAngle(joints.rightShoulder, math.rad(50))
		setAngle(joints.leftElbow, math.rad(55))
		setAngle(joints.rightElbow, math.rad(55))
		joints.posed = true
	elseif joints.posed then
		relax(joints)
		joints.posed = false
	end
end

function NpcWalkAnimator.start()
	for _, model in CollectionService:GetTagged(SIT_TAG) do
		trackSitter(model)
	end
	CollectionService:GetInstanceAddedSignal(SIT_TAG):Connect(trackSitter)
	CollectionService:GetInstanceRemovedSignal(SIT_TAG):Connect(function(item)
		if item:IsA("Model") then
			local joints = sitters[item]
			if joints and joints.posed then
				relax(joints)
			end
			sitters[item] = nil
		end
	end)
	for _, model in CollectionService:GetTagged(TAG) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(item)
		if item:IsA("Model") then
			local state = tracked[item]
			if state and item:GetAttribute("Sitting") ~= true then
				relax(state.joints)
			end
			tracked[item] = nil
		end
	end)
	-- Animator evaluates before PreSimulation; write the final procedural pose here.
	RunService.PreSimulation:Connect(function(dt: number)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local origin = camera.CFrame.Position
		for model, joints in sitters do
			if not model.Parent then
				sitters[model] = nil
			elseif (model:GetPivot().Position - origin).Magnitude <= VIEW_DISTANCE then
				applySitting(model, joints)
			end
		end
		for model, state in tracked do
			if not model.Parent then
				tracked[model] = nil
				continue
			end
			-- Sitting takes precedence over a stale walk tag/transition flag.
			if model:GetAttribute("Sitting") == true then
				state.walking = false
				continue
			end
			local walking = model:GetAttribute("Walking") == true
			if not walking then
				if state.walking then
					state.walking = false
					relax(state.joints)
				end
				continue
			end
			-- Суставы могли появиться позже (модель собирается): ищем, пока не нашли бёдра
			if (model:GetPivot().Position - origin).Magnitude > VIEW_DISTANCE then
				continue
			end
			if needsCollect(model, state.joints) then
				state.joints = collect(model)
			end
			state.walking = true
			local speed = tonumber(model:GetAttribute("WalkSpeed")) or 6
			state.phase += dt * speed * STEP_PER_SPEED
			local swing = math.sin(state.phase) -- левая нога вперёд при > 0
			local joints = state.joints
			setAngle(joints.leftHip, swing * HIP_SWING)
			setAngle(joints.rightHip, -swing * HIP_SWING)
			-- Колено сгибается, пока нога идёт вперёд (в сторону шага), назад не гнётся
			local leftKnee = -math.max(0, swing) * KNEE_BEND
			local rightKnee = -math.max(0, -swing) * KNEE_BEND
			setAngle(joints.leftKnee, leftKnee)
			setAngle(joints.rightKnee, rightKnee)
			-- Counter-rotate the ankle so a lifted foot does not point straight down.
			setAngle(joints.leftAnkle, -swing * HIP_SWING - leftKnee)
			setAngle(joints.rightAnkle, swing * HIP_SWING - rightKnee)
			-- Руки навстречу ногам, локоть слегка согнут вперёд
			local leftArm = -swing * ARM_SWING
			local rightArm = swing * ARM_SWING
			setAngle(joints.leftShoulder, leftArm)
			setAngle(joints.rightShoulder, rightArm)
			setAngle(joints.leftElbow, ELBOW_BEND + math.max(0, leftArm) * 0.6)
			setAngle(joints.rightElbow, ELBOW_BEND + math.max(0, rightArm) * 0.6)
			-- Корпус чуть вперёд и покачивается в такт шагу
			if joints.waist then
				joints.waist.Transform = CFrame.Angles(-LEAN, 0, swing * 0.04)
			end
		end
	end)
end

return NpcWalkAnimator
