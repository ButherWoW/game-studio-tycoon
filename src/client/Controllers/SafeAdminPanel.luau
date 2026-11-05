--!strict
-- Панель владельца сейфа (SafeService) — основной способ задать код вместо /safe в чате:
-- опечатка в команде ушла бы в общий чат вместе с кодом. Кнопка 🔐 видна только тем, кому
-- сервер поставил атрибут SafeAdmin (ownerUserIds / создатель игры / владелец группы);
-- сервер всё равно заново проверяет владельца и поля (SafeAdmin remote → та же логика, что /safe).
-- Тексты только по-русски: панель видит один владелец, как и ответы на /safe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Safe = require(Shared.Config.Safe)
local SafeRemotes = require(Shared.SafeRemotes)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local SafeAdminPanel = {}
local buttonGui: ScreenGui? = nil
local gui: ScreenGui? = nil
local status: TextLabel? = nil

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		status = nil
		Ui.windowClosed()
	end
end

local function textBox(parent: Instance, placeholder: string, y: number): TextBox
	local box = Instance.new("TextBox")
	box.Position = UDim2.fromOffset(150, y)
	box.Size = UDim2.new(1, -166, 0, 40)
	box.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
	box.TextColor3 = Ui.colors.text
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Ui.colors.muted
	box.Font = Ui.bodyFont
	box.TextSize = 22
	box.Text = ""
	box.ClearTextOnFocus = false
	Ui.corner(box, 8)
	box.Parent = parent
	return box
end

local function caption(parent: Instance, text: string, y: number)
	local label = Ui.label(parent, text, 40, Ui.bodyFont, Ui.colors.muted)
	label.Position = UDim2.fromOffset(16, y)
	label.Size = UDim2.fromOffset(126, 40)
	-- На телефоне окно сжимается: подпись не должна налезать на поле справа
	label.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 22
	limit.Parent = label
end

local function open()
	close()
	local screen = Instance.new("ScreenGui")
	screen.Name = "SafeAdminPanel"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 30
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened(close)

	local window = Ui.window(screen, "Window", Vector2.new(480, 470))
	local title =
		Ui.label(window, "🔐 Сейф — панель владельца", 32, Enum.Font.GothamBold)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 32)
	local closeButton = Ui.button(window, "×", Ui.colors.locked, close)
	closeButton.Size = UDim2.fromOffset(40, 40)
	closeButton.Position = UDim2.new(1, -52, 0, 8)

	-- Код: настоящий текст в поле невидим, поверх — точки (у TextBox нет режима пароля)
	caption(window, "Код (6 цифр)", 60)
	local code = textBox(window, "", 60)
	code.Size = UDim2.new(1, -236, 0, 40)
	code.TextTransparency = 1
	local dots = Ui.label(code, "", 40, Ui.bodyFont, Ui.colors.text)
	dots.Size = UDim2.fromScale(1, 1)
	dots.TextXAlignment = Enum.TextXAlignment.Center
	local shown = false
	local function redraw()
		code.TextTransparency = if shown then 0 else 1
		dots.Visible = not shown
		dots.Text = string.rep("•", #code.Text)
	end
	code:GetPropertyChangedSignal("Text"):Connect(function()
		local digits = code.Text:gsub("%D", ""):sub(1, Safe.codeLength)
		if digits ~= code.Text then
			code.Text = digits
			return
		end
		redraw()
	end)
	local toggle = Ui.button(window, "👁", Ui.colors.primary, function()
		shown = not shown
		redraw()
	end)
	toggle.Size = UDim2.fromOffset(60, 40)
	toggle.Position = UDim2.new(1, -76, 0, 60)
	redraw()

	caption(window, "Приз $", 110)
	local cash = textBox(window, tostring(Safe.defaultCash) .. " (или 500k, 20m)", 110)
	caption(window, "Лимит", 160)
	local limit = textBox(window, tostring(Safe.defaultLimit) .. " (0 — без лимита)", 160)
	caption(window, "До (UTC)", 210)
	local untilBox =
		textBox(window, "2026-11-12 или 2026-11-12T18:00 (пусто — бессрочно)", 210)

	local function send(action: string)
		local label = status
		if label then
			label.Text = "…"
			label.TextColor3 = Ui.colors.muted
		end
		SafeRemotes.SafeAdmin:FireServer({
			action = action,
			code = code.Text,
			cash = (cash.Text:gsub("%s", "")),
			limit = (limit.Text:gsub("%s", "")),
			["until"] = (untilBox.Text:gsub("%s", "")),
		})
	end
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(16, 266)
	row.Size = UDim2.new(1, -32, 0, 48)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.Parent = row
	row.Parent = window
	for _, item in
		{
			{ "Задать", Ui.colors.good, "set" },
			{ "Убрать", Ui.colors.bad, "clear" },
			{ "Статус", Ui.colors.primary, "status" },
		}
	do
		local action = item[3] :: string
		local b = Ui.button(row, item[1] :: string, item[2] :: Color3, function()
			send(action)
		end)
		b.Size = UDim2.new(1 / 3, -6, 1, 0)
	end

	local result = Ui.label(
		window,
		"Код не уходит в чат и не виден другим игрокам",
		22,
		Enum.Font.GothamMedium
	)
	result.Position = UDim2.fromOffset(16, 326)
	result.Size = UDim2.new(1, -32, 0, 128)
	result.TextWrapped = true
	result.TextYAlignment = Enum.TextYAlignment.Top
	result.TextColor3 = Ui.colors.muted
	status = result
end

local function showButton()
	if buttonGui or player:GetAttribute("SafeAdmin") ~= true then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "SafeAdminButton"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 2
	screen.Parent = player:WaitForChild("PlayerGui")
	buttonGui = screen
	local b = Ui.button(screen, "🔐", Ui.colors.money, function()
		if gui then
			close()
		else
			open()
		end
	end)
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -12, 0, 140)
	b.Size = UDim2.fromOffset(48, 48)
end

function SafeAdminPanel.start()
	SafeRemotes.SafeNotice.OnClientEvent:Connect(function(info: any)
		local label = status
		if label and type(info) == "table" and info.kind == "admin" and type(info.text) == "string" then
			label.Text = info.text
			label.TextColor3 = Ui.colors.text
		end
	end)
	player:GetAttributeChangedSignal("SafeAdmin"):Connect(showButton)
	showButton()
end

return SafeAdminPanel
