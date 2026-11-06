--!strict
-- Вступление для новичка: 4 экрана при первом входе нового профиля (Config/Texts intro_1..intro_4).
-- Самым первым идёт выбор языка (06.11, владелец): чтобы историю можно было прочитать на своём языке.
-- «Далее» / «Пропустить», на последнем экране «Начать». Показывает атрибут игрока IntroActive
-- (IntroService; true только у профиля, который вступления ещё не видел). Пока он true, туториал
-- (TutorialController) и всплывающие окна (PopupQueue.busy) ждут. Конец или «Пропустить» —
-- IntroSeen на сервер, повторно вступление не покажется.
-- Картинка экрана (Config/Images.intro, 16:9) сверху, текст под ней; пока картинки нет (0) —
-- цветной фон с крупным эмодзи. Окно строится в «дизайнерском» размере и целиком уменьшается
-- UIScale под экран (телефон 844×390).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IntroRemotes = require(ReplicatedStorage.Shared.IntroRemotes)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local IntroController = {}

local DISPLAY_ORDER = 60 -- над всеми окнами, HUD и плашками туториала
local CARD_SIZE = Vector2.new(680, 368)
local ART_SIZE = Vector2.new(320, 180) -- 16:9
local MAX_SCALE = 1.5

type Page = { image: string, emoji: string, color: Color3 }

local PAGES: { Page } = {
	{ image = "intro1", emoji = "🛋️", color = Color3.fromRGB(46, 84, 140) },
	{ image = "intro2", emoji = "🎮", color = Color3.fromRGB(96, 58, 138) },
	{ image = "intro3", emoji = "⭐", color = Color3.fromRGB(150, 104, 28) },
	{ image = "intro4", emoji = "🏢", color = Color3.fromRGB(32, 112, 100) },
}

local screen: ScreenGui? = nil
local finished = false

local function finish()
	if finished then
		return
	end
	finished = true
	IntroRemotes.IntroSeen:FireServer()
	local gui = screen
	screen = nil
	if gui then
		gui:Destroy()
	end
end

local function open()
	if screen or finished then
		return
	end
	-- 0 — выбор языка (до истории), 1..#PAGES — страницы вступления
	local page = 0

	local gui = Instance.new("ScreenGui")
	gui.Name = "IntroScreen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER
	gui.Parent = player:WaitForChild("PlayerGui")
	screen = gui

	-- Затемнение на весь экран забирает нажатия: сквозь него ничего не нажать
	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.25
	shade.BorderSizePixel = 0
	shade.Active = true
	shade.Parent = gui

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
	card.BackgroundColor3 = Ui.colors.panel
	card.Active = true
	Ui.corner(card)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.stroke
	stroke.Parent = card
	local scale = Instance.new("UIScale")
	scale.Parent = card
	card.Parent = gui

	local function fit()
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local byWidth = viewport.X * 0.96 / CARD_SIZE.X
		local byHeight = viewport.Y * 0.96 / CARD_SIZE.Y
		scale.Scale = math.clamp(math.min(byWidth, byHeight), 0.4, MAX_SCALE)
	end
	fit()
	local camera = workspace.CurrentCamera
	local viewportConnection: RBXScriptConnection? = nil
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end

	-- Картинка 16:9 сверху; без картинки — цветной фон с эмодзи
	local art = Instance.new("Frame")
	art.Name = "Art"
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.Position = UDim2.new(0.5, 0, 0, 12)
	art.Size = UDim2.fromOffset(ART_SIZE.X, ART_SIZE.Y)
	art.BorderSizePixel = 0
	art.ClipsDescendants = true
	Ui.corner(art)
	art.Parent = card

	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Crop
	image.Parent = art

	local emoji = Instance.new("TextLabel")
	emoji.Size = UDim2.fromScale(1, 1)
	emoji.BackgroundTransparency = 1
	emoji.Font = Ui.bodyFont
	emoji.TextSize = 110
	emoji.TextColor3 = Ui.colors.text
	emoji.Parent = art

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.new(0.5, 0, 0, 198)
	body.Size = UDim2.fromOffset(CARD_SIZE.X - 40, 104)
	body.BackgroundTransparency = 1
	body.Font = Ui.bodyFont
	body.TextColor3 = Ui.colors.text
	body.TextScaled = true
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Center
	body.Parent = card
	local bodyLimit = Instance.new("UITextSizeConstraint")
	bodyLimit.MinTextSize = 14
	bodyLimit.MaxTextSize = 24
	bodyLimit.Parent = body

	-- Точки страниц между кнопками
	local dots = Instance.new("Frame")
	dots.AnchorPoint = Vector2.new(0.5, 0.5)
	dots.Position = UDim2.new(0.5, 0, 0, 334)
	dots.Size = UDim2.fromOffset(#PAGES * 22, 12)
	dots.BackgroundTransparency = 1
	dots.Parent = card
	local dotLayout = Instance.new("UIListLayout")
	dotLayout.FillDirection = Enum.FillDirection.Horizontal
	dotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotLayout.Padding = UDim.new(0, 10)
	dotLayout.Parent = dots
	local dotFrames: { Frame } = {}
	for i = 1, #PAGES do
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(12, 12)
		dot.BorderSizePixel = 0
		dot.LayoutOrder = i
		Ui.corner(dot, 6)
		dot.Parent = dots
		table.insert(dotFrames, dot)
	end

	-- Выбор языка: заголовок на двух языках и сетка всех языков игры (кнопка — родное название)
	local picker = Instance.new("Frame")
	picker.Name = "LanguagePicker"
	picker.BackgroundTransparency = 1
	picker.Position = UDim2.fromOffset(20, 12)
	picker.Size = UDim2.fromOffset(CARD_SIZE.X - 40, 292)
	picker.Parent = card
	local pickerTitle =
		Ui.label(picker, "🌐  Выбери язык  ·  Choose your language", 36, Enum.Font.GothamBold)
	pickerTitle.TextXAlignment = Enum.TextXAlignment.Center
	pickerTitle.Size = UDim2.new(1, 0, 0, 36)
	local pickerBody = Instance.new("ScrollingFrame")
	pickerBody.BackgroundTransparency = 1
	pickerBody.BorderSizePixel = 0
	pickerBody.Position = UDim2.fromOffset(0, 46)
	pickerBody.Size = UDim2.new(1, 0, 1, -46)
	pickerBody.CanvasSize = UDim2.new()
	pickerBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pickerBody.ScrollBarThickness = 6
	pickerBody.Parent = picker
	local pickerGrid = Instance.new("UIGridLayout")
	pickerGrid.CellSize = UDim2.new(1 / 3, -8, 0, 40)
	pickerGrid.CellPadding = UDim2.fromOffset(6, 6)
	pickerGrid.SortOrder = Enum.SortOrder.LayoutOrder
	pickerGrid.Parent = pickerBody
	local langButtons: { [string]: TextButton } = {}
	local render: () -> ()
	for index, language in Texts.languages do
		local button = Ui.button(pickerBody, language.nativeName, Ui.colors.primary, function()
			ClientState.setLang(language.code)
		end)
		button.Font = Ui.titleFontFor(language.code)
		button.LayoutOrder = index
		langButtons[language.code] = button
	end

	local skip = Ui.button(card, "", Ui.colors.locked, finish)
	skip.Name = "SkipButton"
	skip.AnchorPoint = Vector2.new(0, 0.5)
	skip.Position = UDim2.new(0, 20, 0, 334)
	skip.Size = UDim2.fromOffset(150, 44)

	local nextButton: TextButton
	nextButton = Ui.button(card, "", Ui.colors.primary, function()
		if page >= #PAGES then
			finish()
			return
		end
		page += 1
		render()
	end)
	nextButton.Name = "NextButton"
	nextButton.AnchorPoint = Vector2.new(1, 0.5)
	nextButton.Position = UDim2.new(1, -20, 0, 334)
	nextButton.Size = UDim2.fromOffset(170, 44)

	-- Перерисовка текущей страницы (смена страницы и смена языка)
	render = function()
		-- Экран выбора языка (до истории): без картинки, текста страницы и точек
		local choosing = page == 0
		picker.Visible = choosing
		art.Visible = not choosing
		body.Visible = not choosing
		dots.Visible = not choosing
		for code, button in langButtons do
			button.BackgroundColor3 = if code == ClientState.lang then Ui.colors.good else Ui.colors.primary
		end
		if choosing then
			skip.Visible = false
			nextButton.Text = ClientState.t("intro_next")
			nextButton.BackgroundColor3 = Ui.colors.primary
			return
		end
		local current = PAGES[page]
		art.BackgroundColor3 = current.color
		local imageId = (Images.intro :: { [string]: number })[current.image] or 0
		image.Visible = imageId > 0
		image.Image = if imageId > 0 then "rbxassetid://" .. imageId else ""
		emoji.Visible = imageId <= 0
		emoji.Text = current.emoji
		body.Text = ClientState.t("intro_" .. page)
		local last = page >= #PAGES
		skip.Visible = not last
		skip.Text = ClientState.t("intro_skip")
		nextButton.Text = ClientState.t(if last then "intro_start" else "intro_next")
		nextButton.BackgroundColor3 = if last then Ui.colors.good else Ui.colors.primary
		for i, dot in dotFrames do
			dot.BackgroundColor3 = if i == page then Ui.colors.money else Ui.colors.stroke
		end
	end
	render()

	local langConnection = ClientState.langChanged:Connect(render)
	gui.Destroying:Connect(function()
		langConnection:Disconnect()
		if viewportConnection then
			viewportConnection:Disconnect()
		end
	end)
end

function IntroController.start()
	local function check()
		if player:GetAttribute("IntroActive") == true then
			open()
		end
	end
	player:GetAttributeChangedSignal("IntroActive"):Connect(check)
	check()
end

return IntroController
