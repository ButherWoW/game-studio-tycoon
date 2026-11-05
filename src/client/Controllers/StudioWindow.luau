--!strict
-- Окно «🛋️ Студия»: вкладки «Интерьер» (то же, что кнопки на полу, — покупка через BuyUpgrade
-- с теми же проверками на сервере), «Декор» (Config/Decor, DecorService), «Настроение»
-- (разбор MoodService), «Консоль» (своя консоль и стример, ConsoleClient) и «Стиль» (стиль мебели
-- всей студии, Config/FurnitureStyles, FurnitureStyleService; за Robux — PromptProductPurchase)
-- и «Отделка» (пол/стены/окна оболочек, Config/InteriorFinishes, InteriorFinishService; только за Robux).
-- Клиент только показывает и просит; цены и замки проверяет сервер.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local DecorRemotes = require(Shared.DecorRemotes)
local Decor = require(Shared.Config.Decor)
local DailyEvents = require(Shared.Config.DailyEvents)
local FurnitureStyles = require(Shared.Config.FurnitureStyles)
local Images = require(Shared.Config.Images)
local InteriorFinishes = require(Shared.Config.InteriorFinishes)
local Mood = require(Shared.Config.Mood)
local Stages = require(Shared.Config.Stages)
local Texts = require(Shared.Config.Texts)
local StudioLayout = require(Shared.StudioLayout)
local ClientState = require(script.Parent.Parent.ClientState)
local StudioState = require(script.Parent.Parent.StudioState)
local CompanyEventState = require(script.Parent.Parent.CompanyEventState)
local CompanyEvents = require(Shared.Config.CompanyEvents)
local Ui = require(script.Parent.Parent.Ui)
local ConsoleClient = require(script.Parent.Parent.ConsoleClient)
local ContentDropClient = require(script.Parent.Parent.ContentDropClient)

type Tab = "interior" | "decor" | "mood" | "console" | "style" | "finish"
type StyleState = { owned: { [string]: boolean }, selected: string }

local MENU_SLOT = 13
local ROW_HEIGHT = 72
local ROW_COLOR = Color3.fromRGB(44, 46, 66)
local TABS: { Tab } = { "interior", "decor", "style", "finish", "mood", "console" }
-- Карточка отделки: картинка ShopCard слева (квадрат) и кнопка справа
local FINISH_ROW_HEIGHT = 112
local FINISH_PREVIEW = 96
-- Узкий экран (телефон 844×390): окно ужимается UIScale, и 6 подписей вкладок не читаются —
-- у невыбранных вкладок остаётся только значок, выбранная шире
local COMPACT_WIDTH = 900
local COMPACT_HEIGHT = 520

local StudioWindow = {}
local gui: ScreenGui? = nil
local tab: Tab = "decor"
local decorFloor: number? = nil -- выбранный этаж во вкладке «Декор» (nil — верхний открытый)
local scrollY = 0
local render: () -> ()
-- Стиль мебели с сервера (StyleRemotes.StyleState); до ответа — классика
local styleState: StyleState =
	{ owned = { [FurnitureStyles.default] = true }, selected = FurnitureStyles.default }
local styleRemotes: { [string]: RemoteEvent }? = nil
-- Отделка студии с сервера (StyleRemotes.FinishState); до ответа — классика
local finishState: StyleState =
	{ owned = { [InteriorFinishes.default] = true }, selected = InteriorFinishes.default }

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
	-- Страховка от плохих событий компании (CompanyEventService): цена — минуты дохода
	local events = CompanyEventState.state
	local left = CompanyEventState.insuranceLeft()
	local insuranceText = if left > 0
		then ClientState.t("cev_insurance_active", { time = CompanyEvents.clock(left) })
		else ClientState.t("cev_insurance_desc", { time = CompanyEvents.clock(events.insuranceSeconds) })
	local insurance = row(
		body,
		1,
		"🛡",
		ClientState.t("cev_insurance_title"),
		insuranceText,
		if left > 0 then Ui.colors.good else nil
	)
	-- Продлить можно, пока остаток не больше одного срока (как на сервере)
	priceButton(insurance, events.insurancePrice, CompanyEventState.loaded and left <= 0, function()
		CompanyEventState.buyInsurance()
	end)
	-- Сломанный предмет после потопа: починить здесь же
	local broken = CompanyEventState.broken()
	if broken and broken.item then
		local repair = row(
			body,
			1,
			"🔧",
			CompanyEventState.upgradeName(broken.item),
			CompanyEvents.clock(broken.endsAt - CompanyEventState.now()),
			Ui.colors.bad
		)
		priceButton(repair, events.repairCost, true, function()
			CompanyEventState.repair()
		end)
	end
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
		-- График контента: невышедший декор не показываем (купленный — всегда)
		if
			not state.owned[Decor.key(item.id, floor)] and not ContentDropClient.isReleased("decor", item.id)
		then
			continue
		end
		local name = ClientState.localText("decor_" .. item.id, item.name, item.nameEn)
		local frame = row(body, order, item.emoji, name, "+" .. item.mood .. " 😊 · " .. floorLabel(floor))
		order += 1
		if state.owned[Decor.key(item.id, floor)] then
			rowButton(frame, ClientState.t("studio_decor_owned"), Ui.colors.good, function() end)
		else
			-- «Флеш-распродажа»: та же цена, что спишет сервер
			priceButton(frame, DailyEvents.cashPrice(Decor.cost(item, floor)), true, function()
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

local function styleButton(frame: Frame, style: FurnitureStyles.Style)
	local remotes = styleRemotes
	-- График контента: ещё не вышел — тизер «Скоро: через N дн.»
	local teaser = ContentDropClient.teaser("style", style.id, styleState.owned[style.id] == true)
	if teaser then
		rowButton(frame, teaser, Ui.colors.locked, function() end)
	elseif styleState.selected == style.id then
		rowButton(frame, ClientState.t("fstyle_selected"), Ui.colors.good, function() end)
	elseif styleState.owned[style.id] then
		rowButton(frame, ClientState.t("fstyle_select"), Ui.colors.primary, function()
			if remotes then
				remotes.SelectStyle:FireServer(style.id)
			end
		end)
	elseif FurnitureStyles.isPremium(style) then
		-- productId 0 — продукт ещё не создан в Dashboard: «Скоро»
		local soon = style.productId == 0
		rowButton(
			frame,
			if soon
				then ClientState.t("shop_soon")
				else ClientState.t("shop_robux", { price = style.robuxPrice or 0 }),
			if soon then Ui.colors.locked else Ui.colors.good,
			function()
				if not soon then
					MarketplaceService:PromptProductPurchase(Players.LocalPlayer, style.productId)
				end
			end
		)
	else
		priceButton(frame, DailyEvents.cashPrice(style.cost or 0), remotes ~= nil, function()
			if remotes then
				remotes.BuyStyle:FireServer(style.id)
			end
		end)
	end
end

-- Вкладка «Стиль»: 4 карточки, один стиль на всю студию (только вид, на работу не влияет)
local function buildStyle(body: Instance)
	note(body, ClientState.t("fstyle_hint"), 1)
	ContentDropClient.nextLine(body, 1)
	for i, style in FurnitureStyles.list do
		local frame = row(
			body,
			1 + i,
			style.emoji,
			ClientState.t("fstyle_" .. style.id),
			ClientState.t("fstyle_" .. style.id .. "_desc")
		)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = if styleState.selected == style.id then 3 else 1
		stroke.Color = if styleState.selected == style.id then Ui.colors.good else style.color
		stroke.Transparency = if styleState.selected == style.id then 0 else 0.5
		stroke.Parent = frame
		styleButton(frame, style)
	end
end

-- Превью отделки: ShopCard_512.png, если загружена (Images.interiorFinishes), иначе цвета набора и значок
local function finishPreview(parent: Instance, finish: InteriorFinishes.Finish)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0, 8, 0.5, 0)
	frame.Size = UDim2.fromOffset(FINISH_PREVIEW, FINISH_PREVIEW)
	frame.BackgroundColor3 = finish.color
	frame.BorderSizePixel = 0
	Ui.corner(frame, 8)
	local imageId = if finish.imageKey then Images.interiorFinishes[finish.imageKey] or 0 else 0
	if imageId > 0 then
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Crop
		image.Image = "rbxassetid://" .. imageId
		Ui.corner(image, 8)
		image.Parent = frame
	else
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(finish.color:Lerp(finish.accent, 0.4), finish.color)
		gradient.Parent = frame
		-- Полоса «пола» в цвете вставок набора
		local floor = Instance.new("Frame")
		floor.AnchorPoint = Vector2.new(0, 1)
		floor.Position = UDim2.fromScale(0, 1)
		floor.Size = UDim2.fromScale(1, 0.18)
		floor.BackgroundColor3 = finish.accent
		floor.BorderSizePixel = 0
		Ui.corner(floor, 8)
		floor.Parent = frame
		local emoji = Ui.label(frame, finish.emoji, FINISH_PREVIEW * 0.5)
		emoji.Position = UDim2.fromScale(0.1, 0.12)
		emoji.Size = UDim2.fromScale(0.8, 0.58)
		emoji.TextXAlignment = Enum.TextXAlignment.Center
	end
	frame.Parent = parent
end

local function finishButton(frame: Frame, finish: InteriorFinishes.Finish)
	local remotes = styleRemotes
	-- График контента: ещё не вышла — тизер «Скоро: через N дн.»
	local teaser = ContentDropClient.teaser("finish", finish.id, finishState.owned[finish.id] == true)
	if teaser then
		rowButton(frame, teaser, Ui.colors.locked, function() end)
	elseif finishState.selected == finish.id then
		rowButton(frame, ClientState.t("ifinish_selected"), Ui.colors.good, function() end)
	elseif finishState.owned[finish.id] then
		rowButton(frame, ClientState.t("fstyle_select"), Ui.colors.primary, function()
			if remotes then
				remotes.SelectFinish:FireServer(finish.id)
			end
		end)
	else
		-- Только за Robux; productId 0 — продукт ещё не создан в Dashboard: «Скоро»
		local soon = finish.productId == 0
		rowButton(
			frame,
			if soon
				then ClientState.t("shop_soon")
				else ClientState.t("shop_robux", { price = finish.robuxPrice or 0 }),
			if soon then Ui.colors.locked else Ui.colors.good,
			function()
				if not soon then
					MarketplaceService:PromptProductPurchase(Players.LocalPlayer, finish.productId)
				end
			end
		)
	end
end

-- Вкладка «Отделка»: 4 карточки, одна отделка на всю студию (пол, стены, окна, свет), мебель не меняет
local function buildFinish(body: Instance)
	note(body, ClientState.t("ifinish_hint"), 1)
	for i, finish in InteriorFinishes.list do
		local selected = finishState.selected == finish.id
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = ROW_COLOR
		frame.Size = UDim2.new(1, -8, 0, FINISH_ROW_HEIGHT)
		frame.LayoutOrder = 1 + i
		Ui.corner(frame, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = if selected then 3 else 1
		stroke.Color = if selected then Ui.colors.good else finish.accent
		stroke.Transparency = if selected then 0 else 0.4
		stroke.Parent = frame

		finishPreview(frame, finish)
		local left = FINISH_PREVIEW + 20
		local titleLabel = Ui.label(
			frame,
			ClientState.t("ifinish_" .. finish.id),
			28,
			Ui.titleFontFor(ClientState.lang),
			if finish.id == InteriorFinishes.default
				then nil
				else finish.accent:Lerp(Color3.new(1, 1, 1), 0.3)
		)
		titleLabel.Position = UDim2.fromOffset(left, 12)
		titleLabel.Size = UDim2.new(0.7, -left - 4, 0, 28)
		local descLabel = Ui.label(
			frame,
			ClientState.t("ifinish_" .. finish.id .. "_desc"),
			20,
			Enum.Font.GothamMedium,
			Ui.colors.muted
		)
		descLabel.TextScaled = false
		descLabel.TextSize = 16
		descLabel.TextWrapped = true
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.Position = UDim2.fromOffset(left, 46)
		descLabel.Size = UDim2.new(0.7, -left - 4, 0, FINISH_ROW_HEIGHT - 54)
		frame.Parent = body
		finishButton(frame, finish)
	end
end

local function isCompact(): boolean
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return viewport.X < COMPACT_WIDTH or viewport.Y < COMPACT_HEIGHT
end

local function tabText(id: Tab, compact: boolean): string
	local key = if id == "style"
		then "fstyle_tab"
		elseif id == "finish" then "ifinish_tab"
		else "studio_tab_" .. id
	local text = ClientState.t(key)
	if compact and id ~= tab then
		-- Подписи вкладок начинаются со значка: «🛠 Интерьер» -> «🛠»
		return string.match(text, "^(%S+)%s") or text
	end
	return text
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
	local compact = isCompact()
	-- Выбранная вкладка в компактном режиме — в 3 доли ширины, остальные — по одной
	local shares = if compact then #TABS + 2 else #TABS
	for _, id in TABS do
		local b = Ui.button(
			tabs,
			tabText(id, compact),
			if id == tab then Ui.colors.primary else Ui.colors.locked,
			function()
				if tab ~= id then
					tab = id
					scrollY = 0
					render()
				end
			end
		)
		local share = if compact and id == tab then 3 else 1
		b.Size = UDim2.new(share / shares, -6, 1, 0)
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
	elseif tab == "console" then
		-- Своя консоль и стример (ConsoleClient)
		ConsoleClient.buildTab(body)
	elseif tab == "style" then
		buildStyle(body)
	elseif tab == "finish" then
		buildFinish(body)
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
	Ui.windowOpened(StudioWindow.close) -- окно меню: закрывает другое открытое окно меню
	render()
	StudioState.request()
	ConsoleClient.request()
	if styleRemotes then
		styleRemotes.StyleStateRequest:FireServer()
		styleRemotes.FinishStateRequest:FireServer()
	end
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
	CompanyEventState.changed:Connect(function()
		render()
	end)
	-- «Флеш-распродажа» началась или кончилась — цены декора и стилей другие
	ReplicatedStorage:GetAttributeChangedSignal("DailyEventActive"):Connect(function()
		render()
	end)
	ConsoleClient.changed:Connect(function()
		if tab == "console" then
			render()
		end
	end)
	-- Remotes стилей ждём в своём потоке: окно не должно зависнуть, если сервис не поднялся
	task.spawn(function()
		local remotes = require(Shared.StyleRemotes)
		styleRemotes = remotes
		remotes.StyleState.OnClientEvent:Connect(function(newState: any)
			if
				type(newState) ~= "table"
				or type(newState.owned) ~= "table"
				or type(newState.selected) ~= "string"
			then
				return
			end
			styleState = { owned = newState.owned, selected = newState.selected }
			if tab == "style" then
				render()
			end
		end)
		remotes.FinishState.OnClientEvent:Connect(function(newState: any)
			if
				type(newState) ~= "table"
				or type(newState.owned) ~= "table"
				or type(newState.selected) ~= "string"
			then
				return
			end
			finishState = { owned = newState.owned, selected = newState.selected }
			if tab == "finish" then
				render()
			end
		end)
		remotes.StyleStateRequest:FireServer()
		remotes.FinishStateRequest:FireServer()
	end)
	-- Деньги поменялись — перекрасить кнопки цены
	ClientState.changed:Connect(function()
		render()
	end)
end

return StudioWindow
