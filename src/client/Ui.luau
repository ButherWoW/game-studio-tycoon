--!strict
-- Стиль интерфейса из issue #5 и общие конструкторы элементов.

local TextChatService = game:GetService("TextChatService")

local Ui = {}

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
function Ui.window(parent: Instance, name: string, maxSize: Vector2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0.92, 0.88)
	frame.BackgroundColor3 = Ui.colors.panel
	frame.BackgroundTransparency = 0.05
	Ui.corner(frame)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.stroke
	stroke.Parent = frame
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = maxSize
	limit.Parent = frame
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
	b.Parent = parent
	return b
end

-- Боковое меню слева посередине (слева сверху чат, справа сверху список игроков).
-- Слоты, чтобы фичи не спорили за место: 1 исследования, 2 сотрудники, 3 задания,
-- 4 магазин, 5 rebirth, 6 язык. order внутри слота не нужен — один слот, одна кнопка.
local menuGui: ScreenGui? = nil
local MENU_BUTTON = 52

function Ui.menuButton(slot: number, icon: string, onClick: () -> ()): TextButton
	if not menuGui then
		local Players = game:GetService("Players")
		local screen = Instance.new("ScreenGui")
		screen.Name = "SideMenu"
		screen.ResetOnSpawn = false
		screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		menuGui = screen
	end
	local b = Ui.button(menuGui :: ScreenGui, icon, Ui.colors.panel, onClick)
	b.Name = "Slot" .. slot
	b.AnchorPoint = Vector2.new(0, 0.5)
	b.Size = UDim2.fromOffset(MENU_BUTTON, MENU_BUTTON)
	b.Position = UDim2.new(0, 12, 0.5, (slot - 3.5) * (MENU_BUTTON + 8))
	return b
end

function Ui.list(parent: Instance, padding: number)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = parent
	return layout
end

return Ui
