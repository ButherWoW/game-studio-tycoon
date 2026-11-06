--!strict
-- Админ-панель владельца (AdminService, Config/Admin). Кнопка 🛠 под 🔐 сейфа видна только тем, кому
-- сервер поставил атрибут AdminPanel (OwnerAccess: ownerUserIds / создатель игры / владелец группы);
-- сервер всё равно заново проверяет владельца и каждый аргумент — здесь только окно.
-- Вкладки: Игрок (на себе) / Время / Контент / Модерация / Сервер. Кик, бан и сброс профиля —
-- в два шага: сервер присылает токен, кнопка «Подтвердить» живёт Admin.confirmSeconds.
-- Тексты только по-русски: панель видит один владелец (как SafeAdminPanel).
-- Объявления (AdminAnnounce) показываются всем игрокам — их слушает этот же контроллер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Admin = require(Shared.Config.Admin)
local ContentDrops = require(Shared.Config.ContentDrops)
local DailyEvents = require(Shared.Config.DailyEvents)
local Features = require(Shared.Config.Features)
local Stages = require(Shared.Config.Stages)
local AdminRemotes = require(Shared.AdminRemotes)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

type Reply = { ok: boolean, text: string, confirm: string?, data: any? }

local TABS = { "Игрок", "Время", "Контент", "Модерация", "Сервер" }
local ROW = 48
local FIELD_COLOR = Color3.fromRGB(44, 46, 66)

local AdminPanel = {}
local buttonGui: ScreenGui? = nil
local gui: ScreenGui? = nil
local body: ScrollingFrame? = nil
local status: TextLabel? = nil
local confirmButton: TextButton? = nil
local currentTab = 1
local selectedTarget: number? = nil
local busy = false
local pendingConfirm: { action: string, args: { [string]: any }, onData: ((any) -> ())? }? = nil
local announceGui: ScreenGui? = nil

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		body = nil
		status = nil
		confirmButton = nil
		pendingConfirm = nil
		Ui.windowClosed()
	end
end

local function setStatus(text: string, color: Color3?)
	local label = status
	if label then
		label.Text = text
		label.TextColor3 = color or Ui.colors.text
	end
end

-- «500k», «2.5m», «1b», «-100000» → число (сервер всё равно проверяет целое и пределы)
local function parseAmount(raw: string): number?
	local text = raw:gsub("[%s,_]", ""):lower()
	local number, suffix = text:match("^(%-?[%d%.]+)([kmb]?)$")
	local value = number and tonumber(number)
	if not value then
		return nil
	end
	local scale = if suffix == "k" then 1e3 elseif suffix == "m" then 1e6 elseif suffix == "b" then 1e9 else 1
	return math.floor(value * scale + 0.5)
end

local send: (action: string, args: { [string]: any }?, onData: ((any) -> ())?) -> ()

-- Ответ с токеном: кнопка «Подтвердить» повторяет тот же запрос с ним, пока токен жив
local function showConfirm(action: string, args: { [string]: any }, token: string, onData: ((any) -> ())?)
	local b = confirmButton
	if not b then
		return
	end
	local confirmed = table.clone(args)
	confirmed.confirm = token
	local entry = { action = action, args = confirmed, onData = onData }
	pendingConfirm = entry
	b.Visible = true
	task.delay(Admin.confirmSeconds, function()
		if pendingConfirm == entry then
			pendingConfirm = nil
			b.Visible = false
		end
	end)
end

local function onConfirm()
	local entry = pendingConfirm
	pendingConfirm = nil
	local b = confirmButton
	if b then
		b.Visible = false
	end
	if entry then
		send(entry.action, entry.args, entry.onData)
	end
end

send = function(action: string, args: { [string]: any }?, onData: ((any) -> ())?)
	if busy then
		return
	end
	busy = true
	local payload = args or {}
	pendingConfirm = nil
	local b = confirmButton
	if b then
		b.Visible = false
	end
	setStatus("…", Ui.colors.muted)
	task.spawn(function()
		local ok, result = pcall(function()
			return AdminRemotes.AdminRequest:InvokeServer(action, payload)
		end)
		busy = false
		if not ok or type(result) ~= "table" then
			setStatus("Нет ответа сервера", Ui.colors.bad)
			return
		end
		local response = result :: Reply
		local text = if type(response.text) == "string" then response.text else ""
		if text ~= "" then
			setStatus(text, if response.ok then Ui.colors.good else Ui.colors.bad)
		else
			setStatus(if response.ok then "" else "Не получилось", Ui.colors.bad)
		end
		if type(response.confirm) == "string" then
			setStatus(text, Ui.colors.money)
			showConfirm(action, payload, response.confirm, onData)
		elseif response.ok and onData then
			onData(response.data)
		end
	end)
end

-- ===== Кирпичики окна =====

local function row(parent: Instance, order: number, height: number?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, height or ROW)
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = frame
	frame.Parent = parent
	return frame
end

local function caption(parent: Instance, text: string, width: number): TextLabel
	local label = Ui.label(parent, text, ROW - 8, Ui.bodyFont, Ui.colors.muted)
	label.Size = UDim2.fromOffset(width, ROW - 8)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 22
	limit.Parent = label
	return label
end

local function input(parent: Instance, placeholder: string, width: number): TextBox
	local box = Instance.new("TextBox")
	box.Size = UDim2.fromOffset(width, ROW - 8)
	box.BackgroundColor3 = FIELD_COLOR
	box.TextColor3 = Ui.colors.text
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Ui.colors.muted
	box.Font = Ui.bodyFont
	box.TextSize = 20
	box.Text = ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.Parent = box
	Ui.corner(box, 8)
	box.Parent = parent
	return box
end

local function button(
	parent: Instance,
	text: string,
	color: Color3,
	width: number,
	onClick: () -> ()
): TextButton
	local b = Ui.button(parent, text, color, onClick)
	b.Size = UDim2.fromOffset(width, ROW - 8)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 22
	limit.Parent = b
	return b
end

local function note(parent: Instance, order: number, text: string, height: number?): TextLabel
	local label = Ui.label(parent, text, height or 30, Enum.Font.GothamMedium, Ui.colors.muted)
	label.LayoutOrder = order
	label.TextWrapped = true
	label.TextScaled = false
	label.TextSize = 18
	label.TextYAlignment = Enum.TextYAlignment.Top
	return label
end

-- ===== Вкладки =====

local function amountRow(parent: Instance, order: number, title: string, action: string)
	local r = row(parent, order)
	caption(r, title, 110)
	local box = input(r, "100000, 500k, 2m", 260)
	local function go(sign: number)
		local amount = parseAmount(box.Text)
		if not amount or amount <= 0 then
			setStatus("Введи положительное число", Ui.colors.bad)
			return
		end
		send(action, { amount = sign * amount })
	end
	button(r, "Выдать", Ui.colors.good, 150, function()
		go(1)
	end)
	button(r, "Забрать", Ui.colors.bad, 150, function()
		go(-1)
	end)
end

local function buildPlayer(parent: Instance)
	note(parent, 1, "Действия на этой вкладке — только на тебе.")
	amountRow(parent, 2, "Деньги $", "cash")
	amountRow(parent, 3, "ОИ", "points")
	local stages = row(parent, 4)
	caption(stages, "Этап", 110)
	for _, stage in Stages do
		local level = stage.level
		button(stages, level .. ". " .. stage.name, Ui.colors.primary, 140, function()
			send("stage", { level = level })
		end)
	end
	local timers = row(parent, 5)
	caption(timers, "Закончить", 110)
	for _, item in
		{
			{ "Разработку", "dev" },
			{ "Стройку", "build" },
			{ "Исследование", "research" },
			{ "Обучение", "training" },
			{ "Всё", "all" },
		}
	do
		local kind = item[2]
		button(timers, item[1], if kind == "all" then Ui.colors.good else Ui.colors.primary, 112, function()
			send("finish", { kind = kind })
		end)
	end
end

local function buildTime(parent: Instance)
	local info = note(
		parent,
		1,
		"День контента (волны предметов и обновления по средам) действует на весь сервер — поэтому только "
			.. "на тестовом сервере, где одни владельцы, или в Studio. Запущенные системы не выключаются "
			.. "до перезахода.",
		66
	)
	local r = row(parent, 2)
	caption(r, "День", 110)
	local box = input(r, "0…" .. Admin.maxContentDay, 160)
	button(r, "Поставить", Ui.colors.good, 160, function()
		local day = tonumber(box.Text)
		if not day then
			setStatus("Введи номер дня", Ui.colors.bad)
			return
		end
		send("contentDay", { day = math.floor(day) })
	end)
	button(r, "По календарю", Ui.colors.locked, 180, function()
		send("contentDay", { clear = true })
	end)
	local weeks = row(parent, 3)
	caption(weeks, "Среда", 110)
	local seen: { [number]: boolean } = {}
	for _, update in Features.updates do
		if update.week > 0 and not seen[update.week] then
			seen[update.week] = true
			local day = ContentDrops.wednesdayDay(update.week)
			button(weeks, update.icon .. " " .. update.week, Ui.colors.primary, 82, function()
				send("contentDay", { day = day })
			end)
		end
	end
	button(weeks, "Всё", Ui.colors.good, 82, function()
		send("contentDay", { day = Admin.maxContentDay })
	end)
	local test = row(parent, 4)
	button(test, "🧪 Тестовый сервер (только я)", Ui.colors.money, 360, function()
		send("testServer")
	end)
	send("status", nil, function(data: any)
		if type(data) ~= "table" or not info.Parent then
			return
		end
		local day = if type(data.contentDay) == "number"
			then "день " .. data.contentDay
			else "по календарю"
		local where = if data.contentAllowed
			then "здесь можно"
			else "здесь нельзя (обычный сервер)"
		info.Text = "Сейчас: "
			.. day
			.. " (календарь — день "
			.. tostring(data.realDay)
			.. "), "
			.. where
			.. (if data.onlyOwners then "" else ", на сервере есть игроки")
			.. ". Запущенные системы не выключаются до перезахода."
	end)
end

local function buildContent(parent: Instance)
	note(
		parent,
		1,
		"Событие дня и Золотой час — на этом сервере, для всех игроков на нём "
			.. "(при игроках — с подтверждением).",
		44
	)
	local r = row(parent, 2)
	caption(r, "Минут", 110)
	local box = input(r, tostring(Admin.defaultEventMinutes), 120)
	local function minutes(): number
		local value = tonumber(box.Text)
		return if value then math.floor(value) else Admin.defaultEventMinutes
	end
	button(r, "✨ Золотой час", Ui.colors.money, 200, function()
		send("event", { id = "golden", minutes = minutes() })
	end)
	button(r, "⏹ Стоп", Ui.colors.bad, 120, function()
		send("event", { id = "stop" })
	end)
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.LayoutOrder = 3
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(170, ROW - 8)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	grid.Parent = parent
	for i, event in DailyEvents.events do
		local id = event.id
		local b = Ui.button(grid, event.icon .. " " .. id, Ui.colors.primary, function()
			send("event", { id = id, minutes = minutes() })
		end)
		b.LayoutOrder = i
	end
end

local function buildModeration(parent: Instance)
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.LayoutOrder = 1
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(170, ROW - 8)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	list.Parent = parent
	local chosen = note(parent, 2, "Выбери игрока")
	local function refresh()
		send("players", nil, function(data: any)
			if type(data) ~= "table" or not list.Parent then
				return
			end
			for _, child in list:GetChildren() do
				if child:IsA("GuiButton") then
					child:Destroy()
				end
			end
			for i, entry in data do
				if type(entry) == "table" and type(entry.userId) == "number" then
					local userId = entry.userId
					local name = tostring(entry.name) .. (if entry.owner then " 👑" else "")
					local color = if userId == selectedTarget then Ui.colors.good else Ui.colors.locked
					local b: TextButton
					b = Ui.button(list, name, color, function()
						selectedTarget = userId
						chosen.Text = "Выбран: " .. name .. " (" .. userId .. ")"
						for _, other in list:GetChildren() do
							if other:IsA("GuiButton") then
								other.BackgroundColor3 = Ui.colors.locked
							end
						end
						b.BackgroundColor3 = Ui.colors.good
					end)
					b.LayoutOrder = i
				end
			end
		end)
	end
	local actions = row(parent, 3)
	local profileBox = note(parent, 7, "", 0)
	profileBox.AutomaticSize = Enum.AutomaticSize.Y
	profileBox.TextColor3 = Ui.colors.text
	local reason =
		input(row(parent, 4), "Причина (необязательно, видит игрок)", 560)
	local function withTarget(action: string, extra: { [string]: any }?, onData: ((any) -> ())?)
		if not selectedTarget then
			setStatus("Сначала выбери игрока", Ui.colors.bad)
			return
		end
		local args: { [string]: any } = { target = selectedTarget }
		for key, value in extra or {} do
			args[key] = value
		end
		send(action, args, onData)
	end
	button(actions, "🔄", Ui.colors.locked, 56, refresh)
	button(actions, "Профиль", Ui.colors.primary, 130, function()
		withTarget("view", nil, function(data: any)
			if type(data) ~= "table" or not profileBox.Parent then
				return
			end
			local lines = {}
			for _, pair in data do
				if type(pair) == "table" then
					table.insert(lines, tostring(pair[1]) .. ": " .. tostring(pair[2]))
				end
			end
			profileBox.Text = table.concat(lines, "\n")
		end)
	end)
	button(actions, "Телепорт", Ui.colors.primary, 130, function()
		withTarget("teleport")
	end)
	button(actions, "Кик", Ui.colors.bad, 100, function()
		withTarget("kick", { reason = reason.Text })
	end)
	button(actions, "Сброс профиля", Ui.colors.bad, 190, function()
		withTarget("reset")
	end)
	local bans = row(parent, 5)
	caption(bans, "Бан", 70)
	for _, days in Admin.banDays do
		button(
			bans,
			if days == 0 then "Навсегда" else days .. " дн.",
			Ui.colors.bad,
			120,
			function()
				withTarget("ban", { days = days, reason = reason.Text })
			end
		)
	end
	local unban = row(parent, 6)
	caption(unban, "Разбан", 70)
	local userIdBox = input(unban, "UserId", 220)
	button(unban, "Снять бан", Ui.colors.good, 160, function()
		local userId = tonumber(userIdBox.Text)
		if not userId then
			setStatus("Введи UserId", Ui.colors.bad)
			return
		end
		send("unban", { userId = math.floor(userId) })
	end)
	refresh()
end

local function buildServer(parent: Instance)
	local limit = Admin.announceMaxLength
	note(
		parent,
		1,
		"Объявление увидят все игроки сервера (фильтр Roblox, до "
			.. limit
			.. " символов)."
	)
	local r = row(parent, 2)
	local box = input(r, "Текст объявления", 520)
	box.TextWrapped = true
	button(r, "Отправить", Ui.colors.good, 160, function()
		local text = box.Text
		if text:gsub("%s", "") == "" then
			setStatus("Пустое объявление", Ui.colors.bad)
			return
		end
		send("announce", { text = text:sub(1, Admin.announceMaxLength * 4) })
	end)
	local info = note(parent, 3, "", 90)
	send("status", nil, function(data: any)
		if type(data) ~= "table" or not info.Parent then
			return
		end
		local owners = if data.onlyOwners then " (одни владельцы)" else ""
		local kind = if data.studio
			then "Studio"
			elseif data.contentAllowed then "закрытый (тестовый)"
			else "обычный"
		local lines = {
			"Игроков на сервере: " .. #Players:GetPlayers() .. owners,
			"Сервер: " .. kind,
		}
		local now = tonumber(data.now) or os.time()
		local eventEnds = data.eventEndsAt
		if type(data.eventId) == "string" and type(eventEnds) == "number" and eventEnds > now then
			local left = (eventEnds - now) // 60
			table.insert(
				lines,
				"Событие из панели: " .. data.eventId .. ", ещё " .. left .. " мин"
			)
		end
		local goldenEnds = data.goldenEndsAt
		if type(goldenEnds) == "number" and goldenEnds > now then
			table.insert(
				lines,
				"Золотой час из панели: ещё " .. (goldenEnds - now) // 60 .. " мин"
			)
		end
		info.Text = table.concat(lines, "\n")
	end)
end

local BUILDERS = { buildPlayer, buildTime, buildContent, buildModeration, buildServer }

local tabButtons: { TextButton } = {}

local function showTab(index: number)
	currentTab = index
	for i, b in tabButtons do
		b.BackgroundColor3 = if i == index then Ui.colors.primary else Ui.colors.locked
	end
	local frame = body
	if not frame then
		return
	end
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	BUILDERS[index](frame)
end

local function open()
	close()
	local screen = Instance.new("ScreenGui")
	screen.Name = "AdminPanel"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 30
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened(close)

	local window = Ui.window(screen, "Window", Vector2.new(780, 540))
	local title =
		Ui.label(window, "🛠 Админ-панель владельца", 32, Enum.Font.GothamBold)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 32)
	local closeButton = Ui.button(window, "×", Ui.colors.locked, close)
	Ui.headerClose(closeButton)

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(16, 56)
	tabs.Size = UDim2.new(1, -32, 0, 44)
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabs
	tabs.Parent = window
	table.clear(tabButtons)
	for i, name in TABS do
		local b = Ui.button(tabs, name, Ui.colors.locked, function()
			showTab(i)
		end)
		b.LayoutOrder = i
		b.Size = UDim2.new(1 / #TABS, -7, 1, 0)
		tabButtons[i] = b
	end

	-- Тело тянется по высоте (Ui.window на низком экране прокручивает его)
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(16, 108)
	scroll.Size = UDim2.new(1, -32, 1, -108 - 84)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	Ui.list(scroll, 8)
	scroll.Parent = window
	body = scroll

	local result = Ui.label(
		window,
		"Все действия пишутся в лог",
		22,
		Enum.Font.GothamMedium,
		Ui.colors.muted
	)
	result.Position = UDim2.new(0, 16, 1, -76)
	result.Size = UDim2.new(1, -212, 0, 64)
	result.TextWrapped = true
	result.TextScaled = false
	result.TextSize = 18
	result.TextYAlignment = Enum.TextYAlignment.Top
	status = result

	local confirm = Ui.button(window, "Подтвердить", Ui.colors.bad, onConfirm)
	confirm.Position = UDim2.new(1, -188, 1, -72)
	confirm.Size = UDim2.fromOffset(172, 52)
	confirm.Visible = false
	confirmButton = confirm

	showTab(currentTab)
end

-- ===== Объявление для всех =====

local function showAnnounce(info: any)
	if type(info) ~= "table" or type(info.text) ~= "string" or info.text == "" then
		return
	end
	local seconds = math.clamp(tonumber(info.seconds) or Admin.announceSeconds, 2, 30)
	if announceGui then
		announceGui:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "AdminAnnounce"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 40
	screen.Parent = player:WaitForChild("PlayerGui")
	announceGui = screen
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 64)
	frame.Size = UDim2.new(0.6, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Ui.colors.panel
	Ui.corner(frame)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.money
	stroke.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = frame
	local label = Ui.label(frame, "📢 " .. info.text, 0, Ui.bodyFont, Ui.colors.text)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextScaled = false
	label.TextSize = if Ui.touch then 16 else 22
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	frame.Parent = screen
	task.delay(seconds, function()
		if announceGui == screen then
			screen:Destroy()
			announceGui = nil
		end
	end)
end

local function showButton()
	if buttonGui or player:GetAttribute("AdminPanel") ~= true then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "AdminPanelButton"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 2
	screen.Parent = player:WaitForChild("PlayerGui")
	buttonGui = screen
	local b = Ui.button(screen, "🛠", Ui.colors.primary, function()
		if gui then
			close()
		else
			open()
		end
	end)
	b.AnchorPoint = Vector2.new(1, 0)
	-- Под кнопкой 🔐 сейфа (SafeAdminPanel: y 140, 48 px)
	b.Position = UDim2.new(1, -12, 0, 196)
	b.Size = UDim2.fromOffset(48, 48)
end

function AdminPanel.start()
	AdminRemotes.AdminAnnounce.OnClientEvent:Connect(showAnnounce)
	player:GetAttributeChangedSignal("AdminPanel"):Connect(showButton)
	showButton()
end

return AdminPanel
