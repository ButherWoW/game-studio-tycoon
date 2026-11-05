--!strict
-- Язык и настройки: кнопка 🌐 в боковом меню (слот 6) открывает окно с вкладками
-- «🌐 Язык» (список языков) и «⚙️ Настройки» (Config/Settings: громкость, «меньше эффектов»,
-- чужие титулы и маскоты, уведомления). Язык и настройки хранятся на сервере
-- (LanguageService, SettingsService), при входе загружаются оттуда.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LanguageRemotes = require(ReplicatedStorage.Shared.LanguageRemotes)
local Settings = require(ReplicatedStorage.Shared.Config.Settings)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientSettings = require(script.Parent.Parent.ClientSettings)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local ROW_HEIGHT = 56
local CONTROL_WIDTH = 220

type Tab = "lang" | "settings"

local LanguageController = {}

local gui: ScreenGui? = nil
-- Игрок уже выбрал язык сам — ответ сервера с сохранённым языком его не перебивает
local pickedThisSession = false
local renderedLang = ""
local tab: Tab = "lang"
-- Обновить подписи контролов на вкладке настроек (без перерисовки окна и сброса прокрутки)
local refreshers: { [string]: () -> () } = {}

local function scrollBody(window: Frame): ScrollingFrame
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(16, 112)
	body.Size = UDim2.new(1, -32, 1, -124)
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 6
	body.Parent = window
	return body
end

local function renderLanguages(window: Frame)
	local body = scrollBody(window)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / 3, -8, 0, 44)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body

	for i, language in Texts.languages do
		local selected = language.code == ClientState.lang
		local button = Ui.button(
			body,
			language.nativeName,
			if selected then Ui.colors.good else Ui.colors.primary,
			function()
				pickedThisSession = true
				ClientState.setLang(language.code)
			end
		)
		button.Font = Ui.titleFontFor(language.code)
		button.LayoutOrder = i
	end
end

local function percentText(value: number): string
	return tostring(math.floor(value * 100 + 0.5)) .. "%"
end

-- Строка: подпись слева, контрол справа
local function row(body: ScrollingFrame, order: number, textKey: string): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Ui.colors.stroke
	frame.BackgroundTransparency = 0.6
	frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	frame.LayoutOrder = order
	Ui.corner(frame, 10)
	local label = Ui.label(frame, ClientState.t(textKey), 30)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, 12, 0.5, 0)
	label.Size = UDim2.new(1, -(CONTROL_WIDTH + 28), 0, 30)
	frame.Parent = body
	return frame
end

local function volumeControl(frame: Frame, key: string)
	local step = Settings.volumeStep
	local value: TextLabel
	local function change(delta: number)
		ClientSettings.set(key, (ClientSettings.get(key) :: number) + delta)
	end
	local minus = Ui.button(frame, "−", Ui.colors.primary, function()
		change(-step)
	end)
	minus.AnchorPoint = Vector2.new(1, 0.5)
	minus.Size = UDim2.fromOffset(60, ROW_HEIGHT - 10)
	minus.Position = UDim2.new(1, -(12 + 60 + 88), 0.5, 0)
	value = Ui.label(frame, "", 30)
	value.AnchorPoint = Vector2.new(1, 0.5)
	value.Size = UDim2.fromOffset(84, 30)
	value.Position = UDim2.new(1, -(12 + 62), 0.5, 0)
	value.TextXAlignment = Enum.TextXAlignment.Center
	local plus = Ui.button(frame, "+", Ui.colors.primary, function()
		change(step)
	end)
	plus.AnchorPoint = Vector2.new(1, 0.5)
	plus.Size = UDim2.fromOffset(60, ROW_HEIGHT - 10)
	plus.Position = UDim2.new(1, -12, 0.5, 0)
	refreshers[key] = function()
		local current = ClientSettings.get(key) :: number
		value.Text = percentText(current)
		minus.BackgroundColor3 = if current <= 0 then Ui.colors.locked else Ui.colors.primary
		plus.BackgroundColor3 = if current >= 1 then Ui.colors.locked else Ui.colors.primary
	end
end

local function toggleControl(frame: Frame, key: string)
	local button = Ui.button(frame, "", Ui.colors.locked, function()
		ClientSettings.set(key, not ClientSettings.get(key))
	end)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Size = UDim2.fromOffset(140, ROW_HEIGHT - 10)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	refreshers[key] = function()
		local on = ClientSettings.get(key) == true
		button.Text = ClientState.t(if on then "set_on" else "set_off")
		button.BackgroundColor3 = if on then Ui.colors.good else Ui.colors.locked
	end
end

local function renderSettings(window: Frame)
	local body = scrollBody(window)
	Ui.list(body, 8)
	for i, item in Settings.list do
		local frame = row(body, i, item.text)
		if item.kind == "volume" then
			volumeControl(frame, item.key)
		else
			toggleControl(frame, item.key)
		end
	end
	local hint = Ui.label(body, ClientState.t("set_hint"), 24, nil, Ui.colors.muted)
	hint.LayoutOrder = #Settings.list + 1
	hint.Size = UDim2.new(1, -8, 0, 24)
	for _, refresh in refreshers do
		refresh()
	end
end

local function render()
	local screen = gui
	if not screen then
		return
	end
	local old = screen:FindFirstChild("Window")
	if old then
		old:Destroy()
	end
	table.clear(refreshers)

	renderedLang = ClientState.lang
	local window = Ui.window(screen, "Window", Vector2.new(640, 560))

	local title = Ui.label(
		window,
		ClientState.t(if tab == "lang" then "lang_title" else "set_title"),
		36,
		Ui.titleFontFor(ClientState.lang)
	)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 36)
	local close = Ui.button(window, ClientState.t("create_close"), Ui.colors.locked, function()
		LanguageController.close()
	end)
	close.Size = UDim2.fromOffset(40, 40)
	close.Position = UDim2.new(1, -52, 0, 8)

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(16, 56)
	tabs.Size = UDim2.new(1, -32, 0, 44)
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 8)
	tabsLayout.Parent = tabs
	tabs.Parent = window
	local tabList: { Tab } = { "lang", "settings" }
	for _, id in tabList do
		local b = Ui.button(
			tabs,
			ClientState.t(if id == "lang" then "set_tab_lang" else "set_tab_settings"),
			if id == tab then Ui.colors.primary else Ui.colors.locked,
			function()
				if tab ~= id then
					tab = id
					render()
				end
			end
		)
		b.Size = UDim2.new(0.5, -4, 1, 0)
	end

	if tab == "lang" then
		renderLanguages(window)
	else
		renderSettings(window)
	end
end

function LanguageController.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "LanguageWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 15
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened(LanguageController.close) -- окно меню: закрывает другое открытое окно меню
	render()
end

function LanguageController.close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

function LanguageController.start()
	Ui.menuButton(6, "🌐", function()
		if gui then
			LanguageController.close()
		else
			LanguageController.open()
		end
	end, "menu_language")

	-- Язык поменялся — перерисовать открытое окно (подсветка и заголовок)
	ClientState.changed:Connect(function()
		if ClientState.lang ~= renderedLang then
			render()
		end
	end)
	-- Настройка поменялась (кнопка или ответ сервера при входе) — обновить её контрол
	ClientSettings.changed:Connect(function(key: string)
		local refresh = refreshers[key]
		if refresh and gui then
			refresh()
		end
	end)

	task.spawn(function()
		local ok, saved = pcall(function()
			return LanguageRemotes.GetLanguage:InvokeServer()
		end)
		if ok and not pickedThisSession and Texts.isLanguage(saved) then
			ClientState.setLang(saved, false)
		end
	end)
end

return LanguageController
