--!strict
-- «Инди в парке»: доска заказов (мини-игры), ретро-картриджи и ломбард у спавна,
-- а ещё название студии после покупки гаража (вывеска на постерах и табличка у входа).
-- Парк строит WorldService (папка workspace.StartPark), здесь — поведение.
-- Данные: (profile :: any).cartridges, .jobReadyAt { [jobId]: os.time() }, .studioName.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local StartPark = require(ReplicatedStorage.Shared.Config.StartPark)
local StartRemotes = require(ReplicatedStorage.Shared.StartRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local PROFILE_WAIT = 0.2
local REQUEST_COOLDOWN = 0.3 -- секунд между запросами заказов одного игрока
local NAME_COOLDOWN = 1
local PROMPT_DISTANCE = 10
local PICKUP_DISTANCE = 14 -- запас к PROMPT_DISTANCE на лаги
local EARLY_TOLERANCE = 1 -- результат раньше jobDuration минус это — враньё клиента

type ActiveJob = { id: string, startedAt: number }

local StartParkService = {}
local activeJobs: { [Player]: ActiveJob } = {}
local lastRequest: { [Player]: number } = {}
local lastNameRequest: { [Player]: number } = {}
local naming: { [Player]: boolean } = {}

local jobsById: { [string]: StartPark.Job } = {}
for _, job in StartPark.jobs do
	jobsById[job.id] = job
end

local function park(): Instance?
	return workspace:FindFirstChild("StartPark")
end

local function rootPart(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isSeated(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

local function near(player: Player, target: BasePart, distance: number): boolean
	local root = rootPart(player)
	return root ~= nil and (root.Position - target.Position).Magnitude <= distance
end

-- Деталь модели парка для ProximityPrompt (JobBoard.Board, Pawnshop.Counter)
local function promptPart(modelName: string, partName: string): BasePart?
	local folder = park()
	local model = folder and folder:FindFirstChild(modelName)
	local p = model
		and (model:FindFirstChild(partName, true) or model:FindFirstChildWhichIsA("BasePart", true))
	return if p and p:IsA("BasePart") then p else nil
end

-- Текст подсказки по-русски; клиент переводит по атрибутам ActionKey/ObjectKey
local function makePrompt(
	parent: BasePart,
	action: string,
	actionKey: string,
	object: string,
	objectKey: string
)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("ActionKey", actionKey)
	prompt:SetAttribute("ObjectKey", objectKey)
	prompt.Parent = parent
	return prompt
end

-- ===== Профиль =====

local function cartridgesOf(profile: DataService.Profile): number
	local p = profile :: any
	local count = tonumber(p.cartridges)
	if not count or count ~= count or count < 0 then
		count = 0
	end
	p.cartridges = math.floor(count :: number)
	return p.cartridges
end

local function jobReadyAt(profile: DataService.Profile): { [string]: number }
	local p = profile :: any
	if type(p.jobReadyAt) ~= "table" then
		p.jobReadyAt = {}
	end
	return p.jobReadyAt
end

local function studioNameOf(player: Player, profile: DataService.Profile): string
	local name = (profile :: any).studioName
	return if type(name) == "string" and name ~= "" then name else "Studio " .. player.DisplayName
end

local function hasStudioName(profile: DataService.Profile): boolean
	local name = (profile :: any).studioName
	return type(name) == "string" and name ~= ""
end

-- ===== Доска заказов =====

local board: BasePart? = nil

local function jobBoardState(profile: DataService.Profile): { [string]: number }
	local readyAt = jobReadyAt(profile)
	local now = os.time()
	local state = {}
	for _, job in StartPark.jobs do
		state[job.id] = math.max((tonumber(readyAt[job.id]) or 0) - now, 0)
	end
	return state
end

local function onBoardTriggered(player: Player)
	local profile = DataService.get(player)
	if profile then
		StartRemotes.JobBoardOpen:FireClient(player, jobBoardState(profile))
	end
end

local function rateLimited(player: Player): boolean
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return true
	end
	lastRequest[player] = now
	return false
end

-- Заказ без результата дольше срока — снимаем, перезарядка всё равно идёт
local function dropExpired(player: Player, profile: DataService.Profile)
	local active = activeJobs[player]
	if active and os.clock() - active.startedAt > StartPark.jobDuration + StartPark.jobGrace then
		activeJobs[player] = nil
		jobReadyAt(profile)[active.id] = os.time() + StartPark.jobCooldown
	end
end

local function onJobStart(player: Player, jobId: any)
	if rateLimited(player) or type(jobId) ~= "string" or not jobsById[jobId] then
		return
	end
	local profile = DataService.get(player)
	if not profile or not board then
		return
	end
	dropExpired(player, profile)
	if activeJobs[player] then
		return
	end
	if (tonumber(jobReadyAt(profile)[jobId]) or 0) > os.time() then
		return
	end
	-- Заказ берут у доски и стоя: за ноутбуком параллельно не поработаешь
	if isSeated(player) or not near(player, board :: BasePart, StartPark.jobMaxDistance) then
		return
	end
	activeJobs[player] = { id = jobId, startedAt = os.clock() }
	StartRemotes.JobStarted:FireClient(player, { id = jobId, duration = StartPark.jobDuration })
end

local function onJobFinish(player: Player, jobId: any, rawScore: any)
	if rateLimited(player) or type(jobId) ~= "string" then
		return
	end
	local active = activeJobs[player]
	local profile = DataService.get(player)
	if not active or active.id ~= jobId or not profile then
		return
	end
	local job = jobsById[jobId]
	activeJobs[player] = nil
	jobReadyAt(profile)[jobId] = os.time() + StartPark.jobCooldown

	local elapsed = os.clock() - active.startedAt
	local inTime = elapsed >= StartPark.jobDuration - EARLY_TOLERANCE
		and elapsed <= StartPark.jobDuration + StartPark.jobGrace
	local inPlace = board ~= nil
		and not isSeated(player)
		and near(player, board :: BasePart, StartPark.jobMaxDistance)
	local score = tonumber(rawScore)
	if not inTime or not inPlace or not score or score ~= score then
		StartRemotes.JobResult:FireClient(player, { id = jobId, ok = false, pay = 0 })
		return
	end
	-- Счёт клиента не больше физически возможного за 15 с
	score = math.clamp(math.floor(score :: number), 0, job.maxScore)
	local share = math.clamp(score / job.target, 0, 1)
	local pay = math.floor(job.minPay + (job.maxPay - job.minPay) * share)
	DataService.addCash(player, pay)
	StartRemotes.JobResult:FireClient(player, { id = jobId, ok = true, pay = pay })
end

-- ===== Картриджи и ломбард =====

local CARTRIDGE_COLORS = {
	Color3.fromRGB(255, 90, 95),
	Color3.fromRGB(61, 123, 255),
	Color3.fromRGB(61, 220, 132),
	Color3.fromRGB(255, 201, 60),
	Color3.fromRGB(190, 90, 255),
}
local rng = Random.new()

local spawnCartridge: (spot: BasePart) -> ()

local function onPickup(player: Player, spot: BasePart, cartridge: BasePart)
	-- Два игрока нажали одновременно: второй уже не найдёт картридж на месте
	if cartridge.Parent ~= spot then
		return
	end
	local profile = DataService.get(player)
	if not profile or not near(player, cartridge, PICKUP_DISTANCE) then
		return
	end
	local count = cartridgesOf(profile)
	if count >= StartPark.maxCartridges then
		StartRemotes.ParkNotice:FireClient(player, { kind = "full", count = count })
		return
	end
	cartridge:Destroy()
	count += 1
	(profile :: any).cartridges = count
	player:SetAttribute("Cartridges", count)
	StartRemotes.ParkNotice:FireClient(player, { kind = "cartridge", count = count })
	task.delay(StartPark.cartridgeRespawn, spawnCartridge, spot)
end

spawnCartridge = function(spot: BasePart)
	if not spot.Parent or spot:FindFirstChild("Cartridge") then
		return
	end
	local cartridge = Instance.new("Part")
	cartridge.Name = "Cartridge"
	cartridge.Anchored = true
	cartridge.CanCollide = false
	cartridge.Size = Vector3.new(1.4, 1.7, 0.35)
	cartridge.Color = CARTRIDGE_COLORS[rng:NextInteger(1, #CARTRIDGE_COLORS)]
	cartridge.Material = Enum.Material.SmoothPlastic
	cartridge.CFrame = CFrame.new(spot.Position + Vector3.new(0, 1.5, 0))
		* CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), math.rad(10))
	local labelPart = Instance.new("Part")
	labelPart.Name = "Label"
	labelPart.Anchored = true
	labelPart.CanCollide = false
	labelPart.CanQuery = false
	labelPart.Size = Vector3.new(1, 0.8, 0.05)
	labelPart.Color = Color3.fromRGB(240, 240, 230)
	labelPart.CFrame = cartridge.CFrame * CFrame.new(0, 0.2, 0.19)
	labelPart.Parent = cartridge
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = cartridge.Color
	sparkle.Parent = cartridge
	local prompt = makePrompt(
		cartridge,
		"Подобрать",
		"park_cartridge_prompt",
		"Ретро-картридж",
		"park_cartridge"
	)
	prompt.Triggered:Connect(function(player: Player)
		onPickup(player, spot, cartridge)
	end)
	cartridge.Parent = spot
end

local function onPawn(player: Player)
	local profile = DataService.get(player)
	local counter = promptPart("Pawnshop", "Counter")
	if not profile or not counter or not near(player, counter, PICKUP_DISTANCE) then
		return
	end
	local count = cartridgesOf(profile)
	if count <= 0 then
		StartRemotes.ParkNotice:FireClient(player, { kind = "pawn", count = 0, pay = 0 })
		return
	end
	local pay = count * StartPark.cartridgePrice;
	(profile :: any).cartridges = 0
	player:SetAttribute("Cartridges", 0)
	DataService.addCash(player, pay)
	StartRemotes.ParkNotice:FireClient(player, { kind = "pawn", count = count, pay = pay })
end

-- ===== Название студии =====

local SIGN_OFFSET = CFrame.new(0, 13.5, 30) -- над воротами гаража (передняя стена z = 29.5)

-- Вывеска на постерах и табличка у входа на участке игрока. Табличка — модель, поэтому
-- PlotService.rebuild её сносит, а plotChanged ставит заново
local function applyStudioSigns(player: Player)
	local plot = PlotService.getPlot(player)
	local profile = DataService.get(player)
	if not plot or not profile then
		return
	end
	local old = plot:FindFirstChild("StudioSign")
	if old then
		old:Destroy()
	end
	if not PlotService.ownsGarage(player) then
		return
	end
	local name = studioNameOf(player, profile)
	local posters = plot:FindFirstChild("Posters")
	local neon = posters and posters:FindFirstChild("StudioName", true)
	if neon and neon:IsA("TextLabel") then
		neon.Text = name
	end

	local model = Instance.new("Model")
	model.Name = "StudioSign"
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = plot.CFrame * SIGN_OFFSET
	anchor.Parent = model
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 44)
	billboard.MaxDistance = 90
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 46)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.fromRGB(255, 201, 60)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "🏠 " .. name
	label.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.Parent = label
	model.Parent = plot
end

local function refreshNaming(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	-- Окно открывает клиент по атрибуту: и новым владельцам гаража, и старым игрокам без названия
	player:SetAttribute("NeedsStudioName", PlotService.ownsGarage(player) and not hasStudioName(profile))
end

local function trim(s: string): string
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function onSetStudioName(player: Player, raw: any)
	if type(raw) ~= "string" or #raw > 200 or naming[player] then
		return
	end
	local now = os.clock()
	if (lastNameRequest[player] or 0) + NAME_COOLDOWN > now then
		return
	end
	lastNameRequest[player] = now
	local profile = DataService.get(player)
	if not profile or not PlotService.ownsGarage(player) or hasStudioName(profile) then
		return
	end
	local name = trim((raw:gsub("%c", " ")))
	local length = utf8.len(name)
	if not length or length < StartPark.studioNameMin or length > StartPark.studioNameMax then
		StartRemotes.StudioNameResult:FireClient(player, { ok = false, reason = "length" })
		return
	end

	-- Фильтр уступает поток: второй запрос в это время не пройдёт
	naming[player] = true
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(name, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	naming[player] = nil
	if not player.Parent or DataService.get(player) ~= profile or hasStudioName(profile) then
		return
	end
	if not ok or type(result) ~= "string" then
		warn("[StartParkService] Text filter failed:", result)
		StartRemotes.StudioNameResult:FireClient(player, { ok = false, reason = "error" })
		return
	end
	-- Фильтр заменил слова решётками — просим другое название, а не сохраняем «####»
	if result ~= name then
		StartRemotes.StudioNameResult:FireClient(player, { ok = false, reason = "filtered" })
		return
	end
	(profile :: any).studioName = result
	refreshNaming(player)
	applyStudioSigns(player)
	StartRemotes.StudioNameResult:FireClient(player, { ok = true, name = result })
	task.spawn(DataService.save, player)
end

-- ===== Старт =====

local function onPlayerAdded(player: Player)
	local profile = DataService.get(player)
	while not profile and player.Parent do
		task.wait(PROFILE_WAIT)
		profile = DataService.get(player)
	end
	if profile then
		player:SetAttribute("Cartridges", cartridgesOf(profile))
	end
end

function StartParkService.start()
	local folder = park()
	if not folder then
		warn("[StartParkService] workspace.StartPark not found: park is disabled")
	else
		board = promptPart("JobBoard", "Board")
		if board then
			local prompt = makePrompt(
				board,
				"Взять заказ",
				"park_board_prompt",
				"Доска заказов",
				"park_board"
			)
			prompt.Triggered:Connect(onBoardTriggered)
		end
		local counter = promptPart("Pawnshop", "Counter")
		if counter then
			local prompt = makePrompt(
				counter,
				"Сдать картриджи",
				"park_pawn_prompt",
				"Ломбард",
				"park_pawn"
			)
			prompt.Triggered:Connect(onPawn)
		end
		local spots = folder:FindFirstChild("CartridgeSpots")
		if spots then
			for _, spot in spots:GetChildren() do
				if spot:IsA("BasePart") then
					spawnCartridge(spot)
				end
			end
		end
	end

	StartRemotes.JobStart.OnServerEvent:Connect(onJobStart)
	StartRemotes.JobFinish.OnServerEvent:Connect(onJobFinish)
	StartRemotes.SetStudioName.OnServerEvent:Connect(onSetStudioName)
	-- Участок собран (вход, покупка гаража, апгрейд, переезд): вывески и окно названия
	PlotService.plotChanged:Connect(function(player: Player)
		applyStudioSigns(player)
		refreshNaming(player)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		activeJobs[player] = nil
		lastRequest[player] = nil
		lastNameRequest[player] = nil
		naming[player] = nil
	end)
end

return StartParkService
