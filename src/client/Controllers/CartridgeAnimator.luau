--!strict
-- Анимация старых дискет в парке: парят вверх-вниз и медленно вращаются, чтобы их было видно издалека.
-- Сервер (StartParkService.spawnCartridge) ставит на дискету тег ParkCartridge и атрибуты BasePos и
-- BaseYaw; остальные детали приварены к корпусу и едут вместе с ним. Двигаем только на клиенте
-- и только то, что рядом с камерой (дискет в парке немного, но на телефоне лишнее не крутим).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "ParkCartridge"
local SPIN_SPEED = 1.1 -- рад/с
local BOB_HEIGHT = 0.3 -- studs вверх и вниз
local BOB_SPEED = 2 -- рад/с
local VIEW_DISTANCE = 140 -- дальше камеры не анимируем

local CartridgeAnimator = {}

local phases: { [BasePart]: number } = {}

local function track(part: Instance)
	if part:IsA("BasePart") and phases[part] == nil then
		phases[part] = (part.Position.X * 0.37 + part.Position.Z * 0.53) % (2 * math.pi)
	end
end

function CartridgeAnimator.start()
	for _, part in CollectionService:GetTagged(TAG) do
		track(part)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(part)
		if part:IsA("BasePart") then
			phases[part] = nil
		end
	end)
	RunService.Heartbeat:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local origin = camera.CFrame.Position
		local now = os.clock()
		for part, phase in phases do
			if not part.Parent then
				phases[part] = nil
				continue
			end
			local base = part:GetAttribute("BasePos")
			local yaw = part:GetAttribute("BaseYaw")
			if typeof(base) ~= "Vector3" or type(yaw) ~= "number" then
				continue
			end
			if (base - origin).Magnitude > VIEW_DISTANCE then
				continue
			end
			local bob = math.sin(now * BOB_SPEED + phase) * BOB_HEIGHT
			part.CFrame = CFrame.new(base + Vector3.new(0, bob, 0))
				* CFrame.Angles(0, yaw + now * SPIN_SPEED, math.rad(8))
		end
	end)
end

return CartridgeAnimator
