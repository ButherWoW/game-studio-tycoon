--!strict
-- Совместная разработка и приглашения (CoopService, HoldingService). Клиент только показывает:
--   * кнопка «🤝 Позвать в проект» слева от «Создать игру» (за ПК, есть игра в студии) и выбор
--     игрока; в совместной игре она же — «🚪 Выйти из совместной»;
--   * плашка «👥 Вместе с X: «Игра» N%» в общем стеке плашек (Ui.bannerStack);
--   * всплывашка приглашения «Принять / Отказаться» — и в совместную игру, и в холдинг;
--   * тосты CoopNotice и HoldingNotice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Coop = require(Shared.Config.Coop)
local Texts = require(Shared.Config.Texts)
local CoopRemotes = require(Shared.CoopRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local DevState = require(script.Parent.Parent.DevState)
local Ui = require(script.Parent.Parent.Ui)

local TOAST_SECONDS = 4
local BANNER_ORDER = 45 -- место плашки в общем стеке
local PICK_ROW = 44

local player = Players.LocalPlayer

local CoopController = {}

local state: any = nil -- CoopState: nil — совместной игры нет
local button: TextButton? = nil
local banner: TextLabel? = nil
local picker: ScreenGui? = nil

-- ===== Тосты =====

local queue: { { text: string, color: Color3 } } = {}
local showing = false

local function showNext()
	local item = table.remove(queue, 1)
	if not item then
		showing = false
		return
	end
	showing = true
	local screen = Instance.new("ScreenGui")
	screen.Name = "CoopToast"
	screen.DisplayOrder = 4 -- под окнами (10+), над HUD — как другие тосты
	screen.ResetOnSpawn = false
	screen.Parent = player:WaitForChild("PlayerGui")
	local label = Ui.label(screen, item.text, 36, Ui.titleFontFor(ClientState.lang), item.color)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.36)
	label.Size = UDim2.new(0.9, 0, 0, 36)
	label.BackgroundColor3 = Ui.colors.panel
	label.BackgroundTransparency = 0.15
	Ui.corner(label, 10)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 36)
	limit.Parent = label
	task.delay(TOAST_SECONDS, function()
		screen:Destroy()
		showNext()
	end)
end

local function toast(text: string, color: Color3?)
	table.insert(queue, { text = text, color = color or Ui.colors.text })
	if not showing then
		showNext()
	end
end

local function str(value: any): string
	return if type(value) == "string" then value else ""
end

-- ===== Приглашение «Принять / Отказаться» =====

local invites: { ScreenGui } = {}

-- canAccept: проверка перед «Принять» (false — окно остаётся, подсказку покажет сама проверка)
local function invitePopup(
	text: string,
	seconds: number,
	answer: (boolean) -> (),
	canAccept: (() -> boolean)?
)
	local screen = Instance.new("ScreenGui")
	screen.Name = "InvitePopup"
	screen.DisplayOrder = 12 -- над окнами: приглашение сгорает быстро
	screen.ResetOnSpawn = false
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 140 + #invites * 128)
	frame.Size = UDim2.fromOffset(460, 116)
	frame.BackgroundColor3 = Ui.colors.panel
	Ui.corner(frame, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.good
	stroke.Parent = frame
	local label = Ui.label(frame, text, 48, nil, Ui.colors.text)
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Position = UDim2.fromOffset(12, 8)
	label.Size = UDim2.new(1, -24, 0, 48)
	local closed = false
	local function close(accept: boolean?)
		if closed then
			return
		end
		closed = true
		local index = table.find(invites, screen)
		if index then
			table.remove(invites, index)
		end
		screen:Destroy()
		if accept ~= nil then
			answer(accept)
		end
	end
	local accept = Ui.button(frame, ClientState.t("coop_accept"), Ui.colors.good, function()
		if canAccept and not canAccept() then
			return
		end
		close(true)
	end)
	accept.Position = UDim2.new(0, 12, 1, -52)
	accept.Size = UDim2.new(0.5, -18, 0, 42)
	local decline = Ui.button(frame, ClientState.t("coop_decline"), Ui.colors.locked, function()
		close(false)
	end)
	decline.Position = UDim2.new(0.5, 6, 1, -52)
	decline.Size = UDim2.new(0.5, -18, 0, 42)
	frame.Parent = screen
	table.insert(invites, screen)
	screen.Parent = player:WaitForChild("PlayerGui")
	task.delay(math.clamp(seconds, 1, 120), function()
		close(nil)
	end)
end

-- ===== Выбор игрока =====

local function closePicker()
	if picker then
		picker:Destroy()
		picker = nil
		Ui.windowClosed()
	end
end

-- Игра в студии, в которую зовём (на ноутбуке в парке нельзя)
local function studioProject(): DevState.ProjectInfo?
	for _, project in DevState.projects do
		if not project.laptop then
			return project
		end
	end
	return nil
end

local function openPicker()
	local project = studioProject()
	if picker or not project then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "CoopPicker"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = player:WaitForChild("PlayerGui")
	picker = screen
	Ui.windowOpened()
	local window = Ui.window(screen, "Window", Vector2.new(480, 460))
	local title = Ui.label(
		window,
		ClientState.t("coop_pick_title", { game = project.name }),
		34,
		Ui.titleFontFor(ClientState.lang)
	)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -76, 0, 34)
	local close = Ui.button(window, "×", Ui.colors.bad, closePicker)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Size = UDim2.fromOffset(40, 40)
	local hostPercent = math.floor(Coop.hostShare * 100 + 0.5)
	local hint = Ui.label(
		window,
		ClientState.t("coop_pick_hint", { host = hostPercent, guest = 100 - hostPercent }),
		22,
		nil,
		Ui.colors.muted
	)
	hint.TextWrapped = true
	hint.Position = UDim2.fromOffset(16, 52)
	hint.Size = UDim2.new(1, -32, 0, 40)
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(16, 100)
	scroll.Size = UDim2.new(1, -32, 1, -112)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	Ui.list(scroll, 6)
	scroll.Parent = window
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("OwnsGarage") == true then
			count += 1
			local row = Ui.button(scroll, other.DisplayName, Ui.colors.primary, function()
				CoopRemotes.CoopInvite:FireServer(other.UserId, project.id)
				closePicker()
			end)
			row.LayoutOrder = count
			row.Size = UDim2.new(1, -8, 0, PICK_ROW)
		end
	end
	if count == 0 then
		local empty = Ui.label(scroll, ClientState.t("coop_pick_empty"), 26, nil, Ui.colors.muted)
		empty.Size = UDim2.new(1, -8, 0, 26)
	end
end

-- ===== Кнопка и плашка =====

local function refresh()
	local b = button
	if b then
		if state then
			b.Text = ClientState.t("coop_leave_button")
			b.BackgroundColor3 = Ui.colors.locked
			b.Visible = true
		else
			b.Text = ClientState.t("coop_invite_button")
			b.BackgroundColor3 = Ui.colors.good
			b.Visible = ClientState.atPc() and studioProject() ~= nil
		end
	end
	local label = banner
	if label then
		if state then
			local vars = {
				name = str(state.partner),
				game = str(state.game),
				percent = math.floor((tonumber(state.progress) or 0) * 100),
			}
			-- Гость не за ПК — не помогает: подсказка вместо прогресса
			local idle = state.helping ~= true
			label.Text = ClientState.t(if idle then "coop_with_idle" else "coop_with", vars)
			label.TextColor3 = if idle then Ui.colors.bad else Ui.colors.good
			label.Font = Ui.titleFontFor(ClientState.lang)
			label.Visible = true
		else
			label.Visible = false
		end
	end
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "CoopHud"
	screen.ResetOnSpawn = false
	screen.Parent = player:WaitForChild("PlayerGui")
	-- Слева от «Создать игру» (справа от неё тумблер «Авто-релиз»)
	local b = Ui.button(screen, "", Ui.colors.good, function()
		if state then
			CoopRemotes.CoopLeave:FireServer()
		else
			openPicker()
		end
	end)
	b.Name = "CoopButton"
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(0.5, -140, 1, -30)
	b.Size = UDim2.fromOffset(190, 44)
	b.Visible = false
	button = b

	local label = Ui.label(Ui.bannerStack(), "", 30)
	label.Name = "CoopBanner"
	label.LayoutOrder = BANNER_ORDER
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Size = UDim2.fromOffset(460, 30)
	label.BackgroundColor3 = Ui.colors.panel
	label.BackgroundTransparency = 0.2
	label.Visible = false
	Ui.corner(label, 10)
	banner = label
end

-- ===== Тосты сервера =====

local function onCoopNotice(data: any)
	if type(data) ~= "table" then
		return
	end
	local t = ClientState.t
	local vars = {
		name = str(data.name),
		game = str(data.game),
		money = Texts.money(tonumber(data.money) or 0),
	}
	local kind = data.kind
	if kind == "sent" then
		toast(t("coop_toast_sent", vars), Ui.colors.good)
	elseif kind == "declined" then
		toast(t("coop_toast_declined", vars), Ui.colors.muted)
	elseif kind == "joined" then
		toast(t("coop_toast_joined", vars), Ui.colors.good)
	elseif kind == "joinedGuest" then
		toast(t("coop_toast_joined_guest", vars), Ui.colors.good)
	elseif kind == "split" then
		toast(t("coop_toast_split", vars), Ui.colors.money)
	elseif kind == "paid" then
		toast(t("coop_toast_paid", vars), Ui.colors.money)
	elseif kind == "noSplit" then
		toast(t("coop_toast_nosplit", vars), Ui.colors.muted)
	elseif kind == "noSplitGuest" then
		toast(t("coop_toast_nosplit_guest", vars), Ui.colors.muted)
	elseif kind == "ended" then
		toast(t("coop_toast_ended", vars), Ui.colors.muted)
	elseif kind == "fail" then
		local reason = str(data.reason)
		local key = "coop_fail_" .. reason
		toast(if Texts.lookup("en", key) then t(key) else t("coop_fail_gone"), Ui.colors.bad)
	end
end

local function onHoldingNotice(data: any)
	if type(data) ~= "table" then
		return
	end
	local t = ClientState.t
	local vars = {
		name = str(data.name),
		holding = str(data.holding),
		n = tonumber(data.n) or 0,
		money = Texts.money(tonumber(data.money) or 0),
	}
	local kind = data.kind
	if kind == "created" then
		toast(t("holding_toast_created", vars), Ui.colors.good)
	elseif kind == "sent" then
		toast(t("coop_toast_sent", vars), Ui.colors.good)
	elseif kind == "declined" then
		toast(t("coop_toast_declined", vars), Ui.colors.muted)
	elseif kind == "joined" then
		toast(t("holding_toast_joined", vars), Ui.colors.good)
	elseif kind == "left" then
		toast(t("holding_toast_left"), Ui.colors.muted)
	elseif kind == "kicked" then
		toast(t("holding_toast_kicked", vars), Ui.colors.bad)
	elseif kind == "goal" then
		toast(t("holding_toast_goal", vars), Ui.colors.money)
	elseif kind == "fail" then
		local reason = str(data.reason)
		local key = if reason == "level"
			then "holding_need_office"
			elseif reason == "gone" or reason == "expired" then "coop_fail_" .. reason
			else "holding_fail_" .. reason
		toast(if Texts.lookup("en", key) then t(key, vars) else t("holding_fail_error"), Ui.colors.bad)
	end
end

function CoopController.start()
	build()
	CoopRemotes.CoopState.OnClientEvent:Connect(function(data)
		state = if type(data) == "table" then data else nil
		refresh()
	end)
	CoopRemotes.CoopNotice.OnClientEvent:Connect(onCoopNotice)
	CoopRemotes.HoldingNotice.OnClientEvent:Connect(onHoldingNotice)
	CoopRemotes.CoopInvited.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" or type(data.inviteId) ~= "number" then
			return
		end
		local inviteId = data.inviteId
		invitePopup(
			ClientState.t("coop_invited", { name = str(data.name), game = str(data.game) }),
			tonumber(data.seconds) or Coop.inviteSeconds,
			function(accept)
				CoopRemotes.CoopReply:FireServer(inviteId, accept)
			end,
			-- Принять можно только за своим ПК: окно ждёт, пока игрок сядет
			function(): boolean
				if ClientState.atPc() then
					return true
				end
				toast(ClientState.t("coop_fail_guestPc"), Ui.colors.bad)
				return false
			end
		)
	end)
	CoopRemotes.HoldingInvited.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" or type(data.inviteId) ~= "number" then
			return
		end
		local inviteId = data.inviteId
		invitePopup(
			ClientState.t("holding_invited", { name = str(data.name), holding = str(data.holding) }),
			tonumber(data.seconds) or 30,
			function(accept)
				CoopRemotes.HoldingReply:FireServer(inviteId, accept)
			end
		)
	end)
	DevState.changed:Connect(refresh)
	ClientState.seatChanged:Connect(function()
		refresh()
		if not ClientState.atPc() then
			closePicker()
		end
	end)
	ClientState.langChanged:Connect(refresh)
	refresh()
end

return CoopController
