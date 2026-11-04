--!strict
-- «Инди в парке» на клиенте: окно доски заказов и три мини-игры, уведомления (картриджи,
-- ломбард, гараж), окно «Назови свою студию» и перевод табличек/подсказок парка.
-- Всё решает сервер (StartParkService, PlotService): клиент только показывает и шлёт счёт.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local StartRemotes = require(ReplicatedStorage.Shared.StartRemotes)
local StartPark = require(ReplicatedStorage.Shared.Config.StartPark)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local StartParkController = {}

local TOAST_SECONDS = 3.5
local SEND_DELAY = 0.2 -- после таймера чуть ждём: сервер не примет результат раньше срока
local BUG_COUNT = 3
local BUG_HOP = 0.9 -- секунд между прыжками жука
local PIXEL_SIZE = 4
local PIXEL_ON_MIN, PIXEL_ON_MAX = 5, 8

local jobsById: { [string]: StartPark.Job } = {}
for _, job in StartPark.jobs do
	jobsById[job.id] = job
end

local function playerGui(): Instance
	return player:WaitForChild("PlayerGui")
end

-- ===== Уведомления =====

local toastGui: ScreenGui? = nil
local toastToken = 0

local function toast(text: string, color: Color3?)
	if toastGui then
		toastGui:Destroy()
	end
	toastToken += 1
	local token = toastToken
	local screen = Instance.new("ScreenGui")
	screen.Name = "ParkToast"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 26
	screen.Parent = playerGui()
	toastGui = screen
	local label = Ui.label(screen, text, 44, Ui.titleFontFor(ClientState.lang), color or Ui.colors.money)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.3)
	label.Size = UDim2.new(0.9, 0, 0, 44)
	label.BackgroundColor3 = Ui.colors.panel
	label.BackgroundTransparency = 0.2
	Ui.corner(label, 10)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(620, 44)
	limit.Parent = label
	task.delay(TOAST_SECONDS, function()
		if toastToken == token then
			screen:Destroy()
			toastGui = nil
		end
	end)
end

-- ===== Перевод табличек, подсказок и таблички «Гараж продаётся» =====

local function relabel(item: Instance)
	if item:IsA("TextLabel") then
		local key = item:GetAttribute("TextKey")
		if type(key) == "string" then
			item.Text = ClientState.t(key)
		end
	elseif item:IsA("ProximityPrompt") then
		local action, object = item:GetAttribute("ActionKey"), item:GetAttribute("ObjectKey")
		if type(action) == "string" then
			item.ActionText = ClientState.t(action)
		end
		if type(object) == "string" then
			item.ObjectText = ClientState.t(object)
		end
	elseif item:IsA("BasePart") and item.Name == "Buy_garage" then
		-- Кнопку ставит PlotService по-русски; PlotLabels её не знает (это не апгрейд)
		local billboard = item:FindFirstChildWhichIsA("BillboardGui")
		local label = billboard and billboard:FindFirstChildWhichIsA("TextLabel")
		if label then
			label.Text = ClientState.t("garage_sale") .. "\n" .. Texts.money(StartPark.garagePrice)
		end
	end
end

local function relabelAll()
	local park = workspace:FindFirstChild("StartPark")
	if park then
		for _, d in park:GetDescendants() do
			relabel(d)
		end
	end
	local plots = workspace:FindFirstChild("Plots")
	if plots then
		for _, d in plots:GetDescendants() do
			if d.Name == "Buy_garage" then
				relabel(d)
			end
		end
	end
end

-- ===== Окно с заголовком =====

local function windowWithTitle(name: string, title: string, size: Vector2, order: number): (ScreenGui, Frame)
	local screen = Instance.new("ScreenGui")
	screen.Name = name
	screen.ResetOnSpawn = false
	screen.DisplayOrder = order
	screen.Parent = playerGui()
	local frame = Ui.window(screen, "Panel", size)
	local header = Ui.label(frame, title, 36, Ui.titleFontFor(ClientState.lang))
	header.TextXAlignment = Enum.TextXAlignment.Center
	header.Position = UDim2.fromOffset(16, 12)
	header.Size = UDim2.new(1, -32, 0, 36)
	return screen, frame
end

-- ===== Доска заказов =====

local boardGui: ScreenGui? = nil
local jobRunning = false

local function closeBoard()
	if boardGui then
		boardGui:Destroy()
		boardGui = nil
		Ui.windowClosed()
	end
end

local function openBoard(state: { [string]: number })
	closeBoard()
	if jobRunning then
		return
	end
	local screen, frame =
		windowWithTitle("JobBoardWindow", ClientState.t("jobs_title"), Vector2.new(460, 330), 12)
	boardGui = screen
	Ui.windowOpened()
	local openedAt = os.clock()

	for i, job in StartPark.jobs do
		local y = 56 + (i - 1) * 76
		local row = Instance.new("Frame")
		row.Name = "Job_" .. job.id
		row.BackgroundColor3 = Ui.colors.stroke
		row.BackgroundTransparency = 0.4
		row.Position = UDim2.fromOffset(16, y)
		row.Size = UDim2.new(1, -32, 0, 68)
		Ui.corner(row, 10)
		row.Parent = frame
		local title = Ui.label(row, ClientState.t("job_" .. job.id), 28)
		title.Position = UDim2.fromOffset(10, 6)
		title.Size = UDim2.new(1, -140, 0, 28)
		local pay =
			ClientState.t("jobs_pay", { min = Texts.money(job.minPay), max = Texts.money(job.maxPay) })
		local payLabel = Ui.label(row, pay, 22, nil, Ui.colors.money)
		payLabel.Position = UDim2.fromOffset(10, 38)
		payLabel.Size = UDim2.new(1, -140, 0, 22)

		local left = tonumber(state[job.id]) or 0
		local take = Ui.button(row, ClientState.t("jobs_take"), Ui.colors.good, function()
			if left - (os.clock() - openedAt) > 0 then
				return
			end
			StartRemotes.JobStart:FireServer(job.id)
			closeBoard()
		end)
		take.Name = "TakeButton"
		take.AnchorPoint = Vector2.new(1, 0.5)
		take.Position = UDim2.new(1, -10, 0.5, 0)
		take.Size = UDim2.fromOffset(116, 44)
		-- Перезарядку досчитываем сами: сервер прислал, сколько осталось
		task.spawn(function()
			while take.Parent do
				local remaining = math.ceil(left - (os.clock() - openedAt))
				if remaining > 0 then
					take.Text = ClientState.t("jobs_cooldown", { time = remaining })
					take.BackgroundColor3 = Ui.colors.locked
				else
					take.Text = ClientState.t("jobs_take")
					take.BackgroundColor3 = Ui.colors.good
				end
				task.wait(0.25)
			end
		end)
	end

	local close = Ui.button(frame, ClientState.t("jobs_close"), Ui.colors.locked, closeBoard)
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -12)
	close.Size = UDim2.fromOffset(160, 40)
end

-- ===== Мини-игры =====
-- Каждая получает поле и возвращает функцию «текущий счёт»; таймер и отправка — в runJob

type Game = { score: () -> number, stop: (() -> ())? }

local rng = Random.new()

local function bugsGame(area: Frame): Game
	local score = 0
	local alive = true
	local function randomPos(): UDim2
		return UDim2.fromScale(rng:NextNumber(0.08, 0.92), rng:NextNumber(0.1, 0.9))
	end
	for _ = 1, BUG_COUNT do
		local bug = Instance.new("TextButton")
		bug.Name = "Bug"
		bug.AnchorPoint = Vector2.new(0.5, 0.5)
		bug.Size = UDim2.fromOffset(56, 56)
		bug.BackgroundTransparency = 1
		bug.Text = "🐛"
		bug.TextScaled = true
		bug.Position = randomPos()
		bug.Parent = area
		bug.Activated:Connect(function()
			score += 1
			bug.Position = randomPos()
		end)
		task.spawn(function()
			while alive and bug.Parent do
				local tween = TweenService:Create(
					bug,
					TweenInfo.new(BUG_HOP, Enum.EasingStyle.Sine),
					{ Position = randomPos() }
				)
				tween:Play()
				task.wait(BUG_HOP)
			end
		end)
	end
	return {
		score = function()
			return score
		end,
		stop = function()
			alive = false
		end,
	}
end

local function pixelGame(area: Frame): Game
	local score = 0
	local target: { boolean } = {}
	local mine: { boolean } = {}
	local targetCells: { Frame } = {}
	local myCells: { TextButton } = {}
	local on, off = Ui.colors.primary, Ui.colors.stroke

	local function grid(x: number, name: string): Frame
		local g = Instance.new("Frame")
		g.Name = name
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(x, 0.5)
		g.Size = UDim2.fromScale(0.4, 0.9)
		g.BackgroundTransparency = 1
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.Parent = g
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.fromScale(0.23, 0.23)
		layout.CellPadding = UDim2.fromScale(0.02, 0.02)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = g
		g.Parent = area
		return g
	end

	local function newPattern()
		local count = rng:NextInteger(PIXEL_ON_MIN, PIXEL_ON_MAX)
		for i = 1, PIXEL_SIZE * PIXEL_SIZE do
			target[i] = false
			mine[i] = false
		end
		local placed = 0
		while placed < count do
			local i = rng:NextInteger(1, PIXEL_SIZE * PIXEL_SIZE)
			if not target[i] then
				target[i] = true
				placed += 1
			end
		end
		for i, cell in targetCells do
			cell.BackgroundColor3 = if target[i] then on else off
		end
		for _, cell in myCells do
			cell.BackgroundColor3 = off
		end
	end

	local left, right = grid(0.27, "Target"), grid(0.73, "Mine")
	for i = 1, PIXEL_SIZE * PIXEL_SIZE do
		local cell = Instance.new("Frame")
		cell.LayoutOrder = i
		cell.BorderSizePixel = 0
		cell.Parent = left
		targetCells[i] = cell
		local button = Instance.new("TextButton")
		button.LayoutOrder = i
		button.Text = ""
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Parent = right
		myCells[i] = button
		button.Activated:Connect(function()
			mine[i] = not mine[i]
			button.BackgroundColor3 = if mine[i] then on else off
			for k = 1, PIXEL_SIZE * PIXEL_SIZE do
				if mine[k] ~= target[k] then
					return
				end
			end
			score += 1
			newPattern()
		end)
	end
	newPattern()
	return {
		score = function()
			return score
		end,
	}
end

local function rhythmGame(area: Frame): Game
	local hits, misses = 0, 0
	local hitBeats: { [number]: boolean } = {}
	local startedAt = os.clock()
	local interval, window = StartPark.beatInterval, StartPark.beatWindow
	local alive = true

	local circle = Instance.new("Frame")
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.38)
	circle.Size = UDim2.fromOffset(90, 90)
	circle.BackgroundColor3 = Ui.colors.stroke
	Ui.corner(circle, 45)
	circle.Parent = area

	local tap = Ui.button(area, ClientState.t("job_tap"), Ui.colors.money, function()
		local t = os.clock() - startedAt
		local beat = math.floor(t / interval + 0.5)
		if beat >= 1 and not hitBeats[beat] and math.abs(t - beat * interval) <= window then
			hitBeats[beat] = true
			hits += 1
		else
			-- Промах вычитаем: иначе частые нажатия «попадут» во все удары
			misses += 1
		end
	end)
	tap.AnchorPoint = Vector2.new(0.5, 1)
	tap.Position = UDim2.new(0.5, 0, 1, -8)
	tap.Size = UDim2.fromOffset(200, 60)
	tap.TextColor3 = Color3.fromRGB(40, 30, 0)

	-- Вспышка на каждый удар
	task.spawn(function()
		while alive and circle.Parent do
			local t = os.clock() - startedAt
			local phase = t / interval - math.floor(t / interval + 0.5)
			local flash = math.abs(phase) * interval <= window
			circle.BackgroundColor3 = if flash then Ui.colors.good else Ui.colors.stroke
			circle.Size = if flash then UDim2.fromOffset(110, 110) else UDim2.fromOffset(90, 90)
			task.wait()
		end
	end)
	return {
		score = function()
			return math.max(hits - misses, 0)
		end,
		stop = function()
			alive = false
		end,
	}
end

local GAMES: { [string]: (Frame) -> Game } = {
	bugs = bugsGame,
	pixel = pixelGame,
	rhythm = rhythmGame,
}

local function runJob(jobId: string, duration: number)
	local job = jobsById[jobId]
	local make = GAMES[jobId]
	if not job or not make or jobRunning then
		return
	end
	closeBoard()
	jobRunning = true
	local screen, frame =
		windowWithTitle("JobWindow", ClientState.t("job_" .. jobId), Vector2.new(560, 440), 12)
	Ui.windowOpened()
	local hint = Ui.label(frame, ClientState.t("job_" .. jobId .. "_hint"), 22, nil, Ui.colors.muted)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.Position = UDim2.fromOffset(16, 50)
	hint.Size = UDim2.new(1, -32, 0, 22)
	local status = Ui.label(frame, "", 26, nil, Ui.colors.money)
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.new(0, 16, 1, -10)
	status.Size = UDim2.new(1, -32, 0, 26)

	local area = Instance.new("Frame")
	area.Name = "Area"
	area.Position = UDim2.fromOffset(16, 80)
	area.Size = UDim2.new(1, -32, 1, -124)
	area.BackgroundColor3 = Color3.fromRGB(20, 20, 32)
	area.ClipsDescendants = true
	Ui.corner(area, 10)
	area.Parent = frame

	local minigame = make(area)
	local startedAt = os.clock()
	while os.clock() - startedAt < duration and screen.Parent do
		local left = math.max(math.ceil(duration - (os.clock() - startedAt)), 0)
		status.Text = ClientState.t("job_score", { score = minigame.score() })
			.. "   "
			.. ClientState.t("job_time", { time = left })
		task.wait(0.1)
	end
	if minigame.stop then
		minigame.stop()
	end
	local score = minigame.score()
	screen:Destroy()
	Ui.windowClosed()
	task.wait(SEND_DELAY)
	StartRemotes.JobFinish:FireServer(jobId, score)
	jobRunning = false
end

-- ===== Название студии =====

local nameGui: ScreenGui? = nil

local function closeNameWindow()
	if nameGui then
		nameGui:Destroy()
		nameGui = nil
		Ui.windowClosed()
	end
end

local errorLabel: TextLabel? = nil

local function showNameError(key: string)
	if errorLabel then
		errorLabel.Text = ClientState.t(key, { min = StartPark.studioNameMin, max = StartPark.studioNameMax })
	end
end

local function openNameWindow()
	if nameGui then
		return
	end
	-- Закрыть без названия нельзя: кнопки «✕» нет. Вышел из игры — спросим при следующем входе
	local screen, frame =
		windowWithTitle("StudioNameWindow", ClientState.t("studio_name_title"), Vector2.new(440, 250), 25)
	nameGui = screen
	Ui.windowOpened()
	local rule = Ui.label(
		frame,
		ClientState.t("studio_name_rule", { min = StartPark.studioNameMin, max = StartPark.studioNameMax }),
		22,
		nil,
		Ui.colors.muted
	)
	rule.TextXAlignment = Enum.TextXAlignment.Center
	rule.Position = UDim2.fromOffset(16, 52)
	rule.Size = UDim2.new(1, -32, 0, 22)

	local box = Instance.new("TextBox")
	box.Name = "NameBox"
	box.Position = UDim2.fromOffset(16, 84)
	box.Size = UDim2.new(1, -32, 0, 46)
	box.BackgroundColor3 = Ui.colors.stroke
	box.TextColor3 = Ui.colors.text
	box.PlaceholderText = ClientState.t("studio_name_placeholder")
	box.PlaceholderColor3 = Ui.colors.muted
	box.Font = Ui.bodyFont
	box.TextScaled = true
	box.ClearTextOnFocus = false
	box.Text = ""
	Ui.corner(box, 10)
	box.Parent = frame

	local err = Ui.label(frame, "", 20, nil, Ui.colors.bad)
	err.TextXAlignment = Enum.TextXAlignment.Center
	err.Position = UDim2.fromOffset(16, 136)
	err.Size = UDim2.new(1, -32, 0, 20)
	errorLabel = err

	local done = Ui.button(frame, ClientState.t("studio_name_done"), Ui.colors.good, function()
		local name = box.Text:gsub("^%s+", ""):gsub("%s+$", "")
		local length = utf8.len(name)
		if not length or length < StartPark.studioNameMin or length > StartPark.studioNameMax then
			showNameError("studio_name_err_length")
			return
		end
		err.Text = "…"
		StartRemotes.SetStudioName:FireServer(name)
	end)
	done.Name = "DoneButton"
	done.AnchorPoint = Vector2.new(0.5, 1)
	done.Position = UDim2.new(0.5, 0, 1, -14)
	done.Size = UDim2.fromOffset(180, 46)
end

local function checkNaming()
	if player:GetAttribute("NeedsStudioName") == true then
		openNameWindow()
	else
		closeNameWindow()
	end
end

-- ===== Старт =====

function StartParkController.start()
	StartRemotes.JobBoardOpen.OnClientEvent:Connect(function(state: any)
		if type(state) == "table" then
			openBoard(state)
		end
	end)
	StartRemotes.JobStarted.OnClientEvent:Connect(function(info: any)
		if type(info) == "table" and type(info.id) == "string" and type(info.duration) == "number" then
			task.spawn(runJob, info.id, info.duration)
		end
	end)
	StartRemotes.JobResult.OnClientEvent:Connect(function(result: any)
		if type(result) ~= "table" then
			return
		end
		if result.ok then
			toast(
				ClientState.t("job_paid", { money = Texts.money(tonumber(result.pay) or 0) }),
				Ui.colors.good
			)
		else
			toast(ClientState.t("job_failed"), Ui.colors.bad)
		end
	end)
	StartRemotes.ParkNotice.OnClientEvent:Connect(function(notice: any)
		if type(notice) ~= "table" then
			return
		end
		local count = tonumber(notice.count) or 0
		if notice.kind == "cartridge" then
			toast(ClientState.t("park_got_cartridge", { count = count }))
		elseif notice.kind == "full" then
			toast(ClientState.t("park_full", { count = count }), Ui.colors.bad)
		elseif notice.kind == "pawn" then
			if count > 0 then
				local money = Texts.money(tonumber(notice.pay) or 0)
				toast(ClientState.t("park_pawn_paid", { count = count, money = money }), Ui.colors.good)
			else
				toast(ClientState.t("park_pawn_empty"), Ui.colors.muted)
			end
		end
	end)
	StartRemotes.GarageBought.OnClientEvent:Connect(function()
		toast(ClientState.t("garage_bought"), Ui.colors.good)
	end)
	StartRemotes.StudioNameResult.OnClientEvent:Connect(function(result: any)
		if type(result) ~= "table" then
			return
		end
		if result.ok then
			closeNameWindow()
			toast(ClientState.t("studio_name_saved", { name = tostring(result.name) }), Ui.colors.good)
		elseif result.reason == "filtered" then
			showNameError("studio_name_err_filtered")
		elseif result.reason == "length" then
			showNameError("studio_name_err_length")
		else
			showNameError("studio_name_err_error")
		end
	end)
	player:GetAttributeChangedSignal("NeedsStudioName"):Connect(checkNaming)
	checkNaming()

	-- Таблички парка и кнопка гаража появляются и пересоздаются — переводим новые
	workspace.DescendantAdded:Connect(function(d: Instance)
		if d:IsA("ProximityPrompt") or d.Name == "SignText" or d.Name == "Buy_garage" then
			task.defer(relabel, d)
		elseif d:IsA("TextLabel") then
			-- Надпись кнопки гаража прилетает позже самой кнопки
			local button = d:FindFirstAncestor("Buy_garage")
			if button then
				task.defer(relabel, button)
			end
		end
	end)
	ClientState.changed:Connect(relabelAll)
	relabelAll()
end

return StartParkController
