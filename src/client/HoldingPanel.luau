--!strict
-- Вкладка «🏢 Холдинги» окна «🏘 Студии» (TourWindow): свой холдинг (очки и цели недели,
-- участники, позвать с сервера, выйти) или создание, ниже — топ холдингов недели.
-- Не контроллер: TourWindow зовёт render(frame). Всё проверяет HoldingService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Holdings = require(Shared.Config.Holdings)
local Texts = require(Shared.Config.Texts)
local CoopRemotes = require(Shared.CoopRemotes)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local ROW_HEIGHT = 40

local player = Players.LocalPlayer

local HoldingPanel = {}

local state: any = nil
local draftName = "" -- текст в поле названия переживает перерисовку
local changedEvent = Instance.new("BindableEvent")
-- Пришло новое состояние: TourWindow перерисует вкладку, если она открыта
HoldingPanel.changed = changedEvent.Event

local function textLine(
	parent: Instance,
	text: string,
	order: number,
	color: Color3?,
	height: number?
): TextLabel
	local label = Ui.label(parent, text, height or 26, nil, color or Ui.colors.muted)
	label.LayoutOrder = order
	label.Size = UDim2.new(1, -8, 0, height or 26)
	return label
end

-- Строка: подпись слева, кнопка справа (кнопки может не быть)
local function buttonRow(
	parent: Instance,
	order: number,
	text: string,
	color: Color3,
	buttonText: string?,
	buttonColor: Color3?,
	onClick: (() -> ())?
)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
	row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	row.LayoutOrder = order
	Ui.corner(row, 8)
	local label = Ui.label(row, text, 24, nil, color)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, 10, 0.5, 0)
	label.Size = UDim2.new(if buttonText then 0.68 else 1, -14, 0, 24)
	if buttonText and onClick then
		local b = Ui.button(row, buttonText, buttonColor or Ui.colors.primary, onClick)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -6, 0.5, 0)
		b.Size = UDim2.new(0.3, 0, 0, ROW_HEIGHT - 8)
	end
	row.Parent = parent
end

local function renderCreate(frame: ScrollingFrame, order: number): number
	order += 1
	local intro =
		textLine(frame, ClientState.t("holding_intro", { max = Holdings.maxMembers }), order, nil, 44)
	intro.TextWrapped = true
	if state.levelOk ~= true then
		order += 1
		textLine(frame, ClientState.t("holding_need_office"), order, Ui.colors.bad)
		return order
	end
	order += 1
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -8, 0, 44)
	row.LayoutOrder = order
	local box = Instance.new("TextBox")
	box.Name = "HoldingName"
	box.Size = UDim2.new(0.6, -6, 1, 0)
	box.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
	box.TextColor3 = Ui.colors.text
	box.PlaceholderText = ClientState.t("holding_name_placeholder")
	box.Font = Ui.bodyFont
	box.TextScaled = true
	box.ClearTextOnFocus = false
	box.Text = draftName
	Ui.corner(box, 8)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		-- Не длиннее, чем примет сервер
		local length = utf8.len(box.Text)
		if length and length > Holdings.nameMax then
			box.Text = box.Text:sub(1, (utf8.offset(box.Text, Holdings.nameMax + 1) or (#box.Text + 1)) - 1)
		end
		draftName = box.Text
	end)
	box.Parent = row
	local create = Ui.button(
		row,
		ClientState.t("holding_create", { cost = Texts.money(tonumber(state.cost) or Holdings.createCost) }),
		Ui.colors.money,
		function()
			CoopRemotes.HoldingCreate:FireServer(draftName)
		end
	)
	create.TextColor3 = Color3.fromRGB(40, 30, 0)
	create.AnchorPoint = Vector2.new(1, 0)
	create.Position = UDim2.fromScale(1, 0)
	create.Size = UDim2.new(0.4, 0, 1, 0)
	row.Parent = frame
	return order
end

local function renderHolding(frame: ScrollingFrame, order: number, holding: any): number
	local t = ClientState.t
	order += 1
	textLine(frame, t("holding_title", { name = tostring(holding.name) }), order, Ui.colors.text, 32)
	order += 1
	textLine(
		frame,
		t("holding_week", { points = holding.points or 0, games = holding.games or 0 }),
		order,
		Ui.colors.money,
		28
	)
	order += 1
	textLine(frame, t("holding_points_hint"), order, nil, 22)
	for _, goal in (if type(holding.goals) == "table" then holding.goals else {}) :: { any } do
		order += 1
		textLine(
			frame,
			t(
				if goal.reached then "holding_goal_reached" else "holding_goal",
				{ points = goal.points, minutes = goal.minutes }
			),
			order,
			if goal.reached then Ui.colors.good else Ui.colors.text,
			24
		)
	end

	-- Участники
	local members = if type(holding.members) == "table" then holding.members else {}
	order += 1
	textLine(
		frame,
		t("holding_members", { n = #members, max = holding.max or Holdings.maxMembers }),
		order,
		Ui.colors.text
	)
	for _, m in members :: { any } do
		order += 1
		local mark = (if m.owner then "👑 " else "") .. tostring(m.name)
		local text = if m.online then mark else mark .. " · " .. t("holding_offline")
		local canKick = holding.isOwner == true and m.userId ~= player.UserId
		buttonRow(
			frame,
			order,
			text,
			if m.userId == player.UserId then Ui.colors.good else Ui.colors.text,
			if canKick then t("holding_kick") else nil,
			Ui.colors.bad,
			if canKick
				then function()
					CoopRemotes.HoldingKick:FireServer(m.userId)
				end
				else nil
		)
	end

	-- Позвать с сервера: у кого нет холдинга (атрибут HoldingName ставит сервер)
	if #members < (holding.max or Holdings.maxMembers) then
		order += 1
		textLine(frame, t("holding_invite_title"), order, Ui.colors.text)
		local any = false
		for _, other in Players:GetPlayers() do
			local tag = other:GetAttribute("HoldingName")
			if other ~= player and (type(tag) ~= "string" or tag == "") then
				any = true
				order += 1
				buttonRow(
					frame,
					order,
					other.DisplayName,
					Ui.colors.text,
					t("holding_invite"),
					Ui.colors.primary,
					function()
						CoopRemotes.HoldingInvite:FireServer(other.UserId)
					end
				)
			end
		end
		if not any then
			order += 1
			textLine(frame, t("holding_invite_empty"), order)
		end
	end
	order += 1
	local leave = Ui.button(frame, t("holding_leave"), Ui.colors.bad, function()
		CoopRemotes.HoldingLeave:FireServer()
	end)
	leave.LayoutOrder = order
	leave.Size = UDim2.new(0.5, 0, 0, ROW_HEIGHT)
	return order
end

local function renderBoard(frame: ScrollingFrame, order: number)
	local t = ClientState.t
	order += 1
	textLine(frame, t("holding_board_title"), order, Ui.colors.text, 30)
	local left = tonumber(state.weekLeft) or 0
	order += 1
	textLine(frame, t("tour_week_left", { days = left // 86400, hours = (left % 86400) // 3600 }), order)
	if state.boardAvailable ~= true then
		order += 1
		textLine(frame, t("tour_rating_unavailable"), order)
		return
	end
	local entries = if type(state.board) == "table" then state.board else {}
	if #entries == 0 then
		order += 1
		textLine(frame, t("tour_rating_empty"), order)
		return
	end
	for i, entry in entries :: { any } do
		order += 1
		local medal = if i == 1
			then "🥇"
			elseif i == 2 then "🥈"
			elseif i == 3 then "🥉"
			else tostring(i) .. "."
		local line = string.format(
			"%s %s — %s",
			medal,
			tostring(entry.name),
			t("holding_points", { n = entry.value or 0 })
		)
		local color = if entry.mine then Ui.colors.good elseif i <= 3 then Ui.colors.money else Ui.colors.text
		textLine(frame, line, order, color, 26)
	end
end

-- Нарисовать вкладку в список окна (UIListLayout по LayoutOrder)
function HoldingPanel.render(frame: ScrollingFrame)
	if type(state) ~= "table" then
		textLine(frame, ClientState.t("tour_loading"), 0)
		return
	end
	local order = 0
	if type(state.holding) == "table" then
		order = renderHolding(frame, order, state.holding)
	else
		order = renderCreate(frame, order)
	end
	renderBoard(frame, order + 10)
end

-- Попросить свежее состояние (вкладку открыли или обновили)
function HoldingPanel.request()
	CoopRemotes.HoldingRequest:FireServer()
end

CoopRemotes.HoldingState.OnClientEvent:Connect(function(data)
	if type(data) == "table" then
		state = data
		if type(data.holding) == "table" then
			draftName = ""
		end
		-- Пока вводят название, не перерисовываем: поле потеряло бы фокус
		if not UserInputService:GetFocusedTextBox() then
			changedEvent:Fire()
		end
	end
end)

return HoldingPanel
