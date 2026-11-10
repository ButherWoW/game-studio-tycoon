--!strict
-- Стрелки на земле к текущей цели и подсказка внизу экрана (запрос Dev 1, issue #14 п. 1).
-- Цель по порядку: первая игра на ноутбуке → гараж (копим / покупаем) → «Заказы дня» (пока не подошёл
-- к доске) → ближайшая доступная покупка на участке. Во время обучения (TutorialActive) молчим.
-- Всё локальное, видит только сам игрок. Выключается настройкой «Скрыть стрелки-подсказки» (HideGuide).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local StartPark = require(ReplicatedStorage.Shared.Config.StartPark)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local OrderRemotes = require(ReplicatedStorage.Shared.OrderRemotes)
local ClientState = require(script.Parent.Parent.ClientState)

local player = Players.LocalPlayer

local CHECK_INTERVAL = 0.4
local ARROW_LIFT = 0.45
local ARROW_COUNT = 7
local ARROW_FIRST = 5 -- studs от игрока до первой стрелки
local ARROW_STEP = 4
local ARROW_COLOR = Color3.fromRGB(255, 214, 90)
local ARRIVE_DISTANCE = 12 -- ближе — цель «достигнута» (для доски заказов — больше не показываем)
local AFFORDABLE_TEXT = Color3.fromRGB(130, 255, 170) -- цвет цены, которым PlotService помечает доступное

local GroundArrows = {}

local ordersLeft = false
local boardSeen = false
local arrows: { { Part } } = {}
local folder: Folder? = nil
local hint: TextLabel? = nil
local target: Vector3? = nil

local function ownPlot(): Instance?
	local plotName = player:GetAttribute("PlotName")
	local plots = workspace:FindFirstChild("Plots")
	return if type(plotName) == "string" and plots then plots:FindFirstChild(plotName) else nil
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Ближайшая доступная покупка на участке: цена над кнопкой зелёная (PlotService), название — 1-я строка
local function nearestPurchase(plot: Instance, from: Vector3): (Vector3?, string?)
	local buttons = plot:FindFirstChild("Buttons")
	if not buttons then
		return nil, nil
	end
	local best: Vector3? = nil
	local bestName: string? = nil
	local bestDist = math.huge
	for _, button in buttons:GetChildren() do
		if button:IsA("BasePart") and button.Name ~= "Buy_garage" then
			local gui = button:FindFirstChildWhichIsA("BillboardGui")
			local label = gui and gui:FindFirstChildWhichIsA("TextLabel")
			if label and label.TextColor3 == AFFORDABLE_TEXT then
				local dist = flat(button.Position, from)
				if dist < bestDist then
					bestDist = dist
					best = button.Position
					bestName = label.Text:match("^[^\n]+") or button.Name
				end
			end
		end
	end
	return best, bestName
end

-- Что делать сейчас: точка цели (или nil — только подсказка) и текст подсказки
local function pickGoal(root: BasePart): (Vector3?, string?)
	local data = ClientState.data
	local cash = if data then tonumber(data.cash) or 0 else 0
	local games = if data then tonumber(data.gamesReleased) or 0 else 0
	local plot = ownPlot()
	if player:GetAttribute("TutorialActive") == true then
		return nil, nil
	end
	if games < Economy.firstGames then
		local best: Vector3? = nil
		local bestDist = math.huge
		for _, item in workspace:GetDescendants() do
			if item:IsA("Seat") and item.Name == "PcSeat" then
				local dist = flat(item.Position, root.Position)
				if dist < bestDist then
					bestDist = dist
					best = item.Position
				end
			end
		end
		return best, ClientState.t("hint_first_game")
	end
	if player:GetAttribute("OwnsGarage") ~= true then
		local price = Texts.money(StartPark.garagePrice)
		if cash < StartPark.garagePrice then
			return nil, ClientState.t("hint_save_garage", { price = price })
		end
		local buttons = if plot then plot:FindFirstChild("Buttons") else nil
		local button = if buttons then buttons:FindFirstChild("Buy_garage") else nil
		return if button and button:IsA("BasePart") then button.Position else nil,
			ClientState.t("hint_buy_garage", { price = price })
	end
	local board = plot and plot:FindFirstChild("OrderBoard")
	if ordersLeft and not boardSeen and board and board:IsA("BasePart") then
		if flat(board.Position, root.Position) < ARRIVE_DISTANCE then
			boardSeen = true
		else
			return board.Position, ClientState.t("hint_orders")
		end
	end
	if plot then
		local spot, name = nearestPurchase(plot, root.Position)
		if spot and name then
			return spot, ClientState.t("hint_buy", { name = name })
		end
	end
	return nil, nil
end

local function makeArrow(parent: Instance): { Part }
	local bars = {}
	for _, side in { -1, 1 } do
		local bar = Instance.new("Part")
		bar.Name = "GuideArrow"
		bar.Anchored = true
		bar.CanCollide = false
		bar.CanQuery = false
		bar.CanTouch = false
		bar.CastShadow = false
		bar.Material = Enum.Material.Neon
		bar.Color = ARROW_COLOR
		bar.Size = Vector3.new(0.4, 0.1, 1.7)
		bar:SetAttribute("Side", side)
		bar.Parent = parent
		table.insert(bars, bar)
	end
	return bars
end

local function clearArrows()
	target = nil
	if folder then
		folder:Destroy()
		folder = nil
	end
	arrows = {}
end

local function ensureHint()
	if hint and hint.Parent then
		return hint
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GroundArrowsHint"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -110)
	label.Size = UDim2.fromOffset(520, 44)
	label.BackgroundColor3 = Color3.fromRGB(20, 22, 36)
	label.BackgroundTransparency = 0.25
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 24
	label.TextColor3 = ARROW_COLOR
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label
	hint = label
	return label
end

local function setHint(text: string?)
	if not text or player:GetAttribute("HideGuide") == true then
		if hint then
			hint.Visible = false
		end
		return
	end
	local label = ensureHint()
	label.Text = text
	label.Visible = true
end

local function groundY(point: Vector3, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(point + Vector3.new(0, 6, 0), Vector3.new(0, -16, 0), params)
	return if hit then hit.Position.Y + 0.15 else point.Y - 2.8
end

local function placeArrows()
	local root = rootPart()
	local goal = target
	if not root or not goal then
		return
	end
	local from = Vector3.new(root.Position.X, 0, root.Position.Z)
	local to = Vector3.new(goal.X, 0, goal.Z)
	local distance = (to - from).Magnitude
	if distance < ARRIVE_DISTANCE then
		for _, bars in arrows do
			for _, bar in bars do
				bar.Transparency = 1
			end
		end
		return
	end
	local dir = (to - from).Unit
	local ignore: { Instance } = { player.Character :: Instance, folder :: Instance }
	local pulse = (os.clock() * 2.2) % ARROW_COUNT
	for index, bars in arrows do
		local along = ARROW_FIRST + (index - 1) * ARROW_STEP
		local visible = along < distance - 3
		local flatPos = from + dir * along
		local pos = Vector3.new(
			flatPos.X,
			groundY(Vector3.new(flatPos.X, root.Position.Y, flatPos.Z), ignore),
			flatPos.Z
		)
		-- Над землёй, чтобы стрелки не тонули в газоне и плитах (владелец 10.11)
		pos += Vector3.new(0, ARROW_LIFT, 0)
		local base = CFrame.lookAt(pos, pos + dir)
		-- Волна: стрелка, до которой дошёл «импульс», светится сильнее
		local glow = math.clamp(1 - math.abs(pulse - (index - 1)) / 2, 0, 1)
		for _, bar in bars do
			local side = bar:GetAttribute("Side") :: number
			-- Остриё вперёд (−Z базы, к цели), крылья назад: владелец 10.11 — «стрелка не в ту сторону»
			bar.CFrame = base * CFrame.new(side * 0.55, 0, 0.55) * CFrame.Angles(0, side * math.pi / 4, 0)
			bar.Transparency = if visible then 0.55 - glow * 0.5 else 1
		end
	end
end

local function refresh()
	if player:GetAttribute("HideGuide") == true then
		clearArrows()
		setHint(nil)
		return
	end
	local root = rootPart()
	if not root then
		clearArrows()
		return
	end
	local goal, text = pickGoal(root)
	setHint(text)
	if not goal then
		clearArrows()
		return
	end
	target = goal
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "GroundArrows"
		created.Parent = workspace
		folder = created
		arrows = {}
		for _ = 1, ARROW_COUNT do
			table.insert(arrows, makeArrow(created))
		end
	end
end

function GroundArrows.start()
	OrderRemotes.OrderState.OnClientEvent:Connect(function(info: any)
		if type(info) ~= "table" or type(info.list) ~= "table" then
			return
		end
		local left = false
		for _, order in info.list :: { any } do
			if order.done ~= true then
				left = true
			end
		end
		ordersLeft = left
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			local ok, err = pcall(refresh)
			if not ok then
				warn("[GroundArrows]", err)
			end
		end
	end)
	RunService.Heartbeat:Connect(function()
		if folder then
			placeArrows()
		end
	end)
end

return GroundArrows
