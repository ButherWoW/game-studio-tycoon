--!strict
-- Стример (волна 2, Config/Console.streamer): одного нанятого сотрудника за столом можно
-- назначить стримером (с офиса). Его стол не даёт очков, перков и прибавки к оценке
-- (StaffService.active его пропускает, DevelopmentService.pointsRate — его стол), зато:
--   • донаты каждые tickSeconds: доход в минуту × donationShare × слава × хайп;
--   • хайп растёт со временем и от игр 7+, релиз тратит хайп и даёт до +30% дохода (consumeHype);
--   • над NPC реплики чата, перед ним кольцевая лампа и камера.
-- Данные: profile.streamer = { employeeId?, hype, earned, scores } (scores — оценки последних игр).
-- Стример снимается сам, если сотрудника уволили или он остался без стола (переезд, Rebirth).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Console = require(Shared.Config.Console)
local Debug = require(Shared.Config.Debug)
local ConsoleRemotes = require(Shared.ConsoleRemotes)
local DataService = require(script.Parent.DataService)
local StaffService = require(script.Parent.StaffService)

type Data = { employeeId: string?, hype: number, earned: number, scores: { number } }

local cfg = Console.streamer
local ASSIGN_COOLDOWN = 1
local VISUAL_TICK = 1
local PROPS_PREFIX = "StreamProps_"
-- Только Studio: хайп и донаты идут в streamerSpeed раз быстрее
local speed = if RunService:IsStudio() then math.max(tonumber((Debug :: any).streamerSpeed) or 1, 1) else 1

local StreamerService = {}
local lastAssign: { [Player]: number } = {}
local nextBubble: { [Player]: number } = {}
local rng = Random.new()

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

local function num(value: any, default: number): number
	local n = tonumber(value)
	return if n and n == n and n > -math.huge and n < math.huge then n else default
end

local function data(profile: DataService.Profile): Data
	local raw = (profile :: any).streamer
	if type(raw) ~= "table" then
		raw = {}
	end
	local scores = {}
	if type(raw.scores) == "table" then
		for _, score in raw.scores do
			if type(score) == "number" and score == score then
				table.insert(scores, math.clamp(score, 1, 10))
			end
		end
	end
	while #scores > cfg.fameGames do
		table.remove(scores, 1)
	end
	local fixed: Data = {
		employeeId = if type(raw.employeeId) == "string" then raw.employeeId else nil,
		hype = math.clamp(num(raw.hype, 0), 0, cfg.hypeMax),
		earned = math.max(num(raw.earned, 0), 0),
		scores = scores,
	};
	(profile :: any).streamer = fixed
	return fixed
end

local function pushState(player: Player)
	local console = optional("ConsoleService")
	if console then
		pcall(console.pushState, player)
	end
end

local function logEvent(player: Player, value: number, field: string)
	local analytics = optional("AnalyticsService")
	if analytics and type(analytics.logLiveOps) == "function" then
		pcall(analytics.logLiveOps, player, "streamer", value, field)
	end
end

-- Стример сидит за столом и студия не ниже офиса; иначе — снят
local function validStreamer(profile: DataService.Profile, d: Data): string?
	local id = d.employeeId
	if not id then
		return nil
	end
	local desk = StaffService.hired(profile)[id]
	if profile.studioLevel < cfg.minStudioLevel or type(desk) ~= "string" or desk == "" then
		d.employeeId = nil
		return nil
	end
	return id
end

-- Стримит прямо сейчас: назначен и команда не бастует (нечем платить зарплаты)
local function streaming(profile: DataService.Profile, d: Data): boolean
	return validStreamer(profile, d) ~= nil and (profile :: any).staffStrike ~= true
end

-- Слава студии: средняя оценка последних игр / fameScore
local function fame(profile: DataService.Profile, d: Data): number
	local total = 0
	for _, score in d.scores do
		total += score
	end
	local average = if #d.scores > 0 then total / #d.scores else math.max(profile.runBestScore, 1)
	return math.clamp(average / cfg.fameScore, cfg.fameMin, cfg.fameMax)
end

local function perMinute(player: Player, profile: DataService.Profile, d: Data): number
	if not streaming(profile, d) then
		return 0
	end
	local console = optional("ConsoleService")
	local income = if console then console.incomePerMinute(player, profile) else 0
	local hype = cfg.hypeFloor + (1 - cfg.hypeFloor) * d.hype / cfg.hypeMax
	return math.floor(income * cfg.donationShare * fame(profile, d) * hype)
end

-- Для ConsoleService.pushState: часть состояния окна
function StreamerService.stateFor(player: Player, profile: DataService.Profile): any
	local d = data(profile)
	return {
		allowed = profile.studioLevel >= cfg.minStudioLevel,
		employeeId = validStreamer(profile, d),
		hype = math.floor(d.hype),
		perMinute = perMinute(player, profile, d),
		earned = math.floor(d.earned),
		hypeBonus = math.floor(cfg.hypeMaxBonus * d.hype / cfg.hypeMax * 100),
		strike = (profile :: any).staffStrike == true,
	}
end

-- Стол стримера (для DevelopmentService.pointsRate): очков не даёт
function StreamerService.deskOf(player: Player): string?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local id = validStreamer(profile, data(profile))
	return if id then StaffService.hired(profile)[id] else nil
end

-- Хук релиза: множитель дохода от хайпа, хайп тратится. 1 — стримера нет или хайпа нет
local lastBonus: { [Player]: number } = {}
function StreamerService.consumeHype(player: Player): number
	local profile = DataService.get(player)
	if not profile then
		return 1
	end
	local d = data(profile)
	if not streaming(profile, d) or d.hype <= 0 then
		return 1
	end
	local bonus = cfg.hypeMaxBonus * d.hype / cfg.hypeMax
	d.hype = math.max(d.hype - cfg.hypeSpend, 0)
	lastBonus[player] = bonus
	return 1 + bonus
end

-- Хук DevelopmentService после релиза: { score }
function StreamerService.onGameReleased(player: Player, info: any)
	local profile = DataService.get(player)
	if not profile or type(info) ~= "table" then
		return
	end
	local d = data(profile)
	local score = num(info.score, 0)
	table.insert(d.scores, math.clamp(score, 1, 10))
	while #d.scores > cfg.fameGames do
		table.remove(d.scores, 1)
	end
	if streaming(profile, d) and score >= cfg.hypeHitScore then
		d.hype = math.min(d.hype + cfg.hypePerHit, cfg.hypeMax)
	end
	local bonus = lastBonus[player]
	lastBonus[player] = nil
	if bonus and bonus > 0 then
		ConsoleRemotes.ConsoleNotice:FireClient(player, { kind = "hype", percent = math.floor(bonus * 100) })
	end
	pushState(player)
end

-- ===== Реквизит и чат над NPC =====

local function npcOf(player: Player, employeeId: string): (Folder?, Model?)
	local folder = StaffService.npcFolder(player)
	local npc = folder and folder:FindFirstChild("Staff_" .. employeeId)
	return folder, if npc and npc:IsA("Model") then npc else nil
end

local function part(
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Кольцевая лампа сбоку-спереди и камера на штативе с другой стороны: обе смотрят на NPC
local function buildProps(folder: Folder, npc: Model, employeeId: string)
	local model = Instance.new("Model")
	model.Name = PROPS_PREFIX .. employeeId
	local pivot = npc:GetPivot()
	local face = pivot.Position + Vector3.new(0, 1.5, 0)
	local lightPos = (pivot * CFrame.new(1.8, 1.5, -1.8)).Position
	-- Цилиндр смотрит осью X: поворачиваем, чтобы диск «глядел» на лицо
	local lightFrame = CFrame.lookAt(lightPos, face) * CFrame.Angles(0, math.rad(90), 0)
	local ring = part(
		model,
		Vector3.new(0.12, 1.6, 1.6),
		lightFrame,
		Color3.fromRGB(255, 250, 235),
		Enum.PartType.Cylinder
	)
	ring.Material = Enum.Material.Neon
	part(model, Vector3.new(0.14, 1.1, 1.1), lightFrame, Color3.fromRGB(40, 40, 48), Enum.PartType.Cylinder)
	local light = Instance.new("PointLight")
	light.Brightness = 1.2
	light.Range = 8
	light.Color = Color3.fromRGB(255, 245, 230)
	light.Parent = ring
	part(
		model,
		Vector3.new(0.15, 3.2, 0.15),
		CFrame.new(lightPos - Vector3.new(0, 2.4, 0)),
		Color3.fromRGB(30, 30, 36)
	)
	-- Камера на штативе
	local camPos = (pivot * CFrame.new(-1.8, 1.4, -1.8)).Position
	local camFrame = CFrame.lookAt(camPos, face)
	part(model, Vector3.new(0.7, 0.5, 0.9), camFrame, Color3.fromRGB(25, 25, 30))
	part(
		model,
		Vector3.new(0.3, 0.4, 0.4),
		camFrame * CFrame.new(0, 0, -0.55) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(60, 120, 200),
		Enum.PartType.Cylinder
	)
	local dot = part(
		model,
		Vector3.new(0.12, 0.12, 0.12),
		camFrame * CFrame.new(0.25, 0.3, 0),
		Color3.fromRGB(230, 40, 40),
		Enum.PartType.Ball
	)
	dot.Material = Enum.Material.Neon
	part(
		model,
		Vector3.new(0.12, 3, 0.12),
		CFrame.new(camPos - Vector3.new(0, 1.8, 0)),
		Color3.fromRGB(30, 30, 36)
	)
	model.Parent = folder
end

local function clearProps(player: Player, keep: string?)
	local folder = StaffService.npcFolder(player)
	if not folder then
		return
	end
	for _, child in folder:GetChildren() do
		if
			child.Name:sub(1, #PROPS_PREFIX) == PROPS_PREFIX
			and child.Name ~= (if keep then PROPS_PREFIX .. keep else nil)
		then
			child:Destroy()
		end
	end
end

local function showBubble(npc: Model)
	local head = npc:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StreamChat"
	billboard.Size = UDim2.fromOffset(150, 40)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.MaxDistance = 60
	billboard.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(145, 70, 255)
	label.BackgroundTransparency = 0.1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = cfg.bubbles[rng:NextInteger(1, #cfg.bubbles)]
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	label.Parent = billboard
	billboard.Parent = head
	Debris:AddItem(billboard, cfg.bubbleSeconds)
end

local function visuals(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local d = data(profile)
	local id = if streaming(profile, d) then d.employeeId else nil
	clearProps(player, id)
	if not id then
		return
	end
	local folder, npc = npcOf(player, id)
	if not folder or not npc then
		return
	end
	if not folder:FindFirstChild(PROPS_PREFIX .. id) then
		buildProps(folder, npc, id)
	end
	local now = os.clock()
	if now >= (nextBubble[player] or 0) then
		nextBubble[player] = now + rng:NextNumber(cfg.bubbleMin, cfg.bubbleMax) / speed
		showBubble(npc)
	end
end

-- Донаты и рост хайпа
local function economyTick(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local d = data(profile)
	if not streaming(profile, d) then
		return
	end
	local minutes = cfg.tickSeconds / 60 * speed
	local amount = math.floor(perMinute(player, profile, d) * minutes)
	d.hype = math.min(d.hype + cfg.hypePerMinute * minutes, cfg.hypeMax)
	if amount > 0 then
		DataService.addCash(player, amount)
		d.earned += amount
	end
	pushState(player)
end

local function onAssign(player: Player, employeeId: any)
	local now = os.clock()
	if (lastAssign[player] or 0) + ASSIGN_COOLDOWN > now then
		return
	end
	lastAssign[player] = now
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local d = data(profile)
	local before = validStreamer(profile, d)
	if employeeId == false or employeeId == nil then
		d.employeeId = nil
	elseif type(employeeId) == "string" then
		local desk = StaffService.hired(profile)[employeeId]
		if profile.studioLevel < cfg.minStudioLevel or type(desk) ~= "string" or desk == "" then
			return
		end
		d.employeeId = employeeId
	else
		return
	end
	if before == d.employeeId then
		return
	end
	if before then
		logEvent(player, math.floor(d.earned), "unassigned")
	end
	if d.employeeId then
		logEvent(player, 1, "assigned")
	end
	-- Команда поменялась: мощность и прибавка к оценке без стримера
	StaffService.refreshStaff(player)
	StaffService.refreshPower(player)
	visuals(player)
	pushState(player)
end

function StreamerService.start()
	ConsoleRemotes.StreamerAssign.OnServerEvent:Connect(onAssign)
	Players.PlayerRemoving:Connect(function(player)
		lastAssign[player] = nil
		nextBubble[player] = nil
		lastBonus[player] = nil
	end)
	task.spawn(function()
		local elapsed = 0
		while true do
			task.wait(VISUAL_TICK)
			elapsed += VISUAL_TICK
			local economy = elapsed >= cfg.tickSeconds
			if economy then
				elapsed = 0
			end
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(visuals, player)
				if ok and economy then
					ok, err = pcall(economyTick, player)
				end
				if not ok then
					warn("[StreamerService] Tick failed for", player.Name, err)
				end
			end
		end
	end)
end

return StreamerService
