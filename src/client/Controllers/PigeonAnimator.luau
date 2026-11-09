--!strict
-- Голуби парка (WorldService.ensurePigeons, тег ParkPigeon): иногда клюют (наклон вперёд), а когда игрок
-- подходит ближе SCARE_DISTANCE, взлетают и отлетают от него, потом возвращаются на место. Всё клиентское:
-- модель двигается PivotTo только у игрока, ничего не реплицируется. Дальше VIEW_DISTANCE не анимируем.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TAG = "ParkPigeon"
local VIEW_DISTANCE = 120
local SCARE_DISTANCE = 7
local FLEE_DISTANCE = 12 -- насколько отлетает
local FLEE_SECONDS = 0.9
local STAY_SECONDS = 7 -- сколько сидит вдали, прежде чем вернуться
local RETURN_SECONDS = 1.6
local PECK_EVERY = { 2.5, 6 }
local PECK_SECONDS = 0.5
local PECK_ANGLE = math.rad(28)

type Pigeon = {
	home: CFrame,
	mode: string, -- "idle" | "flee" | "away" | "return"
	t: number,
	nextPeck: number,
	peckStart: number,
	target: CFrame,
}

local PigeonAnimator = {}
local pigeons: { [Model]: Pigeon } = {}
local rng = Random.new()

local function track(item: Instance)
	if item:IsA("Model") and pigeons[item] == nil then
		pigeons[item] = {
			home = item:GetPivot(),
			mode = "idle",
			t = 0,
			nextPeck = os.clock() + rng:NextNumber(PECK_EVERY[1], PECK_EVERY[2]),
			peckStart = -1,
			target = item:GetPivot(),
		}
	end
end

local function lerpCFrame(a: CFrame, b: CFrame, alpha: number): CFrame
	return a:Lerp(b, math.clamp(alpha, 0, 1))
end

function PigeonAnimator.start()
	for _, model in CollectionService:GetTagged(TAG) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(item)
		if item:IsA("Model") then
			pigeons[item] = nil
		end
	end)
	RunService.Heartbeat:Connect(function(dt: number)
		local camera = workspace.CurrentCamera
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not camera or not root or not root:IsA("BasePart") then
			return
		end
		local now = os.clock()
		local origin = camera.CFrame.Position
		for model, state in pigeons do
			if not model.Parent then
				pigeons[model] = nil
				continue
			end
			if (state.home.Position - origin).Magnitude > VIEW_DISTANCE then
				continue
			end
			local away = Vector3.new(state.home.X - root.Position.X, 0, state.home.Z - root.Position.Z)
			if state.mode == "idle" then
				if away.Magnitude < SCARE_DISTANCE then
					local direction = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
					local spot = state.home.Position + direction * FLEE_DISTANCE + Vector3.new(0, 0.2, 0)
					state.target = CFrame.lookAt(spot, spot + direction)
					state.mode = "flee"
					state.t = 0
				elseif state.peckStart >= 0 then
					local k = (now - state.peckStart) / PECK_SECONDS
					if k >= 1 then
						state.peckStart = -1
						model:PivotTo(state.home)
					else
						model:PivotTo(state.home * CFrame.Angles(math.sin(k * math.pi) * PECK_ANGLE, 0, 0))
					end
				elseif now >= state.nextPeck then
					state.peckStart = now
					state.nextPeck = now + rng:NextNumber(PECK_EVERY[1], PECK_EVERY[2])
				end
			elseif state.mode == "flee" then
				state.t += dt
				local k = state.t / FLEE_SECONDS
				-- Взлёт дугой: высота растёт к середине и падает к концу
				local lifted = lerpCFrame(state.home, state.target, k)
					+ Vector3.new(0, math.sin(math.clamp(k, 0, 1) * math.pi) * 4, 0)
				model:PivotTo(lifted)
				if k >= 1 then
					state.mode = "away"
					state.t = 0
				end
			elseif state.mode == "away" then
				state.t += dt
				if state.t >= STAY_SECONDS and away.Magnitude > SCARE_DISTANCE * 1.6 then
					state.mode = "return"
					state.t = 0
				end
			else
				state.t += dt
				local k = state.t / RETURN_SECONDS
				model:PivotTo(
					lerpCFrame(state.target, state.home, k)
						+ Vector3.new(0, math.sin(math.clamp(k, 0, 1) * math.pi) * 2.5, 0)
				)
				if k >= 1 then
					state.mode = "idle"
					model:PivotTo(state.home)
				end
			end
		end
	end)
end

return PigeonAnimator
