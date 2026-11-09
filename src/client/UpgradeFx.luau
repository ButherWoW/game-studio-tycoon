--!strict
-- Эффект «улучшения здания» (владелец 07.11: «анимация при улучшении здания»): когда студия переехала на
-- новый этап (офис, 2-й или 3-й этаж, MoveCelebration.celebrate), над участком вспыхивает золотой столб света,
-- расходится кольцо на высоте нового этажа, у основания поднимается пыль, над крышей взрываются искры и
-- конфетти. Всё строится на клиенте из деталей и частиц, ничего не реплицируется. Текстуры: уже загруженные
-- Images.fx (искра, дым, конфетти), а когда Астра сдаст V38 (Images.upgradeFx: искра, пыль, конфетти, луч,
-- кольцо) — они подхватываются автоматически. «Меньше эффектов» (атрибут LowGraphics) — без эффекта.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Images = require(ReplicatedStorage.Shared.Config.Images)
local StudioLayout = require(ReplicatedStorage.Shared.StudioLayout)

local GOLD = Color3.fromRGB(255, 210, 90)
local RAY_HEIGHT = 70
local FX_SECONDS = 3

local UpgradeFx = {}

local function texture(id: number, fallback: number): string?
	local value = if id > 0 then id elseif fallback > 0 then fallback else 0
	return if value > 0 then "rbxassetid://" .. value else nil
end

local function ownPlot(): BasePart?
	local name = Players.LocalPlayer:GetAttribute("PlotName")
	local plots = workspace:FindFirstChild("Plots")
	local plot = if type(name) == "string" and plots then plots:FindFirstChild(name) else nil
	return if plot and plot:IsA("BasePart") then plot else nil
end

local function part(parent: Instance, size: Vector3, cframe: CFrame, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = GOLD
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cframe
	p.Parent = parent
	return p
end

local function emitter(
	parent: Instance,
	image: string?,
	count: number,
	speed: NumberRange,
	size: NumberSequence,
	color: Color3?
)
	if not image then
		return
	end
	local e = Instance.new("ParticleEmitter")
	e.Texture = image
	e.Rate = 0
	e.Lifetime = NumberRange.new(1.2, 2.2)
	e.Speed = speed
	e.SpreadAngle = Vector2.new(60, 60)
	e.Acceleration = Vector3.new(0, -12, 0)
	e.Drag = 1.2
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Size = size
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.LightEmission = 0.6
	if color then
		e.Color = ColorSequence.new(color)
	end
	e.Parent = parent
	e:Emit(count)
end

-- Эффект при переезде на этап level (studioLevel 2..4); участок игрока, если он есть на карте
function UpgradeFx.play(level: number)
	if Players.LocalPlayer:GetAttribute("LowGraphics") == true then
		return
	end
	local plot = ownPlot()
	if not plot then
		return
	end
	local fx = Images.upgradeFx
	local floors = StudioLayout.floorsUnlocked(level)
	local top = plot.Size.Y / 2 + StudioLayout.floorY(math.max(floors, 1)) + StudioLayout.FLOOR_HEIGHT
	local base = plot.CFrame * CFrame.new(0, plot.Size.Y / 2, 0)
	local roof = plot.CFrame * CFrame.new(0, top, 0)
	local folder = Instance.new("Folder")
	folder.Name = "UpgradeFx"
	folder.Parent = workspace

	-- Столб света над зданием: растёт и гаснет
	local ray =
		part(folder, Vector3.new(2, 1, 2), roof * CFrame.new(0, RAY_HEIGHT / 2, 0), Enum.PartType.Cylinder)
	ray.CFrame = ray.CFrame * CFrame.Angles(0, 0, math.rad(90))
	ray.Size = Vector3.new(RAY_HEIGHT, 6, 6)
	ray.Transparency = 0.35
	TweenService:Create(ray, TweenInfo.new(FX_SECONDS, Enum.EasingStyle.Quad), {
		Size = Vector3.new(RAY_HEIGHT, 22, 22),
		Transparency = 1,
	}):Play()

	-- Кольцо на высоте нового этажа: расходится и гаснет
	local ringHeight = plot.Size.Y / 2 + StudioLayout.floorY(math.max(floors, 1)) + 0.5
	local ring = part(
		folder,
		Vector3.new(0.4, 8, 8),
		plot.CFrame * CFrame.new(0, ringHeight, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Enum.PartType.Cylinder
	)
	ring.Transparency = 0.2
	TweenService:Create(ring, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, plot.Size.X * 1.4, plot.Size.X * 1.4),
		Transparency = 1,
	}):Play()

	-- Пыль у основания и искры с конфетти над крышей
	local dustAnchor = part(folder, Vector3.new(1, 1, 1), base, nil)
	dustAnchor.Transparency = 1
	local dustAttachment = Instance.new("Attachment")
	dustAttachment.Parent = dustAnchor
	emitter(
		dustAttachment,
		texture(fx.dust, Images.fx.smoke),
		40,
		NumberRange.new(10, 22),
		NumberSequence.new(3, 7),
		Color3.fromRGB(230, 220, 200)
	)
	local sparkAnchor = part(folder, Vector3.new(1, 1, 1), roof * CFrame.new(0, 4, 0), nil)
	sparkAnchor.Transparency = 1
	local sparkAttachment = Instance.new("Attachment")
	sparkAttachment.Parent = sparkAnchor
	emitter(
		sparkAttachment,
		texture(fx.sparkle, Images.fx.sparkle),
		50,
		NumberRange.new(14, 26),
		NumberSequence.new(1.2, 0.4),
		GOLD
	)
	emitter(
		sparkAttachment,
		texture(fx.confetti, Images.fx.confetti1),
		40,
		NumberRange.new(10, 20),
		NumberSequence.new(1.4, 0.8),
		nil
	)
	emitter(
		sparkAttachment,
		texture(0, Images.fx.confetti2),
		40,
		NumberRange.new(10, 20),
		NumberSequence.new(1.4, 0.8),
		nil
	)

	task.delay(FX_SECONDS + 1, function()
		folder:Destroy()
	end)
end

return UpgradeFx
