--!strict
-- Окно «Исследования» (шаг 3.4): ОИ игрока и три ветки дерева.
-- Клиент только показывает и просит сервер; проверки ОИ и зависимостей — на сервере.
-- Исследование идёт таймером (Config/Research.TIMING): сверху — активное с полосой и временем,
-- «⚡ Ускорить» (выбор товаров Products.research за Robux) и «Отменить» (полный возврат).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Research = require(ReplicatedStorage.Shared.Config.Research)
local RebirthPerks = require(ReplicatedStorage.Shared.Config.RebirthPerks)
local ResearchRemotes = require(ReplicatedStorage.Shared.ResearchRemotes)
local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local Products = require(ReplicatedStorage.Shared.Config.Products)
local UnlockRules = require(ReplicatedStorage.Shared.UnlockRules)
local ClientState = require(script.Parent.Parent.ClientState)
local RobuxPrice = require(script.Parent.Parent.RobuxPrice)
local Ui = require(script.Parent.Parent.Ui)
local ArtIcon = require(script.Parent.Parent.ArtIcon)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local SoundController = require(script.Parent.SoundController)

local MENU_SLOT = 1
local CARD_HEIGHT = 112
-- Плашка активного исследования над колонками
local ACTIVE_HEIGHT = 58
local CANCEL_CONFIRM_SECONDS = 4
local TIMER_STEP = 0.5

local ResearchWindow = {}

local gui: ScreenGui? = nil
-- Последнее состояние с сервера
local points = 0
local owned: { [string]: boolean } = {}
-- Скидка звёзд студии (ветка «Лаборатория», Config/RebirthPerks); цену проверяет сервер
local discount = 0
-- Сокращение времени той же ветки (RebirthPerks.researchTime)
local timeReduction = 0
-- Активное исследование (Research.Active) и кредиты ускорений за Robux
local active: Research.Active? = nil
local creditSeconds = 0
local creditSkips = 0
local cancelAskedAt = 0
local pickerOpen = false
-- Обновляет время и полосу без перерисовки окна (ставит render)
local updateTimer: (() -> ())? = nil
-- Позиции прокрутки колонок, чтобы перерисовка после покупки не сбрасывала их
local scrollPositions: { [string]: Vector2 } = {}

local render: () -> ()

local function nodeText(node: Research.Node): (string, string)
	local key = "research_" .. node.id
	return ClientState.localText(key, node.name, node.nameEn),
		ClientState.localText(key .. "_desc", node.description, node.descriptionEn)
end

-- Имя того, что исследуется: узел дерева или «Открытие: Хоррор» (жанр/тема за $)
-- Название без приставки: узел дерева, жанр или тема
function ResearchWindow.itemName(kind: any, id: any): string
	if kind == "node" then
		local node = Research.byId[id]
		return if node then (nodeText(node)) else tostring(id)
	end
	local item = if kind == "genre"
		then (Genres :: any)[id]
		elseif kind == "topic" then (Topics :: any)[id]
		else nil
	return if item then ClientState.localName(item) else tostring(id)
end

function ResearchWindow.activeName(kind: any, id: any): string
	local name = ResearchWindow.itemName(kind, id)
	return if kind == "node" then name else ClientState.t("rtime_unlock_name", { name = name })
end

-- Сколько секунд осталось (по часам сервера)
local function secondsLeft(endsAt: number): number
	return math.max(endsAt - workspace:GetServerTimeNow(), 0)
end

local function promptProduct(productId: number)
	if productId ~= 0 then
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
	end
end

local function requiredNames(node: Research.Node): string
	local names = {}
	for _, id in node.requires do
		local req = Research.byId[id]
		if req and not owned[id] then
			table.insert(names, (nodeText(req)))
		end
	end
	return table.concat(names, ", ")
end

-- Узел жанра, условия которого ещё не выполнены (shared/UnlockRules): причины, иначе nil.
-- Уже открытый жанр (куплен) узел не блокирует — как на сервере
local function genreLockReason(node: Research.Node): string?
	local genreId = node.effect.unlockGenre
	local data = ClientState.data
	local genre = genreId and (Genres :: any)[genreId]
	if owned[node.id] or not genre or not data or (data.unlockedGenres and data.unlockedGenres[genreId]) then
		return nil
	end
	local reasons = UnlockRules.reasons(ClientState.lang, genre, data)
	return if reasons ~= "" then reasons else nil
end

local function buildCard(parent: Instance, node: Research.Node, order: number)
	local isOwned = owned[node.id] == true
	local current = active
	local isActive = current ~= nil and current.kind == "node" and current.id == node.id
	local lockReason = genreLockReason(node)
	local available = not isOwned
		and not isActive
		and Research.requirementsMet(node, owned)
		and lockReason == nil
	local cost = RebirthPerks.researchCost(node.cost, discount)
	local busy = current ~= nil
	local affordable = available and points >= cost and not busy

	local card = Instance.new("Frame")
	card.Name = node.id
	card.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
	card.Size = UDim2.new(1, -8, 0, CARD_HEIGHT)
	card.LayoutOrder = order
	Ui.corner(card, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = if isOwned
		then Ui.colors.good
		elseif isActive then Ui.colors.money
		elseif affordable then Ui.colors.primary
		else Ui.colors.stroke
	stroke.Parent = card

	local name, description = nodeText(node)
	local genreId = node.effect.unlockGenre
	local data = ClientState.data
	if not isOwned and genreId and data and data.unlockedGenres and data.unlockedGenres[genreId] then
		description ..= " " .. ClientState.t("research_genre_owned")
	end
	-- Сколько будет идти (с перком «Лаборатория»)
	if not isOwned then
		description ..= " " .. ClientState.t("rtime_duration", {
			time = Research.formatTime(Research.durationSeconds(node.minutes, timeReduction)),
		})
	end

	local title = Ui.label(
		card,
		name,
		24,
		Ui.titleFont,
		if available or isOwned or isActive then Ui.colors.text else Ui.colors.muted
	)
	title.Position = UDim2.fromOffset(10, 6)
	title.Size = UDim2.new(1, -90, 0, 24)
	-- Узел открывает жанр: иконка жанра (V21) перед названием; 0 — как раньше
	if genreId then
		ArtIcon.prefix(title, "", Images.genres[genreId] or 0, 22)
	end

	local costLabel =
		Ui.label(card, ClientState.t("research_cost", { cost = cost }), 20, nil, Ui.colors.money)
	costLabel.Position = UDim2.new(1, -84, 0, 8)
	costLabel.Size = UDim2.fromOffset(74, 20)
	costLabel.TextXAlignment = Enum.TextXAlignment.Right

	local desc = Ui.label(card, description, 34, Enum.Font.GothamMedium, Ui.colors.muted)
	desc.Position = UDim2.fromOffset(10, 32)
	desc.Size = UDim2.new(1, -20, 0, 34)
	desc.TextWrapped = true

	local bottom = UDim2.new(1, -20, 0, 34)
	local bottomPos = UDim2.new(0, 10, 1, -40)
	if isOwned then
		local status = Ui.label(card, ClientState.t("research_owned"), 26, Ui.titleFont, Ui.colors.good)
		status.Size = bottom
		status.Position = bottomPos
	elseif isActive then
		-- Идёт сейчас: время обновляет плашка сверху, здесь — только пометка
		local status = Ui.label(card, ClientState.t("rtime_in_progress"), 26, Ui.titleFont, Ui.colors.money)
		status.Size = bottom
		status.Position = bottomPos
	elseif lockReason and Research.requirementsMet(node, owned) then
		-- Ранние этапы: жанр откроется по прогрессу, ОИ не помогут
		local status = Ui.label(card, lockReason, 26, nil, Ui.colors.muted)
		status.Size = bottom
		status.Position = bottomPos
		status.TextWrapped = true
	elseif not available then
		local status = Ui.label(
			card,
			ClientState.t("research_requires", { names = requiredNames(node) }),
			26,
			nil,
			Ui.colors.muted
		)
		status.Size = bottom
		status.Position = bottomPos
	else
		-- Лаборатория занята другим исследованием: одно за раз
		local text = if busy
			then ClientState.t("rtime_busy_short")
			elseif affordable then ClientState.t("research_buy", { cost = cost })
			else ClientState.t("research_need", { cost = cost })
		local button = Ui.button(
			card,
			text,
			if affordable then Ui.colors.primary else Ui.colors.locked,
			function()
				if owned[node.id] or points < cost or active ~= nil then
					return
				end
				ResearchRemotes.BuyResearch:FireServer(node.id)
				SoundController.play("research_start")
			end
		)
		button.Size = bottom
		button.Position = bottomPos
		if not affordable then
			button.TextColor3 = Ui.colors.muted
		end
	end

	card.Parent = parent
end

local function buildColumn(parent: Instance, branch: Research.Branch, order: number)
	local column = Instance.new("Frame")
	column.Name = branch
	column.BackgroundTransparency = 1
	column.Size = UDim2.new(1 / 3, -8, 1, 0)
	column.LayoutOrder = order

	local header = Ui.label(column, ClientState.t("research_branch_" .. branch), 28, Ui.titleFont)
	header.TextXAlignment = Enum.TextXAlignment.Center

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 34)
	list.Size = UDim2.new(1, 0, 1, -34)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	Ui.list(list, 8)
	list.Parent = column

	for i, node in Research.branchNodes(branch) do
		buildCard(list, node, i)
	end
	column.Parent = parent

	-- Восстанавливаем после пересчёта AutomaticCanvasSize (сразу холст ещё нулевой и позиция
	-- обрезалась до 0), а слушатель вешаем после восстановления — иначе он затирал сохранённое
	task.defer(function()
		if not list.Parent then
			return
		end
		local saved = scrollPositions[branch]
		if saved then
			list.CanvasPosition = saved
		end
		list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			scrollPositions[branch] = list.CanvasPosition
		end)
	end)
end

-- Плашка активного исследования: имя, время, полоса, «⚡ Ускорить» и «Отменить» (второй клик)
local function buildActivePanel(window: Frame, current: Research.Active)
	local panel = Instance.new("Frame")
	panel.Name = "Active"
	panel.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
	panel.Position = UDim2.fromOffset(16, 76)
	panel.Size = UDim2.new(1, -32, 0, ACTIVE_HEIGHT)
	Ui.corner(panel, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.money
	stroke.Parent = panel
	panel.Parent = window

	local name = Ui.label(
		panel,
		"🔬 " .. ResearchWindow.activeName(current.kind, current.id),
		24,
		Ui.titleFontFor(ClientState.lang)
	)
	name.Position = UDim2.fromOffset(10, 4)
	name.Size = UDim2.new(1, -460, 0, 24)

	local timeLabel = Ui.label(panel, "", 22, Ui.titleFont, Ui.colors.money)
	timeLabel.Position = UDim2.new(1, -440, 0, 5)
	timeLabel.Size = UDim2.fromOffset(120, 22)
	timeLabel.TextXAlignment = Enum.TextXAlignment.Right

	local track = Instance.new("Frame")
	track.BackgroundColor3 = Ui.colors.locked
	track.Position = UDim2.fromOffset(10, 36)
	track.Size = UDim2.new(1, -330, 0, 14)
	Ui.corner(track, 7)
	track.Parent = panel
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Ui.colors.money
	fill.Size = UDim2.fromScale(0, 1)
	Ui.corner(fill, 7)
	fill.Parent = track

	local speed = Ui.button(panel, ClientState.t("rtime_speedup"), Ui.colors.good, function()
		pickerOpen = true
		render()
	end)
	speed.Position = UDim2.new(1, -308, 0.5, -22)
	speed.Size = UDim2.fromOffset(160, 44)

	local asking = os.clock() - cancelAskedAt < CANCEL_CONFIRM_SECONDS
	local cancel = Ui.button(
		panel,
		if asking then ClientState.t("rtime_cancel_ask") else ClientState.t("rtime_cancel"),
		if asking then Ui.colors.bad else Ui.colors.locked,
		function()
			if os.clock() - cancelAskedAt < CANCEL_CONFIRM_SECONDS then
				cancelAskedAt = 0
				ResearchRemotes.CancelResearch:FireServer()
			else
				cancelAskedAt = os.clock()
				render()
			end
		end
	)
	cancel.Position = UDim2.new(1, -140, 0.5, -22)
	cancel.Size = UDim2.fromOffset(130, 44)

	updateTimer = function()
		local total = math.max(current.endsAt - current.startedAt, 1)
		local left = secondsLeft(current.endsAt)
		timeLabel.Text = if left > 0
			then ClientState.t("rtime_left", { time = Research.formatTime(left) })
			else ClientState.t("rtime_almost")
		fill.Size = UDim2.fromScale(math.clamp(1 - left / total, 0, 1), 1)
		-- Второй клик «Отменить» не пришёл вовремя — кнопка снова обычная
		if asking and os.clock() - cancelAskedAt >= CANCEL_CONFIRM_SECONDS then
			asking = false
			cancel.Text = ClientState.t("rtime_cancel")
			cancel.BackgroundColor3 = Ui.colors.locked
		end
	end
	updateTimer()
end

-- Выбор ускорения за Robux (Products.research). Цены — только для показа, решает владелец
local function buildPicker(window: Frame, current: Research.Active)
	local shade = Instance.new("TextButton")
	shade.Name = "PickerShade"
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = 20
	Ui.corner(shade)
	shade.Activated:Connect(function()
		pickerOpen = false
		render()
	end)
	shade.Parent = window

	local left = secondsLeft(current.endsAt)
	local shown = {}
	for _, product in Products.research do
		-- Короткий остаток: «Завершить сейчас» (самый дорогой) не предлагаем, хватит −5 мин
		if product.skip and left <= Research.TIMING.skipHideSeconds then
			continue
		end
		table.insert(shown, product)
	end

	local rowHeight = 56
	local box = Instance.new("Frame")
	box.Name = "Picker"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(480, 70 + #shown * (rowHeight + 8))
	box.BackgroundColor3 = Ui.colors.panel
	box.ZIndex = 21
	Ui.corner(box)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.good
	stroke.Parent = box
	box.Parent = window

	local title = Ui.label(box, ClientState.t("rtime_pick_title"), 30, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(14, 12)
	title.Size = UDim2.new(1, -70, 0, 30)

	local close = Ui.button(box, "×", Ui.colors.locked, function()
		pickerOpen = false
		render()
	end)
	Ui.headerClose(close)

	for i, product in shown do
		local y = 58 + (i - 1) * (rowHeight + 8)
		local label = Ui.label(
			box,
			ClientState.t("rtime_product_" .. product.id),
			30,
			Ui.titleFontFor(ClientState.lang)
		)
		label.Position = UDim2.fromOffset(16, y + 13)
		label.Size = UDim2.new(1, -200, 0, 30)
		local soon = product.productId == 0
		local buy = Ui.button(
			box,
			if soon
				then ClientState.t("shop_soon")
				else ClientState.t(
					"shop_robux",
					{ price = RobuxPrice.of(product.productId, product.robuxPrice) }
				),
			if soon then Ui.colors.locked else Ui.colors.good,
			function()
				promptProduct(product.productId)
			end
		)
		buy.Position = UDim2.new(1, -176, 0, y)
		buy.Size = UDim2.fromOffset(160, rowHeight)
	end
	for _, child in box:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex = 22
		end
	end
end

render = function()
	local screen = gui
	if not screen then
		return
	end
	local old = screen:FindFirstChild("Window")
	if old then
		old:Destroy()
	end

	local window = Ui.window(screen, "Window", Vector2.new(900, 640))

	local title = Ui.label(window, ClientState.t("research_title"), 36, Ui.titleFont)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(0.5, -16, 0, 36)

	local pointsLabel = Ui.label(
		window,
		ClientState.t("research_points", { points = points }),
		30,
		Ui.titleFont,
		Ui.colors.money
	)
	pointsLabel.Position = UDim2.new(0.5, 0, 0, 13)
	pointsLabel.Size = UDim2.new(0.5, -72, 0, 30)
	pointsLabel.TextXAlignment = Enum.TextXAlignment.Right

	local close = Ui.button(window, "×", Ui.colors.locked, function()
		ResearchWindow.close()
	end)
	Ui.headerClose(close)

	local hint = Ui.label(window, ClientState.t("research_hint"), 18, Enum.Font.GothamMedium, Ui.colors.muted)
	hint.Position = UDim2.fromOffset(16, 50)
	hint.Size = UDim2.new(1, -32, 0, 18)
	-- Кредит ускорений за Robux (купили без активного исследования): применится к следующему
	if active == nil and (creditSkips > 0 or creditSeconds > 0) then
		hint.Text = if creditSkips > 0
			then ClientState.t("rtime_credit_skip")
			else ClientState.t("rtime_credit", { time = Research.formatTime(creditSeconds) })
		hint.TextColor3 = Ui.colors.money
	end

	local columnsTop = 78
	updateTimer = nil
	local current = active
	if current then
		columnsTop += ACTIVE_HEIGHT + 6
		buildActivePanel(window, current)
	end

	local columns = Instance.new("Frame")
	columns.BackgroundTransparency = 1
	columns.Position = UDim2.fromOffset(16, columnsTop)
	columns.Size = UDim2.new(1, -24, 1, -(columnsTop + 12))
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = columns
	columns.Parent = window

	for i, branch in Research.BRANCHES do
		buildColumn(columns, branch, i)
	end
	if current and pickerOpen then
		buildPicker(window, current)
	end
end

function ResearchWindow.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "ResearchWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened(ResearchWindow.close) -- окно меню: закрывает другое открытое окно меню
	ResearchRemotes.RequestResearch:FireServer()
	render()
end

function ResearchWindow.close()
	if gui then
		gui:Destroy()
		gui = nil
		pickerOpen = false
		updateTimer = nil
		Ui.windowClosed()
	end
end

function ResearchWindow.start()
	ResearchRemotes.ResearchChanged.OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then
			return
		end
		points = if type(state.points) == "number" then state.points else 0
		owned = if type(state.owned) == "table" then state.owned else {}
		discount = if type(state.discount) == "number" then state.discount else 0
		timeReduction = if type(state.timeReduction) == "number" then state.timeReduction else 0
		local a = state.active
		active = if type(a) == "table"
				and type(a.endsAt) == "number"
				and type(a.startedAt) == "number"
			then a :: Research.Active
			else nil
		creditSeconds = if type(state.creditSeconds) == "number" then state.creditSeconds else 0
		creditSkips = if type(state.creditSkips) == "number" then state.creditSkips else 0
		if not active then
			pickerOpen = false
		end
		render()
	end)

	-- Время и полоса активного исследования — без перерисовки окна
	task.spawn(function()
		while true do
			task.wait(TIMER_STEP)
			local update = updateTimer
			if gui and update then
				update()
			end
		end
	end)

	-- Профиль на сервере грузится асинхронно: просим состояние, когда пришли первые данные
	local requested = false
	local function requestOnce()
		if not requested and ClientState.data then
			requested = true
			ResearchRemotes.RequestResearch:FireServer()
		end
	end
	requestOnce()
	-- Из ClientState окно показывает только открытые жанры (пометка «жанр уже открыт») и язык:
	-- деньги меняются каждые несколько секунд, лишняя перерисовка сбрасывала колонки
	local function stateKey(): string
		local data = ClientState.data
		local genres = {}
		if data and data.unlockedGenres then
			for id, open in data.unlockedGenres do
				if open then
					table.insert(genres, id)
				end
			end
		end
		table.sort(genres)
		-- Причины замков узлов жанров: перерисовать, когда условие продвинулось
		local locks = {}
		for _, node in Research.list do
			table.insert(locks, genreLockReason(node) or "")
		end
		return ClientState.lang .. "|" .. table.concat(genres, ",") .. "|" .. table.concat(locks, ",")
	end
	local lastKey = stateKey()
	ClientState.changed:Connect(function()
		requestOnce()
		local key = stateKey()
		if key ~= lastKey then
			lastKey = key
			render()
		end
	end)

	Ui.menuButton(MENU_SLOT, "🔬", function()
		if gui then
			ResearchWindow.close()
		else
			ResearchWindow.open()
		end
	end, "menu_research")
end

return ResearchWindow
