--!strict
-- Окно «Создать игру» (шаг 2.4): название, жанр, тема, фокус по 4 направлениям.
-- Клиент только собирает выбор и просит сервер; проверки и деньги — на сервере.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local WordFilter = require(ReplicatedStorage.Shared.WordFilter)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local FOCUS_KEYS = { "gameplay", "graphics", "sound", "story" }
local MAX_FOCUS = 10
local UNLOCK_CONFIRM_SECONDS = 3

type Item = { id: string, name: string, nameEn: string, unlockCost: number }

local CreateGameWindow = {}

local gui: ScreenGui? = nil
local selectedGenre: string? = nil
local selectedTopic: string? = nil
local focus: { [string]: number } = { gameplay = 4, graphics = 3, sound = 2, story = 1 }
-- Первый клик по закрытой карточке спрашивает, второй — покупает
local pendingUnlock: string? = nil
local pendingUnlockAt = 0

local function sortedByCost(source: { [string]: any }): { Item }
	local list: { Item } = {}
	for _, item in source do
		table.insert(list, item)
	end
	table.sort(list, function(a, b)
		if a.unlockCost ~= b.unlockCost then
			return a.unlockCost < b.unlockCost
		end
		return a.id < b.id
	end)
	return list
end

local GENRE_LIST = sortedByCost(Genres)
local TOPIC_LIST = sortedByCost(Topics)

local render: () -> ()

local function onCardClick(kind: string, item: Item, unlocked: boolean)
	if unlocked then
		if kind == "genre" then
			selectedGenre = item.id
		else
			selectedTopic = item.id
		end
		render()
		return
	end
	local key = kind .. "/" .. item.id
	local now = os.clock()
	if pendingUnlock == key and now - pendingUnlockAt < UNLOCK_CONFIRM_SECONDS then
		pendingUnlock = nil
		Remotes.UnlockContent:FireServer(kind, item.id)
	else
		pendingUnlock = key
		pendingUnlockAt = now
		render()
	end
end

local function buildGrid(
	parent: Instance,
	kind: string,
	list: { Item },
	unlockedSet: { [string]: boolean },
	selected: string?
)
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.2, -6, 0, 40)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for i, item in list do
		local unlocked = unlockedSet[item.id] == true
		-- Сезонную тему показываем, только пока идёт её ивент (сервер открыл её игроку)
		if not unlocked and (item :: any).seasonal then
			continue
		end
		local key = kind .. "/" .. item.id
		local text = ClientState.localName(item)
		local color = Ui.colors.primary
		if not unlocked then
			color = Ui.colors.locked
			text = if pendingUnlock == key
				then ClientState.t("create_unlock_ask", { price = Texts.money(item.unlockCost) })
				else text .. "\n" .. ClientState.t(
					"create_locked",
					{ price = Texts.money(item.unlockCost) }
				)
		elseif selected == item.id then
			color = Ui.colors.good
		end
		local card = Ui.button(grid, text, color, function()
			onCardClick(kind, item, unlocked)
		end)
		card.LayoutOrder = i
	end
	grid.Parent = parent
end

local function focusTotal(): number
	local total = 0
	for _, key in FOCUS_KEYS do
		total += focus[key]
	end
	return total
end

local function buildFocusRow(parent: Instance, key: string, order: number)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 34)
	row.LayoutOrder = order

	local name = Ui.label(row, ClientState.t("focus_" .. key), 34)
	name.Size = UDim2.new(0.28, 0, 1, 0)

	local minus = Ui.button(row, "−", Ui.colors.locked, function()
		focus[key] = math.max(focus[key] - 1, 0)
		render()
	end)
	minus.Size = UDim2.new(0, 34, 1, 0)
	minus.Position = UDim2.new(0.28, 0, 0, 0)

	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Ui.colors.locked
	bar.Size = UDim2.new(0.5, -84, 0, 14)
	bar.Position = UDim2.new(0.28, 42, 0.5, -7)
	Ui.corner(bar, 7)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Ui.colors.money
	fill.Size = UDim2.fromScale(focus[key] / MAX_FOCUS, 1)
	Ui.corner(fill, 7)
	fill.Parent = bar
	bar.Parent = row

	local plus = Ui.button(row, "+", Ui.colors.primary, function()
		focus[key] = math.min(focus[key] + 1, MAX_FOCUS)
		render()
	end)
	plus.Size = UDim2.new(0, 34, 1, 0)
	plus.Position = UDim2.new(0.78, -34, 0, 0)

	local total = focusTotal()
	local percent = if total > 0 then math.floor(focus[key] / total * 100 + 0.5) else 0
	local pct = Ui.label(row, percent .. "%", 34, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	pct.Size = UDim2.new(0.2, 0, 1, 0)
	pct.Position = UDim2.new(0.8, 0, 0, 0)
	pct.TextXAlignment = Enum.TextXAlignment.Right

	row.Parent = parent
end

local function comboHint(): (string, Color3)
	if not selectedGenre or not selectedTopic then
		return "", Ui.colors.muted
	end
	-- Подсказываем только то, что игрок уже узнал сам: так он учится, а не читает таблицу
	local best = ClientState.knownCombos[selectedGenre .. "/" .. selectedTopic]
	if not best then
		return ClientState.t("create_combo_unknown"), Ui.colors.muted
	elseif best >= 8 then
		return ClientState.t("create_combo_great"), Ui.colors.good
	elseif best <= 4 then
		return ClientState.t("create_combo_bad"), Ui.colors.bad
	end
	return ClientState.t("create_combo_unknown"), Ui.colors.muted
end

local nameText = ""
-- Кнопка старта текущего окна: обновляем её на лету, пока игрок печатает название
-- (полная перерисовка снесла бы поле ввода вместе с фокусом)
local startButton: TextButton? = nil

local MIN_NAME_LENGTH = 2

local function trimmedName(): string
	return (nameText:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function startError(): string?
	if ClientState.developing then
		return ClientState.t("error_busy")
	elseif utf8.len(trimmedName()) == nil or (utf8.len(trimmedName()) :: number) < MIN_NAME_LENGTH then
		return ClientState.t("error_name_empty")
	elseif not WordFilter.isClean(trimmedName()) then
		return ClientState.t("error_name_bad")
	elseif not selectedGenre then
		return ClientState.t("error_pick_genre")
	elseif not selectedTopic then
		return ClientState.t("error_pick_topic")
	elseif focusTotal() <= 0 then
		return ClientState.t("error_focus_empty")
	end
	return nil
end

render = function()
	if not gui then
		return
	end
	local data = ClientState.data
	if not data then
		return
	end
	local old = gui:FindFirstChild("Window")
	if old then
		old:Destroy()
	end

	local window = Ui.window(gui, "Window", Vector2.new(640, 640))

	local title = Ui.label(window, ClientState.t("create_title"), 36, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 36)
	local close = Ui.button(window, ClientState.t("create_close"), Ui.colors.locked, function()
		CreateGameWindow.close()
	end)
	close.Size = UDim2.fromOffset(40, 40)
	close.Position = UDim2.new(1, -52, 0, 8)

	local body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(16, 56)
	body.Size = UDim2.new(1, -32, 1, -128)
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 6
	Ui.list(body, 8)
	body.Parent = window

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	Ui.label(body, ClientState.t("create_name_label"), 22, nil, Ui.colors.muted).LayoutOrder = nextOrder()
	local nameBox = Instance.new("TextBox")
	nameBox.Size = UDim2.new(1, 0, 0, 40)
	nameBox.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
	nameBox.TextColor3 = Ui.colors.text
	nameBox.PlaceholderText = ClientState.t("create_name_placeholder")
	-- Не длиннее, чем примет сервер (30 символов)
	nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		local length = utf8.len(nameBox.Text)
		if length and length > 30 then
			nameBox.Text = nameBox.Text:sub(1, (utf8.offset(nameBox.Text, 31) or (#nameBox.Text + 1)) - 1)
		end
	end)
	nameBox.Font = Ui.bodyFont
	nameBox.TextScaled = true
	nameBox.ClearTextOnFocus = false
	nameBox.Text = nameText
	nameBox.LayoutOrder = nextOrder()
	Ui.corner(nameBox, 10)
	nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		nameText = nameBox.Text
		local button = startButton
		if button and button.Parent then
			local err = startError()
			button.Text = err or ClientState.t("create_start")
			button.BackgroundColor3 = if err then Ui.colors.locked else Ui.colors.money
			button.TextColor3 = if err then Ui.colors.muted else Color3.fromRGB(40, 30, 0)
			button:SetAttribute("Ready", err == nil)
		end
	end)
	nameBox.Parent = body

	Ui.label(body, ClientState.t("create_genre_label"), 22, nil, Ui.colors.muted).LayoutOrder = nextOrder()
	local genreHolder = Instance.new("Frame")
	genreHolder.BackgroundTransparency = 1
	genreHolder.Size = UDim2.fromScale(1, 0)
	genreHolder.AutomaticSize = Enum.AutomaticSize.Y
	genreHolder.LayoutOrder = nextOrder()
	genreHolder.Parent = body
	buildGrid(genreHolder, "genre", GENRE_LIST, data.unlockedGenres, selectedGenre)

	Ui.label(body, ClientState.t("create_topic_label"), 22, nil, Ui.colors.muted).LayoutOrder = nextOrder()
	local topicHolder = Instance.new("Frame")
	topicHolder.BackgroundTransparency = 1
	topicHolder.Size = UDim2.fromScale(1, 0)
	topicHolder.AutomaticSize = Enum.AutomaticSize.Y
	topicHolder.LayoutOrder = nextOrder()
	topicHolder.Parent = body
	buildGrid(topicHolder, "topic", TOPIC_LIST, data.unlockedTopics, selectedTopic)

	local hintText, hintColor = comboHint()
	Ui.label(body, hintText, 24, Ui.titleFontFor(ClientState.lang), hintColor).LayoutOrder = nextOrder()

	Ui.label(body, ClientState.t("create_focus_label"), 22, nil, Ui.colors.muted).LayoutOrder = nextOrder()
	Ui.label(body, ClientState.t("create_focus_hint"), 18, Enum.Font.GothamMedium, Ui.colors.muted).LayoutOrder =
		nextOrder()
	for _, key in FOCUS_KEYS do
		buildFocusRow(body, key, nextOrder())
	end

	local err = startError()
	local start = Ui.button(
		window,
		err or ClientState.t("create_start"),
		if err then Ui.colors.locked else Ui.colors.money,
		function()
			if startError() then
				return
			end
			Remotes.StartDevelopment:FireServer({
				name = trimmedName(),
				genreId = selectedGenre,
				topicId = selectedTopic,
				focus = table.clone(focus),
			})
			CreateGameWindow.close()
		end
	)
	start.Name = "StartButton"
	startButton = start
	-- Туториал смотрит на атрибут, а не на текст: тексты переводятся
	start:SetAttribute("Ready", err == nil)
	start.TextColor3 = if err then Ui.colors.muted else Color3.fromRGB(40, 30, 0)
	start.Size = UDim2.new(1, -32, 0, 52)
	start.Position = UDim2.new(0, 16, 1, -64)
end

function CreateGameWindow.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "CreateGameWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	pendingUnlock = nil
	Ui.windowOpened()
	render()
end

function CreateGameWindow.close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

function CreateGameWindow.start()
	-- Деньги или открытые жанры поменялись — перерисовать открытое окно
	ClientState.changed:Connect(function()
		render()
	end)
end

return CreateGameWindow
