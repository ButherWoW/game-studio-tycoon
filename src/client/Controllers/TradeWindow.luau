--!strict
-- Обмен на клиенте (TradeService): выбор игрока, плашка входящего запроса и окно обмена.
-- Окно: сверху «Ты отдаёшь» / «<имя> отдаёт», снизу свои предметы (нажми — добавить,
-- нажми в своём предложении — убрать) и кнопки денег. Изменения уходят на сервер пачкой
-- через SEND_DELAY; сервер снимает подтверждения и запирает кнопку на lockSeconds.
-- Всё решает сервер: окно только рисует TradeState.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Friends = require(Shared.Config.Friends)
local Texts = require(Shared.Config.Texts)
local FriendRemotes = require(Shared.FriendRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local FriendsController = require(script.Parent.FriendsController)

local SEND_DELAY = 0.3
local TICK = 0.25
local CASH_STEPS = { 1_000, 10_000, 100_000, 1_000_000 }

type Item = { kind: string, id: string }

local player = Players.LocalPlayer

local TradeWindow = {}

local state: any = nil -- последний TradeState
local draftItems: { Item } = {}
local draftCash = 0
local dirty = false -- есть изменения, ещё не отправленные на сервер
local sendToken = 0
local lockEndsAt = 0

-- ===== Выбор игрока =====

local pickerGui: ScreenGui? = nil

function TradeWindow.closePicker()
	if pickerGui then
		pickerGui:Destroy()
		pickerGui = nil
		Ui.windowClosed()
	end
end

function TradeWindow.openPicker()
	TradeWindow.closePicker()
	local screen = Instance.new("ScreenGui")
	screen.Name = "TradePicker"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 12
	screen.Parent = player:WaitForChild("PlayerGui")
	pickerGui = screen
	Ui.windowOpened()

	local window = Ui.window(screen, "Window", Vector2.new(440, 440))
	local title = Ui.label(window, ClientState.t("trade_pick_title"), 36, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -76, 0, 36)
	local close = Ui.button(window, "×", Ui.colors.bad, TradeWindow.closePicker)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Size = UDim2.fromOffset(44, 44)
	local hint = Ui.label(window, ClientState.t("trade_hint"), 20, Enum.Font.GothamMedium, Ui.colors.muted)
	hint.Position = UDim2.fromOffset(16, 58)
	hint.Size = UDim2.new(1, -32, 0, 20)

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(16, 88)
	scroll.Size = UDim2.new(1, -32, 1, -100)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	Ui.list(scroll, 8)
	scroll.Parent = window

	local others = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(others, other)
		end
	end
	table.sort(others, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	if #others == 0 then
		local empty = Ui.label(scroll, ClientState.t("trade_pick_empty"), 26, nil, Ui.colors.muted)
		empty.Size = UDim2.new(1, -8, 0, 26)
	end
	for i, other in others do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
		row.Size = UDim2.new(1, -8, 0, 56)
		row.LayoutOrder = i
		Ui.corner(row, 10)
		local label = Ui.label(row, other.DisplayName, 26)
		label.Position = UDim2.fromOffset(12, 15)
		label.Size = UDim2.new(1, -170, 0, 26)
		local button = Ui.button(row, ClientState.t("trade_button"), Ui.colors.primary, function()
			FriendRemotes.TradeRequest:FireServer(other.UserId)
			TradeWindow.closePicker()
		end)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -8, 0.5, 0)
		button.Size = UDim2.fromOffset(150, 44)
		row.Parent = scroll
	end
end

-- ===== Входящий запрос =====

local requestGui: ScreenGui? = nil

local function closeRequest()
	if requestGui then
		requestGui:Destroy()
		requestGui = nil
	end
end

local function showRequest(fromName: string, userId: number)
	closeRequest()
	local screen = Instance.new("ScreenGui")
	screen.Name = "TradeRequest"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 30 -- над окнами: ответить можно из любого окна
	screen.Parent = player:WaitForChild("PlayerGui")
	requestGui = screen

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -150)
	frame.Size = UDim2.fromOffset(420, 116)
	frame.BackgroundColor3 = Ui.colors.panel
	Ui.corner(frame)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.primary
	stroke.Parent = frame
	local scale = Instance.new("UIScale")
	local camera = workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X else 1280
	scale.Scale = math.clamp(width * 0.94 / 420, 0.6, 1)
	scale.Parent = frame
	frame.Parent = screen

	local label = Ui.label(frame, ClientState.t("trade_request_in", { name = fromName }), 30)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Position = UDim2.fromOffset(12, 10)
	label.Size = UDim2.new(1, -24, 0, 30)
	local accept = Ui.button(frame, ClientState.t("trade_accept"), Ui.colors.good, function()
		FriendRemotes.TradeRespond:FireServer(userId, true)
		closeRequest()
	end)
	accept.Position = UDim2.fromOffset(12, 56)
	accept.Size = UDim2.new(0.5, -18, 0, 48)
	local decline = Ui.button(frame, ClientState.t("trade_decline"), Ui.colors.bad, function()
		FriendRemotes.TradeRespond:FireServer(userId, false)
		closeRequest()
	end)
	decline.AnchorPoint = Vector2.new(1, 0)
	decline.Position = UDim2.new(1, -12, 0, 56)
	decline.Size = UDim2.new(0.5, -18, 0, 48)

	task.delay(Friends.trade.requestSeconds, function()
		if requestGui == screen then
			closeRequest()
		end
	end)
end

-- ===== Окно обмена =====

local gui: ScreenGui? = nil
local refs: { [string]: any } = {}

local function sendDraft()
	sendToken += 1
	local token = sendToken
	dirty = true
	task.delay(SEND_DELAY, function()
		if token == sendToken and state and state.trade then
			FriendRemotes.TradeOffer:FireServer(draftItems, draftCash)
			dirty = false
		end
	end)
end

local function hasItem(list: { Item }, item: Item): number?
	for i, other in list do
		if other.kind == item.kind and other.id == item.id then
			return i
		end
	end
	return nil
end

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function grid(parent: Instance, cell: Vector2): UIGridLayout
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

local function scrollBox(parent: Instance, position: UDim2, size: UDim2): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundColor3 = Color3.fromRGB(40, 42, 60)
	scroll.BorderSizePixel = 0
	scroll.Position = position
	scroll.Size = size
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	Ui.corner(scroll, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.Parent = scroll
	scroll.Parent = parent
	return scroll
end

-- Подпись и цвет кнопки «Подтвердить»; ready — можно нажать
local function confirmLook(): (string, Color3, boolean)
	local trade = state and state.trade
	if not trade then
		return "", Ui.colors.locked, false
	end
	if trade.myConfirm then
		return ClientState.t("trade_confirmed"), Ui.colors.locked, false
	end
	local left = math.ceil(lockEndsAt - os.clock())
	if dirty or left > 0 then
		return ClientState.t("trade_wait", { sec = math.max(left, 1) }), Ui.colors.locked, false
	end
	return ClientState.t("trade_confirm"), Ui.colors.good, true
end

local function refreshConfirm()
	local button = refs.confirm :: TextButton?
	if button then
		local text, color = confirmLook()
		button.Text = text
		button.BackgroundColor3 = color
	end
end

local function renderOffers()
	local trade = state and state.trade
	if not trade or not gui then
		return
	end
	local mine = refs.mine :: ScrollingFrame
	local theirs = refs.theirs :: ScrollingFrame
	clear(mine)
	clear(theirs)
	for i, item in draftItems do
		local chip = Ui.button(
			mine,
			FriendsController.itemLabel(item.kind, item.id),
			Ui.colors.primary,
			function()
				local index = hasItem(draftItems, item)
				if index then
					table.remove(draftItems, index)
					sendDraft()
					TradeWindow.render()
				end
			end
		)
		chip.LayoutOrder = i
	end
	local their = if type(trade.theirs) == "table" then trade.theirs else { items = {}, cash = 0 }
	for i, item in their.items or {} do
		local chip = Ui.label(theirs, FriendsController.itemLabel(item.kind, item.id), 36)
		chip.BackgroundColor3 = Color3.fromRGB(60, 62, 86)
		chip.BackgroundTransparency = 0
		chip.TextXAlignment = Enum.TextXAlignment.Center
		Ui.corner(chip, 8)
		chip.LayoutOrder = i
	end
	refs.myCash.Text = ClientState.t("trade_cash", { money = Texts.money(draftCash) })
	refs.theirCash.Text = ClientState.t("trade_cash", { money = Texts.money(tonumber(their.cash) or 0) })
	refs.status.Text = if trade.theirConfirm
		then ClientState.t("trade_partner_ready", { name = tostring(trade.partnerName) })
		else ClientState.t("trade_partner_waiting", { name = tostring(trade.partnerName) })
	refs.status.TextColor3 = if trade.theirConfirm then Ui.colors.good else Ui.colors.muted
	refreshConfirm()
end

local function renderInventory()
	local inv = refs.inventory :: ScrollingFrame?
	if not inv or not state then
		return
	end
	local position = inv.CanvasPosition
	clear(inv)
	local list = if type(state.inventory) == "table" then state.inventory else {}
	if #list == 0 then
		local empty =
			Ui.label(inv, ClientState.t("trade_no_items"), 40, Enum.Font.GothamMedium, Ui.colors.muted)
		empty.TextWrapped = true
	end
	for i, item in list do
		local chosen = hasItem(draftItems, item) ~= nil
		local chip = Ui.button(
			inv,
			FriendsController.itemLabel(item.kind, item.id),
			if chosen then Ui.colors.locked else Color3.fromRGB(60, 62, 86),
			function()
				if hasItem(draftItems, item) or #draftItems >= Friends.trade.maxItems then
					return
				end
				table.insert(draftItems, { kind = item.kind, id = item.id })
				sendDraft()
				TradeWindow.render()
			end
		)
		chip.LayoutOrder = i
	end
	inv.CanvasPosition = position
end

function TradeWindow.render()
	renderOffers()
	renderInventory()
end

local function closeWindow()
	if gui then
		gui:Destroy()
		gui = nil
		refs = {}
		Ui.windowClosed()
	end
end

local function openWindow()
	if gui then
		return
	end
	TradeWindow.closePicker()
	local screen = Instance.new("ScreenGui")
	screen.Name = "TradeWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 12
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local trade = state.trade
	local window = Ui.window(screen, "Window", Vector2.new(700, 580))
	local title = Ui.label(
		window,
		ClientState.t("trade_title", { name = tostring(trade.partnerName) }),
		36,
		Ui.titleFontFor(ClientState.lang)
	)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 36)
	local close = Ui.button(window, "×", Ui.colors.bad, function()
		FriendRemotes.TradeCancel:FireServer()
	end)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 8)
	close.Size = UDim2.fromOffset(44, 44)

	-- Две колонки предложений
	for side, key in { mine = "trade_you_give", theirs = "trade_they_give" } do
		local x = if side == "mine" then 16 else 358
		local header = Ui.label(
			window,
			ClientState.t(key, { name = tostring(trade.partnerName) }),
			22,
			nil,
			Ui.colors.muted
		)
		header.Position = UDim2.fromOffset(x, 58)
		header.Size = UDim2.fromOffset(326, 22)
		local box = scrollBox(window, UDim2.fromOffset(x, 84), UDim2.fromOffset(326, 128))
		grid(box, Vector2.new(152, 36))
		refs[side] = box
		local cash = Ui.label(window, "", 24, nil, Ui.colors.money)
		cash.Position = UDim2.fromOffset(x, 216)
		cash.Size = UDim2.fromOffset(326, 24)
		refs[if side == "mine" then "myCash" else "theirCash"] = cash
	end

	local invTitle = Ui.label(window, ClientState.t("trade_your_items"), 22, nil, Ui.colors.muted)
	invTitle.Position = UDim2.fromOffset(16, 248)
	invTitle.Size = UDim2.new(1, -32, 0, 22)
	local inv = scrollBox(window, UDim2.fromOffset(16, 274), UDim2.new(1, -32, 0, 140))
	grid(inv, Vector2.new(160, 44))
	refs.inventory = inv

	-- Деньги: +1K … +1M, сброс. Не больше доли баланса (сервер всё равно обрежет)
	local cashRow = Instance.new("Frame")
	cashRow.BackgroundTransparency = 1
	cashRow.Position = UDim2.fromOffset(16, 422)
	cashRow.Size = UDim2.new(1, -32, 0, 44)
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = cashRow
	cashRow.Parent = window
	local count = #CASH_STEPS + 1
	for i, step in CASH_STEPS do
		local button = Ui.button(cashRow, "+" .. Texts.money(step), Color3.fromRGB(70, 90, 60), function()
			local limit = if state and type(state.maxCash) == "number" then state.maxCash else 0
			draftCash = math.min(draftCash + step, limit)
			sendDraft()
			renderOffers()
		end)
		button.LayoutOrder = i
		button.Size = UDim2.new(1 / count, -6, 1, 0)
	end
	local reset = Ui.button(cashRow, ClientState.t("trade_cash_reset"), Ui.colors.locked, function()
		draftCash = 0
		sendDraft()
		renderOffers()
	end)
	reset.LayoutOrder = count
	reset.Size = UDim2.new(1 / count, -6, 1, 0)
	-- Деньги в обмене выключены (Config/Friends.trade.cashEnabled): ни кнопок, ни строк с суммой
	if not Friends.trade.cashEnabled then
		cashRow.Visible = false
		refs.myCash.Visible = false
		refs.theirCash.Visible = false
	end

	local status = Ui.label(window, "", 22, Enum.Font.GothamMedium, Ui.colors.muted)
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.Position = UDim2.fromOffset(16, 474)
	status.Size = UDim2.new(1, -32, 0, 22)
	refs.status = status

	local confirm = Ui.button(window, "", Ui.colors.locked, function()
		local _, _, ready = confirmLook()
		if ready then
			FriendRemotes.TradeConfirm:FireServer()
		end
	end)
	confirm.Position = UDim2.fromOffset(16, 508)
	confirm.Size = UDim2.new(0.62, -16, 0, 56)
	refs.confirm = confirm
	local cancel = Ui.button(window, ClientState.t("trade_cancel"), Ui.colors.bad, function()
		FriendRemotes.TradeCancel:FireServer()
	end)
	cancel.AnchorPoint = Vector2.new(1, 0)
	cancel.Position = UDim2.new(1, -16, 0, 508)
	cancel.Size = UDim2.new(0.38, -8, 0, 56)

	-- Обратный отсчёт замка на кнопке
	task.spawn(function()
		while gui == screen do
			refreshConfirm()
			task.wait(TICK)
		end
	end)
end

local function onState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local wasTrading = state ~= nil and state.trade ~= nil
	state = payload
	local trade = payload.trade
	if type(trade) ~= "table" then
		draftItems = {}
		draftCash = 0
		dirty = false
		sendToken += 1
		closeWindow()
		return
	end
	lockEndsAt = os.clock() + (tonumber(trade.lockLeft) or 0)
	-- Своё предложение берём с сервера, если не ждём отправки своих изменений
	if not dirty or not wasTrading then
		local mine = if type(trade.mine) == "table" then trade.mine else { items = {}, cash = 0 }
		draftItems = {}
		for _, item in mine.items or {} do
			table.insert(draftItems, { kind = item.kind, id = item.id })
		end
		draftCash = tonumber(mine.cash) or 0
		dirty = false
	end
	closeRequest()
	openWindow()
	TradeWindow.render()
end

function TradeWindow.start()
	FriendRemotes.TradeState.OnClientEvent:Connect(onState)
	FriendRemotes.FriendNotice.OnClientEvent:Connect(function(notice: any)
		if type(notice) == "table" and notice.kind == "tradeRequest" and type(notice.userId) == "number" then
			showRequest(tostring(notice.name), notice.userId)
		end
	end)
	-- Перезашёл в персонажа / сменил язык: перерисовать
	ClientState.langChanged:Connect(function()
		if gui then
			closeWindow()
			if state and state.trade then
				openWindow()
				TradeWindow.render()
			end
		end
	end)
end

return TradeWindow
