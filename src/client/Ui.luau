--!strict
-- Стиль интерфейса из issue #5 и общие конструкторы элементов.

local GuiService = game:GetService("GuiService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Ui = {}

-- Телефон/планшет: кнопки не меньше пальца, боковое меню не лезет на джойстик
Ui.touch = UserInputService.TouchEnabled
Ui.MIN_TOUCH = 44

-- Пока открыто окно игры, прячем окно чата: оно рисуется поверх нашего UI и забирает клики
local openWindows = 0

function Ui.windowOpened()
	openWindows += 1
	TextChatService.ChatWindowConfiguration.Enabled = false
end

function Ui.windowClosed()
	openWindows = math.max(openWindows - 1, 0)
	if openWindows == 0 then
		TextChatService.ChatWindowConfiguration.Enabled = true
	end
end

Ui.colors = {
	primary = Color3.fromRGB(61, 123, 255),
	money = Color3.fromRGB(255, 201, 60),
	panel = Color3.fromRGB(30, 30, 46),
	stroke = Color3.fromRGB(62, 64, 90),
	text = Color3.new(1, 1, 1),
	muted = Color3.fromRGB(184, 188, 208),
	good = Color3.fromRGB(61, 220, 132),
	bad = Color3.fromRGB(255, 90, 95),
	locked = Color3.fromRGB(70, 72, 90),
}

Ui.titleFont = Enum.Font.FredokaOne
Ui.bodyFont = Enum.Font.GothamBold

-- В Fredoka One нет кириллицы, греческого, деванагари и иероглифов
local NON_LATIN_LANGS: { [string]: boolean } = {
	ru = true,
	uk = true,
	bg = true,
	sr = true,
	el = true,
	["zh-cn"] = true,
	hi = true,
}

-- Шрифт заголовков для языка интерфейса (передавай ClientState.lang)
function Ui.titleFontFor(lang: string): Enum.Font
	return if NON_LATIN_LANGS[lang] then Enum.Font.GothamBold else Ui.titleFont
end

function Ui.scoreColor(score: number): Color3
	if score >= 8 then
		return Ui.colors.good
	elseif score >= 5 then
		return Ui.colors.money
	end
	return Ui.colors.bad
end

function Ui.corner(parent: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
end

-- Окно по центру экрана; maxSize ограничивает размер на больших мониторах
-- Окно по центру. Строится в «дизайнерском» размере maxSize и целиком уменьшается UIScale,
-- если экран меньше: раньше на невысоком экране кнопки внизу обрезались, а текст наезжал (отчёт #42)
function Ui.window(parent: Instance, name: string, maxSize: Vector2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(maxSize.X, maxSize.Y)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local function fit()
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		-- ScreenGui рисуется под верхней панелью Roblox: на телефоне 844×390 это ~58 px из 390
		local inset = GuiService:GetGuiInset()
		local height = viewport.Y - inset.Y
		scale.Scale = math.clamp(math.min(viewport.X * 0.94 / maxSize.X, height * 0.92 / maxSize.Y), 0.4, 1)
	end
	fit()
	local camera = workspace.CurrentCamera
	if camera then
		local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
		frame.Destroying:Connect(function()
			connection:Disconnect()
		end)
	end
	frame.BackgroundColor3 = Ui.colors.panel
	frame.BackgroundTransparency = 0.05
	Ui.corner(frame)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.stroke
	stroke.Parent = frame
	frame.Parent = parent
	return frame
end

function Ui.label(parent: Instance, text: string, height: number, font: Enum.Font?, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, height)
	l.BackgroundTransparency = 1
	l.Font = font or Ui.bodyFont
	l.TextColor3 = color or Ui.colors.text
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

-- Кнопка с эффектом нажатия (сжимается до 95%)
function Ui.button(parent: Instance, text: string, color: Color3, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = color
	b.TextColor3 = Ui.colors.text
	b.Font = Ui.bodyFont
	b.TextScaled = true
	b.AutoButtonColor = true
	b.Text = text
	Ui.corner(b, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.MouseButton1Down:Connect(function()
		scale.Scale = 0.95
	end)
	b.MouseButton1Up:Connect(function()
		scale.Scale = 1
	end)
	b.MouseLeave:Connect(function()
		scale.Scale = 1
	end)
	b.Activated:Connect(onClick)
	if Ui.touch then
		Ui.touchPad(b, onClick, scale)
	end
	b.Parent = parent
	return b
end

-- На тач-экране окна уменьшаются UIScale, и кнопка 40 px становится 25 px. Прозрачная
-- «подушка» поверх кнопки растягивает зону нажатия до MIN_TOUCH px по каждой оси (по центру),
-- сам вид кнопки не меняется. Нажатие ловит подушка и вызывает тот же onClick.
function Ui.touchPad(b: GuiButton, onClick: () -> (), pressScale: UIScale?)
	local pad = Instance.new("TextButton")
	pad.Name = "TouchPad"
	pad.Text = ""
	pad.BackgroundTransparency = 1
	pad.AutoButtonColor = false
	pad.AnchorPoint = Vector2.new(0.5, 0.5)
	pad.Position = UDim2.fromScale(0.5, 0.5)
	pad.Size = UDim2.fromScale(1, 1)
	pad.ZIndex = b.ZIndex
	local sx, sy = 1, 1
	-- Подушка лежит внутри UIPadding кнопки, поэтому её «1» — область без отступов:
	-- меряем её через собственный AbsoluteSize и подбираем масштаб под нужный размер
	local function fit()
		local own, button = pad.AbsoluteSize, b.AbsoluteSize
		if own.X <= 0 or own.Y <= 0 or button.X <= 0 or button.Y <= 0 then
			return
		end
		local inner = Vector2.new(own.X / sx, own.Y / sy)
		local nx = math.max(button.X, Ui.MIN_TOUCH) / inner.X
		local ny = math.max(button.Y, Ui.MIN_TOUCH) / inner.Y
		if math.abs(nx - sx) > 0.01 or math.abs(ny - sy) > 0.01 then
			sx, sy = nx, ny
			pad.Size = UDim2.fromScale(sx, sy)
		end
	end
	pad:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	b:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	if pressScale then
		pad.MouseButton1Down:Connect(function()
			pressScale.Scale = 0.95
		end)
		pad.MouseButton1Up:Connect(function()
			pressScale.Scale = 1
		end)
		pad.MouseLeave:Connect(function()
			pressScale.Scale = 1
		end)
	end
	pad.Activated:Connect(onClick)
	pad.Parent = b
end

-- Боковое меню слева посередине (слева сверху чат, справа сверху список игроков).
-- Слоты, чтобы фичи не спорили за место: 1 исследования, 2 сотрудники, 3 задания,
-- 4 магазин, 5 rebirth, 6 язык. order внутри слота не нужен — один слот, одна кнопка.
local menuColumn: Frame? = nil
local MENU_BUTTON = 52
local MENU_GAP = 8
-- Сверху HUD и плашки, снизу кнопка «Создать игру»: столько по высоте меню не занимает
local MENU_RESERVED = 200

-- Тач: меню начинается сверху и не опускается в нижние MENU_TOUCH_BOTTOM px —
-- там джойстик (низ-лево). Не влезло в высоту — следующий столбец справа, кнопки не мельчают
local MENU_TOUCH_TOP = 8
local MENU_TOUCH_BOTTOM = 120

-- Колонка кнопок сама уменьшается, если все не влезают по высоте (ПК с низким окном);
-- на тач-экране вместо уменьшения кнопки переносятся в соседний столбец (≥ 44 px)
local function fitMenu(column: Frame, scale: UIScale)
	local camera = workspace.CurrentCamera
	local count = 0
	for _, child in column:GetChildren() do
		if child:IsA("GuiButton") then
			count += 1
		end
	end
	local grid = column:FindFirstChildOfClass("UIGridLayout")
	if grid then
		local screen = column.Parent
		local height = if screen and screen:IsA("ScreenGui") then screen.AbsoluteSize.Y else 0
		if height <= 0 then
			height = (if camera then camera.ViewportSize.Y else 720) - GuiService:GetGuiInset().Y
		end
		local available = height - MENU_TOUCH_TOP - MENU_TOUCH_BOTTOM
		local perColumn = math.max(math.floor((available + MENU_GAP) / (MENU_BUTTON + MENU_GAP)), 1)
		grid.FillDirectionMaxCells = perColumn
		return
	end
	local needed = count * (MENU_BUTTON + MENU_GAP)
	local available = (if camera then camera.ViewportSize.Y else 720) - MENU_RESERVED
	scale.Scale = if needed > 0 then math.clamp(available / needed, 0.55, 1) else 1
end

function Ui.menuButton(slot: number, icon: string, onClick: () -> ()): TextButton
	if not menuColumn then
		local Players = game:GetService("Players")
		local screen = Instance.new("ScreenGui")
		screen.Name = "SideMenu"
		screen.ResetOnSpawn = false
		local column = Instance.new("Frame")
		column.Name = "Column"
		column.BackgroundTransparency = 1
		column.AnchorPoint = Vector2.new(0, 0.5)
		column.Position = UDim2.new(0, 12, 0.5, 0)
		column.Size = UDim2.fromOffset(MENU_BUTTON, 0)
		column.AutomaticSize = Enum.AutomaticSize.Y
		if Ui.touch then
			-- Сверху вниз столбцами, сколько влезает над джойстиком (fitMenu)
			column.AnchorPoint = Vector2.new(0, 0)
			column.Position = UDim2.fromOffset(12, MENU_TOUCH_TOP)
			column.Size = UDim2.new()
			column.AutomaticSize = Enum.AutomaticSize.XY
			local grid = Instance.new("UIGridLayout")
			grid.SortOrder = Enum.SortOrder.LayoutOrder
			grid.FillDirection = Enum.FillDirection.Vertical
			grid.CellSize = UDim2.fromOffset(MENU_BUTTON, MENU_BUTTON)
			grid.CellPadding = UDim2.fromOffset(MENU_GAP, MENU_GAP)
			grid.Parent = column
		else
			local layout = Instance.new("UIListLayout")
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0, MENU_GAP)
			layout.Parent = column
		end
		local scale = Instance.new("UIScale")
		scale.Parent = column
		column.Parent = screen
		screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		menuColumn = column
		column.ChildAdded:Connect(function()
			fitMenu(column, scale)
		end)
		screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			fitMenu(column, scale)
		end)
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				fitMenu(column, scale)
			end)
		end
	end
	-- Слот задаёт порядок сверху вниз: 1 исследования, 2 команда, 3 задания, 4 магазин, 5 rebirth,
	-- 6 язык, 7 хиты, 8 воры, 10 вид студии
	local b = Ui.button(menuColumn :: Frame, icon, Ui.colors.panel, onClick)
	b.Name = "Slot" .. slot
	b.LayoutOrder = slot
	b.Size = UDim2.fromOffset(MENU_BUTTON, MENU_BUTTON)
	return b
end

-- Общий стек плашек под HUD (тренд, выставка, итоги выставки, тревога): каждая плашка
-- кладётся сюда со своим LayoutOrder, скрытые не занимают места — плашки не наезжают друг на друга.
-- HUD занимает y 12..132 (3 плашки по 40 px), стек начинается ниже.
local BANNER_TOP = 140
local BANNER_GAP = 6
-- Низкий экран (телефон в альбомной): плашки стека чуть меньше, чтобы не дойти до кнопки «Создать игру»
local SHORT_SCREEN = 500
local SHORT_SCALE = 0.8
local bannerStack: Frame? = nil

function Ui.bannerStack(): Frame
	local existing = bannerStack
	if existing then
		return existing
	end
	local Players = game:GetService("Players")
	local screen = Instance.new("ScreenGui")
	screen.Name = "Banners"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 1 -- над HUD (0), под окнами (10+)
	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = UDim2.new(0.5, 0, 0, BANNER_TOP)
	stack.Size = UDim2.new(1, 0, 0, 0)
	stack.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Ui.list(stack, BANNER_GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local scale = Instance.new("UIScale")
	scale.Parent = stack
	local function fit()
		local camera = workspace.CurrentCamera
		local height = if camera then camera.ViewportSize.Y else 720
		scale.Scale = if height < SHORT_SCREEN then SHORT_SCALE else 1
	end
	fit()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	stack.Parent = screen
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	bannerStack = stack
	return stack
end

function Ui.list(parent: Instance, padding: number)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = parent
	return layout
end

return Ui
