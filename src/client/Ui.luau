--!strict
-- Стиль интерфейса из issue #5 и общие конструкторы элементов.

local GuiService = game:GetService("GuiService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Hud = require(ReplicatedStorage.Shared.Config.Hud)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local Unlocks = require(ReplicatedStorage.Shared.Config.Unlocks)

local Ui = {}

-- Телефон/планшет: кнопки не меньше пальца, боковое меню не лезет на джойстик
Ui.touch = UserInputService.TouchEnabled
Ui.MIN_TOUCH = 44
-- Кнопки шапки окна (×, «Коды», Premium): на тач-экране выше и с зазором побольше — окно
-- ужимается до 0.65, и 40 px превращались в ~26 px, а подушка не росла из-за соседа (аудит P2-16)
Ui.HEADER_BUTTON = if Ui.touch then 48 else 40
Ui.HEADER_TOP = if Ui.touch then 4 else 8
Ui.HEADER_GAP = if Ui.touch then 16 else 10
Ui.HEADER_RIGHT = 12

-- «×» в правом верхнем углу окна: размер и место по Ui.HEADER_*
function Ui.headerClose(button: GuiObject)
	button.Size = UDim2.fromOffset(Ui.HEADER_BUTTON, Ui.HEADER_BUTTON)
	button.Position = UDim2.new(1, -(Ui.HEADER_BUTTON + Ui.HEADER_RIGHT), 0, Ui.HEADER_TOP)
end

-- Пока открыто окно игры, прячем окно чата: оно рисуется поверх нашего UI и забирает клики
local openWindows = 0
-- Окно меню, открытое сейчас (его close): окна меню взаимоисключающие — новое закрывает старое,
-- иначе два окна DisplayOrder 10 лежали друг на друге. Закрыть уже закрытое окно — ничего не делает
local exclusiveClose: (() -> ())? = nil
-- Окно открылось (true) / закрылось (false) — для звуков (SoundController)
local windowSignal = Instance.new("BindableEvent")
Ui.windowEvent = windowSignal.Event

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
	windowSignal:Fire(true)
end

-- Открыто ли сейчас хоть одно окно игры (HUD не открывает «Создать игру» поверх него)
function Ui.anyWindowOpen(): boolean
	return openWindows > 0
end

function Ui.windowClosed()
	windowSignal:Fire(false)
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
-- Пересчитать лоток плашек (задаёт Ui.bannerStack): экран или меню сменили размер
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

-- Ширина верхней строки HUD (HudController, Config/Hud): меню на тач-экране правее не заходит.
-- Плашки событий по центру больше не висят — они в лотке справа (Ui.bannerStack)
Ui.HUD_PLATE_WIDTH = if Ui.touch then Hud.topBarWidthTouch else Hud.topBarWidth

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
-- Рамки, где лежат плашки Ui.bannerStack (склад, объявление, карточка): плашка из карточки
-- закрывается воротами так же, как со склада
local bannerHosts: { [Instance]: boolean } = {}

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
	local parent = object.Parent
	local inBanners = parent ~= nil and bannerHosts[parent] == true
	if open then
		if parent ~= home and not inBanners then
			object.Parent = home
		end
	elseif parent == home or inBanners then
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
-- Нажата кнопка бокового меню (slot): GuideController показывает карточку обучения системы
local menuClickedEvent = Instance.new("BindableEvent")
Ui.menuClicked = menuClickedEvent.Event

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
	-- 14 достижения, 15 студии игроков и рейтинги (TourWindow), 16 сезон и гейм-джем, 17 топ индустрии,
	-- 18 налоги, 19 биржа, 20 справочник обучения (GuideController)
	local b: TextButton
	-- Нажатие снимает значок 🆕 (Ui.markNew)
	b = Ui.button(menuColumn :: Frame, icon, Ui.colors.panel, function()
		clearNewBadge(b)
		onClick()
		menuClickedEvent:Fire(slot)
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

-- ===== Плашки событий: лоток значков справа и объявления сверху (Config/Hud) =====
-- Контроллеры, как раньше, кладут свои плашки в Ui.bannerStack() и сами меняют Visible и текст.
-- Стек — теперь «склад» за краем экрана (отзыв владельца 06.11: плашки висели посреди экрана
-- над персонажем). Игрок видит плашку:
--   * объявлением — полосой во всю ширину под HUD на Hud.announceSeconds, когда она появилась
--     (Visible false → true) или контроллер позвал Ui.bannerAnnounce (начался Золотой час);
--   * значком в лотке справа: эмодзи или картинка + таймер «9:22» из текста плашки. Нажатие —
--     карточка ≤ Hud.cardWidth слева от значка: та же плашка, уменьшенная UIScale, её кнопки
--     (банк/погасить/уволить, контракт, ⚡ стройки) работают — это тот же объект.
-- Ui.bannerMeta(object, key, …) — ключ приоритета (Hud.bannerPriority) и значок. Плашка без ключа
-- (тосты, итоги выставки) — только объявление; пережила его — значок в конце лотка.
-- Ворота онбординга (Ui.gate) работают как раньше: закрытая плашка лежит в LockedFeatures того же
-- ScreenGui, не на складе — значка у неё нет.
local BANNER_GAP = 6
-- Низкий экран (телефон в альбомной): объявление чуть меньше
local SHORT_SCREEN = 500
local SHORT_SCALE = 0.8
local HUD_BOTTOM_MIN = 46 -- под верхней строкой HUD (HudController зовёт Ui.setHudBottom)
local TRAY_RIGHT = 8
local CARD_PAD = 6
local CARD_GAP = 6
local ANNOUNCE_EXPLICIT_COOLDOWN = 10
local SYNC_SECONDS = 0.5

type BannerUi = {
	screen: ScreenGui,
	source: Frame,
	strip: Frame,
	stripBody: Frame,
	stripScale: UIScale,
	card: Frame,
	cardBody: Frame,
	cardScale: UIScale,
	tray: Frame,
	grid: UIGridLayout,
	more: TextButton,
}

type Chip = {
	button: TextButton,
	stroke: UIStroke,
	icon: TextLabel,
	image: ImageLabel,
	timer: TextLabel,
}

local bannerUi: BannerUi? = nil
local bannerStarted = os.clock()
local hudBottom = HUD_BOTTOM_MIN
local watchedBanners: { [GuiObject]: boolean } = {}
local wasActive: { [GuiObject]: boolean } = {}
local lastAnnounced: { [GuiObject]: number } = {}
local announceQueue: { GuiObject } = {}
local announcing: GuiObject? = nil
local announceToken = 0
local announceFresh = false
local stripTween: Tween? = nil
local selectedBanner: GuiObject? = nil
local chips: { [GuiObject]: Chip } = {}
local trayExpanded = false
local bannerSyncScheduled = false
local syncBanners: () -> () = function() end

local function scheduleBannerSync()
	if bannerSyncScheduled then
		return
	end
	bannerSyncScheduled = true
	task.defer(function()
		bannerSyncScheduled = false
		syncBanners()
	end)
end

local function lowGraphics(): boolean
	return game:GetService("Players").LocalPlayer:GetAttribute("LowGraphics") == true
end

local function textOf(node: Instance): string?
	if node:IsA("TextLabel") then
		return if node.Visible then node.Text else nil
	elseif node:IsA("TextButton") then
		return if node.Visible then node.Text else nil
	end
	return nil
end

-- Видимые тексты плашки без rich-text тегов (сверху вниз по дереву)
local function bannerTexts(object: GuiObject): { string }
	local result = {}
	local function add(node: Instance)
		local text = textOf(node)
		if text and text ~= "" then
			table.insert(result, (string.gsub(text, "<[^>]+>", "")))
		end
	end
	add(object)
	for _, node in object:GetDescendants() do
		add(node)
	end
	return result
end

-- Эмодзи в начале текста («🔥 В тренде…» → «🔥»); кириллица и латиница — не эмодзи
local function leadingEmoji(text: string): string?
	local s = string.gsub(text, "^%s+", "")
	if s == "" then
		return nil
	end
	local ok, code = pcall(utf8.codepoint, s, 1)
	if not ok or type(code) ~= "number" or code < 0x2190 then
		return nil
	end
	local word = string.match(s, "^[^%s]+")
	if word and #word <= 12 then
		return word
	end
	local nextAt = utf8.offset(s, 2)
	return if nextAt then string.sub(s, 1, nextAt - 1) else s
end

local function bannerPriority(object: GuiObject): number
	local key = object:GetAttribute("BannerKey")
	local value = if type(key) == "string"
		then Hud.bannerPriority[key] or Hud.othersPriority
		else Hud.othersPriority
	if object:GetAttribute("BannerIdle") == true then
		value += Hud.idlePriority
	end
	return value
end

local function bannerAccent(object: GuiObject): Color3
	local color = object:GetAttribute("BannerColor")
	if typeof(color) == "Color3" then
		return color
	end
	if object:IsA("TextLabel") then
		return object.TextColor3
	elseif object:IsA("TextButton") then
		return object.TextColor3
	end
	local stroke = object:FindFirstChildOfClass("UIStroke")
	if stroke then
		return stroke.Color
	end
	return Ui.colors.money
end

-- Размер плашки в «дизайнерских» px (без UIScale карточки или объявления)
local function designSize(object: GuiObject, ui: BannerUi): Vector2
	local size = object.Size
	if size.X.Scale == 0 and size.Y.Scale == 0 and object.AutomaticSize == Enum.AutomaticSize.None then
		return Vector2.new(size.X.Offset, size.Y.Offset)
	end
	local scale = 1
	if object.Parent == ui.stripBody then
		scale = ui.stripScale.Scale
	elseif object.Parent == ui.cardBody then
		scale = ui.cardScale.Scale
	end
	local absolute = object.AbsoluteSize / math.max(scale, 0.01)
	return Vector2.new(math.max(absolute.X, size.X.Offset, 1), math.max(absolute.Y, size.Y.Offset, 1))
end

local function screenHeight(ui: BannerUi): number
	local height = ui.screen.AbsoluteSize.Y
	if height <= 0 then
		local camera = workspace.CurrentCamera
		height = (if camera then camera.ViewportSize.Y else 720) - GuiService:GetGuiInset().Y
	end
	return height
end

local function chipSize(): number
	return if Ui.touch then Hud.chipSizeTouch else Hud.chipSize
end

-- Сколько значков в столбце лотка: тач — сверху справа до кнопки прыжка, ПК — по центру справа
local function trayCapacity(ui: BannerUi): number
	local pitch = chipSize() + Hud.chipGap
	local height = screenHeight(ui)
	local room = if Ui.touch
		then height - Hud.trayTouchTop - Hud.trayTouchBottom
		else height * Hud.trayDesktopShare
	return math.clamp(math.floor((room + Hud.chipGap) / pitch), 1, Hud.maxChips)
end

local function queueAnnounce(object: GuiObject, front: boolean)
	if object == announcing or object == selectedBanner or table.find(announceQueue, object) then
		return
	end
	if front then
		table.insert(announceQueue, 1, object)
	else
		table.insert(announceQueue, object)
	end
	while #announceQueue > Hud.announceQueueMax do
		table.remove(announceQueue)
	end
end

-- Плашка появилась: объявить (после входа — только важные и тосты)
local function onBannerActivated(object: GuiObject, now: number)
	local key = object:GetAttribute("BannerKey")
	if type(key) ~= "string" then
		queueAnnounce(object, false)
		return
	end
	-- «В фоне» (событие дня между событиями) не объявляем: контроллер позовёт Ui.bannerAnnounce
	if object:GetAttribute("BannerIdle") == true then
		return
	end
	local important = Hud.announceImportant[key] == true
	if not important and now - bannerStarted < Hud.joinQuietSeconds then
		return
	end
	local last = lastAnnounced[object]
	if last and now - last < Hud.announceCooldown then
		return
	end
	queueAnnounce(object, important)
end

local function startNextAnnounce(present: { [GuiObject]: boolean })
	while #announceQueue > 0 do
		local object = table.remove(announceQueue, 1) :: GuiObject
		if present[object] and object.Visible and object ~= selectedBanner then
			announcing = object
			announceFresh = true
			lastAnnounced[object] = os.clock()
			announceToken += 1
			local token = announceToken
			task.delay(Hud.announceSeconds, function()
				if announceToken == token then
					announcing = nil
					scheduleBannerSync()
				end
			end)
			return
		end
	end
end

local function watchBanner(object: GuiObject)
	if watchedBanners[object] then
		return
	end
	watchedBanners[object] = true
	object:GetPropertyChangedSignal("Visible"):Connect(scheduleBannerSync)
	object:GetPropertyChangedSignal("AbsoluteSize"):Connect(scheduleBannerSync)
	object.Destroying:Connect(function()
		watchedBanners[object] = nil
		wasActive[object] = nil
		lastAnnounced[object] = nil
		local index = table.find(announceQueue, object)
		if index then
			table.remove(announceQueue, index)
		end
		if announcing == object then
			announcing = nil
			announceToken += 1
		end
		if selectedBanner == object then
			selectedBanner = nil
		end
		scheduleBannerSync()
	end)
end

local function makeChip(ui: BannerUi, object: GuiObject): Chip
	local button = Instance.new("TextButton")
	button.Name = "Chip_" .. object.Name
	button.Text = ""
	button.AutoButtonColor = true
	button.BackgroundColor3 = Ui.colors.panel
	button.BackgroundTransparency = 0.15
	Ui.corner(button, 10)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 2
	stroke.Parent = button
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.TextScaled = true
	icon.Font = Ui.bodyFont
	icon.TextColor3 = Ui.colors.text
	icon.Parent = button
	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Visible = false
	image.Parent = button
	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.BackgroundTransparency = 1
	timer.TextScaled = true
	timer.Font = Ui.bodyFont
	timer.TextColor3 = Ui.colors.text
	timer.Position = UDim2.new(0, 2, 0.62, 0)
	timer.Size = UDim2.new(1, -4, 0.34, 0)
	timer.Parent = button
	local lastClick = 0
	button.Activated:Connect(function()
		local now = os.clock()
		if now - lastClick < CLICK_DEBOUNCE then
			return
		end
		lastClick = now
		selectedBanner = if selectedBanner == object then nil else object
		scheduleBannerSync()
	end)
	if not lowGraphics() then
		local pop = Instance.new("UIScale")
		pop.Scale = 0.6
		pop.Parent = button
		TweenService:Create(pop, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	button.Parent = ui.tray
	return { button = button, stroke = stroke, icon = icon, image = image, timer = timer }
end

local function updateChip(chip: Chip, object: GuiObject, selected: boolean)
	local texts = bannerTexts(object)
	local timer: string? = nil
	local emoji: string? = nil
	for _, text in texts do
		timer = timer or string.match(text, "(%d+:%d%d)")
		emoji = emoji or leadingEmoji(text)
	end
	local iconAttr = object:GetAttribute("BannerIcon")
	local imageAttr = object:GetAttribute("BannerImage")
	local imageId = if type(imageAttr) == "number" then imageAttr else 0
	local iconText = if type(iconAttr) == "string" then iconAttr else emoji or "🔔"
	local iconSize = if timer then UDim2.new(1, -6, 0.6, 0) else UDim2.new(1, -8, 1, -8)
	local iconPosition = if timer then UDim2.fromOffset(3, 3) else UDim2.fromOffset(4, 4)
	chip.icon.Size, chip.image.Size = iconSize, iconSize
	chip.icon.Position, chip.image.Position = iconPosition, iconPosition
	chip.image.Visible = imageId > 0
	chip.icon.Visible = imageId <= 0
	if imageId > 0 then
		local image = "rbxassetid://" .. imageId
		if chip.image.Image ~= image then
			chip.image.Image = image
		end
	elseif chip.icon.Text ~= iconText then
		chip.icon.Text = iconText
	end
	chip.timer.Visible = timer ~= nil
	chip.timer.Text = timer or ""
	chip.stroke.Color = if selected then Ui.colors.text else bannerAccent(object)
	chip.stroke.Thickness = if selected then 3 else 2
end

local function layoutStrip(ui: BannerUi)
	local object = announcing
	if not object then
		ui.strip.Visible = false
		return
	end
	local size = designSize(object, ui)
	local camera = workspace.CurrentCamera
	local short = (if camera then camera.ViewportSize.Y else 720) < SHORT_SCREEN
	-- Тач: меню сверху слева и лоток сверху справа — полоса между ними, не поверх кнопок
	local origin = ui.screen.AbsolutePosition
	local left, right = 0, 0
	if Ui.touch then
		local menuPosition, menuSize = menuRect()
		if menuPosition and menuSize then
			left = math.max(menuPosition.X - origin.X + menuSize.X + CARD_GAP, 0)
		end
		if ui.tray.Visible then
			right = ui.tray.AbsoluteSize.X + TRAY_RIGHT + CARD_GAP
		end
	end
	local width = ui.screen.AbsoluteSize.X - left - right
	local scale = if short then SHORT_SCALE else 1
	if width > 0 then
		scale = math.min(scale, (width - 16) / size.X)
	end
	ui.stripScale.Scale = scale
	ui.stripBody.Size = UDim2.fromOffset(size.X, size.Y)
	ui.strip.Size = UDim2.new(1, -(left + right), 0, math.ceil(size.Y * scale) + 8)
	local target = UDim2.fromOffset(left, hudBottom)
	if announceFresh then
		announceFresh = false
		if stripTween then
			stripTween:Cancel()
			stripTween = nil
		end
		if lowGraphics() then
			ui.strip.Position = target
		else
			ui.strip.Position = UDim2.fromOffset(left, hudBottom - 16)
			local tween = TweenService:Create(ui.strip, TweenInfo.new(0.2), { Position = target })
			stripTween = tween
			tween:Play()
		end
	elseif not stripTween or stripTween.PlaybackState ~= Enum.PlaybackState.Playing then
		ui.strip.Position = target
	end
	ui.strip.Visible = true
end

local function layoutCard(ui: BannerUi)
	local object = selectedBanner
	if not object then
		ui.card.Visible = false
		return
	end
	local size = designSize(object, ui)
	local scale = math.min(1, Hud.cardWidth / size.X)
	ui.cardScale.Scale = scale
	ui.cardBody.Size = UDim2.fromOffset(size.X, size.Y)
	local width = math.ceil(size.X * scale) + 2 * CARD_PAD
	local height = math.ceil(size.Y * scale) + 2 * CARD_PAD
	ui.card.Size = UDim2.fromOffset(width, height)
	local chip = chips[object]
	local anchor: GuiObject = if chip and chip.button.Visible then chip.button else ui.tray
	local origin = ui.screen.AbsolutePosition
	local right = ui.tray.AbsolutePosition.X - origin.X - CARD_GAP
	local y = anchor.AbsolutePosition.Y - origin.Y
	y = math.clamp(y, 4, math.max(screenHeight(ui) - height - 4, 4))
	ui.card.Position = UDim2.fromOffset(right, y)
	ui.card.Visible = true
end

syncBanners = function()
	local ui = bannerUi
	if not ui then
		return
	end
	local now = os.clock()
	local objects: { GuiObject } = {}
	for _, host in { ui.source, ui.stripBody, ui.cardBody } do
		for _, child in host:GetChildren() do
			if child:IsA("GuiObject") then
				table.insert(objects, child)
			end
		end
	end
	local present: { [GuiObject]: boolean } = {}
	for _, object in objects do
		present[object] = true
		watchBanner(object)
		local active = object.Visible
		if active and not wasActive[object] then
			onBannerActivated(object, now)
		end
		wasActive[object] = active
	end
	local selected = selectedBanner
	if selected and not (present[selected] and selected.Visible) then
		selectedBanner = nil
	end
	local current = announcing
	if current and not (present[current] and current.Visible) then
		announcing = nil
		announceToken += 1
	end
	if not announcing then
		startNextAnnounce(present)
	end
	for _, object in objects do
		local target = if object == announcing
			then ui.stripBody
			elseif object == selectedBanner then ui.cardBody
			else ui.source
		if object.Parent ~= target then
			object.Parent = target
		end
	end

	-- Значки: активные плашки по приоритету. Тост в очереди объявления значка не получает
	local list: { GuiObject } = {}
	for _, object in objects do
		local waiting = object:GetAttribute("BannerKey") == nil and table.find(announceQueue, object) ~= nil
		if object.Visible and object ~= announcing and not waiting then
			table.insert(list, object)
		end
	end
	table.sort(list, function(a, b)
		local pa, pb = bannerPriority(a), bannerPriority(b)
		if pa ~= pb then
			return pa < pb
		end
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return a.Name < b.Name
	end)
	if #list <= Hud.maxChips then
		trayExpanded = false
	end
	local size = chipSize()
	ui.grid.CellSize = UDim2.fromOffset(size, size)
	ui.grid.FillDirectionMaxCells = trayCapacity(ui)
	local shownCount = if #list > Hud.maxChips and not trayExpanded then Hud.maxChips - 1 else #list
	local used: { [GuiObject]: boolean } = {}
	for i, object in list do
		local chip = chips[object]
		if i <= shownCount then
			if not chip then
				chip = makeChip(ui, object)
				chips[object] = chip
			end
			local shown = chip :: Chip
			shown.button.LayoutOrder = i
			shown.button.Visible = true
			updateChip(shown, object, object == selectedBanner)
			used[object] = true
		end
	end
	for object, chip in chips do
		if not present[object] then
			chip.button:Destroy()
			chips[object] = nil
		elseif not used[object] then
			chip.button.Visible = false
		end
	end
	ui.more.Visible = #list > Hud.maxChips
	ui.more.LayoutOrder = shownCount + 1
	ui.more.Text = if trayExpanded then "▲" else "+" .. (#list - shownCount)
	ui.tray.Visible = #list > 0
	if Ui.touch then
		ui.tray.AnchorPoint = Vector2.new(1, 0)
		ui.tray.Position = UDim2.new(1, -TRAY_RIGHT, 0, Hud.trayTouchTop)
	else
		ui.tray.AnchorPoint = Vector2.new(1, 0.5)
		ui.tray.Position = UDim2.new(1, -TRAY_RIGHT, 0.5, 0)
	end
	layoutStrip(ui)
	layoutCard(ui)
end

local function bannerHost(parent: Instance, name: string): (Frame, UIScale)
	local body = Instance.new("Frame")
	body.Name = name
	body.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Parent = body
	local layout = Ui.list(body, 0)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	body.Parent = parent
	bannerHosts[body] = true
	return body, scale
end

function Ui.bannerStack(): Frame
	local existing = bannerUi
	if existing then
		return existing.source
	end
	local Players = game:GetService("Players")
	local screen = Instance.new("ScreenGui")
	screen.Name = "Banners"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 1 -- над HUD (0), под окнами (10+)

	-- Склад: плашки контроллеров, которые сейчас не в объявлении и не в карточке
	local source = Instance.new("Frame")
	source.Name = "Stack"
	source.BackgroundTransparency = 1
	source.Position = UDim2.fromOffset(-10000, -10000)
	source.Size = UDim2.fromOffset(600, 0)
	source.AutomaticSize = Enum.AutomaticSize.Y
	Ui.list(source, BANNER_GAP)
	source.Parent = screen
	bannerHosts[source] = true

	local strip = Instance.new("Frame")
	strip.Name = "Announce"
	strip.BackgroundColor3 = Ui.colors.panel
	strip.BackgroundTransparency = 0.35
	strip.BorderSizePixel = 0
	strip.Visible = false
	strip.Parent = screen
	local stripBody, stripScale = bannerHost(strip, "Body")
	stripBody.AnchorPoint = Vector2.new(0.5, 0)
	stripBody.Position = UDim2.new(0.5, 0, 0, 4)

	local tray = Instance.new("Frame")
	tray.Name = "Tray"
	tray.BackgroundTransparency = 1
	tray.Size = UDim2.new()
	tray.AutomaticSize = Enum.AutomaticSize.XY
	tray.Visible = false
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Vertical
	grid.StartCorner = Enum.StartCorner.TopRight
	grid.CellPadding = UDim2.fromOffset(Hud.chipGap, Hud.chipGap)
	grid.Parent = tray
	tray.Parent = screen
	local more = Instance.new("TextButton")
	more.Name = "More"
	more.BackgroundColor3 = Ui.colors.panel
	more.BackgroundTransparency = 0.15
	more.TextColor3 = Ui.colors.text
	more.Font = Ui.bodyFont
	more.TextScaled = true
	more.Visible = false
	Ui.corner(more, 10)
	local morePadding = Instance.new("UIPadding")
	morePadding.PaddingTop = UDim.new(0, 8)
	morePadding.PaddingBottom = UDim.new(0, 8)
	morePadding.PaddingLeft = UDim.new(0, 6)
	morePadding.PaddingRight = UDim.new(0, 6)
	morePadding.Parent = more
	more.Activated:Connect(function()
		trayExpanded = not trayExpanded
		scheduleBannerSync()
	end)
	more.Parent = tray

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(1, 0)
	card.BackgroundColor3 = Ui.colors.panel
	card.BackgroundTransparency = 0.1
	card.Visible = false
	Ui.corner(card, 12)
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Ui.colors.stroke
	cardStroke.Thickness = 2
	cardStroke.Parent = card
	card.Parent = screen
	local cardBody, cardScale = bannerHost(card, "Body")
	cardBody.Position = UDim2.fromOffset(CARD_PAD, CARD_PAD)

	bannerUi = {
		screen = screen,
		source = source,
		strip = strip,
		stripBody = stripBody,
		stripScale = stripScale,
		card = card,
		cardBody = cardBody,
		cardScale = cardScale,
		tray = tray,
		grid = grid,
		more = more,
	}
	bannerStarted = os.clock()
	refitBanners = scheduleBannerSync
	for _, host in { source, stripBody, cardBody } do
		host.ChildAdded:Connect(scheduleBannerSync)
		host.ChildRemoved:Connect(scheduleBannerSync)
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(scheduleBannerSync)
	tray:GetPropertyChangedSignal("AbsolutePosition"):Connect(scheduleBannerSync)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(scheduleBannerSync)
	end
	-- Таймеры значков («9:22») берутся из текста плашек: обновляем дважды в секунду
	task.spawn(function()
		while screen.Parent do
			task.wait(SYNC_SECONDS)
			syncBanners()
		end
	end)
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return source
end

-- Ключ приоритета (Config/Hud.bannerPriority), значок (эмодзи или id картинки) и цвет обводки
-- значка плашки из Ui.bannerStack. Без значка — эмодзи из начала текста плашки
function Ui.bannerMeta(object: GuiObject, key: string, icon: string?, imageId: number?, color: Color3?)
	object:SetAttribute("BannerKey", key)
	if icon then
		object:SetAttribute("BannerIcon", icon)
	end
	if imageId and imageId > 0 then
		object:SetAttribute("BannerImage", imageId)
	end
	if color then
		object:SetAttribute("BannerColor", color)
	end
	scheduleBannerSync()
end

-- Плашка «в фоне» (событие дня между событиями): значок в конце лотка
function Ui.bannerIdle(object: GuiObject, idle: boolean)
	if object:GetAttribute("BannerIdle") ~= idle then
		object:SetAttribute("BannerIdle", idle)
		scheduleBannerSync()
	end
end

-- Объявить плашку полосой сверху ещё раз (началось событие внутри уже видимой плашки)
function Ui.bannerAnnounce(object: GuiObject)
	local last = lastAnnounced[object]
	if last and os.clock() - last < ANNOUNCE_EXPLICIT_COOLDOWN then
		return
	end
	local key = object:GetAttribute("BannerKey")
	queueAnnounce(object, type(key) == "string" and Hud.announceImportant[key] == true)
	scheduleBannerSync()
end

-- Найти плашку по имени, где бы она сейчас ни была (склад, объявление, карточка)
function Ui.bannerFind(name: string): Instance?
	local ui = bannerUi
	if not ui then
		return nil
	end
	return ui.source:FindFirstChild(name)
		or ui.stripBody:FindFirstChild(name)
		or ui.cardBody:FindFirstChild(name)
end

-- Низ HUD (верхняя строка и строки разработки), px от верха экрана: под ним полоса объявлений
function Ui.setHudBottom(y: number)
	local value = math.max(y, HUD_BOTTOM_MIN)
	if value ~= hudBottom then
		hudBottom = value
		scheduleBannerSync()
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
