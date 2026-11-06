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
local KNEE_BEND = 0.85
local ARM_SWING = 0.5
local ELBOW_BEND = 0.2
local LEAN = 0.07

type Joints = {
	leftHip: Motor6D?,
	rightHip: Motor6D?,
	leftKnee: Motor6D?,
	rightKnee: Motor6D?,
	leftShoulder: Motor6D?,
	rightShoulder: Motor6D?,
	leftElbow: Motor6D?,
	rightElbow: Motor6D?,
	waist: Motor6D?,
}

type Tracked = { joints: Joints, phase: number, walking: boolean }

local NpcWalkAnimator = {}

local tracked: { [Model]: Tracked } = {}
-- Сидящие за столом (StaffService.poseSitting: тег NpcSitter, атрибут Sitting): ноги согнуты, руки к столу
local sitters: { [Model]: any } = {}

local function motor(model: Model, name: string): Motor6D?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("Motor6D") then found else nil
end

local function collect(model: Model): Joints
	return {
		leftHip = motor(model, "LeftHip"),
		rightHip = motor(model, "RightHip"),
		leftKnee = motor(model, "LeftKnee"),
		rightKnee = motor(model, "RightKnee"),
		leftShoulder = motor(model, "LeftShoulder"),
		rightShoulder = motor(model, "RightShoulder"),
		leftElbow = motor(model, "LeftElbow"),
		rightElbow = motor(model, "RightElbow"),
		waist = motor(model, "Waist"),
	}
end

local function setAngle(joint: Motor6D?, angle: number)
	if joint then
		joint.Transform = CFrame.Angles(angle, 0, 0)
	end
end

local function relax(joints: Joints)
	for _, joint in joints :: any do
		if joint then
			(joint :: Motor6D).Transform = CFrame.identity
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
	if not joints.leftHip then
		local fresh = collect(model)
		for key, value in fresh do
			joints[key] = value
		end
	end
	local sitting = model:GetAttribute("Sitting") == true
	if sitting then
		-- Бёдра вперёд на 90°, колени вниз, плечи вперёд к клавиатуре, локти согнуты
		setAngle(joints.leftHip, math.rad(90))
		setAngle(joints.rightHip, math.rad(90))
		setAngle(joints.leftKnee, math.rad(-90))
		setAngle(joints.rightKnee, math.rad(-90))
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
			tracked[item] = nil
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
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
			local walking = model:GetAttribute("Walking") == true
			if not walking then
				if state.walking then
					state.walking = false
					relax(state.joints)
				end
				continue
			end
			-- Суставы могли появиться позже (модель собирается): ищем, пока не нашли бёдра
			if not state.joints.leftHip then
				state.joints = collect(model)
			end
			if (model:GetPivot().Position - origin).Magnitude > VIEW_DISTANCE then
				continue
			end
			state.walking = true
			local speed = tonumber(model:GetAttribute("WalkSpeed")) or 6
			state.phase += dt * speed * STEP_PER_SPEED
			local swing = math.sin(state.phase) -- левая нога вперёд при > 0
			local joints = state.joints
			setAngle(joints.leftHip, swing * HIP_SWING)
			setAngle(joints.rightHip, -swing * HIP_SWING)
			-- Колено сгибается, пока нога идёт вперёд (в сторону шага), назад не гнётся
			setAngle(joints.leftKnee, -math.max(0, math.cos(state.phase)) * KNEE_BEND)
			setAngle(joints.rightKnee, -math.max(0, -math.cos(state.phase)) * KNEE_BEND)
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
