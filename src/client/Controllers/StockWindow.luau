--!strict
-- Окно биржи (Config/Stocks, StockService) — кнопка 📈 в меню (слот 19). Слева — компании на бирже
-- (цена, изменение за сутки), справа — свечной график выбранной компании, сделка (купить/продать)
-- и портфель; вкладка IPO — условия выхода своей студии на биржу.
-- Свечи рисуются Frame-ами; оформление в стиле Forex — Астра V27 (#26), пока цвета по умолчанию.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Stocks = require(ReplicatedStorage.Shared.Config.Stocks)
local StockRemotes = require(ReplicatedStorage.Shared.StockRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local ArtIcon = require(script.Parent.Parent.ArtIcon)
local ClientState = require(script.Parent.Parent.ClientState)
local DepthToast = require(script.Parent.Parent.DepthToast)
local Ui = require(script.Parent.Parent.Ui)

local MENU_SLOT = 19
local REFRESH_SECONDS = 20
local ROW_HEIGHT = 46
-- Показываем кнопку биржи с офиса (studioLevel 2) или если есть акции/своя компания
local MENU_MIN_LEVEL = 2

local COLORS = {
	up = Color3.fromRGB(38, 194, 129),
	down = Color3.fromRGB(239, 83, 80),
	grid = Color3.fromRGB(40, 44, 62),
	chart = Color3.fromRGB(18, 20, 30),
	row = Color3.fromRGB(36, 38, 56),
	rowSelected = Color3.fromRGB(46, 62, 96),
	priceLine = Color3.fromRGB(255, 201, 60),
}

local player = Players.LocalPlayer
local StockWindow = {}

local gui: ScreenGui? = nil
local state: any = nil
local selected: number? = nil
local view = "market" -- "market" | "ipo"
local amount = 10
local refs: any = {}

local function pct(value: number): string
	local sign = if value > 0 then "+" else ""
	return string.format("%s%.1f%%", sign, value)
end

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function findCompany(id: number?): any
	if not state or type(state.companies) ~= "table" or not id then
		return nil
	end
	for _, c in state.companies do
		if c.id == id then
			return c
		end
	end
	return nil
end

local function holdingOf(id: number?): any
	if not state or type(state.portfolio) ~= "table" or not id then
		return nil
	end
	for _, h in state.portfolio do
		if h.id == id then
			return h
		end
	end
	return nil
end

local function request()
	StockRemotes.StockRequest:FireServer(selected)
end

local function drawCandles(frame: Frame, candles: any)
	clear(frame)
	if type(candles) ~= "table" or #candles == 0 then
		local empty = Ui.label(frame, ClientState.t("stock_no_chart"), 28, nil, Ui.colors.muted)
		empty.TextXAlignment = Enum.TextXAlignment.Center
		empty.Position = UDim2.new(0, 0, 0.5, -14)
		empty.Size = UDim2.new(1, 0, 0, 28)
		return
	end
	local low, high = math.huge, -math.huge
	for _, c in candles do
		low = math.min(low, c.l)
		high = math.max(high, c.h)
	end
	if high <= low then
		high = low + 1
	end
	local pad = (high - low) * 0.08
	low -= pad
	high += pad
	local function y(price: number): number
		return 1 - (price - low) / (high - low)
	end
	-- Сетка и подписи цены
	for i = 0, 4 do
		local level = low + (high - low) * i / 4
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = COLORS.grid
		line.Position = UDim2.new(0, 0, y(level), 0)
		line.Size = UDim2.new(1, -64, 0, 1)
		line.Parent = frame
		local tag =
			Ui.label(frame, Texts.money(math.floor(level + 0.5)), 16, Enum.Font.GothamMedium, Ui.colors.muted)
		tag.TextXAlignment = Enum.TextXAlignment.Right
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.new(1, -2, y(level), 0)
		tag.Size = UDim2.fromOffset(60, 16)
	end
	local n = #candles
	local plot = Instance.new("Frame")
	plot.BackgroundTransparency = 1
	plot.Size = UDim2.new(1, -66, 1, 0)
	plot.Parent = frame
	for i, c in candles do
		local color = if c.c >= c.o then COLORS.up else COLORS.down
		local xCenter = (i - 0.5) / n
		local wick = Instance.new("Frame")
		wick.BorderSizePixel = 0
		wick.BackgroundColor3 = color
		wick.AnchorPoint = Vector2.new(0.5, 0)
		wick.Position = UDim2.new(xCenter, 0, y(c.h), 0)
		wick.Size = UDim2.new(0, 2, y(c.l) - y(c.h), 0)
		wick.Parent = plot
		local top = math.max(c.o, c.c)
		local bottom = math.min(c.o, c.c)
		local body = Instance.new("Frame")
		body.BorderSizePixel = 0
		body.BackgroundColor3 = color
		body.AnchorPoint = Vector2.new(0.5, 0)
		body.Position = UDim2.new(xCenter, 0, y(top), 0)
		body.Size = UDim2.new(0.7 / n, 0, math.max(y(bottom) - y(top), 0.004), 0)
		body.Parent = plot
	end
	-- Линия текущей цены
	local last = candles[n].c
	local line = Instance.new("Frame")
	line.BorderSizePixel = 0
	line.BackgroundColor3 = COLORS.priceLine
	line.BackgroundTransparency = 0.3
	line.Position = UDim2.new(0, 0, y(last), 0)
	line.Size = UDim2.new(1, -64, 0, 1)
	line.Parent = frame
end

local function renderList()
	local list = refs.list
	if not list then
		return
	end
	clear(list)
	if not state then
		Ui.label(list, ClientState.t("quests_loading"), 28, nil, Ui.colors.muted)
		return
	end
	if #state.companies == 0 then
		local empty =
			Ui.label(list, ClientState.t("stock_empty"), 60, Enum.Font.GothamMedium, Ui.colors.muted)
		empty.TextWrapped = true
		return
	end
	for i, c in state.companies do
		local row = Instance.new("TextButton")
		row.AutoButtonColor = true
		row.Text = ""
		row.BackgroundColor3 = if c.id == selected then COLORS.rowSelected else COLORS.row
		row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		row.LayoutOrder = i
		Ui.corner(row, 8)
		local own = c.id == state.you
		local name = Ui.label(row, (if own then "⭐ " else "") .. tostring(c.name), 20, nil, Ui.colors.text)
		name.Position = UDim2.fromOffset(8, 4)
		name.Size = UDim2.new(0.62, -8, 0, 20)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local owner = Ui.label(row, tostring(c.owner), 16, Enum.Font.GothamMedium, Ui.colors.muted)
		owner.Position = UDim2.fromOffset(8, 25)
		owner.Size = UDim2.new(0.62, -8, 0, 16)
		owner.TextTruncate = Enum.TextTruncate.AtEnd
		local price = Ui.label(row, Texts.money(c.price), 20, nil, Ui.colors.money)
		price.TextXAlignment = Enum.TextXAlignment.Right
		price.Position = UDim2.new(0.62, 0, 0, 4)
		price.Size = UDim2.new(0.38, -8, 0, 20)
		local change = Ui.label(
			row,
			(if c.change >= 0 then "▲ " else "▼ ") .. pct(c.change),
			16,
			Enum.Font.GothamBold,
			if c.change >= 0 then COLORS.up else COLORS.down
		)
		change.TextXAlignment = Enum.TextXAlignment.Right
		change.Position = UDim2.new(0.62, 0, 0, 25)
		change.Size = UDim2.new(0.38, -8, 0, 16)
		row.Activated:Connect(function()
			selected = c.id
			view = "market"
			StockWindow.render()
			request()
		end)
		row.Parent = list
	end
end

local function renderMarket(right: Frame)
	local company = findCompany(selected)
	if not company then
		local hint = Ui.label(right, ClientState.t("stock_pick"), 28, Enum.Font.GothamMedium, Ui.colors.muted)
		hint.TextXAlignment = Enum.TextXAlignment.Center
		hint.Position = UDim2.new(0, 0, 0.4, 0)
		hint.Size = UDim2.new(1, 0, 0, 28)
		return
	end
	local header = Ui.label(right, tostring(company.name), 30, Ui.titleFontFor(ClientState.lang))
	header.Size = UDim2.new(0.6, 0, 0, 30)
	header.TextTruncate = Enum.TextTruncate.AtEnd
	local price = Ui.label(
		right,
		Texts.money(company.price) .. "  " .. pct(company.change),
		30,
		nil,
		if company.change >= 0 then COLORS.up else COLORS.down
	)
	price.TextXAlignment = Enum.TextXAlignment.Right
	price.Position = UDim2.new(0.6, 0, 0, 0)
	price.Size = UDim2.new(0.4, 0, 0, 30)
	local info = Ui.label(
		right,
		ClientState.t("stock_info", {
			income = Texts.money(company.income),
			avg = company.avg,
			dividend = Texts.money(math.floor(company.dividend * 1000 + 0.5)),
		}) .. (if company.online then "" else "  · " .. ClientState.t("stock_offline")),
		18,
		Enum.Font.GothamMedium,
		Ui.colors.muted
	)
	info.Position = UDim2.fromOffset(0, 32)
	info.Size = UDim2.new(1, 0, 0, 18)
	info.TextTruncate = Enum.TextTruncate.AtEnd

	local chart = Instance.new("Frame")
	chart.BackgroundColor3 = COLORS.chart
	chart.Position = UDim2.fromOffset(0, 56)
	chart.Size = UDim2.new(1, 0, 0.5, -40)
	chart.ClipsDescendants = true
	Ui.corner(chart, 8)
	chart.Parent = right
	local inner = Instance.new("Frame")
	inner.BackgroundTransparency = 1
	inner.Position = UDim2.fromOffset(6, 8)
	inner.Size = UDim2.new(1, -12, 1, -16)
	inner.Parent = chart
	drawCandles(inner, if state.selected == company.id then state.candles else nil)

	-- Сделка
	local trade = Instance.new("Frame")
	trade.BackgroundTransparency = 1
	trade.Position = UDim2.new(0, 0, 0.5, 22)
	trade.Size = UDim2.new(1, 0, 0, 96)
	trade.Parent = right
	local own = company.id == state.you
	local holding = holdingOf(company.id)
	local presets = { 1, 10, 100, 1000, 10000 }
	local presetRow = Instance.new("Frame")
	presetRow.BackgroundTransparency = 1
	presetRow.Size = UDim2.new(1, 0, 0, 34)
	presetRow.Parent = trade
	local presetLayout = Instance.new("UIListLayout")
	presetLayout.FillDirection = Enum.FillDirection.Horizontal
	presetLayout.Padding = UDim.new(0, 6)
	presetLayout.Parent = presetRow
	for _, n in presets do
		local b = Ui.button(
			presetRow,
			tostring(n),
			if n == amount then Ui.colors.primary else Ui.colors.locked,
			function()
				amount = n
				StockWindow.render()
			end
		)
		b.Size = UDim2.new(1 / #presets, -6, 1, 0)
	end
	local cost = Stocks.buyCost(company.price, amount)
	local payout = Stocks.sellPayout(company.price, math.min(amount, if holding then holding.shares else 0))
	local actions = Instance.new("Frame")
	actions.BackgroundTransparency = 1
	actions.Position = UDim2.fromOffset(0, 42)
	actions.Size = UDim2.new(1, 0, 0, 50)
	actions.Parent = trade
	local cash = if ClientState.data then ClientState.data.cash else 0
	local buy = Ui.button(
		actions,
		ClientState.t("stock_buy", { shares = amount, money = Texts.money(cost) }),
		if own or cash < cost then Ui.colors.locked else COLORS.up,
		function()
			if not own then
				StockRemotes.StockBuy:FireServer(company.id, amount)
			end
		end
	)
	buy.Size = UDim2.new(0.5, -4, 1, 0)
	local sell = Ui.button(
		actions,
		ClientState.t("stock_sell", { money = Texts.money(payout) }),
		if holding then COLORS.down else Ui.colors.locked,
		function()
			if holding then
				StockRemotes.StockSell:FireServer(company.id, amount)
			end
		end
	)
	sell.Position = UDim2.new(0.5, 4, 0, 0)
	sell.Size = UDim2.new(0.5, -4, 1, 0)
	if own then
		local note = Ui.label(right, ClientState.t("stock_own"), 18, Enum.Font.GothamMedium, Ui.colors.muted)
		note.Position = UDim2.new(0, 0, 0.5, 120)
		note.Size = UDim2.new(1, 0, 0, 18)
	end

	-- Портфель
	local portfolio = Instance.new("ScrollingFrame")
	portfolio.BackgroundTransparency = 1
	portfolio.BorderSizePixel = 0
	portfolio.Position = UDim2.new(0, 0, 0.5, 142)
	portfolio.Size = UDim2.new(1, 0, 0.5, -142)
	portfolio.CanvasSize = UDim2.new()
	portfolio.AutomaticCanvasSize = Enum.AutomaticSize.Y
	portfolio.ScrollBarThickness = 4
	Ui.list(portfolio, 4)
	portfolio.Parent = right
	local title = Ui.label(portfolio, ClientState.t("stock_portfolio"), 22, nil, Ui.colors.text)
	title.LayoutOrder = 0
	if #state.portfolio == 0 then
		local empty = Ui.label(
			portfolio,
			ClientState.t("stock_portfolio_empty"),
			18,
			Enum.Font.GothamMedium,
			Ui.colors.muted
		)
		empty.LayoutOrder = 1
	end
	for i, h in state.portfolio do
		local profit = h.value - h.cost
		local line = Ui.label(
			portfolio,
			ClientState.t("stock_holding", {
				name = h.name,
				shares = h.shares,
				value = Texts.money(h.value),
				profit = (if profit >= 0 then "+" else "−") .. Texts.money(math.abs(profit)),
				dividend = Texts.money(math.floor(h.dividend)),
			}),
			20,
			Enum.Font.GothamMedium,
			if profit >= 0 then COLORS.up else COLORS.down
		)
		line.LayoutOrder = i
		line.TextTruncate = Enum.TextTruncate.AtEnd
	end
end

local function renderIpo(right: Frame)
	local ipo = state and state.ipo
	local layoutFrame = Instance.new("Frame")
	layoutFrame.BackgroundTransparency = 1
	layoutFrame.Size = UDim2.fromScale(1, 1)
	layoutFrame.Parent = right
	Ui.list(layoutFrame, 8)
	local title =
		Ui.label(layoutFrame, ClientState.t("stock_ipo_title"), 32, Ui.titleFontFor(ClientState.lang))
	title.LayoutOrder = 1
	ArtIcon.prefix(title, "🔔", Images.windows.ipo, 32)
	if not ipo then
		return
	end
	if ipo.listed then
		local done = Ui.label(
			layoutFrame,
			ClientState.t("stock_ipo_listed", { percent = math.floor(Stocks.ipo.incomeBonus * 100) }),
			60,
			Enum.Font.GothamMedium,
			COLORS.up
		)
		done.TextWrapped = true
		done.LayoutOrder = 2
		local warn = Ui.label(
			layoutFrame,
			ClientState.t("stock_bankrupt_rule", { minutes = math.floor(Stocks.bankruptAfterSeconds / 60) }),
			60,
			Enum.Font.GothamMedium,
			Ui.colors.muted
		)
		warn.TextWrapped = true
		warn.LayoutOrder = 3
		return
	end
	local intro = Ui.label(
		layoutFrame,
		ClientState.t("stock_ipo_intro", { percent = math.floor(Stocks.ipo.incomeBonus * 100) }),
		60,
		Enum.Font.GothamMedium,
		Ui.colors.muted
	)
	intro.TextWrapped = true
	intro.LayoutOrder = 2
	local rows = {
		{ ok = ipo.checks.level, text = ClientState.t("stock_ipo_level") },
		{ ok = ipo.checks.interior, text = ClientState.t("stock_ipo_interior") },
		{
			ok = ipo.checks.income,
			text = ClientState.t(
				"stock_ipo_income",
				{ have = Texts.money(ipo.income), need = Texts.money(ipo.needIncome) }
			),
		},
		{
			ok = ipo.checks.avg,
			text = ClientState.t(
				"stock_ipo_avg",
				{ have = ipo.avg, need = ipo.needAvg, games = ipo.games, needGames = ipo.needGames }
			),
		},
		{ ok = ipo.checks.cash, text = ClientState.t("stock_ipo_cash", { money = Texts.money(ipo.cost) }) },
	}
	for i, r in rows do
		local line = Ui.label(
			layoutFrame,
			(if r.ok then "✅ " else "⬜ ") .. r.text,
			24,
			Enum.Font.GothamMedium,
			if r.ok then COLORS.up else Ui.colors.text
		)
		line.LayoutOrder = 2 + i
		line.TextWrapped = true
	end
	local go = Ui.button(
		layoutFrame,
		ClientState.t("stock_ipo_go", { money = Texts.money(ipo.cost) }),
		if ipo.ready then Ui.colors.good else Ui.colors.locked,
		function()
			if ipo.ready then
				StockRemotes.StockIpo:FireServer()
			end
		end
	)
	go.Size = UDim2.new(1, 0, 0, 50)
	go.LayoutOrder = 20
end

function StockWindow.render()
	if not gui then
		return
	end
	renderList()
	local right = refs.right
	if not right then
		return
	end
	clear(right)
	if state and state.available == false then
		local off =
			Ui.label(right, ClientState.t("stock_unavailable"), 60, Enum.Font.GothamMedium, Ui.colors.muted)
		off.TextWrapped = true
		return
	end
	if view == "ipo" then
		renderIpo(right)
	else
		renderMarket(right)
	end
	if refs.ipoButton then
		refs.ipoButton.Text = if view == "ipo"
			then ClientState.t("stock_tab_market")
			else ClientState.t("stock_tab_ipo")
	end
end

function StockWindow.close()
	if gui then
		gui:Destroy()
		gui = nil
		refs = {}
		Ui.windowClosed()
	end
end

function StockWindow.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "StockWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened(StockWindow.close)

	local window = Ui.window(screen, "Window", Vector2.new(940, 640))
	local title = Ui.label(window, ClientState.t("stock_title"), 40, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -260, 0, 40)
	ArtIcon.prefix(title, "📈", Images.windows.stock, 40)
	local close = Ui.button(window, ClientState.t("create_close"), Ui.colors.bad, StockWindow.close)
	Ui.headerClose(close)
	local ipoButton = Ui.button(window, ClientState.t("stock_tab_ipo"), Ui.colors.primary, function()
		view = if view == "ipo" then "market" else "ipo"
		StockWindow.render()
	end)
	ipoButton.AnchorPoint = Vector2.new(1, 0)
	ipoButton.Position = UDim2.new(1, -(Ui.HEADER_BUTTON + Ui.HEADER_RIGHT + 8), 0, 10)
	ipoButton.Size = UDim2.fromOffset(170, 40)
	refs.ipoButton = ipoButton

	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(16, 60)
	list.Size = UDim2.new(0.34, -16, 1, -76)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 4
	Ui.list(list, 6)
	list.Parent = window
	refs.list = list

	local right = Instance.new("Frame")
	right.BackgroundTransparency = 1
	right.Position = UDim2.new(0.34, 8, 0, 60)
	right.Size = UDim2.new(0.66, -24, 1, -76)
	right.Parent = window
	refs.right = right

	StockWindow.render()
	request()
	task.spawn(function()
		while gui == screen do
			task.wait(REFRESH_SECONDS)
			if gui == screen then
				request()
			end
		end
	end)
end

function StockWindow.start()
	local menu = Ui.menuButton(MENU_SLOT, "📈", function()
		if gui then
			StockWindow.close()
		else
			StockWindow.open()
		end
	end, "menu_stock")
	local function updateMenu()
		local level = if ClientState.data then tonumber(ClientState.data.studioLevel) or 1 else 1
		menu.Visible = level >= MENU_MIN_LEVEL
			or player:GetAttribute("StockListed") == true
			or (state ~= nil and #state.portfolio > 0)
	end
	ClientState.changed:Connect(updateMenu)
	player:GetAttributeChangedSignal("StockListed"):Connect(updateMenu)
	updateMenu()

	StockRemotes.StockState.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if type(payload.message) == "string" then
			local params = payload.params or {}
			if type(params.money) == "number" then
				params.money = Texts.money(params.money)
			end
			local bad = string.find(payload.message, "err") ~= nil
				or string.find(payload.message, "bankrupt") ~= nil
			DepthToast.show(
				ClientState.t(payload.message, params),
				if bad then Ui.colors.bad else Ui.colors.good
			)
			return
		end
		state = payload
		if selected == nil and type(payload.companies) == "table" and payload.companies[1] then
			selected = payload.companies[1].id
			request()
		end
		updateMenu()
		StockWindow.render()
	end)
	-- IPO стал доступен — тост один раз за сессию
	local toasted = false
	player:GetAttributeChangedSignal("StockIpoReady"):Connect(function()
		if player:GetAttribute("StockIpoReady") == true and not toasted then
			toasted = true
			DepthToast.show(ClientState.t("stock_ipo_ready"), Ui.colors.good)
		end
	end)
	-- Предупреждение о банкротстве
	local warnedMinutes = 0
	player:GetAttributeChangedSignal("StockBankruptIn"):Connect(function()
		local left = tonumber(player:GetAttribute("StockBankruptIn"))
		local minutes = if left and left > 0 then math.ceil(left / 60) else 0
		if minutes > 0 and minutes ~= warnedMinutes then
			DepthToast.show(ClientState.t("stock_bankrupt_warn", { minutes = minutes }), Ui.colors.bad)
		end
		warnedMinutes = minutes
	end)
	ClientState.langChanged:Connect(StockWindow.render)
end

return StockWindow
