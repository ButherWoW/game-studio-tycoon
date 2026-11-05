--!strict
-- Мини-аркада «Сыграй в свою игру» (Config/Arcade): кнопка в окне релиза открывает 20-секундную
-- мини-игру по жанру. Пять игр — тир, гонка, головоломка, забег, монеты — из простых рамок.
-- Клиент рисует и считает очки; сервер (ArcadeService) выдаёт сессию с seed, проверяет время,
-- обрезает счёт по максимуму расписания и начисляет бонус. Ввод: тап/мышь, клавиатура и геймпад
-- (ContextActionService с высоким приоритетом: пока идёт игра, клавиши не двигают персонажа).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Arcade = require(ReplicatedStorage.Shared.Config.Arcade)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local WINDOW_SIZE = Vector2.new(600, 500)
local FIELD_HEIGHT = 300
local ACTION_KEYS = "ArcadeKeys"
local PRIORITY = Enum.ContextActionPriority.High.Value + 20
local FIELD_COLOR = Color3.fromRGB(22, 24, 38)
local GAME_COLOR: { [string]: Color3 } = {
	whack = Color3.fromRGB(255, 120, 80),
	lanes = Color3.fromRGB(80, 170, 255),
	puzzle = Color3.fromRGB(190, 110, 255),
	jump = Color3.fromRGB(90, 210, 130),
	catch = Color3.fromRGB(255, 201, 60),
}
-- Цвета головоломки: красный, зелёный, синий, жёлтый
local PUZZLE_COLORS = {
	Color3.fromRGB(255, 90, 95),
	Color3.fromRGB(61, 220, 132),
	Color3.fromRGB(61, 140, 255),
	Color3.fromRGB(255, 201, 60),
}
local MEDAL_COLOR: { [string]: Color3 } = {
	gold = Color3.fromRGB(255, 201, 60),
	silver = Color3.fromRGB(200, 210, 225),
	bronze = Color3.fromRGB(215, 140, 80),
}

-- Клавиши → действие: лунка/полоса/сторона
local LEFT =
	{ Enum.KeyCode.Left, Enum.KeyCode.A, Enum.KeyCode.DPadLeft, Enum.KeyCode.ButtonX, Enum.KeyCode.One }
local MIDDLE =
	{ Enum.KeyCode.Down, Enum.KeyCode.S, Enum.KeyCode.DPadDown, Enum.KeyCode.ButtonA, Enum.KeyCode.Two }
local RIGHT =
	{ Enum.KeyCode.Right, Enum.KeyCode.D, Enum.KeyCode.DPadRight, Enum.KeyCode.ButtonB, Enum.KeyCode.Three }
local UP = { Enum.KeyCode.Up, Enum.KeyCode.W, Enum.KeyCode.DPadUp, Enum.KeyCode.ButtonY }
local JUMP = { Enum.KeyCode.Space, Enum.KeyCode.Return }

local KEY_ACTION: { [Enum.KeyCode]: string } = {}
for action, keys in { left = LEFT, middle = MIDDLE, right = RIGHT, up = UP, jump = JUMP } do
	for _, key in keys do
		KEY_ACTION[key] = action
	end
end

-- Игра: step — каждый кадр (t — секунды с начала), key — действие с клавиатуры/геймпада,
-- stick — наклон левого стика по X (−1..1)
type Game = {
	step: (t: number) -> (),
	key: (action: string, down: boolean) -> (),
	stick: ((x: number) -> ())?,
}
type Builder = (field: Frame, schedule: { Arcade.Spawn }, add: (n: number) -> ()) -> Game

local ArcadeWindow = {}
local remotes: { [string]: RemoteEvent }? = nil
local gui: ScreenGui? = nil
local connections: { RBXScriptConnection } = {}
local played: { [number]: boolean } = {} -- projectId: плейтест уже начинали
local waitingProject: number? = nil
local token: number? = nil
local live = false -- идёт игра (не отсчёт и не итог): нажатия засчитываются
-- Элементы текущего окна
local ui: {
	title: TextLabel,
	hint: TextLabel,
	field: Frame,
	status: TextLabel,
	buttons: Frame,
}? = nil

local function connect(signal: RBXScriptSignal, fn: any)
	table.insert(connections, signal:Connect(fn))
end

local function unbind()
	ContextActionService:UnbindAction(ACTION_KEYS)
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
end

local function close()
	unbind()
	live = false
	waitingProject = nil
	token = nil
	ui = nil
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function box(parent: Instance, color: Color3, position: UDim2, size: UDim2, z: number?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = position
	frame.Size = size
	frame.ZIndex = z or 2
	frame.Parent = parent
	return frame
end

local function glyph(parent: Instance, text: string, position: UDim2, size: UDim2, z: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = size
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Ui.colors.text
	label.Text = text
	label.ZIndex = z or 3
	label.Parent = parent
	return label
end

-- Прозрачная зона нажатия (тап/клик ловим на «вниз», как в быстрых событиях)
local function tapZone(parent: Instance, position: UDim2, size: UDim2, onTap: () -> ()): TextButton
	local zone = Instance.new("TextButton")
	zone.Text = ""
	zone.BackgroundTransparency = 1
	zone.AutoButtonColor = false
	zone.AnchorPoint = Vector2.new(0.5, 0.5)
	zone.Position = position
	zone.Size = size
	zone.ZIndex = 6
	zone.Parent = parent
	connect(zone.InputBegan, function(input: InputObject)
		if isPointer(input) and live then
			onTap()
		end
	end)
	return zone
end

-- Короткая вспышка рамки: зелёная — попал, красная — промах
local function flash(target: GuiObject, color: Color3)
	local stroke = target:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = color
	stroke.Transparency = 0
	stroke.Parent = target
	TweenService:Create(stroke, TweenInfo.new(0.35), { Transparency = 1 }):Play()
end

-- 🎯 Тир: мишени выскакивают в 3 лунках; тап / ← ↓ → / A S D / X A B
local function buildWhack(field: Frame, schedule: { Arcade.Spawn }, add: (n: number) -> ()): Game
	local cfg = Arcade.games.whack
	local visible = cfg.visible or 1
	local clock = 0
	local hit: { [number]: boolean } = {}
	local holes: { { hole: Frame, target: TextLabel } } = {}
	local keys = { "←", "↓", "→" }
	local function active(lane: number): number?
		for index, spawn in schedule do
			if spawn.lane == lane and not hit[index] and clock >= spawn.t and clock < spawn.t + visible then
				return index
			end
		end
		return nil
	end
	local function shoot(lane: number)
		local index = active(lane)
		local hole = holes[lane].hole
		if index then
			hit[index] = true
			add(1)
			flash(hole, Ui.colors.good)
		else
			add(-1)
			flash(hole, Ui.colors.bad)
		end
	end
	for lane = 1, 3 do
		local position = UDim2.fromScale((lane - 0.5) / 3, 0.5)
		local hole = box(field, Color3.fromRGB(48, 50, 72), position, UDim2.fromOffset(130, 130))
		Ui.corner(hole, 65)
		local target = glyph(hole, "🎯", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.8, 0.8))
		target.Visible = false
		glyph(field, keys[lane], UDim2.new((lane - 0.5) / 3, 0, 1, -24), UDim2.fromOffset(40, 30)).TextColor3 =
			Ui.colors.muted
		tapZone(field, position, UDim2.fromOffset(150, 150), function()
			shoot(lane)
		end)
		holes[lane] = { hole = hole, target = target }
	end
	return {
		step = function(t: number)
			clock = t
			for lane, item in holes do
				item.target.Visible = active(lane) ~= nil
			end
		end,
		key = function(action: string, down: boolean)
			if not down then
				return
			end
			if action == "left" then
				shoot(1)
			elseif action == "middle" or action == "up" or action == "jump" then
				shoot(2)
			elseif action == "right" then
				shoot(3)
			end
		end,
	}
end

-- 🏎 Гонка: препятствия едут по 3 полосам; ◀ ▶ / A D / стрелки / крестовина / стик
local function buildLanes(field: Frame, schedule: { Arcade.Spawn }, add: (n: number) -> ()): Game
	local cfg = Arcade.games.lanes
	local travel = cfg.travel or 1.6
	local carY = 0.85
	local lane = 2
	local stickCentered = true
	for index = 1, 2 do
		box(field, Color3.fromRGB(60, 62, 86), UDim2.fromScale(index / 3, 0.5), UDim2.new(0, 4, 1, 0), 1)
	end
	local car = glyph(field, "🏎", UDim2.fromScale(0.5, carY), UDim2.fromOffset(64, 64), 4)
	local obstacles: { TextLabel } = {}
	local resolved: { [number]: boolean } = {}
	for _, spawn in schedule do
		local item =
			glyph(field, "🚧", UDim2.fromScale((spawn.lane - 0.5) / 3, -0.2), UDim2.fromOffset(56, 56))
		item.Visible = false
		table.insert(obstacles, item)
	end
	local function move(delta: number)
		lane = math.clamp(lane + delta, 1, 3)
		TweenService:Create(car, TweenInfo.new(0.08), { Position = UDim2.fromScale((lane - 0.5) / 3, carY) })
			:Play()
	end
	local left = tapZone(field, UDim2.fromScale(0.25, 0.5), UDim2.fromScale(0.5, 1), function()
		move(-1)
	end)
	local right = tapZone(field, UDim2.fromScale(0.75, 0.5), UDim2.fromScale(0.5, 1), function()
		move(1)
	end)
	glyph(left, "◀", UDim2.new(0, 24, 1, -24), UDim2.fromOffset(36, 36), 5).TextTransparency = 0.5
	glyph(right, "▶", UDim2.new(1, -24, 1, -24), UDim2.fromOffset(36, 36), 5).TextTransparency = 0.5
	return {
		step = function(t: number)
			for index, spawn in schedule do
				local item = obstacles[index]
				local y = carY - (spawn.t - t) / travel * (carY + 0.1)
				item.Visible = y > -0.15 and y < 1.15 and item.TextTransparency < 1
				item.Position = UDim2.fromScale((spawn.lane - 0.5) / 3, y)
				if not resolved[index] and t >= spawn.t then
					resolved[index] = true
					if spawn.lane == lane then
						item.TextTransparency = 1
						flash(car, Ui.colors.bad)
					else
						add(1)
					end
				end
			end
		end,
		key = function(action: string, down: boolean)
			if down and action == "left" then
				move(-1)
			elseif down and action == "right" then
				move(1)
			end
		end,
		stick = function(x: number)
			if math.abs(x) < 0.3 then
				stickCentered = true
			elseif stickCentered and math.abs(x) > 0.6 then
				stickCentered = false
				move(if x < 0 then -1 else 1)
			end
		end,
	}
end

-- 🧩 Головоломка: фишку — в корзину её цвета; корзины по 4 сторонам, каждые N фишек меняются
local function buildPuzzle(field: Frame, schedule: { Arcade.Spawn }, add: (n: number) -> ()): Game
	local cfg = Arcade.games.puzzle
	local minInterval = cfg.minInterval or 0.3
	local shuffleEvery = cfg.shuffleEvery or 8
	local round = 1
	local lastAnswer = -math.huge
	local clock = 0
	-- Стороны по часовой: верх, право, низ, лево
	local sides = { "up", "right", "down", "left" }
	local positions = {
		UDim2.fromScale(0.5, 0.15),
		UDim2.fromScale(0.82, 0.5),
		UDim2.fromScale(0.5, 0.85),
		UDim2.fromScale(0.18, 0.5),
	}
	local arrows = { "▲", "▶", "▼", "◀" }
	local tile = box(field, PUZZLE_COLORS[1], UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(84, 84), 3)
	Ui.corner(tile, 18)
	local bins: { Frame } = {}
	local function colorOf(side: number): number
		local turn = math.floor((round - 1) / shuffleEvery)
		return (side - 1 + turn) % 4 + 1
	end
	local function paint()
		local spawn = schedule[round]
		tile.Visible = spawn ~= nil
		if spawn then
			tile.BackgroundColor3 = PUZZLE_COLORS[spawn.lane]
		end
		for side, bin in bins do
			bin.BackgroundColor3 = PUZZLE_COLORS[colorOf(side)]
		end
	end
	local function answer(side: number)
		local spawn = schedule[round]
		if not spawn or clock - lastAnswer < minInterval then
			return
		end
		lastAnswer = clock
		local bin = bins[side]
		if colorOf(side) == spawn.lane then
			add(1)
			flash(bin, Ui.colors.good)
		else
			add(-1)
			flash(bin, Ui.colors.bad)
		end
		round += 1
		paint()
	end
	for side = 1, 4 do
		local bin = box(field, PUZZLE_COLORS[side], positions[side], UDim2.fromOffset(110, 70))
		bin.BackgroundTransparency = 0.15
		Ui.corner(bin, 14)
		glyph(bin, arrows[side], UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.6))
		tapZone(field, positions[side], UDim2.fromOffset(130, 90), function()
			answer(side)
		end)
		bins[side] = bin
	end
	paint()
	return {
		step = function(t: number)
			clock = t
		end,
		key = function(action: string, down: boolean)
			if not down then
				return
			end
			local side = if action == "middle" then 3 else table.find(sides, action)
			if side then
				answer(side)
			end
		end,
	}
end

-- 🏃 Забег: ямы подъезжают справа; прыжок — тап, Space, ↑, A на геймпаде
local function buildJump(field: Frame, schedule: { Arcade.Spawn }, add: (n: number) -> ()): Game
	local cfg = Arcade.games.jump
	local travel = cfg.travel or 2
	local jumpTime = cfg.jumpTime or 0.75
	local runnerX = 0.18
	local groundY = 0.75
	local clock = 0
	local jumpAt = -math.huge
	box(
		field,
		Color3.fromRGB(70, 160, 90),
		UDim2.fromScale(0.5, groundY + 0.125),
		UDim2.fromScale(1, 0.25),
		1
	)
	local runner =
		box(field, GAME_COLOR.jump, UDim2.fromScale(runnerX, groundY - 0.07), UDim2.fromOffset(40, 40), 4)
	Ui.corner(runner, 8)
	glyph(runner, "••", UDim2.fromScale(0.62, 0.38), UDim2.fromScale(0.6, 0.4), 5)
	local pits: { Frame } = {}
	local resolved: { [number]: boolean } = {}
	for _ = 1, #schedule do
		local pit =
			box(field, FIELD_COLOR, UDim2.fromScale(2, groundY + 0.125), UDim2.fromScale(0.09, 0.26), 2)
		table.insert(pits, pit)
	end
	local function jump()
		if clock - jumpAt >= jumpTime then
			jumpAt = clock
		end
	end
	tapZone(field, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1), jump)
	return {
		step = function(t: number)
			clock = t
			local air = (t - jumpAt) / jumpTime
			local lift = if air >= 0 and air < 1 then 4 * air * (1 - air) * 0.42 else 0
			runner.Position = UDim2.fromScale(runnerX, groundY - 0.07 - lift)
			runner.Rotation = if lift > 0 then air * 180 else 0
			for index, spawn in schedule do
				local x = runnerX + (spawn.t - t) / travel * (1 - runnerX + 0.1)
				pits[index].Position = UDim2.fromScale(x, groundY + 0.125)
				if not resolved[index] and t >= spawn.t then
					resolved[index] = true
					if lift > 0 then
						add(1)
					else
						flash(runner, Ui.colors.bad)
					end
				end
			end
		end,
		key = function(action: string, down: boolean)
			if down and (action == "jump" or action == "up" or action == "middle") then
				jump()
			end
		end,
	}
end

-- 🪙 Монеты: лови корзиной; палец/мышь над полем, A D / стрелки / крестовина / стик
local function buildCatch(field: Frame, schedule: { Arcade.Spawn }, add: (n: number) -> ()): Game
	local cfg = Arcade.games.catch
	local travel = cfg.travel or 1.8
	local paddleWidth = cfg.paddle or 0.24
	local speed = cfg.speed or 1.4
	local paddleY = 0.88
	local x = 0.5
	local held = { left = false, right = false }
	local stickX = 0
	local last = 0
	local paddle =
		box(field, GAME_COLOR.catch, UDim2.fromScale(x, paddleY), UDim2.new(paddleWidth, 0, 0, 16), 4)
	Ui.corner(paddle, 8)
	local coins: { Frame } = {}
	local resolved: { [number]: boolean } = {}
	for _, spawn in schedule do
		local coin = box(field, Ui.colors.money, UDim2.fromScale(spawn.x, -0.2), UDim2.fromOffset(30, 30), 3)
		Ui.corner(coin, 15)
		glyph(coin, "$", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.7, 0.7), 4).TextColor3 =
			Color3.fromRGB(120, 80, 0)
		table.insert(coins, coin)
	end
	-- Палец/мышь: корзина едет к указателю над полем
	local function pointAt(input: InputObject)
		local size = field.AbsoluteSize
		local pos = field.AbsolutePosition
		if size.X <= 0 then
			return
		end
		local inside = input.Position.Y >= pos.Y - 40 and input.Position.Y <= pos.Y + size.Y + 40
		if inside then
			x = math.clamp((input.Position.X - pos.X) / size.X, paddleWidth / 2, 1 - paddleWidth / 2)
		end
	end
	connect(UserInputService.InputChanged, function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			pointAt(input)
		end
	end)
	connect(UserInputService.InputBegan, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			pointAt(input)
		end
	end)
	return {
		step = function(t: number)
			local dt = math.clamp(t - last, 0, 0.1)
			last = t
			local direction = (if held.right then 1 else 0) - (if held.left then 1 else 0) + stickX
			x = math.clamp(
				x + math.clamp(direction, -1, 1) * speed * dt,
				paddleWidth / 2,
				1 - paddleWidth / 2
			)
			paddle.Position = UDim2.fromScale(x, paddleY)
			for index, spawn in schedule do
				local coin = coins[index]
				local y = paddleY - (spawn.t - t) / travel * (paddleY + 0.1)
				coin.Position = UDim2.fromScale(spawn.x, y)
				if not resolved[index] and t >= spawn.t then
					resolved[index] = true
					if math.abs(spawn.x - x) <= paddleWidth / 2 + 0.03 then
						add(1)
						coin.Visible = false
						flash(paddle, Ui.colors.good)
					end
				end
			end
		end,
		key = function(action: string, down: boolean)
			if action == "left" then
				held.left = down
			elseif action == "right" then
				held.right = down
			end
		end,
		stick = function(value: number)
			stickX = if math.abs(value) < 0.2 then 0 else value
		end,
	}
end

local BUILDERS: { [string]: Builder } = {
	whack = buildWhack,
	lanes = buildLanes,
	puzzle = buildPuzzle,
	jump = buildJump,
	catch = buildCatch,
}

local function bindKeys(run: Game)
	local keys = {}
	for key in KEY_ACTION do
		table.insert(keys, key)
	end
	table.insert(keys, Enum.KeyCode.Thumbstick1)
	ContextActionService:BindActionAtPriority(
		ACTION_KEYS,
		function(_name: string, state: Enum.UserInputState, input: InputObject)
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				if run.stick then
					run.stick(if state == Enum.UserInputState.End then 0 else input.Position.X)
				end
				return Enum.ContextActionResult.Sink
			end
			local action = KEY_ACTION[input.KeyCode]
			if action and (state == Enum.UserInputState.Begin or state == Enum.UserInputState.End) then
				run.key(action, state == Enum.UserInputState.Begin)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		PRIORITY,
		table.unpack(keys)
	)
end

local function clearChildren(frame: Instance)
	for _, child in frame:GetChildren() do
		if not child:IsA("UICorner") and not child:IsA("UIStroke") then
			child:Destroy()
		end
	end
end

-- Ряд кнопок внизу окна
local function setButtons(list: { { text: string, color: Color3, onClick: () -> () } })
	local parts = ui
	if not parts then
		return
	end
	clearChildren(parts.buttons)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = parts.buttons
	for _, item in list do
		Ui.button(parts.buttons, item.text, item.color, item.onClick).Size = UDim2.new(0.4, 0, 1, 0)
	end
end

local function showResult(info: any)
	local parts = ui
	if not parts or type(info) ~= "table" or info.token ~= token then
		return
	end
	token = nil
	clearChildren(parts.field)
	local grade = if type(info.grade) == "string" and MEDAL_COLOR[info.grade] then info.grade else nil
	local medal = Ui.label(
		parts.field,
		ClientState.t(if grade then "arcade_" .. grade else "arcade_none"),
		56,
		Ui.titleFontFor(ClientState.lang),
		if grade then MEDAL_COLOR[grade] else Ui.colors.muted
	)
	medal.AnchorPoint = Vector2.new(0.5, 0.5)
	medal.Position = UDim2.fromScale(0.5, 0.36)
	medal.Size = UDim2.new(0.9, 0, 0, if grade then 56 else 34)
	medal.TextXAlignment = Enum.TextXAlignment.Center
	local pop = Instance.new("UIScale")
	pop.Scale = 1.4
	pop.Parent = medal
	TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	local bonus = tonumber(info.bonus) or 0
	if bonus > 0 then
		local money = Ui.label(
			parts.field,
			ClientState.t("arcade_bonus", { money = Texts.money(bonus) }),
			32,
			Ui.titleFontFor(ClientState.lang),
			Ui.colors.money
		)
		money.AnchorPoint = Vector2.new(0.5, 0.5)
		money.Position = UDim2.fromScale(0.5, 0.62)
		money.Size = UDim2.new(0.9, 0, 0, 32)
		money.TextXAlignment = Enum.TextXAlignment.Center
	end
	parts.status.Text = ClientState.t("arcade_score", { n = tonumber(info.score) or 0 })
	setButtons({ { text = ClientState.t("arcade_close"), color = Ui.colors.primary, onClick = close } })
end

local function play(session: any)
	local parts = ui
	local builder = BUILDERS[session.kind]
	if not parts or not builder or type(session.seed) ~= "number" or type(session.token) ~= "number" then
		return
	end
	token = session.token
	local sessionToken = session.token
	local kind = session.kind :: Arcade.Kind
	parts.title.Text = ClientState.t("arcade_title_" .. kind)
	parts.hint.Text = ClientState.t("arcade_hint_" .. kind)
	setButtons({})
	clearChildren(parts.field)
	local duration = tonumber(session.duration) or Arcade.duration
	local countdown = tonumber(session.countdown) or Arcade.countdown
	local score = 0
	local run = builder(parts.field, Arcade.schedule(kind, session.seed), function(n: number)
		score = math.max(score + n, 0)
	end)
	local overlay = glyph(parts.field, "", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(160, 120), 8)
	overlay.Font = Ui.titleFontFor(ClientState.lang)
	local startAt = os.clock() + countdown
	local started = false
	local finished = false
	connect(RunService.RenderStepped, function()
		local t = os.clock() - startAt
		if t < 0 then
			overlay.Text = tostring(math.ceil(-t))
			parts.status.Text = ClientState.t("arcade_score", { n = 0 }) .. "   ⏱ " .. duration
			return
		end
		if not started then
			started = true
			live = true
			overlay.Text = ClientState.t("arcade_go")
			bindKeys(run)
			task.delay(0.6, function()
				overlay.Visible = false
			end)
		end
		if finished then
			return
		end
		if t >= duration then
			finished = true
			live = false
			unbind()
			parts.status.Text = ClientState.t("arcade_score", { n = score })
			overlay.Visible = true
			overlay.Size = UDim2.new(0.9, 0, 0, 40)
			overlay.Text = ClientState.t("arcade_wait")
			local remote = remotes
			if remote then
				remote.ArcadeSubmit:FireServer(sessionToken, score)
			end
			-- Ответ не пришёл — дать закрыть окно
			task.delay(6, function()
				if token == sessionToken and ui == parts then
					setButtons({
						{ text = ClientState.t("arcade_close"), color = Ui.colors.locked, onClick = close },
					})
				end
			end)
			return
		end
		run.step(t)
		parts.status.Text = ClientState.t("arcade_score", { n = score })
			.. "   ⏱ "
			.. math.max(math.ceil(duration - t), 0)
	end)
end

local function onSession(session: any)
	local parts = ui
	if not parts or type(session) ~= "table" or session.projectId ~= waitingProject then
		return
	end
	waitingProject = nil
	if type(session.error) == "string" then
		if session.error == "busy" then
			return
		end
		parts.hint.Text =
			ClientState.t("arcade_err_" .. session.error, { min = tonumber(session.minutes) or 3 })
		parts.hint.TextColor3 = Ui.colors.bad
		setButtons({ { text = ClientState.t("arcade_close"), color = Ui.colors.locked, onClick = close } })
		return
	end
	play(session)
end

-- Можно ли предложить плейтест для этого релиза (кнопка в ReleaseWindow)
function ArcadeWindow.available(info: any): boolean
	return remotes ~= nil
		and Arcade.enabled
		and type(info) == "table"
		and type(info.projectId) == "number"
		and (tonumber(info.revenue) or 0) > 0
		and not played[info.projectId]
end

function ArcadeWindow.open(info: any)
	local remote = remotes
	if not remote or not ArcadeWindow.available(info) then
		return
	end
	close()
	local projectId = info.projectId :: number
	local kind = Arcade.kindFor(tostring(info.genreId))

	local screen = Instance.new("ScreenGui")
	screen.Name = "ArcadeWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 21
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local window = Ui.window(screen, "Window", WINDOW_SIZE)
	local title =
		Ui.label(window, ClientState.t("arcade_title_" .. kind), 36, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.new(1, -72, 0, 36)
	title.TextXAlignment = Enum.TextXAlignment.Center
	local hint = Ui.label(window, ClientState.t("arcade_hint_" .. kind), 22, nil, Ui.colors.muted)
	hint.Position = UDim2.fromOffset(16, 52)
	hint.Size = UDim2.new(1, -32, 0, 22)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	local closeButton = Ui.button(window, "×", Ui.colors.locked, close)
	closeButton.Size = UDim2.fromOffset(40, 40)
	closeButton.Position = UDim2.new(1, -52, 0, 10)

	local field = Instance.new("Frame")
	field.BackgroundColor3 = FIELD_COLOR
	field.ClipsDescendants = true
	field.Position = UDim2.fromOffset(20, 84)
	field.Size = UDim2.new(1, -40, 0, FIELD_HEIGHT)
	Ui.corner(field, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = GAME_COLOR[kind] or Ui.colors.primary
	stroke.Parent = field
	field.Parent = window

	local intro = Ui.label(
		field,
		ClientState.t("arcade_intro", { name = tostring(info.name or ""), sec = Arcade.duration }),
		60
	)
	intro.AnchorPoint = Vector2.new(0.5, 0.5)
	intro.Position = UDim2.fromScale(0.5, 0.5)
	intro.Size = UDim2.new(0.9, 0, 0, 60)
	intro.TextWrapped = true
	intro.TextXAlignment = Enum.TextXAlignment.Center

	local status = Ui.label(window, "", 26, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	status.Position = UDim2.fromOffset(16, 84 + FIELD_HEIGHT + 8)
	status.Size = UDim2.new(1, -32, 0, 26)
	status.TextXAlignment = Enum.TextXAlignment.Center

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Position = UDim2.fromOffset(16, WINDOW_SIZE.Y - 64)
	buttons.Size = UDim2.new(1, -32, 0, 48)
	buttons.Parent = window

	ui = { title = title, hint = hint, field = field, status = status, buttons = buttons }
	setButtons({
		{
			text = ClientState.t("arcade_start"),
			color = GAME_COLOR[kind] or Ui.colors.primary,
			onClick = function()
				if waitingProject or token then
					return
				end
				played[projectId] = true
				waitingProject = projectId
				remote.ArcadeStart:FireServer(projectId)
			end,
		},
		{ text = ClientState.t("arcade_skip"), color = Ui.colors.locked, onClick = close },
	})
end

function ArcadeWindow.start()
	-- Remotes ждём только здесь: ReleaseWindow требует модуль сразу, и без сервера аркады он не должен висеть
	remotes = require(ReplicatedStorage.Shared.ArcadeRemotes) :: any
	local remote = remotes :: { [string]: RemoteEvent }
	remote.ArcadeSession.OnClientEvent:Connect(onSession)
	remote.ArcadeResult.OnClientEvent:Connect(showResult)
end

return ArcadeWindow
