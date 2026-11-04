--!strict
-- Окно «🏘 Студии» (кнопка меню — слот 15): вкладки «Студии» (кто на сервере, «Посетить», 👍)
-- и «Рейтинги» (глобальные топы TourService). Плюс плавающая кнопка «👍 Нравится», пока стоишь
-- на чужом участке, и тосты лайков. Всё проверяет сервер, клиент только показывает и просит.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tours = require(Shared.Config.Tours)
local Stages = require(Shared.Config.Stages)
local Texts = require(Shared.Config.Texts)
local TourRemotes = require(Shared.TourRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local StudioCamera = require(script.Parent.StudioCamera)

type Tab = "studios" | "ratings"
type Board = "likes" | "value" | "hit"

local MENU_SLOT = 15
local ROW_HEIGHT = 64
local LIST_REFRESH = 5 -- пока окно открыто, список просим заново раз в столько секунд
local PLOT_CHECK = 0.5
local FRONT_MARGIN = 7 -- как в TourService
local PLOT_HEIGHT = 80
local TOAST_SECONDS = 4

local player = Players.LocalPlayer

local TourWindow = {}

local gui: ScreenGui? = nil
local content: ScrollingFrame? = nil
local tabButtons: { [string]: TextButton } = {}
local tab: Tab = "studios"
local boardTab: Board = "likes"
local list: any = nil
local boards: any = nil
local likedToday: { [number]: boolean } = {}

-- ===== Тосты =====

local toastQueue: { { text: string, color: Color3 } } = {}
local toastShowing = false

local function showNextToast()
	local item = table.remove(toastQueue, 1)
	if not item then
		toastShowing = false
		return
	end
	toastShowing = true
	local screen = Instance.new("ScreenGui")
	screen.Name = "TourToast"
	screen.DisplayOrder = 4 -- под окнами (10+), над HUD — как другие тосты
	screen.ResetOnSpawn = false
	screen.Parent = player:WaitForChild("PlayerGui")
	local label = Ui.label(screen, item.text, 36, Ui.titleFontFor(ClientState.lang), item.color)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.3)
	label.Size = UDim2.new(0.9, 0, 0, 36)
	label.BackgroundColor3 = Ui.colors.panel
	label.BackgroundTransparency = 0.15
	Ui.corner(label, 10)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 36)
	limit.Parent = label
	task.delay(TOAST_SECONDS, function()
		screen:Destroy()
		showNextToast()
	end)
end

local function toast(text: string, color: Color3?)
	table.insert(toastQueue, { text = text, color = color or Ui.colors.text })
	if not toastShowing then
		showNextToast()
	end
end

-- ===== Подписи =====

local function stageName(level: any): string
	for _, stage in Stages do
		if stage.level == level then
			return ClientState.localName(stage)
		end
	end
	return ""
end

local function formatValue(kind: Board, value: number): string
	if kind == "value" then
		return Texts.money(value)
	elseif kind == "hit" then
		local factor = Tours.hitScoreFactor
		return ClientState.t("tour_hit_value", { score = value // factor, points = value % factor })
	end
	return "👍 " .. value
end

-- ===== Окно =====

local function clearContent(): ScrollingFrame?
	local frame = content
	if not frame then
		return nil
	end
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	return frame
end

local function textLine(parent: Instance, text: string, order: number, color: Color3?, height: number?)
	local label = Ui.label(parent, text, height or 26, nil, color or Ui.colors.muted)
	label.LayoutOrder = order
	label.Size = UDim2.new(1, -8, 0, height or 26)
	return label
end

local function sendLike(userId: number)
	TourRemotes.TourLike:FireServer(userId)
end

local function studioRow(parent: Instance, order: number, item: any, recentRow: boolean)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = if item.own then Color3.fromRGB(40, 58, 52) else Color3.fromRGB(44, 46, 66)
	row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	row.LayoutOrder = order
	Ui.corner(row, 10)

	local marks = (if item.vip then "👑 " else "") .. (if item.star then "⭐ " else "")
	local title = Ui.label(row, marks .. tostring(item.studio), 26)
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(0.62, -12, 0, 26)
	local detail = if recentRow
		then tostring(item.name) .. " · " .. ClientState.t("tour_left")
		elseif item.garage then tostring(item.name) .. " · " .. ClientState.t(
			"tour_stage_likes",
			{ stage = stageName(item.stage), likes = item.likes or 0 }
		)
		else tostring(item.name) .. " · " .. ClientState.t("tour_no_garage")
	local info = Ui.label(row, detail, 20, Enum.Font.GothamMedium, Ui.colors.muted)
	info.Position = UDim2.fromOffset(12, 36)
	info.Size = UDim2.new(0.62, -12, 0, 20)

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.AnchorPoint = Vector2.new(1, 0.5)
	buttons.Position = UDim2.new(1, -8, 0.5, 0)
	buttons.Size = UDim2.new(0.38, -8, 0, 40)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = buttons
	buttons.Parent = row

	if item.own then
		local you = Ui.label(buttons, ClientState.t("tour_you"), 40, nil, Ui.colors.good)
		you.TextXAlignment = Enum.TextXAlignment.Right
		you.Size = UDim2.fromScale(1, 1)
	else
		local liked = item.liked == true or likedToday[item.userId] == true
		local canLike = recentRow or item.canLike == true
		if item.garage or recentRow then
			local likeButton = Ui.button(
				buttons,
				if liked then ClientState.t("tour_liked") else "👍",
				if liked then Ui.colors.locked elseif canLike then Ui.colors.good else Ui.colors.locked,
				function()
					if not liked then
						sendLike(item.userId)
					end
				end
			)
			likeButton.LayoutOrder = 1
			likeButton.Size = UDim2.new(0.4, -3, 1, 0)
		end
		if item.garage and not recentRow then
			local visit = Ui.button(buttons, ClientState.t("tour_visit"), Ui.colors.primary, function()
				-- Вид сверху показывает только свой этаж — выходим из него, как кнопка 🏠
				StudioCamera.exit()
				TourRemotes.TourVisit:FireServer(item.userId)
			end)
			visit.LayoutOrder = 2
			visit.Size = UDim2.new(0.6, -3, 1, 0)
		end
	end
	row.Parent = parent
end

local function renderStudios(frame: ScrollingFrame)
	if type(list) ~= "table" or type(list.studios) ~= "table" then
		textLine(frame, ClientState.t("tour_loading"), 0)
		return
	end
	local me = list.me
	if type(me) == "table" then
		textLine(
			frame,
			ClientState.t("tour_my_likes", { total = me.likes or 0, week = me.likesWeek or 0 }),
			0,
			Ui.colors.money,
			28
		)
	end
	textLine(frame, ClientState.t("tour_like_hint"), 1, nil, 22)
	-- Своя студия первой, остальные — по лайкам
	local studios = table.clone(list.studios)
	table.sort(studios, function(a: any, b: any)
		if a.own ~= b.own then
			return a.own == true
		end
		if (a.likes or 0) ~= (b.likes or 0) then
			return (a.likes or 0) > (b.likes or 0)
		end
		return tostring(a.name) < tostring(b.name)
	end)
	local order = 10
	for _, item in studios do
		order += 1
		studioRow(frame, order, item, false)
	end
	if #studios <= 1 then
		order += 1
		textLine(frame, ClientState.t("tour_empty"), order)
	end
	if type(list.recent) == "table" and #list.recent > 0 then
		order += 1
		textLine(frame, ClientState.t("tour_recent"), order, Ui.colors.text)
		for _, item in list.recent do
			order += 1
			studioRow(frame, order, item, true)
		end
	end
end

local function myValue(kind: Board): number
	local me = type(list) == "table" and list.me
	if type(me) ~= "table" then
		return 0
	end
	if kind == "likes" then
		return tonumber(me.likesWeek) or 0
	elseif kind == "value" then
		return tonumber(me.value) or 0
	end
	return tonumber(me.hit) or 0
end

local function renderRatings(frame: ScrollingFrame)
	-- Переключатель досок
	local switch = Instance.new("Frame")
	switch.BackgroundTransparency = 1
	switch.Size = UDim2.new(1, -8, 0, 40)
	switch.LayoutOrder = 0
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = switch
	for i, kind in { "likes", "value", "hit" } do
		local button = Ui.button(
			switch,
			ClientState.t("tour_rating_" .. kind),
			if kind == boardTab then Ui.colors.primary else Ui.colors.locked,
			function()
				boardTab = kind :: any
				TourWindow.render()
			end
		)
		button.LayoutOrder = i
		button.Size = UDim2.new(1 / 3, -4, 1, 0)
	end
	switch.Parent = frame

	if boards == nil then
		textLine(frame, ClientState.t("tour_loading"), 1)
		return
	end
	if not boards.available then
		textLine(frame, ClientState.t("tour_rating_unavailable"), 1)
		return
	end
	if boardTab ~= "value" then
		local left = Tours.weekLeft()
		textLine(
			frame,
			ClientState.t("tour_week_left", { days = left // 86400, hours = (left % 86400) // 3600 }),
			1
		)
	end
	if boardTab == "likes" then
		textLine(frame, ClientState.t("tour_reward_hint", { n = Tours.weeklyTop }), 2, nil, 22)
	end
	local entries = boards[boardTab]
	if type(entries) ~= "table" then
		entries = {}
	end
	-- Своё место: в топе — номер, иначе своё значение
	local myRank: number? = nil
	for i, entry in entries do
		if entry.userId == player.UserId then
			myRank = i
		end
	end
	local mine = if myRank then entries[myRank].value else myValue(boardTab)
	local meText = if myRank
		then ClientState.t("tour_rating_me", { rank = myRank, value = formatValue(boardTab, mine) })
		else ClientState.t(
			"tour_rating_me_out",
			{ n = Tours.topSize, value = formatValue(boardTab, mine) }
		)
	textLine(frame, meText, 3, Ui.colors.good, 28)
	if #entries == 0 then
		textLine(frame, ClientState.t("tour_rating_empty"), 4)
		return
	end
	for i, entry in entries do
		local medal = if i == 1
			then "🥇"
			elseif i == 2 then "🥈"
			elseif i == 3 then "🥉"
			else tostring(i) .. "."
		local line =
			string.format("%s %s — %s", medal, tostring(entry.name), formatValue(boardTab, entry.value))
		local color = if entry.userId == player.UserId
			then Ui.colors.good
			elseif i <= 3 then Ui.colors.money
			else Ui.colors.text
		textLine(frame, line, 10 + i, color, 26)
	end
end

function TourWindow.render()
	local frame = clearContent()
	if not frame then
		return
	end
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == tab then Ui.colors.primary else Ui.colors.locked
	end
	if tab == "studios" then
		renderStudios(frame)
	else
		renderRatings(frame)
	end
end

function TourWindow.close()
	if gui then
		gui:Destroy()
		gui = nil
		content = nil
		tabButtons = {}
		Ui.windowClosed()
	end
end

function TourWindow.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "TourWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local window = Ui.window(screen, "Window", Vector2.new(680, 580))
	local title = Ui.label(window, ClientState.t("tour_title"), 40, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 40)
	local close = Ui.button(window, "×", Ui.colors.bad, TourWindow.close)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Size = UDim2.fromOffset(40, 40)

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(16, 58)
	tabs.Size = UDim2.new(1, -32, 0, 40)
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 8)
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Parent = tabs
	tabs.Parent = window
	for i, name in { "studios", "ratings" } do
		local button = Ui.button(tabs, ClientState.t("tour_tab_" .. name), Ui.colors.locked, function()
			tab = name :: any
			TourWindow.render()
		end)
		button.LayoutOrder = i
		button.Size = UDim2.new(0.5, -4, 1, 0)
		tabButtons[name] = button
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(16, 108)
	scroll.Size = UDim2.new(1, -32, 1, -120)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	Ui.list(scroll, 8)
	scroll.Parent = window
	content = scroll

	TourWindow.render()
	TourRemotes.TourRequest:FireServer()
	task.spawn(function()
		while gui == screen do
			task.wait(LIST_REFRESH)
			if gui == screen then
				TourRemotes.TourRequest:FireServer()
			end
		end
	end)
end

-- ===== Кнопка «👍 Нравится» на чужом участке =====

local likeButton: TextButton? = nil
local likeTarget: Player? = nil

-- Владелец участка под точкой (как TourService.ownerAt)
local function ownerAt(position: Vector3): Player?
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, other in Players:GetPlayers() do
		local name = other:GetAttribute("PlotName")
		local plot = if type(name) == "string" then plots:FindFirstChild(name) else nil
		if plot and plot:IsA("BasePart") then
			local p = plot.CFrame:PointToObjectSpace(position)
			local hx, hz = plot.Size.X / 2, plot.Size.Z / 2
			if
				math.abs(p.X) <= hx
				and p.Z >= -hz
				and p.Z <= hz + FRONT_MARGIN
				and p.Y > -5
				and p.Y < PLOT_HEIGHT
			then
				return other
			end
		end
	end
	return nil
end

local function ensureLikeButton(): TextButton
	local existing = likeButton
	if existing then
		return existing
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "TourLike"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 2
	screen.Parent = player:WaitForChild("PlayerGui")
	local button = Ui.button(screen, "", Ui.colors.good, function()
		local target = likeTarget
		if target then
			sendLike(target.UserId)
		end
	end)
	-- Над кнопкой «Создать игру» внизу по центру
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -96)
	button.Size = UDim2.fromOffset(300, 46)
	button.Visible = false
	likeButton = button
	return button
end

local function studioNameFor(target: Player): string
	if type(list) == "table" and type(list.studios) == "table" then
		for _, item in list.studios do
			if item.userId == target.UserId then
				return tostring(item.studio)
			end
		end
	end
	return target.DisplayName
end

local function refreshLikeButton()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local owner = if root and root:IsA("BasePart") then ownerAt(root.Position) else nil
	local show = owner ~= nil
		and owner ~= player
		and owner:GetAttribute("OwnsGarage") == true
		and not likedToday[owner.UserId]
	if owner ~= likeTarget and show then
		-- Зашли на новый участок: подтянем название студии и «уже лайкал сегодня»
		TourRemotes.TourRequest:FireServer()
	end
	likeTarget = if show then owner else nil
	if not show and not likeButton then
		return
	end
	local button = ensureLikeButton()
	button.Visible = show
	if show and owner then
		button.Text = ClientState.t("tour_like_button", { name = studioNameFor(owner) })
	end
end

-- ===== Старт =====

function TourWindow.start()
	Ui.menuButton(MENU_SLOT, "🏘", function()
		if gui then
			TourWindow.close()
		else
			TourWindow.open()
		end
	end, "menu_tours")

	TourRemotes.TourList.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then
			return
		end
		list = data
		if type(data.studios) == "table" then
			for _, item in data.studios do
				if item.liked then
					likedToday[item.userId] = true
				end
			end
		end
		if gui and tab == "studios" then
			TourWindow.render()
		end
		refreshLikeButton()
	end)
	TourRemotes.TourBoards.OnClientEvent:Connect(function(data)
		if type(data) == "table" then
			boards = data
			if gui and tab == "ratings" then
				TourWindow.render()
			end
		end
	end)
	TourRemotes.TourNotice.OnClientEvent:Connect(function(notice)
		if type(notice) ~= "table" then
			return
		end
		local t = ClientState.t
		local kind = notice.kind
		if kind == "liked" then
			if notice.name then
				toast(t("tour_toast_liked", { name = notice.name }), Ui.colors.good)
			else
				toast(t("tour_toast_liked_offline", { count = notice.count or 1 }), Ui.colors.good)
			end
		elseif kind == "likedOffline" then
			toast(t("tour_toast_liked_offline", { count = notice.count or 1 }), Ui.colors.good)
		elseif kind == "weeklyStar" then
			toast(
				t(
					"tour_toast_star",
					{ rank = notice.rank or 1, money = Texts.money(tonumber(notice.money) or 0) }
				),
				Ui.colors.money
			)
		elseif kind == "like" then
			if notice.ok then
				if type(notice.userId) == "number" then
					likedToday[notice.userId] = true
				end
				toast(t("tour_toast_like_ok", { name = notice.name or "" }), Ui.colors.good)
			elseif notice.reason == "already" then
				if likeTarget then
					likedToday[likeTarget.UserId] = true
				end
				toast(t("tour_toast_already"), Ui.colors.muted)
			else
				toast(t("tour_toast_visit_first"), Ui.colors.muted)
			end
			refreshLikeButton()
		elseif kind == "visit" then
			if notice.ok then
				toast(t("tour_toast_visit_ok", { name = notice.name or "" }), Ui.colors.good)
				TourWindow.close()
			else
				local reason = notice.reason
				local key = if reason == "cooldown"
					then "tour_toast_cooldown"
					elseif reason == "chase" then "tour_toast_chase"
					elseif reason == "nogarage" then "tour_toast_nogarage"
					else "tour_toast_gone"
				toast(t(key), Ui.colors.bad)
			end
		end
	end)

	ClientState.langChanged:Connect(function()
		if gui then
			TourWindow.close()
			TourWindow.open()
		end
		local target = likeTarget
		if likeButton and target then
			likeButton.Text = ClientState.t("tour_like_button", { name = studioNameFor(target) })
		end
	end)

	task.spawn(function()
		while true do
			task.wait(PLOT_CHECK)
			local ok, err = pcall(refreshLikeButton)
			if not ok then
				warn("[TourWindow] like button:", err)
			end
		end
	end)
end

return TourWindow
