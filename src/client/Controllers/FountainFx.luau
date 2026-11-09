--!strict
-- Вода фонтана парка (владелец 09.11: «паршиво выглядит, нужна нормальная анимация воды»).
-- Модель Астры (Fountain) статична: 30 неподвижных «капель» WaterCascade, плоская вода. Здесь, на клиенте,
-- капли прячем и оживляем: фонтан бьёт вверх, с чаш стекают брызги, на воде расходятся круги, поверхность
-- переливается. Всё локально (ничего не реплицируется), дальше VIEW_DISTANCE от камеры эффекты выключены.
-- Текстуры частиц — встроенные в Roblox (rbxasset), загрузка не нужна.

local RunService = game:GetService("RunService")

local VIEW_DISTANCE = 150
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local WATER_LIGHT = Color3.fromRGB(205, 240, 250)
local WATER_BLUE = Color3.fromRGB(120, 200, 225)
local RIPPLE_COUNT = 4
local RIPPLE_SECONDS = 3.2

type Setup = {
	model: Model,
	waters: { BasePart },
	baseColors: { [BasePart]: Color3 },
	emitters: { ParticleEmitter },
	rings: { BasePart },
	active: boolean,
}

local FountainFx = {}
local setups: { [Model]: Setup } = {}

local function part(model: Model, name: string): BasePart?
	local item = model:FindFirstChild(name, true)
	return if item and item:IsA("BasePart") then item else nil
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK
	e.LightEmission = 0.35
	e.LockedToPart = false
	e.Rotation = NumberRange.new(0, 360)
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

-- Брызги с края чаши: цилиндрическая эмиссия наружу, дальше гравитация
local function bowlSpray(bowl: BasePart, rate: number, speed: number): ParticleEmitter
	return emitter(bowl, {
		Shape = Enum.ParticleEmitterShape.Cylinder,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		Rate = rate,
		Lifetime = NumberRange.new(0.7, 1.1),
		Speed = NumberRange.new(speed * 0.6, speed),
		SpreadAngle = Vector2.new(15, 15),
		Acceleration = Vector3.new(0, -38, 0),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0.15),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.7, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(WATER_LIGHT, WATER_BLUE),
	})
end

local function build(model: Model): Setup?
	local jetTop = part(model, "JetTop") or part(model, "Jet")
	if not jetTop then
		return nil
	end
	local setup: Setup = {
		model = model,
		waters = {},
		baseColors = {},
		emitters = {},
		rings = {},
		active = true,
	}
	-- Неподвижные «капли» убираем: их заменяют частицы
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") and item.Name == "WaterCascade" then
			item.Transparency = 1
		end
	end
	for _, name in { "BasinWater", "LowerWater", "UpperWater" } do
		local water = part(model, name)
		if water then
			table.insert(setup.waters, water)
			setup.baseColors[water] = water.Color
		end
	end
	-- Центральная струя: бьёт вверх, веером падает обратно
	local top = Instance.new("Attachment")
	top.Name = "FountainJet"
	top.WorldPosition = jetTop.Position + Vector3.new(0, jetTop.Size.Y / 2, 0)
	top.Parent = jetTop
	table.insert(
		setup.emitters,
		emitter(top, {
			Rate = 110,
			Lifetime = NumberRange.new(1.1, 1.6),
			Speed = NumberRange.new(20, 26),
			SpreadAngle = Vector2.new(9, 9),
			Acceleration = Vector3.new(0, -42, 0),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(1, 0.2),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(0.8, 0.4),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Color = ColorSequence.new(Color3.new(1, 1, 1), WATER_BLUE),
		})
	)
	-- Лёгкий туман над струёй
	table.insert(
		setup.emitters,
		emitter(top, {
			Texture = SMOKE,
			LightEmission = 0.1,
			Rate = 6,
			Lifetime = NumberRange.new(1.5, 2.2),
			Speed = NumberRange.new(2, 4),
			SpreadAngle = Vector2.new(30, 30),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1.2),
				NumberSequenceKeypoint.new(1, 3),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.85),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Color = ColorSequence.new(Color3.new(1, 1, 1)),
		})
	)
	-- Стекание с чаш
	local upper = part(model, "UpperBowl")
	if upper then
		table.insert(setup.emitters, bowlSpray(upper, 45, 5))
	end
	local lower = part(model, "LowerBowl")
	if lower then
		table.insert(setup.emitters, bowlSpray(lower, 70, 6))
	end
	-- Круги на воде большого бассейна вокруг пьедестала
	local basin = part(model, "BasinWater")
	if basin then
		local maxRadius = math.min(basin.Size.X, basin.Size.Z) / 2 * 0.9
		for i = 1, RIPPLE_COUNT do
			local ring = Instance.new("Part")
			ring.Name = "FountainRipple"
			ring.Shape = Enum.PartType.Cylinder
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.CanTouch = false
			ring.CastShadow = false
			ring.Material = Enum.Material.SmoothPlastic
			ring.Color = Color3.new(1, 1, 1)
			ring.Transparency = 1
			ring.Size = Vector3.new(0.05, 1, 1)
			ring.CFrame = CFrame.new(basin.Position + Vector3.new(0, basin.Size.Y / 2 + 0.06, 0))
				* CFrame.Angles(0, 0, math.rad(90))
			ring:SetAttribute("Phase", (i - 1) / RIPPLE_COUNT)
			ring:SetAttribute("MaxRadius", maxRadius)
			ring.Parent = model
			table.insert(setup.rings, ring)
		end
	end
	return setup
end

local function setActive(setup: Setup, on: boolean)
	if setup.active == on then
		return
	end
	setup.active = on
	for _, e in setup.emitters do
		e.Enabled = on
	end
end

local function track(item: Instance)
	if item:IsA("Model") and item.Name == "Fountain" and setups[item] == nil then
		local setup = build(item)
		if setup then
			setups[item] = setup
		end
	end
end

function FountainFx.start()
	for _, item in workspace:GetDescendants() do
		track(item)
	end
	workspace.DescendantAdded:Connect(track)
	local clock = 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		for model, setup in setups do
			if not model.Parent then
				setups[model] = nil
				continue
			end
			local near = (model:GetPivot().Position - camera.CFrame.Position).Magnitude <= VIEW_DISTANCE
			setActive(setup, near)
			if not near then
				continue
			end
			-- Поверхность воды переливается: цвет чуть плывёт между базовым и более светлым
			for index, water in setup.waters do
				local wave = (math.sin(clock * 1.3 + index) + 1) / 2
				water.Color = (setup.baseColors[water] :: Color3):Lerp(WATER_LIGHT, wave * 0.18)
			end
			-- Круги: растут от пьедестала к краю, бледнеют
			for _, ring in setup.rings do
				local phase = ((clock / RIPPLE_SECONDS) + (ring:GetAttribute("Phase") :: number)) % 1
				local maxRadius = ring:GetAttribute("MaxRadius") :: number
				local diameter = math.max(1, (0.25 + phase * 0.75) * maxRadius * 2)
				ring.Size = Vector3.new(0.05, diameter, diameter)
				ring.Transparency = 0.55 + phase * 0.45
			end
		end
	end)
end

return FountainFx
