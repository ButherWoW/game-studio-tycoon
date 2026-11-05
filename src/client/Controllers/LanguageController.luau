--!strict
-- Выбор языка: кнопка 🌐 в боковом меню (слот 6) и окно со списком языков.
-- Выбор сохраняется на сервере (LanguageService), при входе загружается оттуда.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LanguageRemotes = require(ReplicatedStorage.Shared.LanguageRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local LanguageController = {}

local gui: ScreenGui? = nil
-- Игрок уже выбрал язык сам — ответ сервера с сохранённым языком его не перебивает
local pickedThisSession = false
local renderedLang = ""

local function render()
	local screen = gui
	if not screen then
		return
	end
	local old = screen:FindFirstChild("Window")
	if old then
		old:Destroy()
	end

	renderedLang = ClientState.lang
	local window = Ui.window(screen, "Window", Vector2.new(640, 560))

	local title = Ui.label(window, ClientState.t("lang_title"), 36, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 36)
	local close = Ui.button(window, ClientState.t("create_close"), Ui.colors.locked, function()
		LanguageController.close()
	end)
	close.Size = UDim2.fromOffset(40, 40)
	close.Position = UDim2.new(1, -52, 0, 8)

	local body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(16, 56)
	body.Size = UDim2.new(1, -32, 1, -68)
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 6
	body.Parent = window

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
