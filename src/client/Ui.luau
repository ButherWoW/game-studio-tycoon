--!strict
-- Стиль интерфейса из issue #5 и общие конструкторы элементов.

local GuiService = game:GetService("GuiService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Images = require(ReplicatedStorage.Shared.Config.Images)
local Unlocks = require(ReplicatedStorage.Shared.Config.Unlocks)

local Ui = {}

-- Телефон/планшет: кнопки не меньше пальца, боковое меню не лезет на джойстик
Ui.touch = UserInputService.TouchEnabled
Ui.MIN_TOUCH = 44

-- Пока открыто окно игры, прячем окно чата: оно рисуется поверх нашего UI и забирает клики
local openWindows = 0
-- Окно меню, открытое сейчас (его close): окна меню взаимоисключающие — новое закрывает старое,
-- иначе два окна DisplayOrder 10 лежали друг на друге. Закрыть уже закрытое окно — ничего не делает
local exclusiveClose: (() -> ())? = nil

-- close — передают окна меню (кнопки бокового меню): открытие такого окна закрывает
-- предыдущее окно меню. Всплывающие окна (награда, банк, релиз…) зовут без аргумента
function Ui.windowOpened(close: (() -> ())?)
	if close then
		local previous = exclusiveClose
		exclusiveClose = close
		if previous and previous ~= close then
			previous()
		end
	end
	openWindows += 1
	TextChatService.ChatWindowConfiguration.Enabled = false
end

-- Открыто ли сейчас хоть одно окно игры (HUD не открывает «Создать игру» поверх него)
function Ui.anyWindowOpen(): boolean
	return openWindows > 0
end

function Ui.windowClosed()
	openWindows = math.max(openWindows - 1, 0)
	if openWindows == 0 then
		TextChatService.ChatWindowConfiguration.Enabled = true
	end
end

local CLICK_DEBOUNCE = 0.15 -- секунд между срабатываниями одной кнопки

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

-- Картинка из Config/Images поверх объекта: квадрат по высоте holder (с учётом UIPadding),
-- по центру или у левого края (align = "left"). id 0/nil — ничего не делает и возвращает nil:
-- тогда остаётся эмодзи, а убрать текст или сдвинуть его вызывающий решает сам по результату
function Ui.artImage(holder: GuiObject, imageId: number?, align: string?): ImageLabel?
	if not imageId or imageId <= 0 then
		return nil
	end
	local image = Instance.new("ImageLabel")
	image.Name = "Art"
	image.BackgroundTransparency = 1
	image.SizeConstraint = Enum.SizeConstraint.RelativeYY
	image.Size = UDim2.fromScale(1, 1)
	image.ScaleType = Enum.ScaleType.Fit
	if align == "left" then
		image.AnchorPoint = Vector2.new(0, 0.5)
		image.Position = UDim2.fromScale(0, 0.5)
	else
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
	end
	image.ZIndex = holder.ZIndex
	image.Image = "rbxassetid://" .. imageId
	image.Parent = holder
	return image
end

-- Текст без эмодзи в начале («🎁 Подарить» → «Подарить»), когда эмодзи заменила картинка
function Ui.stripIcon(text: string, icon: string): string
	if string.sub(text, 1, #icon) == icon then
		return (string.gsub(string.sub(text, #icon + 1), "^%s+", ""))
	end
	return text
end

-- Боковое меню (Ui.menuButton): колонка кнопок, нужна окнам (дыра в подложке) и плашкам
local menuColumn: Frame? = nil
-- Пересчитать стек плашек (задаёт Ui.bannerStack): меню на тач-экране сменило ширину
local refitBanners: () -> () = function() end

-- Прямоугольник бокового меню в координатах экрана; nil — меню нет или оно пустое
local function menuRect(): (Vector2?, Vector2?)
	local column = menuColumn
	if not column or not column.Parent then
		return nil, nil
	end
	local size = column.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil, nil
	end
	return column.AbsolutePosition, size
end

-- Не шире столько окно уменьшаем на низком экране (телефон в альбомной): ниже текст не прочитать.
-- Окно с растягиваемой прокруткой тогда становится ниже в «дизайнерских» px, а тело прокручивается
local SHORT_MIN_SCALE = 0.65
local MENU_HOLE_MARGIN = 4

-- Тело окна тянется по высоте: ScrollingFrame, у которого он сам и все рамки до окна
-- заданы долей высоты (Size.Y.Scale > 0). Такое окно можно сделать ниже — тело прокрутится
local function hasStretchyScroll(frame: Frame): boolean
	for _, item in frame:GetDescendants() do
		if item:IsA("ScrollingFrame") and item.Size.Y.Scale > 0 then
			local node = item.Parent
			local stretchy = true
			while node and node ~= frame do
				if node:IsA("GuiObject") and node.Size.Y.Scale <= 0 then
					stretchy = false
					break
				end
				node = node.Parent
			end
			if stretchy then
				return true
			end
		end
	end
	return false
end

-- Прозрачная подложка во весь экран под окном (Active): нажатия мимо окна не доходят до HUD,
-- плашек и мира под ним. Боковое меню остаётся доступным — в подложке дыра под колонку меню
-- (через меню переключают окна, Ui.windowOpened). Три куска: справа от меню, над ним и под ним
local function backdrop(parent: Instance, frame: Frame)
	local holder = Instance.new("Frame")
	holder.Name = "Backdrop"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 0
	local pieces: { Frame } = {}
	for i = 1, 3 do
		local piece = Instance.new("Frame")
		piece.Name = "Block" .. i
		piece.BackgroundTransparency = 1
		piece.BorderSizePixel = 0
		piece.Active = true
		piece.ZIndex = 0
		piece.Parent = holder
		pieces[i] = piece
	end
	local function layout()
		local position, size = menuRect()
		if not position or not size then
			pieces[1].Position = UDim2.new()
			pieces[1].Size = UDim2.fromScale(1, 1)
			pieces[2].Visible = false
			pieces[3].Visible = false
			return
		end
		local origin = holder.AbsolutePosition
		local right = position.X - origin.X + size.X + MENU_HOLE_MARGIN
		local top = math.max(position.Y - origin.Y - MENU_HOLE_MARGIN, 0)
		local bottom = position.Y - origin.Y + size.Y + MENU_HOLE_MARGIN
		pieces[1].Position = UDim2.fromOffset(right, 0)
		pieces[1].Size = UDim2.new(1, -right, 1, 0)
		pieces[2].Visible = true
		pieces[2].Position = UDim2.new()
		pieces[2].Size = UDim2.fromOffset(right, top)
		pieces[3].Visible = true
		pieces[3].Position = UDim2.fromOffset(0, bottom)
		pieces[3].Size = UDim2.new(0, right, 1, -bottom)
	end
	local connections: { RBXScriptConnection } = {
		holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout),
		frame:GetPropertyChangedSignal("Visible"):Connect(function()
			holder.Visible = frame.Visible
		end),
	}
	local column = menuColumn
	if column then
		table.insert(connections, column:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
		table.insert(connections, column:GetPropertyChangedSignal("AbsolutePosition"):Connect(layout))
	end
	frame.Destroying:Connect(function()
		for _, connection in connections do
			connection:Disconnect()
		end
		holder:Destroy()
	end)
	-- Подложка раньше окна в дереве и с ZIndex 0: при любом ZIndexBehavior она под окном
	holder.Parent = parent
	layout()
end

-- Окно по центру. Строится в «дизайнерском» размере maxSize и целиком уменьшается UIScale,
-- если экран меньше: раньше на невысоком экране кнопки внизу обрезались, а текст наезжал (отчёт #42).
-- На низком экране масштаб не меньше SHORT_MIN_SCALE, если тело окна прокручивается: окно
-- становится ниже, лишнее уходит в прокрутку (иначе на телефоне текст был ~45% и не читался)
function Ui.window(parent: Instance, name: string, maxSize: Vector2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(maxSize.X, maxSize.Y)
	-- Окно забирает нажатия: раньше тап по фону окна проходил к кнопкам под ним
	frame.Active = true
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	-- Тело тянется по высоте (hasStretchyScroll): содержимое окна появляется после Ui.window,
	-- поэтому проверяем по DescendantAdded раз в кадр, пока не найдём
	local stretchy = false
	local function fit()
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		-- ScreenGui рисуется под верхней панелью Roblox: на телефоне 844×390 это ~58 px из 390
		local inset = GuiService:GetGuiInset()
		local height = viewport.Y - inset.Y
		local byWidth = viewport.X * 0.94 / maxSize.X
		local natural = math.min(byWidth, height * 0.92 / maxSize.Y)
		local value = math.clamp(natural, 0.4, 1)
		local designHeight = maxSize.Y
		if stretchy and natural < SHORT_MIN_SCALE then
			local floor = math.min(SHORT_MIN_SCALE, byWidth)
			if floor > natural then
				value = floor
				designHeight = math.floor(height * 0.92 / floor)
			end
		end
		scale.Scale = value
		frame.Size = UDim2.fromOffset(maxSize.X, designHeight)
	end
	fit()
	local checkScheduled = false
	local descendantConnection: RBXScriptConnection? = nil
	descendantConnection = frame.DescendantAdded:Connect(function()
		if checkScheduled or stretchy then
			return
		end
		checkScheduled = true
		task.defer(function()
			checkScheduled = false
			if stretchy or not frame.Parent then
				return
			end
			if hasStretchyScroll(frame) then
				stretchy = true
				local connection = descendantConnection
				if connection then
					connection:Disconnect()
				end
				fit()
			end
		end)
	end)
	local camera = workspace.CurrentCamera
	if camera then
		local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
		frame.Destroying:Connect(function()
			connection:Disconnect()
		end)
	end
	backdrop(parent, frame)
	frame.BackgroundColor3 = Ui.colors.panel
	-- Непрозрачный фон: сквозь полупрозрачный просвечивали цифры HUD (отчёт #2, п. 9)
	frame.BackgroundTransparency = 0
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
	-- Кнопка и тач-подушка над ней не должны сработать на одно нажатие дважды
	-- (иначе подтверждения «нажми ещё раз» проходят сами)
	local lastClick = 0
	local function click()
		local now = os.clock()
		if now - lastClick < CLICK_DEBOUNCE then
			return
		end
		lastClick = now
		onClick()
	end
	b.Activated:Connect(click)
	if Ui.touch then
		Ui.touchPad(b, click, scale)
	end
	b.Parent = parent
	return b
end

-- На тач-экране окна уменьшаются UIScale, и кнопка 40 px становится 25 px. Прозрачная
-- «подушка» поверх кнопки растягивает зону нажатия до MIN_TOUCH px по каждой оси,
-- сам вид кнопки не меняется. Нажатие ловит подушка и вызывает тот же onClick.
-- Подушка не залезает на соседние кнопки: в плотных рядах (фокус −/+, сетка жанров,
-- перки команды) она растёт в сторону соседа не больше чем на половину зазора до него,
-- иначе соседняя подушка перехватывала нажатия (поле ввода тоже считается соседом).
type PadFit = () -> ()
local padFits: { [TextButton]: PadFit } = {}
local refitScheduled = false

-- Пересчитать все подушки за один кадр: кнопки окна создаются пачкой, и подушка,
-- посчитанная раньше соседа, иначе о нём не узнала бы
local function scheduleRefit()
	if refitScheduled then
		return
	end
	refitScheduled = true
	task.defer(function()
		refitScheduled = false
		for pad, fit in padFits do
			if pad.Parent then
				fit()
			else
				padFits[pad] = nil
			end
		end
	end)
end

-- Где искать соседей: ближайший ScrollingFrame (внутри него всё прокручивается вместе)
-- или весь ScreenGui
local function padScope(b: GuiButton): Instance?
	local node = b.Parent
	while node do
		if node:IsA("ScrollingFrame") or node:IsA("LayerCollector") then
			return node
		end
		node = node.Parent
	end
	return nil
end

function Ui.touchPad(b: GuiButton, onClick: () -> (), pressScale: UIScale?)
	local pad = Instance.new("TextButton")
	pad.Name = "TouchPad"
	pad.Text = ""
	pad.BackgroundTransparency = 1
	pad.AutoButtonColor = false
	pad.Position = UDim2.fromScale(0, 0)
	pad.Size = UDim2.fromScale(1, 1)
	pad.ZIndex = b.ZIndex
	-- Подушка лежит внутри UIPadding кнопки, поэтому её «1» — область без отступов.
	-- Эту область меряем пустой рамкой во всю неё (сама подушка меняет размер — по ней нельзя)
	local ref = Instance.new("Frame")
	ref.Name = "TouchPadRef"
	ref.BackgroundTransparency = 1
	ref.Size = UDim2.fromScale(1, 1)
	ref.Parent = b
	-- Текущий прямоугольник подушки в долях внутренней области кнопки
	local px, py, sx, sy = 0, 0, 1, 1
	local function fit()
		local innerSize, button = ref.AbsoluteSize, b.AbsoluteSize
		if innerSize.X <= 0 or innerSize.Y <= 0 or button.X <= 0 or button.Y <= 0 then
			return
		end
		local innerPos = ref.AbsolutePosition
		local x0, y0 = b.AbsolutePosition.X, b.AbsolutePosition.Y
		local x1, y1 = x0 + button.X, y0 + button.Y
		local growX = math.max(Ui.MIN_TOUCH - button.X, 0) / 2
		local growY = math.max(Ui.MIN_TOUCH - button.Y, 0) / 2
		local left, right, up, down = growX, growX, growY, growY
		local scope = padScope(b)
		if scope and (growX > 0 or growY > 0) then
			for _, other in scope:GetDescendants() do
				if
					other == b
					or not (other:IsA("GuiButton") or other:IsA("TextBox"))
					or other.Name == "TouchPad"
					or not other.Visible
					or other:IsDescendantOf(b)
					or b:IsDescendantOf(other)
				then
					continue
				end
				local o = other :: GuiObject
				local oPos, oSize = o.AbsolutePosition, o.AbsoluteSize
				if oSize.X <= 0 or oSize.Y <= 0 then
					continue
				end
				local ox0, oy0 = oPos.X, oPos.Y
				local ox1, oy1 = ox0 + oSize.X, oy0 + oSize.Y
				-- Сосед слева/справа: пересекается по высоте с выросшей подушкой
				if oy0 < y1 + down and oy1 > y0 - up then
					if ox0 >= x1 then
						right = math.min(right, (ox0 - x1) / 2)
					elseif ox1 <= x0 then
						left = math.min(left, (x0 - ox1) / 2)
					end
				end
				-- Сосед сверху/снизу: пересекается по ширине
				if ox0 < x1 + right and ox1 > x0 - left then
					if oy0 >= y1 then
						down = math.min(down, (oy0 - y1) / 2)
					elseif oy1 <= y0 then
						up = math.min(up, (y0 - oy1) / 2)
					end
				end
			end
		end
		local nx = (x0 - left - innerPos.X) / innerSize.X
		local ny = (y0 - up - innerPos.Y) / innerSize.Y
		local nsx = (button.X + left + right) / innerSize.X
		local nsy = (button.Y + up + down) / innerSize.Y
		if
			math.abs(nx - px) > 0.01
			or math.abs(ny - py) > 0.01
			or math.abs(nsx - sx) > 0.01
			or math.abs(nsy - sy) > 0.01
		then
			px, py, sx, sy = nx, ny, nsx, nsy
			pad.Position = UDim2.fromScale(px, py)
			pad.Size = UDim2.fromScale(sx, sy)
		end
	end
	padFits[pad] = fit
	pad.Destroying:Connect(function()
		padFits[pad] = nil
	end)
	-- Размер (UIScale окна) или место (раскладка, вне прокрутки) кнопки сменились — пересчитать все
	b:GetPropertyChangedSignal("AbsoluteSize"):Connect(scheduleRefit)
	local function watchPosition()
		-- В прокрутке позиция меняется каждый кадр, а соседи двигаются вместе — не следим
		if not b:FindFirstAncestorWhichIsA("ScrollingFrame") then
			b:GetPropertyChangedSignal("AbsolutePosition"):Connect(scheduleRefit)
		end
	end
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
	task.defer(watchPosition)
	scheduleRefit()
end

-- Боковое меню слева посередине (слева сверху чат, справа сверху список игроков).
-- Слоты, чтобы фичи не спорили за место: 1 исследования, 2 сотрудники, 3 задания,
-- 4 магазин, 5 rebirth, 6 язык. order внутри слота не нужен — один слот, одна кнопка.
local MENU_BUTTON = 52
local MENU_GAP = 8
-- Сверху HUD и плашки, снизу кнопка «Создать игру»: столько по высоте меню не занимает
local MENU_RESERVED = 200
local MENU_LEFT = 12

-- Тач: меню начинается сверху и не опускается в нижние MENU_TOUCH_BOTTOM px —
-- там джойстик (низ-лево). Не влезло в высоту — следующий столбец справа. Столбцы не заходят
-- под HUD и плашки по центру (Ui.HUD_PLATE_WIDTH): на телефоне 844×390 при 5–6 столбцах по 52 px
-- меню доходило до x 364 и перекрывало HUD (x 272–572). Клетка поменьше (не меньше MIN_TOUCH),
-- и если всё равно не влезает — колонка целиком уменьшается
local MENU_TOUCH_TOP = 8
local MENU_TOUCH_BOTTOM = 120
local MENU_TOUCH_CELL = 46
local MENU_TOUCH_GAP = 4
local MENU_HUD_GAP = 8 -- зазор от меню до плашек HUD
local MENU_TOUCH_MIN_SCALE = 0.7

-- Ширина плашек HUD по центру сверху (HudController): меню на тач-экране правее не заходит
Ui.HUD_PLATE_WIDTH = 300

local function visibleButtons(column: Frame): number
	local count = 0
	for _, child in column:GetChildren() do
		if child:IsA("GuiButton") and child.Visible then
			count += 1
		end
	end
	return count
end

-- Размер области SideMenu: ScreenGui с ScreenInsets по умолчанию (CoreUISafeInsets) — уже без
-- верхней панели Roblox и выреза экрана. Ещё не посчитан — камера минус GuiInset
local function screenSize(column: Frame): Vector2
	local screen = column.Parent
	local size = if screen and screen:IsA("ScreenGui") then screen.AbsoluteSize else Vector2.zero
	if size.X <= 0 or size.Y <= 0 then
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		size = viewport - Vector2.new(0, GuiService:GetGuiInset().Y)
	end
	return size
end

-- Тач: перебираем число столбцов и берём раскладку с самым крупным масштабом (при равном —
-- меньше столбцов). Ширина — до края HUD, высота — над джойстиком
local function fitTouchMenu(column: Frame, grid: UIGridLayout, scale: UIScale, count: number)
	if count <= 0 then
		scale.Scale = 1
		return
	end
	local size = screenSize(column)
	local widthRoom = size.X * 0.5 - Ui.HUD_PLATE_WIDTH / 2 - MENU_HUD_GAP - MENU_LEFT
	local heightRoom = size.Y - MENU_TOUCH_TOP - MENU_TOUCH_BOTTOM
	local pitch = MENU_TOUCH_CELL + MENU_TOUCH_GAP
	local bestScale, bestRows = 0, count
	for columns = 1, count do
		local rows = math.ceil(count / columns)
		local value = math.min(
			1,
			widthRoom / (columns * pitch - MENU_TOUCH_GAP),
			heightRoom / (rows * pitch - MENU_TOUCH_GAP)
		)
		if value > bestScale + 0.001 then
			bestScale, bestRows = value, rows
		end
	end
	grid.FillDirectionMaxCells = bestRows
	scale.Scale = math.max(bestScale, MENU_TOUCH_MIN_SCALE)
end

-- Колонка кнопок сама уменьшается, если все не влезают по высоте (ПК с низким окном);
-- на тач-экране — раскладка столбцами (fitTouchMenu). Считаются только видимые кнопки:
-- скрытые (праздник вне ивента, банк без долга) места не занимают
local function fitMenu(column: Frame, scale: UIScale)
	local count = visibleButtons(column)
	local grid = column:FindFirstChildOfClass("UIGridLayout")
	if grid then
		fitTouchMenu(column, grid, scale, count)
	else
		local camera = workspace.CurrentCamera
		local needed = count * (MENU_BUTTON + MENU_GAP)
		local available = (if camera then camera.ViewportSize.Y else 720) - MENU_RESERVED
		scale.Scale = if needed > 0 then math.clamp(available / needed, 0.55, 1) else 1
	end
	refitBanners()
end

-- Пересчитать меню (кнопку показали/спрятали); задаётся при создании колонки
local refitMenu: () -> () = function() end

-- ===== Постепенное открытие систем (Config/Unlocks, контроллер FeatureGate) =====
-- Закрытая система: её кнопка меню / плашка лежит в невидимой рамке LockedFeatures того же
-- ScreenGui, а не просто Visible = false — контроллеры сами меняют Visible (банк с долгом,
-- праздник во время ивента), и это не должно открывать закрытое. Рамка — прямо в ScreenGui,
-- не в колонке меню / стеке плашек: их AutomaticSize и раскладку она не трогает, fitMenu
-- считает только кнопки колонки. Пока FeatureGate не сказал «открыто», система закрыта:
-- кнопки не мигают при входе
local gateOpen: { [string]: boolean } = {}
local gated: { [string]: { GuiObject } } = {}
local gateHome: { [GuiObject]: Instance } = {}
local lockers: { [Instance]: Frame } = {}
local newBadges: { [GuiObject]: Instance } = {}
-- Системы с 🆕 в этой сессии: кнопка, созданная позже Ui.markNew, тоже получит значок
local newFeatures: { [string]: boolean } = {}

local function locker(home: Instance): Frame
	local parent: Instance = home:FindFirstAncestorWhichIsA("LayerCollector") or home
	local existing = lockers[parent]
	if existing and existing.Parent == parent then
		return existing
	end
	local frame = Instance.new("Frame")
	frame.Name = "LockedFeatures"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(0, 0)
	frame.Position = UDim2.fromOffset(-10000, -10000) -- тач-подушки соседей её не видят
	frame.Visible = false
	frame.Parent = parent
	lockers[parent] = frame
	return frame
end

local function applyGate(object: GuiObject, open: boolean)
	local home = gateHome[object]
	if not home then
		return
	end
	if open then
		if object.Parent ~= home then
			object.Parent = home
		end
	elseif object.Parent == home then
		object.Parent = locker(home)
	end
end

-- Прятать object (уже с родителем), пока система featureId закрыта. nil / система без ворот — ничего
function Ui.gate(object: GuiObject, featureId: string?)
	if not featureId or not Unlocks.features[featureId] or not object.Parent then
		return
	end
	local list = gated[featureId]
	if not list then
		list = {}
		gated[featureId] = list
	end
	table.insert(list, object)
	gateHome[object] = object.Parent :: Instance
	object.Destroying:Connect(function()
		gateHome[object] = nil
		newBadges[object] = nil
		local index = table.find(list, object)
		if index then
			table.remove(list, index)
		end
	end)
	applyGate(object, gateOpen[featureId] == true)
	if newFeatures[featureId] then
		Ui.markNew(featureId)
	end
end

-- Открыта ли система для интерфейса (система без ворот — всегда)
function Ui.gateIsOpen(featureId: string): boolean
	return not Unlocks.features[featureId] or gateOpen[featureId] == true
end

function Ui.setGateOpen(featureId: string, open: boolean)
	if gateOpen[featureId] == open then
		return
	end
	gateOpen[featureId] = open
	for _, object in gated[featureId] or {} do
		applyGate(object, open)
	end
end

local function clearNewBadge(object: GuiObject)
	object:SetAttribute("NewSeen", true)
	local badge = newBadges[object]
	newBadges[object] = nil
	if badge then
		badge:Destroy()
	end
	local stroke = object:FindFirstChild("NewStroke")
	if stroke then
		stroke:Destroy()
	end
end

-- Значок 🆕 и золотая обводка на кнопках меню системы, пока игрок на неё не нажмёт
function Ui.markNew(featureId: string)
	newFeatures[featureId] = true
	for _, object in gated[featureId] or {} do
		if not object:IsA("GuiButton") or newBadges[object] or object:GetAttribute("NewSeen") == true then
			continue
		end
		local badge = Instance.new("TextLabel")
		badge.Name = "NewBadge"
		badge.BackgroundTransparency = 1
		badge.Text = "🆕"
		badge.TextScaled = true
		badge.Font = Ui.bodyFont
		badge.AnchorPoint = Vector2.new(0, 0)
		-- Левый верхний угол: в правом на тач-экране тумблер авто-вида 🎥 (StudioCamera).
		-- Кнопка с UIPadding (8 px по бокам, 6 сверху), отсюда смещение
		badge.Position = UDim2.new(0, -12, 0, -10)
		badge.Size = UDim2.fromOffset(22, 22)
		badge.ZIndex = object.ZIndex + 2
		badge.Parent = object
		newBadges[object] = badge
		local stroke = Instance.new("UIStroke")
		stroke.Name = "NewStroke"
		stroke.Thickness = 2
		stroke.Color = Ui.colors.money
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = object
	end
end

-- imageKey — ключ из Config/Images.menu: есть id картинки — вместо эмодзи показываем её
function Ui.menuButton(slot: number, icon: string, onClick: () -> (), imageKey: string?): TextButton
	if not menuColumn then
		local Players = game:GetService("Players")
		local screen = Instance.new("ScreenGui")
		screen.Name = "SideMenu"
		screen.ResetOnSpawn = false
		local column = Instance.new("Frame")
		column.Name = "Column"
		column.BackgroundTransparency = 1
		column.AnchorPoint = Vector2.new(0, 0.5)
		column.Position = UDim2.new(0, MENU_LEFT, 0.5, 0)
		column.Size = UDim2.fromOffset(MENU_BUTTON, 0)
		column.AutomaticSize = Enum.AutomaticSize.Y
		if Ui.touch then
			-- Сверху вниз столбцами, сколько влезает над джойстиком (fitMenu)
			column.AnchorPoint = Vector2.new(0, 0)
			column.Position = UDim2.fromOffset(MENU_LEFT, MENU_TOUCH_TOP)
			column.Size = UDim2.new()
			column.AutomaticSize = Enum.AutomaticSize.XY
			local grid = Instance.new("UIGridLayout")
			grid.SortOrder = Enum.SortOrder.LayoutOrder
			grid.FillDirection = Enum.FillDirection.Vertical
			grid.CellSize = UDim2.fromOffset(MENU_TOUCH_CELL, MENU_TOUCH_CELL)
			grid.CellPadding = UDim2.fromOffset(MENU_TOUCH_GAP, MENU_TOUCH_GAP)
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
		-- Кнопки создаются пачкой при старте и меняют Visible: пересчёт раз в кадр
		local scheduled = false
		refitMenu = function()
			if scheduled then
				return
			end
			scheduled = true
			task.defer(function()
				scheduled = false
				fitMenu(column, scale)
			end)
		end
		column.ChildAdded:Connect(refitMenu)
		column.ChildRemoved:Connect(refitMenu)
		-- Ширина меню на тач-экране ограничивает ширину плашек (Ui.bannerStack)
		column:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			refitBanners()
		end)
		screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(refitMenu)
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(refitMenu)
		end
	end
	-- Слот задаёт порядок сверху вниз: 1 исследования, 2 команда, 3 задания, 4 магазин, 5 rebirth,
	-- 6 язык, 7 хиты, 8 воры, 9 праздничный ивент (видна только во время ивента), 10 вид студии,
	-- 11 банк (с долгом), 12 домой (к своему участку), 13 студия (интерьер, декор, настроение),
	-- 14 достижения, 15 студии игроков и рейтинги (TourWindow), 16 сезон и гейм-джем, 17 топ индустрии
	local b: TextButton
	-- Нажатие снимает значок 🆕 (Ui.markNew)
	b = Ui.button(menuColumn :: Frame, icon, Ui.colors.panel, function()
		clearNewBadge(b)
		onClick()
	end)
	b.Name = "Slot" .. slot
	b.LayoutOrder = slot
	b.Size = UDim2.fromOffset(MENU_BUTTON, MENU_BUTTON)
	b:GetPropertyChangedSignal("Visible"):Connect(refitMenu)
	local imageId = if imageKey then Images.menu[imageKey] else nil
	if imageId and imageId > 0 then
		b.Text = ""
		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = "rbxassetid://" .. imageId
		image.Parent = b -- отступы даёт UIPadding кнопки
	end
	-- Система ещё закрыта для новичка (Config/Unlocks) — кнопка ждёт в LockedFeatures
	Ui.gate(b, Unlocks.menuFeature(slot))
	return b
end

-- Общий стек плашек под HUD (тренд, выставка, итоги выставки, тревога): каждая плашка
-- кладётся сюда со своим LayoutOrder, скрытые не занимают места — плашки не наезжают друг на друга.
-- Стек прижат к низу HUD: деньги и строка игр — y 12..86, под ними строки прогресса
-- разработки. HUD сообщает, где кончается (Ui.setBannerTop), — плашки не висят посреди
-- экрана над студией (отчёт #2, п. 14)
local BANNER_TOP = 94
local BANNER_GAP = 6
-- Низкий экран (телефон в альбомной): плашки стека чуть меньше, чтобы не дойти до кнопки «Создать игру»
local SHORT_SCREEN = 500
local SHORT_SCALE = 0.8
-- Тач или низкий экран: стек целиком помещается между HUD и кнопкой «Создать игру» (низ −24,
-- высота 56) и не заходит под боковое меню — уменьшается, но не мельче BANNER_MIN_SCALE.
-- HUD длинный (настроение, мощность, 2 проекта) — стек поднимается на нижние строки HUD,
-- оставляя себе BANNER_MIN_SPACE: кнопки плашек (контракт, долг) должны быть на экране
local BANNER_BOTTOM = 86
local BANNER_MIN_SPACE = 64
local BANNER_MIN_SCALE = 0.5
local BANNER_MENU_GAP = 8
local bannerStack: Frame? = nil
local bannerTop = BANNER_TOP

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
	stack.Position = UDim2.new(0.5, 0, 0, bannerTop)
	stack.Size = UDim2.new(1, 0, 0, 0)
	stack.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Ui.list(stack, BANNER_GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local scale = Instance.new("UIScale")
	scale.Parent = stack
	local function fit()
		local camera = workspace.CurrentCamera
		local viewportHeight = if camera then camera.ViewportSize.Y else 720
		local short = viewportHeight < SHORT_SCREEN
		local value = if short then SHORT_SCALE else 1
		local top = bannerTop
		local size = screen.AbsoluteSize
		if (short or Ui.touch) and size.Y > 0 then
			local current = math.max(scale.Scale, 0.01)
			top = math.max(math.min(top, size.Y - BANNER_BOTTOM - BANNER_MIN_SPACE), 0)
			-- Высота и ширина в «дизайнерских» px: AbsoluteSize уже умножен на текущий масштаб
			local height = layout.AbsoluteContentSize.Y / current
			if height > 0 then
				value = math.min(value, (size.Y - BANNER_BOTTOM - top) / height)
			end
			local menuPosition, menuSize = menuRect()
			if Ui.touch and menuPosition and menuSize then
				local menuRight = menuPosition.X - screen.AbsolutePosition.X + menuSize.X
				local room = size.X - 2 * (menuRight + BANNER_MENU_GAP)
				local widest = 0
				for _, child in stack:GetChildren() do
					if child:IsA("GuiObject") and child.Visible and child.Size.X.Scale == 0 then
						widest = math.max(widest, child.AbsoluteSize.X / current)
					end
				end
				if widest > 0 then
					value = math.min(value, room / widest)
				end
			end
			value = math.max(value, BANNER_MIN_SCALE)
		end
		if math.abs(scale.Scale - value) > 0.01 then
			scale.Scale = value
		end
		stack.Position = UDim2.new(0.5, 0, 0, top)
	end
	-- Плашки появляются, прячутся и меняют текст часто: пересчёт раз в кадр
	local scheduled = false
	refitBanners = function()
		if scheduled then
			return
		end
		scheduled = true
		task.defer(function()
			scheduled = false
			fit()
		end)
	end
	fit()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refitBanners)
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(refitBanners)
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refitBanners)
	stack.Parent = screen
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	bannerStack = stack
	return stack
end

-- Верх стека плашек (px от верха экрана): HUD зовёт, когда меняется число строк прогресса
function Ui.setBannerTop(y: number)
	bannerTop = math.max(y, BANNER_TOP)
	local stack = bannerStack
	if stack then
		stack.Position = UDim2.new(0.5, 0, 0, bannerTop)
		refitBanners()
	end
end

function Ui.list(parent: Instance, padding: number)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = parent
	return layout
end

return Ui
