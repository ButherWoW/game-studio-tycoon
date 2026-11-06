--!strict
-- Быстрые события разработки (Config/QuickEvents): полоса, ритм, комбо стрелок, зарядка.
-- Клиент только рисует и шлёт моменты нажатий (время — workspace:GetServerTimeNow());
-- попадание считает сервер (QuickEventService), результат приходит в QuickEventResult.
-- Ввод: большая кнопка / тап, Space / Enter, геймпад ButtonA; стрелки — клавиши, WASD,
-- крестовина или кнопки на экране. Пока событие открыто, эти клавиши не двигают персонажа
-- (иначе Space поднял бы его из-за компьютера и разработка встала бы на паузу).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local QuickEvents = require(ReplicatedStorage.Shared.Config.QuickEvents)
local QuickRemotes = require(ReplicatedStorage.Shared.QuickRemotes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ClientState = require(script.Parent.Parent.ClientState)
local DevState = require(script.Parent.Parent.DevState)
local Ui = require(script.Parent.Parent.Ui)

local PANEL_SIZE = Vector2.new(500, 270)
local RESULT_SECONDS = 1.8
local ACTION_PRESS = "QuickEventPress"
local ACTION_ARROWS = "QuickEventArrows"
local PRIORITY = Enum.ContextActionPriority.High.Value + 10

local ARROW_GLYPH = { up = "▲", down = "▼", left = "◀", right = "▶" }
local KEY_DIRECTION: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Up] = "up",
	[Enum.KeyCode.W] = "up",
	[Enum.KeyCode.DPadUp] = "up",
	[Enum.KeyCode.Down] = "down",
	[Enum.KeyCode.S] = "down",
	[Enum.KeyCode.DPadDown] = "down",
	[Enum.KeyCode.Left] = "left",
	[Enum.KeyCode.A] = "left",
	[Enum.KeyCode.DPadLeft] = "left",
	[Enum.KeyCode.Right] = "right",
	[Enum.KeyCode.D] = "right",
	[Enum.KeyCode.DPadRight] = "right",
}
local GRADE_COLOR = {
	perfect = Ui.colors.good,
	good = Ui.colors.money,
	miss = Ui.colors.bad,
	ignored = Ui.colors.muted,
}

local QuickEventPopup = {}
local gui: ScreenGui? = nil
local current: any = nil -- данные события от сервера
local connections: { RBXScriptConnection } = {}
local inputs = 0 -- сколько нажатий уже отправлено (локальный предел, сервер проверяет сам)
local pressed = false -- «Зарядка»: кнопка зажата
local onPress: (() -> ())? = nil
local onRelease: (() -> ())? = nil
local onArrow: ((direction: string) -> ())? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

-- «+0.4», «−0.15»
function QuickEventPopup.formatDelta(value: number): string
	local text = string.format("%.2f", math.abs(value)):gsub("0+$", ""):gsub("%.$", "")
	return (if value < 0 then "−" else "+") .. text
end

local function unbind()
	ContextActionService:UnbindAction(ACTION_PRESS)
	ContextActionService:UnbindAction(ACTION_ARROWS)
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
	onPress, onRelease, onArrow = nil, nil, nil
	pressed = false
end

local function clear()
	unbind()
	current = nil
	local root = gui
	if root then
		for _, child in root:GetChildren() do
			child:Destroy()
		end
	end
end

local function send(action: string)
	local event = current
	if not event then
		return
	end
	inputs += 1
	QuickRemotes.QuickEventInput:FireServer(event.id, action, now())
end

-- Панель снизу по центру; на маленьком экране целиком уменьшается
local function panel(height: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -96) -- над кнопкой «Создать игру», как событие с выбором
	frame.Size = UDim2.fromOffset(PANEL_SIZE.X, height)
	frame.BackgroundColor3 = Ui.colors.panel
	Ui.corner(frame)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.primary
	stroke.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local height2 = viewport.Y - GuiService:GetGuiInset().Y
	scale.Scale = math.clamp(math.min(viewport.X * 0.94 / PANEL_SIZE.X, height2 * 0.62 / height), 0.45, 1)
	frame.Parent = gui
	return frame
end

local function textLabel(parent: Instance, text: string, y: number, height: number, color: Color3?): TextLabel
	local label = Ui.label(parent, text, height, Ui.titleFontFor(ClientState.lang), color)
	label.Position = UDim2.fromOffset(14, y)
	label.Size = UDim2.new(1, -28, 0, height)
	label.TextXAlignment = Enum.TextXAlignment.Center
	return label
end

local function box(parent: Instance, color: Color3, position: UDim2, size: UDim2, z: number?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Position = position
	frame.Size = size
	frame.ZIndex = z or 1
	frame.Parent = parent
	return frame
end

-- Большая кнопка: нажатие ловим на «вниз» (Activated срабатывает при отпускании — поздно)
local function bigButton(
	parent: Instance,
	text: string,
	color: Color3,
	position: UDim2,
	size: UDim2
): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = color
	button.TextColor3 = Ui.colors.text
	button.Font = Ui.titleFontFor(ClientState.lang)
	button.TextScaled = true
	button.AutoButtonColor = true
	button.Text = text
	button.Position = position
	button.Size = size
	Ui.corner(button, 12)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = button
	button.Parent = parent
	return button
end

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

-- Кнопка действия + Space / Enter / ButtonA
local function bindPress(button: TextButton)
	table.insert(
		connections,
		button.InputBegan:Connect(function(input: InputObject)
			if isPointer(input) and onPress then
				onPress()
			end
		end)
	)
	-- Отпускание ловим глобально: палец мог съехать с кнопки
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if isPointer(input) and pressed and onRelease then
				onRelease()
			end
		end)
	)
	ContextActionService:BindActionAtPriority(
		ACTION_PRESS,
		function(_name: string, state: Enum.UserInputState, _input: InputObject)
			if state == Enum.UserInputState.Begin and onPress then
				onPress()
			elseif state == Enum.UserInputState.End and onRelease then
				onRelease()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		PRIORITY,
		Enum.KeyCode.Space,
		Enum.KeyCode.Return,
		Enum.KeyCode.ButtonA
	)
end

local function bindArrows()
	local keys = {}
	for key in KEY_DIRECTION do
		table.insert(keys, key)
	end
	ContextActionService:BindActionAtPriority(
		ACTION_ARROWS,
		function(_name: string, state: Enum.UserInputState, input: InputObject)
			local direction = KEY_DIRECTION[input.KeyCode]
			if state == Enum.UserInputState.Begin and direction and onArrow then
				onArrow(direction)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		PRIORITY,
		table.unpack(keys)
	)
end

local function everyFrame(fn: (t: number) -> ())
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function()
			fn(now())
		end)
	)
end

-- Полоса оставшегося времени внизу панели
local function timeBar(frame: Frame, event: any)
	local bar = box(frame, Ui.colors.primary, UDim2.new(0, 14, 1, -12), UDim2.new(1, -28, 0, 5))
	Ui.corner(bar, 3)
	local total = math.max(event.expiresAt - event.startedAt, 0.1)
	everyFrame(function(t: number)
		local left = math.clamp((event.expiresAt - t) / total, 0, 1)
		bar.Size = UDim2.new(left, -28 * left, 0, 5)
	end)
end

-- Шкала с зелёной зоной (полоса и зарядка). Возвращает рамку шкалы
local function zoneBar(frame: Frame, event: any, y: number): Frame
	local track = box(frame, Color3.fromRGB(44, 46, 66), UDim2.new(0, 24, 0, y), UDim2.new(1, -48, 0, 34))
	track.ClipsDescendants = true
	Ui.corner(track, 8)
	local width = tonumber(event.zoneWidth) or 0.2
	local center = tonumber(event.zoneCenter) or 0.5
	local share = tonumber(event.perfectShare) or 0.45
	box(track, Ui.colors.good, UDim2.fromScale(center - width / 2, 0), UDim2.fromScale(width, 1), 2).BackgroundTransparency =
		0.35
	box(
		track,
		Ui.colors.good,
		UDim2.fromScale(center - width * share / 2, 0),
		UDim2.fromScale(width * share, 1),
		3
	)
	return track
end

local function buildTiming(frame: Frame, event: any)
	local track = zoneBar(frame, event, 96)
	local marker = box(track, Ui.colors.text, UDim2.fromScale(0, 0), UDim2.new(0, 6, 1, 0), 5)
	marker.AnchorPoint = Vector2.new(0.5, 0)
	local stopped: number? = nil
	everyFrame(function(t: number)
		local at = stopped or t
		local value = QuickEvents.sweep(at - event.startedAt - event.leadIn, event.period, event.phase)
		marker.Position = UDim2.fromScale(value, 0)
	end)
	local button = bigButton(
		frame,
		ClientState.t("qte_press"),
		Ui.colors.primary,
		UDim2.new(0.5, -110, 0, 150),
		UDim2.fromOffset(220, 90)
	)
	bindPress(button)
	onPress = function()
		if not stopped and now() >= event.startedAt + event.leadIn then
			stopped = now()
			send("press")
		end
	end
end

local function buildRhythm(frame: Frame, event: any)
	local beats = math.clamp(tonumber(event.beats) or 3, 1, 6)
	local interval = tonumber(event.interval) or 0.8
	local window = QuickEvents.rhythm.goodWindow
	local circles: { Frame } = {}
	for index = 1, beats do
		local x = (index - 0.5) / beats
		local circle = box(frame, Ui.colors.locked, UDim2.new(x, 0, 0, 116), UDim2.fromOffset(52, 52), 2)
		circle.AnchorPoint = Vector2.new(0.5, 0.5)
		Ui.corner(circle, 26)
		table.insert(circles, circle)
	end
	everyFrame(function(t: number)
		for index, circle in circles do
			local beatAt = event.startedAt + event.leadIn + (index - 1) * interval
			local closeness = math.clamp(1 - math.abs(t - beatAt) / 0.3, 0, 1)
			local size = 52 + 30 * closeness
			circle.Size = UDim2.fromOffset(size, size)
			if circle:GetAttribute("Tapped") ~= true then
				circle.BackgroundColor3 = if math.abs(t - beatAt) <= window
					then Ui.colors.money
					else Ui.colors.locked
			end
		end
	end)
	local button = bigButton(
		frame,
		ClientState.t("qte_press"),
		Ui.colors.primary,
		UDim2.new(0.5, -110, 0, 156),
		UDim2.fromOffset(220, 84)
	)
	bindPress(button)
	onPress = function()
		local t = now()
		if inputs >= beats + 2 or t < event.startedAt + event.leadIn - window then
			return
		end
		-- Подсветить ближайший удар
		local nearest =
			math.clamp(math.floor((t - event.startedAt - event.leadIn) / interval + 0.5) + 1, 1, beats)
		local circle = circles[nearest]
		circle:SetAttribute("Tapped", true)
		local beatAt = event.startedAt + event.leadIn + (nearest - 1) * interval
		circle.BackgroundColor3 = if math.abs(t - beatAt) <= window then Ui.colors.good else Ui.colors.bad
		send("press")
	end
end

local function buildSequence(frame: Frame, event: any)
	local sequence: { string } = if type(event.sequence) == "table" then event.sequence else {}
	local cells: { TextLabel } = {}
	local count = math.max(#sequence, 1)
	for index, direction in sequence do
		local cell = textLabel(frame, ARROW_GLYPH[direction] or "?", 0, 50, Ui.colors.money)
		cell.Font = Enum.Font.GothamBold
		cell.AnchorPoint = Vector2.new(0.5, 0)
		cell.Position = UDim2.new((index - 0.5) / count, 0, 0, 90)
		cell.Size = UDim2.fromOffset(60, 50)
		table.insert(cells, cell)
	end
	local typed = 0
	local hidden = false
	everyFrame(function(t: number)
		if not hidden and t >= event.startedAt + event.leadIn then
			hidden = true
			for _, cell in cells do
				cell.Text = "?"
				cell.TextColor3 = Ui.colors.muted
			end
		end
	end)
	-- Кнопки-стрелки (для телефона; на ПК тоже можно нажимать)
	local order = { "left", "up", "down", "right" }
	for index, direction in order do
		local button = bigButton(
			frame,
			ARROW_GLYPH[direction],
			Ui.colors.primary,
			UDim2.new((index - 1) / 4, 14 - (index - 1) * 7, 0, 156),
			UDim2.new(0.25, -21, 0, 84)
		)
		button.Font = Enum.Font.GothamBold
		table.insert(
			connections,
			button.InputBegan:Connect(function(input: InputObject)
				if isPointer(input) and onArrow then
					onArrow(direction)
				end
			end)
		)
	end
	bindArrows()
	onArrow = function(direction: string)
		if not hidden or typed >= #sequence then
			return
		end
		typed += 1
		local cell = cells[typed]
		cell.Text = ARROW_GLYPH[direction] or "?"
		cell.TextColor3 = if sequence[typed] == direction then Ui.colors.good else Ui.colors.bad
		send(direction)
	end
end

local function buildHold(frame: Frame, event: any)
	local track = zoneBar(frame, event, 96)
	local fill = box(track, Ui.colors.primary, UDim2.fromScale(0, 0), UDim2.fromScale(0, 1), 4)
	fill.BackgroundTransparency = 0.15
	local fillSeconds = tonumber(event.fillSeconds) or 1.6
	local pressAt: number? = nil
	local releasedAt: number? = nil
	everyFrame(function(t: number)
		local startAt = pressAt
		if startAt then
			local value = ((releasedAt or t) - startAt) / fillSeconds
			fill.Size = UDim2.fromScale(math.clamp(value, 0, 1), 1)
			fill.BackgroundColor3 = if value > 1 then Ui.colors.bad else Ui.colors.primary
		end
	end)
	local button = bigButton(
		frame,
		ClientState.t("qte_hold_button"),
		Ui.colors.primary,
		UDim2.new(0.5, -110, 0, 150),
		UDim2.fromOffset(220, 90)
	)
	bindPress(button)
	onPress = function()
		if not pressAt and now() >= event.startedAt + event.leadIn then
			pressAt = now()
			pressed = true
			send("press")
		end
	end
	onRelease = function()
		if pressAt and not releasedAt then
			releasedAt = now()
			pressed = false
			send("release")
		end
	end
end

local BUILDERS: { [string]: (Frame, any) -> () } = {
	timing = buildTiming,
	rhythm = buildRhythm,
	sequence = buildSequence,
	hold = buildHold,
}

local function show(event: any)
	if type(event) ~= "table" or type(event.id) ~= "number" or type(event.kind) ~= "string" then
		return
	end
	local builder = BUILDERS[event.kind]
	if not builder then
		return
	end
	clear()
	current = event
	inputs = 0
	local frame = panel(PANEL_SIZE.Y)
	textLabel(frame, ClientState.t("qte_" .. event.kind .. "_title"), 10, 40)
	local hint = textLabel(frame, ClientState.t("qte_ready"), 52, 26, Ui.colors.muted)
	local hintKey = if event.kind == "sequence" then "qte_sequence_hint" else "qte_" .. event.kind .. "_hint"
	everyFrame(function(t: number)
		-- Пока «приготовься»/показ стрелок — подсказка, потом — что делать
		if t >= event.startedAt + event.leadIn then
			hint.Text = ClientState.t(if event.kind == "sequence" then "qte_repeat" else hintKey)
		elseif event.kind == "sequence" then
			hint.Text = ClientState.t(hintKey)
		end
	end)
	builder(frame, event)
	timeBar(frame, event)
	-- Сервер закроет событие сам; это — страховка, если ответ не дошёл
	local id = event.id
	task.delay(math.max(event.expiresAt - now(), 0) + 3, function()
		if current and current.id == id then
			clear()
		end
	end)
end

local function showResult(info: any)
	if type(info) ~= "table" or not current or info.id ~= current.id then
		return
	end
	clear()
	local grade = info.grade
	if grade == "cancel" or not GRADE_COLOR[grade] then
		return
	end
	local frame = panel(56)
	local delta = tonumber(info.delta) or 0
	local label = textLabel(
		frame,
		ClientState.t("qte_" .. grade) .. "  " .. QuickEventPopup.formatDelta(delta),
		8,
		40,
		GRADE_COLOR[grade]
	)
	local pop = Instance.new("UIScale")
	pop.Scale = 1.3
	pop.Parent = label
	task.spawn(function()
		for step = 1, 6 do
			task.wait(0.03)
			pop.Scale = 1.3 - 0.05 * step
		end
	end)
	task.delay(RESULT_SECONDS, function()
		if frame.Parent then
			frame:Destroy()
		end
	end)
end

function QuickEventPopup.start()
	local screen = Instance.new("ScreenGui")
	screen.Name = "QuickEventPopup"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 16
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	QuickRemotes.QuickEvent.OnClientEvent:Connect(show)
	QuickRemotes.QuickEventResult.OnClientEvent:Connect(showResult)
	-- Пауза (встал из-за ПК) или проектов не осталось: быстрое событие разработки не должно висеть.
	-- Сервер тоже его закроет; это — страховка на случай потерянного ответа
	Remotes.DevelopmentProgress.OnClientEvent:Connect(function(data: any)
		if current and type(data) == "table" and data.paused == true then
			clear()
		end
	end)
	DevState.changed:Connect(function()
		if current and #DevState.projects == 0 then
			clear()
		end
	end)
	Remotes.GameReleased.OnClientEvent:Connect(function(info: any)
		-- Событие второй игры в разработке не прячем
		if type(info) == "table" and (tonumber(info.activeProjects) or 0) > 0 then
			return
		end
		if current then
			clear()
		end
	end)
end

return QuickEventPopup
