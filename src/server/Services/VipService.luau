--!strict
-- VIP-статус для владельцев геймпасса «VIP-офис» (Config/Social.vip), виден всем:
--   * атрибут игрока IsVip (чат-тег «[👑 VIP]» и 👑 в списках ставит клиент, SocialController);
--   * табличка «👑 VIP» над головой (BillboardGui, дальше tagMaxDistance не видно);
--   * золотая вывеска над воротами: рамка, 👑 перед названием, искры (StartParkService зовёт
--     decorateSign после каждой перестройки вывески);
--   * золотое кресло: Highlight + неоновое кольцо под креслом, детали рамы по именам — в золото.
-- Модели Астры (docs/VISUAL.md, V14) необязательны: VipSignFrame / VipChair в ServerStorage
-- (или ServerStorage.Upgrades) — если есть, ставятся поверх.
-- Бонус к оценке и табличка над участком остаются как были (DevelopmentService, PerksService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local Social = require(Shared.Config.Social)
local Images = require(Shared.Config.Images)
local PlotService = require(script.Parent.PlotService)
local ShopService = require(script.Parent.ShopService)
local StartParkService = require(script.Parent.StartParkService)

local TAG_NAME = "VipTag"
local TRIM_NAME = "VipTrim" -- папка золотых добавок в кресле
local GOLD_ATTR = "VipGold"
local HEAD_WAIT = 10
-- Части кресла, которые красим в золото (по имени, без учёта регистра)
local GOLD_PATTERNS =
	{ "frame", "leg", "arm", "base", "trim", "wheel", "metal", "stand", "pole", "star", "caster" }

local VipService = {}
local status: { [Player]: boolean } = {}

local function gold(): Color3
	return Social.vip.color
end

-- Модель Астры: ServerStorage[name] или ServerStorage.Upgrades[name]
local function template(name: string): Model?
	local found = ServerStorage:FindFirstChild(name)
	if not found then
		local upgrades = ServerStorage:FindFirstChild("Upgrades")
		found = upgrades and upgrades:FindFirstChild(name)
	end
	return if found and found:IsA("Model") then found else nil
end

local function decorPart(parent: Instance, name: string, size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = size
	part.CFrame = cframe
	part.Color = gold()
	part.Material = Enum.Material.Neon
	part.Parent = parent
	return part
end

-- Чужая модель поверх: неподвижная и «бестелесная», чтобы не мешать ходить и садиться
local function overlay(source: Model, pivot: CFrame, parent: Instance)
	local clone = source:Clone()
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Seat") or d:IsA("Script") then
			d:Destroy()
		end
	end
	clone:PivotTo(pivot)
	clone.Parent = parent
end

-- ===== Вывеска =====

local function decorateSign(player: Player, model: Model, board: BasePart)
	if not status[player] then
		return
	end
	local size = board.Size
	-- Боковые неоновые планки: верх и низ уже золотые — рамка замыкается
	for _, x in { size.X / 2 + 0.1, -size.X / 2 - 0.1 } do
		decorPart(model, "VipFrame", Vector3.new(0.2, size.Y + 0.4, 0.5), board.CFrame * CFrame.new(x, 0, 0))
	end
	board.Color = Color3.fromRGB(58, 40, 8)
	for _, d in model:GetDescendants() do
		if d:IsA("TextLabel") and d.Name == "StudioName" then
			d.Text = "👑 " .. d.Text
		end
	end
	local frame = template("VipSignFrame")
	if frame then
		overlay(frame, board.CFrame, model)
	end
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "VipSparkle"
	if Images.vip > 0 then
		sparkle.Texture = "rbxassetid://" .. Images.vip
	end
	sparkle.Color = ColorSequence.new(gold())
	sparkle.LightEmission = 1
	sparkle.Rate = 3
	sparkle.Lifetime = NumberRange.new(1, 1.6)
	sparkle.Speed = NumberRange.new(0.3, 0.8)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Parent = board
end

-- ===== Табличка над головой =====

local function setTag(player: Player, on: boolean)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local existing = head:FindFirstChild(TAG_NAME)
	if not on then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = TAG_NAME
	gui.Adornee = head
	gui.Size = UDim2.fromScale(4, 1) -- в studs: издалека табличка меньше
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.MaxDistance = Social.vip.tagMaxDistance
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = gold()
	label.TextStrokeColor3 = Color3.fromRGB(70, 45, 0)
	label.TextStrokeTransparency = 0.2
	label.Text = "👑 VIP"
	label.Parent = gui
	gui.Parent = head
end

local function onCharacterAdded(player: Player, character: Model)
	task.spawn(function()
		character:WaitForChild("Head", HEAD_WAIT)
		if status[player] then
			setTag(player, true)
		end
	end)
end

-- ===== Кресло =====

local function goldName(name: string): boolean
	local lower = string.lower(name)
	for _, pattern in GOLD_PATTERNS do
		if string.find(lower, pattern, 1, true) then
			return true
		end
	end
	return false
end

local function goldChair(player: Player, on: boolean)
	local plot = PlotService.getPlot(player)
	local chair = plot and plot:FindFirstChild("Chair")
	if not chair or not chair:IsA("Model") or (chair:GetAttribute(GOLD_ATTR) == true) == on then
		return
	end
	chair:SetAttribute(GOLD_ATTR, on)
	local old = chair:FindFirstChild(TRIM_NAME)
	if old then
		old:Destroy()
	end
	-- Детали рамы: золото или исходный цвет (запомнен в атрибутах)
	for _, d in chair:GetDescendants() do
		if not d:IsA("BasePart") or d:IsA("Seat") then
			continue
		end
		if on and goldName(d.Name) then
			d:SetAttribute("VipColor", d.Color)
			d:SetAttribute("VipMaterial", d.Material.Name)
			d.Color = gold()
			d.Material = Enum.Material.Metal
		elseif not on and d:GetAttribute("VipColor") ~= nil then
			local color = d:GetAttribute("VipColor")
			local material = d:GetAttribute("VipMaterial")
			if typeof(color) == "Color3" then
				d.Color = color
			end
			if type(material) == "string" then
				pcall(function()
					d.Material = (Enum.Material :: any)[material]
				end)
			end
			d:SetAttribute("VipColor", nil)
			d:SetAttribute("VipMaterial", nil)
		end
	end
	if not on then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = TRIM_NAME
	local custom = template("VipChair")
	if custom then
		overlay(custom, chair:GetPivot(), folder)
	end
	-- Подсветка видна и у импортированных мешей с текстурой (их цвет не перекрасить)
	local highlight = Instance.new("Highlight")
	highlight.Adornee = chair
	highlight.FillColor = gold()
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = gold()
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = folder
	-- Неоновое кольцо на полу под креслом
	local cframe, size = chair:GetBoundingBox()
	local diameter = math.max(size.X, size.Z) + 0.6
	local ring = decorPart(
		folder,
		"VipRing",
		Vector3.new(0.1, diameter, diameter),
		cframe * CFrame.new(0, -size.Y / 2 + 0.06, 0) * CFrame.Angles(0, 0, math.rad(90))
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.35
	local light = Instance.new("PointLight")
	light.Color = gold()
	light.Range = 8
	light.Brightness = 0.8
	light.Parent = ring
	folder.Parent = chair
end

-- ===== Статус =====

local function refresh(player: Player)
	local vip = ShopService.ownsPass(player, "vipOffice")
	if status[player] ~= vip then
		status[player] = vip
		player:SetAttribute("IsVip", vip)
		setTag(player, vip)
		StartParkService.refreshSigns(player)
	end
	-- Кресло могли купить позже: проверка дешёвая
	goldChair(player, vip)
end

function VipService.isVip(player: Player): boolean
	return status[player] == true
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	refresh(player)
end

function VipService.start()
	StartParkService.decorateSign = decorateSign
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		status[player] = nil
	end)
	-- Участок пересобран: кресло новое (вывеску украсит StartParkService через decorateSign)
	PlotService.plotChanged:Connect(function(player: Player)
		goldChair(player, status[player] == true)
	end)
	task.spawn(function()
		while true do
			task.wait(Social.vip.checkSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(refresh, player)
				if not ok then
					warn("[VipService] refresh failed:", err)
				end
			end
		end
	end)
end

return VipService
