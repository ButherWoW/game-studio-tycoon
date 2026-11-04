--!strict
-- Окно «🛋️ Студия»: вкладки «Интерьер» (то же, что кнопки на полу, — покупка через BuyUpgrade
-- с теми же проверками на сервере), «Декор» (Config/Decor, DecorService) и «Настроение»
-- (разбор MoodService). Клиент только показывает и просит; цены и замки проверяет сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local DecorRemotes = require(Shared.DecorRemotes)
local Decor = require(Shared.Config.Decor)
local Mood = require(Shared.Config.Mood)
local Stages = require(Shared.Config.Stages)
local Texts = require(Shared.Config.Texts)
local StudioLayout = require(Shared.StudioLayout)
local ClientState = require(script.Parent.Parent.ClientState)
local StudioState = require(script.Parent.Parent.StudioState)
local Ui = require(script.Parent.Parent.Ui)

type Tab = "interior" | "decor" | "mood"

local MENU_SLOT = 13
local ROW_HEIGHT = 72
local ROW_COLOR = Color3.fromRGB(44, 46, 66)
local TABS: { Tab } = { "interior", "decor", "mood" }

local StudioWindow = {}
local gui: ScreenGui? = nil
local tab: Tab = "decor"
local decorFloor: number? = nil -- выбранный этаж во вкладке «Декор» (nil — верхний открытый)
local scrollY = 0
local render: () -> ()

local function upgradeName(id: string): string
	local upgrade = StudioLayout.get(id)
	if upgrade then
		local key = "upgrade_" .. upgrade.id
		return ClientState.localText(key, upgrade.name, Texts.en[key] or upgrade.name)
	end
	return id
end

local function floorLabel(floor: number): string
	if StudioState.state.studioLevel <= 1 then
		return ClientState.t("studio_floor_garage")
	end
	return StudioLayout.floorName(ClientState.lang, floor)
end

-- Строка: иконка, название, описание; справа кнопка. Возвращает рамку
local function row(
	parent: Instance,
	order: number,
	icon: string,
	title: string,
	description: string,
	descColor: Color3?
): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = ROW_COLOR
	frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	frame.LayoutOrder = order
	Ui.corner(frame, 10)

	local iconLabel = Ui.label(frame, icon, ROW_HEIGHT, Ui.titleFont)
	iconLabel.Size = UDim2.new(0, 56, 1, 0)
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center

	local titleLabel = Ui.label(frame, title, 26, Ui.titleFontFor(ClientState.lang))
	titleLabel.Position = UDim2.fromOffset(60, 8)
	titleLabel.Size = UDim2.new(0.66, -64, 0, 26)

	local descLabel = Ui.label(frame, description, 20, Enum.Font.GothamMedium, descColor or Ui.colors.muted)
	descLabel.Position = UDim2.fromOffset(60, 40)
	descLabel.Size = UDim2.new(0.66, -64, 0, 20)

	frame.Parent = parent
	return frame
end

local function rowButton(frame: Frame, text: string, color: Color3, onClick: () -> ()): TextButton
	local b = Ui.button(frame, text, color, onClick)
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -8, 0.5, 0)
	b.Size = UDim2.new(0.3, 0, 0, 44)
	return b
end

-- Кнопка цены: зелёная/золотая — хватает денег, серая — нет или закрыто
local function priceButton(frame: Frame, cost: number, enabled: boolean, onBuy: () -> ())
	local data = ClientState.data
	local canPay = enabled and data ~= nil and data.cash >= cost
	local b = rowButton(
		frame,
		if cost <= 0 then ClientState.t("price_free") else Texts.money(cost),
		if canPay then Ui.colors.money else Ui.colors.locked,
		function()
			if canPay then
				onBuy()
			end
		end
	)
	b.TextColor3 = if canPay then Color3.fromRGB(40, 30, 0) else Ui.colors.muted
end

local function note(body: Instance, text: string, order: number)
	local label = Ui.label(body, text, 22, Enum.Font.GothamMedium, Ui.colors.muted)
	label.TextScaled = false
	label.TextSize = 17
	label.TextWrapped = true
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, -8, 0, 22)
	label.LayoutOrder = order
end

local function lockText(offer: StudioState.Offer): string?
	local key = offer.lock
	if not key then
		return nil
	end
	local vars = table.clone(offer.lockVars or {})
	if type(vars.id) == "string" then
		vars.name = upgradeName(vars.id)
	end
	return ClientState.t(key, vars)
end

local function buildInterior(body: Instance)
	local state = StudioState.state
	if not state.ownsGarage then
		note(body, ClientState.t("studio_no_garage"), 1)
		return
	end
	note(body, ClientState.t("studio_interior_hint"), 1)
	if #state.offers == 0 then
		note(body, ClientState.t("studio_interior_done"), 2)
		return
	end
	for i, offer in state.offers do
		local title, icon
		if offer.stage then
			local stage = Stages[offer.stage]
			title =
				ClientState.t("studio_move", { stage = if stage then ClientState.localName(stage) else "?" })
			icon = "🏢"
		else
			title = upgradeName(offer.id)
			icon = if offer.move then "🏢" else "🛠"
		end
		local parts = { floorLabel(offer.floor) }
		local moodPoints = Mood.upgrades[offer.id]
		if moodPoints then
			table.insert(parts, "+" .. moodPoints .. " 😊")
		end
		local locked = lockText(offer)
		if locked then
			table.insert(parts, "🔒 " .. locked)
		end
		local frame = row(body, i + 1, icon, title, table.concat(parts, " · "))
		priceButton(frame, offer.cost, locked == nil, function()
			Remotes.BuyUpgrade:FireServer(offer.id)
		end)
	end
end

local function buildFloorPicker(body: Instance, open: number, selected: number)
	local bar = Instance.new("Frame")
	bar.BackgroundTransparency = 1
	bar.Size = UDim2.new(1, -8, 0, 44)
	bar.LayoutOrder = 2
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.Parent = bar
	bar.Parent = body
	for floor = 1, open do
		local b = Ui.button(
			bar,
			floorLabel(floor),
			if floor == selected then Ui.colors.primary else Ui.colors.locked,
			function()
				if decorFloor ~= floor then
					decorFloor = floor
					render()
				end
			end
		)
		b.Size = UDim2.new(1 / open, -6, 1, 0)
	end
end

local function buildDecor(body: Instance)
	local state = StudioState.state
	if not state.ownsGarage then
		note(body, ClientState.t("studio_no_garage"), 1)
		return
	end
	local open = math.max(state.floorsOpen, 1)
	local floor = math.clamp(decorFloor or open, 1, open)
	note(body, ClientState.t("studio_decor_hint"), 1)
	if open > 1 then
		buildFloorPicker(body, open, floor)
	end
	local stage = Decor.stageFor(floor, state.studioLevel)
	local order = 10
	for _, item in Decor.list do
		if not item.slots[stage] then
			continue
		end
		local name = ClientState.localText("decor_" .. item.id, item.name, item.nameEn)
		local frame = row(body, order, item.emoji, name, "+" .. item.mood .. " 😊 · " .. floorLabel(floor))
		order += 1
		if state.owned[Decor.key(item.id, floor)] then
			rowButton(frame, ClientState.t("studio_decor_owned"), Ui.colors.good, function() end)
		else
			priceButton(frame, Decor.cost(item, floor), true, function()
				DecorRemotes.BuyDecor:FireServer(item.id, floor)
			end)
		end
	end
end

local function buildMood(body: Instance)
	local info = StudioState.state.mood
	if not info then
		note(body, ClientState.t("studio_loading"), 1)
		return
	end
	local head = Ui.label(
		body,
		ClientState.t("mood_title", { value = info.value })
			.. "  "
			.. ClientState.t("mood_target", { value = info.target }),
		32,
		Ui.titleFontFor(ClientState.lang),
		StudioState.moodColor(info.value)
	)
	head.LayoutOrder = 1
	local lines = StudioState.moodLines(info)
	for i, line in lines do
		note(body, line, 1 + i)
	end
	note(body, ClientState.t("mood_how"), 100)
end

render = function()
	if not gui then
		return
	end
	local old = gui:FindFirstChild("Window")
	if old then
		local oldBody = old:FindFirstChild("Body")
		if oldBody and oldBody:IsA("ScrollingFrame") then
			scrollY = oldBody.CanvasPosition.Y
		end
		old:Destroy()
	end

	local window = Ui.window(gui, "Window", Vector2.new(680, 600))
	local title = Ui.label(window, ClientState.t("studio_title"), 36, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 36)
	local close = Ui.button(window, ClientState.t("create_close"), Ui.colors.locked, function()
		StudioWindow.close()
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
	for _, id in TABS do
		local b = Ui.button(
			tabs,
			ClientState.t("studio_tab_" .. id),
			if id == tab then Ui.colors.primary else Ui.colors.locked,
			function()
				if tab ~= id then
					tab = id
					scrollY = 0
					render()
				end
			end
		)
		b.Size = UDim2.new(1 / #TABS, -6, 1, 0)
	end

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(16, 112)
	body.Size = UDim2.new(1, -32, 1, -124)
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 6
	Ui.list(body, 8)
	body.Parent = window

	if tab == "interior" then
		buildInterior(body)
	elseif tab == "decor" then
		buildDecor(body)
	else
		buildMood(body)
	end
	local savedY = scrollY
	task.defer(function()
		if body.Parent then
			body.CanvasPosition = Vector2.new(0, savedY)
		end
	end)
end

function StudioWindow.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "StudioWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	scrollY = 0
	Ui.windowOpened()
	render()
	StudioState.request()
end

function StudioWindow.close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

function StudioWindow.start()
	Ui.menuButton(MENU_SLOT, "🛋️", function()
		if gui then
			StudioWindow.close()
		else
			StudioWindow.open()
		end
	end, "menu_studio")
	StudioState.changed:Connect(function()
		render()
	end)
	-- Деньги поменялись — перекрасить кнопки цены
	ClientState.changed:Connect(function()
		render()
	end)
end

return StudioWindow
