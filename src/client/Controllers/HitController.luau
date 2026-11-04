--!strict
-- Картриджи-хиты на клиенте: тосты, тревога при краже, окно 🔒 (слот меню 7)
-- и prompts «Украсть» (язык игрока; у своих картриджей и у новичка prompt скрыт).
-- Всё решает сервер (HitService), здесь только отображение и запросы.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HitRemotes = require(ReplicatedStorage.Shared.HitRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local MENU_SLOT = 7
local TOAST_SECONDS = 4
local MAX_TOASTS = 3

local player = Players.LocalPlayer

local HitController = {}

-- Последнее состояние с сервера; остатки таймеров пересчитываем от момента получения
local state: any = nil
local stateAt = 0
local window: ScreenGui? = nil
local refreshWindow: (() -> ())? = nil
-- Слабые ключи: уничтоженные prompts не держим
local prompts: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function left(field: string): number
	if not state then
		return 0
	end
	return math.max(math.ceil((tonumber(state[field]) or 0) - (os.clock() - stateAt)), 0)
end

local function mmss(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- ===== Prompts =====

local function newbie(): boolean
	local data = ClientState.data
	local need = if state then tonumber(state.newbieGames) or 3 else 3
	return data ~= nil and (tonumber(data.gamesReleased) or 0) < need
end

local function applyPrompt(prompt: ProximityPrompt)
	prompt.ActionText = ClientState.t("hit_prompt")
	local own = prompt:GetAttribute("HitOwner") == player.UserId
	local open = prompt:GetAttribute("Open") == true
	local enabled = open and not own and not newbie()
	if prompt.Enabled ~= enabled then
		prompt.Enabled = enabled
	end
end

local function watchPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or prompt:GetAttribute("HitOwner") == nil then
		return
	end
	prompts[prompt] = true
	applyPrompt(prompt)
	-- Сервер меняет Enabled/Open при закрытии студии — пересчитываем свою локальную видимость
	prompt:GetAttributeChangedSignal("Open"):Connect(function()
		applyPrompt(prompt)
	end)
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		applyPrompt(prompt)
	end)
	prompt.AncestryChanged:Connect(function()
		if not prompt:IsDescendantOf(workspace) then
			prompts[prompt] = nil
		end
	end)
end

local function applyAllPrompts()
	for prompt in prompts do
		applyPrompt(prompt)
	end
end

-- ===== Тосты и тревога =====

local toastFrame: Frame
local alarmLabel: TextLabel
local arrow: BillboardGui? = nil
local alarmThiefId: number? = nil

local function showToast(text: string, color: Color3?)
	local count = 0
	for _, child in toastFrame:GetChildren() do
		if child:IsA("TextLabel") then
			count += 1
		end
	end
	if count >= MAX_TOASTS then
		local oldest: TextLabel? = nil
		for _, child in toastFrame:GetChildren() do
			if child:IsA("TextLabel") and (not oldest or child.LayoutOrder < oldest.LayoutOrder) then
				oldest = child
			end
		end
		if oldest then
			oldest:Destroy()
		end
	end
	local label = Ui.label(toastFrame, text, 34, Ui.titleFontFor(ClientState.lang), color)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.BackgroundTransparency = 0.15
	label.BackgroundColor3 = Ui.colors.panel
	label.LayoutOrder = math.floor(os.clock() * 100)
	Ui.corner(label, 10)
	task.delay(TOAST_SECONDS, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

local TOAST_COLORS: { [string]: Color3 } = {
	hit_income = Ui.colors.money,
	hit_new = Ui.colors.good,
	hit_stolen_by_you = Ui.colors.good,
	hit_caught_thief = Ui.colors.good,
	hit_lost = Ui.colors.bad,
	hit_you_were_caught = Ui.colors.bad,
}

local function headOf(userId: number): BasePart?
	local target = Players:GetPlayerByUserId(userId)
	local character = target and target.Character
	local head = character
		and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	return if head and head:IsA("BasePart") then head else nil
end

local function stopAlarm()
	alarmThiefId = nil
	alarmLabel.Visible = false
	if arrow then
		arrow:Destroy()
		arrow = nil
	end
end

local function startAlarm(info: any)
	local thiefId = tonumber(info.thiefId)
	if not thiefId then
		return
	end
	stopAlarm()
	alarmThiefId = thiefId
	alarmLabel.Text = ClientState.t("hit_alarm", { name = info.name, player = info.thiefName })
	alarmLabel.Visible = true
	-- Стрелка над вором видна сквозь стены только хозяину
	local gui = Instance.new("BillboardGui")
	gui.Name = "ThiefArrow"
	gui.Size = UDim2.fromOffset(120, 70)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = headOf(thiefId)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Ui.colors.bad
	label.TextStrokeTransparency = 0
	label.Text = ClientState.t("hit_alarm_arrow") .. "\n⬇"
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	arrow = gui
	-- Пока тревога, мигаем плашкой
	task.spawn(function()
		local on = true
		while alarmThiefId == thiefId do
			on = not on
			alarmLabel.BackgroundColor3 = if on then Ui.colors.bad else Ui.colors.panel
			task.wait(0.4)
		end
	end)
end

-- ===== Окно 🔒 =====

local function closeWindow()
	if window then
		window:Destroy()
		window = nil
		refreshWindow = nil
		Ui.windowClosed()
	end
end

local function openWindow()
	if window then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "HitWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 15
	screen.Parent = player:WaitForChild("PlayerGui")
	window = screen
	Ui.windowOpened()
	HitRemotes.RequestHitState:FireServer()

	local frame = Ui.window(screen, "Window", Vector2.new(520, 420))
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	Ui.list(body, 8)
	body.Parent = frame

	local title = Ui.label(body, ClientState.t("hit_window_title"), 38, Ui.titleFontFor(ClientState.lang))
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 1
	local summary = Ui.label(body, "", 28, nil, Ui.colors.money)
	summary.TextXAlignment = Enum.TextXAlignment.Center
	summary.LayoutOrder = 2
	local rules = Ui.label(body, ClientState.t("hit_rules"), 64, Enum.Font.GothamMedium, Ui.colors.muted)
	rules.TextWrapped = true
	rules.LayoutOrder = 3
	local stats = Ui.label(body, "", 22, Enum.Font.GothamMedium)
	stats.LayoutOrder = 4
	local hint = Ui.label(body, ClientState.t("hit_lock_hint"), 22, Enum.Font.GothamMedium, Ui.colors.muted)
	hint.LayoutOrder = 5

	local lock = Ui.button(body, "", Ui.colors.primary, function()
		if left("lockLeft") <= 0 and left("lockReadyIn") <= 0 then
			HitRemotes.RequestLock:FireServer()
		end
	end)
	lock.Size = UDim2.new(1, 0, 0, 50)
	lock.LayoutOrder = 6
	local close = Ui.button(body, ClientState.t("hit_close"), Ui.colors.locked, closeWindow)
	close.Size = UDim2.new(1, 0, 0, 44)
	close.LayoutOrder = 7

	local function update()
		if not state then
			return
		end
		summary.Text = ClientState.t("hit_summary", {
			count = state.count,
			slots = state.slots,
			income = Texts.money(tonumber(state.income) or 0),
		})
		stats.Text = ClientState.t("hit_my_stats", {
			steals = state.steals,
			income = Texts.money(tonumber(state.stolenIncome) or 0),
			catches = state.catches,
			caught = state.caught,
		})
		local lockLeft, readyIn = left("lockLeft"), left("lockReadyIn")
		if lockLeft > 0 then
			lock.Text = ClientState.t("hit_locked", { seconds = lockLeft })
			lock.BackgroundColor3 = Ui.colors.good
		elseif readyIn > 0 then
			lock.Text = ClientState.t("hit_lock_cooldown", { time = mmss(readyIn) })
			lock.BackgroundColor3 = Ui.colors.locked
		else
			lock.Text = ClientState.t("hit_lock", { seconds = state.lockSeconds })
			lock.BackgroundColor3 = Ui.colors.primary
		end
	end
	refreshWindow = update
	update()
	-- Таймеры тикают и без новых данных с сервера
	task.spawn(function()
		while window == screen do
			task.wait(0.5)
			if window == screen then
				update()
			end
		end
	end)
end

function HitController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HitToasts"
	gui.ResetOnSpawn = false
	-- Под окнами (10+): тост не рисуется поверх открытого окна (отчёт #3, P2-7)
	gui.DisplayOrder = 4
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Тосты над кнопкой «Создать игру»
	toastFrame = Instance.new("Frame")
	toastFrame.BackgroundTransparency = 1
	toastFrame.AnchorPoint = Vector2.new(0.5, 1)
	toastFrame.Position = UDim2.new(0.5, 0, 1, -92)
	toastFrame.Size = UDim2.fromOffset(520, 3 * 40)
	local layout = Ui.list(toastFrame, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	toastFrame.Parent = gui

	-- Тревога — в общем стеке плашек под выставкой и её итогами (Ui.bannerStack)
	alarmLabel = Ui.label(Ui.bannerStack(), "", 40, Ui.titleFontFor(ClientState.lang))
	alarmLabel.LayoutOrder = 4
	alarmLabel.Size = UDim2.fromOffset(560, 40)
	alarmLabel.TextXAlignment = Enum.TextXAlignment.Center
	alarmLabel.BackgroundTransparency = 0.1
	alarmLabel.BackgroundColor3 = Ui.colors.bad
	alarmLabel.Visible = false
	Ui.corner(alarmLabel, 10)

	Ui.menuButton(MENU_SLOT, "🔒", function()
		if window then
			closeWindow()
		else
			openWindow()
		end
	end, "menu_hits")

	HitRemotes.HitState.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then
			return
		end
		state = data
		stateAt = os.clock()
		applyAllPrompts()
		if refreshWindow then
			refreshWindow()
		end
	end)
	HitRemotes.HitToast.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" or type(data.key) ~= "string" then
			return
		end
		if data.key == "hit_new" or data.key == "hit_shelf_full" then
			-- «Хит! ★8» не спойлерит оценку: ждём, пока окно релиза её откроет (отчёт #2, п. 6)
			ClientState.afterReveal(function()
				showToast(ClientState.t(data.key, data.vars), TOAST_COLORS[data.key])
			end)
			return
		end
		showToast(ClientState.t(data.key, data.vars), TOAST_COLORS[data.key])
	end)
	HitRemotes.HitAlarm.OnClientEvent:Connect(function(info)
		if type(info) ~= "table" then
			return
		end
		if info.stop then
			stopAlarm()
		else
			startAlarm(info)
		end
	end)

	-- Голова вора могла смениться (персонаж загрузился позже): переставляем стрелку
	task.spawn(function()
		while true do
			task.wait(0.5)
			local id = alarmThiefId
			if arrow and id then
				arrow.Adornee = headOf(id)
			end
		end
	end)

	local plots = workspace:WaitForChild("Plots")
	plots.DescendantAdded:Connect(watchPrompt)
	for _, descendant in plots:GetDescendants() do
		watchPrompt(descendant)
	end

	ClientState.changed:Connect(function()
		-- Язык или число игр (новичок) могли смениться
		applyAllPrompts()
		if refreshWindow then
			refreshWindow()
		end
	end)
	-- Заголовок, правила и кнопки строятся один раз: при смене языка собираем окно заново
	ClientState.langChanged:Connect(function()
		if window then
			closeWindow()
			openWindow()
		end
	end)
	HitRemotes.RequestHitState:FireServer()
end

return HitController
