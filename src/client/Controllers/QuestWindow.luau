--!strict
-- Окно «Задания» (шаг 4.5): вкладки «Задания / Ежедневные / Лидеры». Кнопка меню — слот 3.
-- Клиент только показывает присланное сервером и просит «Забрать»; проверку делает сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestRemotes = require(ReplicatedStorage.Shared.QuestRemotes)
local Quests = require(ReplicatedStorage.Shared.Config.Quests)
local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Rewards = require(ReplicatedStorage.Shared.Config.Rewards)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local RewardFormulas = require(ReplicatedStorage.Shared.RewardFormulas)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

type Tab = "quests" | "daily" | "leaders"
type Entry = { id: string, progress: number, target: number, claimed: boolean }

local ROW_HEIGHT = 74
local MENU_SLOT = 3

local QuestWindow = {}

local gui: ScreenGui? = nil
local content: ScrollingFrame? = nil
local tabButtons: { [string]: TextButton } = {}
local tab: Tab = "quests"
local questState: any = nil
local board: any = nil
-- Награда за вход, которую закрыли «×» не забрав: день и как открыть окно (DailyRewardWindow
-- требует этот модуль, поэтому он сам регистрирует себя здесь, без циклического require)
local dailyRewardDay: number? = nil
local openDailyReward: (() -> ())? = nil

local function nameOf(item: { id: string, name: string, nameEn: string }): string
	return ClientState.localText("quest_" .. item.id, item.name, item.nameEn)
end

-- «N мин дохода (~$X)» и т.п.; деньги — подсказка по текущим данным, выдаёт сервер
-- cash — сколько сервер на самом деле начислил за incomeMinutes (тост сразу после выдачи:
-- ClientState ещё может быть старым, например до переезда в офис)
function QuestWindow.describeReward(reward: Rewards.Reward, cash: number?): string
	local t = ClientState.t
	local parts = {}
	if reward.incomeMinutes then
		local data = ClientState.data
		local money = if cash
			then cash
			elseif data then RewardFormulas.incomeForMinutes({
				-- Как RewardService.incomeState на сервере
				score = tonumber(data.runBestScore) or 0,
				studioLevel = data.studioLevel,
				rebirths = data.rebirths,
				ownsGarage = Players.LocalPlayer:GetAttribute("OwnsGarage") == true,
			}, reward.incomeMinutes)
			else 0
		table.insert(
			parts,
			t("reward_income", { minutes = reward.incomeMinutes, money = Texts.money(money) })
		)
	end
	if reward.researchPoints then
		table.insert(parts, t("reward_research", { count = reward.researchPoints }))
	end
	if reward.badge then
		table.insert(parts, t("reward_badge", { name = t("badge_" .. reward.badge) }))
	end
	if reward.incomeBonus then
		table.insert(
			parts,
			t("reward_income_bonus", { percent = math.floor(reward.incomeBonus * 100 + 0.5) })
		)
	end
	if reward.employee then
		table.insert(parts, t("reward_employee", { name = t("employee_" .. reward.employee) }))
	end
	if reward.coffeeMinutes then
		table.insert(parts, t("reward_coffee", { minutes = reward.coffeeMinutes }))
	end
	if reward.adBonus and reward.adMinutes then
		table.insert(
			parts,
			t("reward_ad", { percent = math.floor(reward.adBonus * 100 + 0.5), minutes = reward.adMinutes })
		)
	end
	if reward.trophy then
		table.insert(parts, t("reward_trophy", { name = t("trophy_" .. reward.trophy) }))
	end
	return table.concat(parts, " + ")
end

local function dailyName(quest: Quests.DailyQuest, target: number): string
	local genreId = questState and questState.dailyGenre
	local genre = if type(genreId) == "string" then Genres[genreId] else nil
	local targetText = if quest.kind == "earnIncome" then Texts.money(target) else tostring(target)
	local vars: { [string]: string } = {
		target = targetText,
		genre = if genre then nameOf(genre) else "",
		percent = tostring(math.floor((quest.minFocus or 0) * 100 + 0.5)),
		score = tostring(quest.minScore or 0),
	}
	return (nameOf(quest):gsub("{(%w+)}", function(key: string): string?
		return vars[key]
	end))
end

local function formatDuration(seconds: number): string
	seconds = math.max(seconds, 0)
	return string.format("%d:%02d", seconds // 3600, (seconds % 3600) // 60)
end

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

local function questRow(
	parent: Instance,
	order: number,
	title: string,
	rewardText: string,
	entry: Entry,
	kind: string
)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
	row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	row.LayoutOrder = order
	Ui.corner(row, 10)

	local done = entry.progress >= entry.target
	local titleLabel =
		Ui.label(row, title, 26, nil, if entry.claimed then Ui.colors.muted else Ui.colors.text)
	titleLabel.Position = UDim2.fromOffset(12, 6)
	titleLabel.Size = UDim2.new(0.68, -12, 0, 26)

	local rewardLabel = Ui.label(row, "🎁 " .. rewardText, 20, Enum.Font.GothamMedium, Ui.colors.money)
	rewardLabel.Position = UDim2.fromOffset(12, 36)
	rewardLabel.Size = UDim2.new(0.68, -12, 0, 20)

	local progressText = if kind == "earn"
		then ClientState.t(
			"quests_progress",
			{ progress = Texts.money(entry.progress), target = Texts.money(entry.target) }
		)
		else ClientState.t("quests_progress", { progress = entry.progress, target = entry.target })
	local progress = Ui.label(row, progressText, 20, nil, if done then Ui.colors.good else Ui.colors.muted)
	progress.TextXAlignment = Enum.TextXAlignment.Center
	progress.AnchorPoint = Vector2.new(1, 0)
	progress.Position = UDim2.new(1, -8, 0, 4)
	progress.Size = UDim2.new(0.3, 0, 0, 20)

	local buttonText = if entry.claimed
		then ClientState.t("quests_claimed")
		else ClientState.t("quests_claim")
	local canClaim = done and not entry.claimed
	local button = Ui.button(
		row,
		buttonText,
		if canClaim then Ui.colors.good else Ui.colors.locked,
		function()
			if canClaim then
				QuestRemotes.ClaimQuest:FireServer(if kind == "quest" then "quest" else "daily", entry.id)
			end
		end
	)
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -8, 1, -6)
	button.Size = UDim2.new(0.3, 0, 0, 36)
	row.Parent = parent
end

-- Кнопка «День N — забрать» над списком, пока награда за вход доступна
local function dailyRewardRow(frame: ScrollingFrame)
	local day, openReward = dailyRewardDay, openDailyReward
	if not day or not openReward then
		return
	end
	local button = Ui.button(
		frame,
		"🎁 " .. ClientState.t("daily_reward_claim", { day = day }),
		Ui.colors.good,
		openReward
	)
	button.LayoutOrder = -1
	button.Size = UDim2.new(1, -8, 0, 44)
end

local function renderQuests(frame: ScrollingFrame)
	local list = questState and questState.quests
	if type(list) ~= "table" then
		Ui.label(frame, ClientState.t("quests_loading"), 28, nil, Ui.colors.muted)
		return
	end
	-- Сначала готовые к получению, потом в процессе, полученные — в конце
	local function rank(e: Entry): number
		if e.claimed then
			return 3
		end
		return if e.progress >= e.target then 1 else 2
	end
	local order = {}
	for i, entry in list do
		table.insert(order, { index = i, entry = entry :: Entry })
	end
	table.sort(order, function(a, b)
		local ra, rb = rank(a.entry), rank(b.entry)
		if ra ~= rb then
			return ra < rb
		end
		return a.index < b.index
	end)
	for n, item in order do
		local quest = Quests.find(item.entry.id)
		if quest then
			questRow(frame, n, nameOf(quest), QuestWindow.describeReward(quest.reward), item.entry, "quest")
		end
	end
end

local function renderDaily(frame: ScrollingFrame)
	local list = questState and questState.daily
	if type(list) ~= "table" then
		Ui.label(frame, ClientState.t("quests_loading"), 28, nil, Ui.colors.muted)
		return
	end
	local resetAt = tonumber(questState.resetAt) or 0
	local timer = Ui.label(
		frame,
		ClientState.t("quests_daily_reset", { time = formatDuration(resetAt - os.time()) }),
		24,
		nil,
		Ui.colors.muted
	)
	timer.LayoutOrder = 0
	local rewardText = QuestWindow.describeReward(Quests.dailyReward)
	for i, entry in list do
		local quest = Quests.findDaily(entry.id)
		if quest then
			local kind = if quest.kind == "earnIncome" then "earn" else "daily"
			questRow(frame, i, dailyName(quest, entry.target), rewardText, entry :: Entry, kind)
		end
	end
end

local BOARD_HEIGHT = 40 + 10 * 30

local function boardColumn(parent: Instance, title: string, entries: any, position: UDim2, width: UDim?)
	local column = Instance.new("Frame")
	column.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
	column.Position = position
	column.Size = UDim2.new(width or UDim.new(0.5, -6), UDim.new(0, BOARD_HEIGHT))
	Ui.corner(column, 10)
	local inner = Instance.new("Frame")
	inner.BackgroundTransparency = 1
	inner.Position = UDim2.fromOffset(10, 6)
	inner.Size = UDim2.new(1, -20, 1, -12)
	Ui.list(inner, 4)
	inner.Parent = column
	Ui.label(inner, title, 30, Ui.titleFont, Ui.colors.money).LayoutOrder = 0
	if type(entries) ~= "table" or #entries == 0 then
		Ui.label(inner, ClientState.t("leaders_empty"), 24, nil, Ui.colors.muted).LayoutOrder = 1
	else
		local me = Players.LocalPlayer.Name
		for i, e in entries do
			-- Числа с разрядами (фанаты студии: «12 345»); оценки и игры — как раньше
			local value = if type(e.value) == "number" and e.value >= 1000
				then Texts.money(e.value):sub(2)
				else tostring(e.value)
			local line = string.format("%d. %s — %s", i, tostring(e.name), value)
			local color = if e.name == me then Ui.colors.good else Ui.colors.text
			Ui.label(inner, line, 24, Enum.Font.GothamMedium, color).LayoutOrder = i
		end
	end
	column.Parent = parent
end

local function renderLeaders(frame: ScrollingFrame)
	if board == nil then
		Ui.label(frame, ClientState.t("quests_loading"), 28, nil, Ui.colors.muted)
		return
	end
	if not board.available then
		Ui.label(frame, ClientState.t("leaders_unavailable"), 28, nil, Ui.colors.muted)
		return
	end
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, -8, 0, BOARD_HEIGHT * 2 + 12)
	boardColumn(holder, ClientState.t("leaders_best"), board.best, UDim2.fromScale(0, 0))
	boardColumn(holder, ClientState.t("leaders_games"), board.games, UDim2.new(0.5, 6, 0, 0))
	-- Фанаты студии (FansService) — второй ряд во всю ширину
	boardColumn(
		holder,
		ClientState.t("fans_leaders"),
		board.fans,
		UDim2.fromOffset(0, BOARD_HEIGHT + 12),
		UDim.new(1, 0)
	)
	holder.Parent = frame
end

local function render()
	local frame = clearContent()
	if not frame then
		return
	end
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == tab then Ui.colors.primary else Ui.colors.locked
	end
	if tab == "quests" then
		dailyRewardRow(frame)
		renderQuests(frame)
	elseif tab == "daily" then
		dailyRewardRow(frame)
		renderDaily(frame)
	else
		renderLeaders(frame)
	end
end

-- DailyRewardWindow: награда доступна (day) или нет (nil)
function QuestWindow.setDailyReward(day: number?, open: (() -> ())?)
	if dailyRewardDay == day and openDailyReward == open then
		return
	end
	dailyRewardDay = day
	openDailyReward = open
	if tab ~= "leaders" then
		render()
	end
end

function QuestWindow.close()
	if gui then
		gui:Destroy()
		gui = nil
		content = nil
		tabButtons = {}
		Ui.windowClosed()
	end
end

function QuestWindow.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "QuestWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened(QuestWindow.close) -- окно меню: закрывает другое открытое окно меню

	local window = Ui.window(screen, "Window", Vector2.new(680, 580))

	local title = Ui.label(window, ClientState.t("quests_title"), 40, Ui.titleFont)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 40)
	local close = Ui.button(window, "×", Ui.colors.bad, QuestWindow.close)
	Ui.headerClose(close)

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
	for i, name in { "quests", "daily", "leaders" } do
		local button = Ui.button(tabs, ClientState.t("quests_tab_" .. name), Ui.colors.locked, function()
			tab = name :: any
			render()
		end)
		button.LayoutOrder = i
		button.Size = UDim2.new(1 / 3, -6, 1, 0)
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

	render()
	QuestRemotes.RequestQuestData:FireServer()

	-- Таймер ежедневных: перерисовка раз в 30 с, пока окно открыто
	task.spawn(function()
		while gui == screen do
			task.wait(30)
			if gui == screen and tab == "daily" then
				render()
			end
		end
	end)
end

function QuestWindow.start()
	Ui.menuButton(MENU_SLOT, "📋", function()
		if gui then
			QuestWindow.close()
		else
			QuestWindow.open()
		end
	end, "menu_quests")
	QuestRemotes.QuestState.OnClientEvent:Connect(function(state)
		if type(state) == "table" then
			questState = state
			render()
		end
	end)
	QuestRemotes.LeaderboardData.OnClientEvent:Connect(function(data)
		if type(data) == "table" then
			board = data
			if tab == "leaders" then
				render()
			end
		end
	end)
	-- Награды «минуты дохода» зависят от лучшей оценки — обновим подсказки
	-- (DataChanged приходит на каждое изменение денег — перерисовываем только при смене этих полей).
	-- Поля те же, что у describeReward: лучшая оценка забега, уровень, rebirth, гараж
	local incomeKey = ""
	local function refreshIncome()
		local data = ClientState.data
		if not data then
			return
		end
		local key = string.format(
			"%s/%s/%s/%s",
			tostring(data.runBestScore),
			tostring(data.studioLevel),
			tostring(data.rebirths),
			tostring(Players.LocalPlayer:GetAttribute("OwnsGarage") == true)
		)
		if key ~= incomeKey then
			incomeKey = key
			if tab ~= "leaders" then
				render()
			end
		end
	end
	ClientState.changed:Connect(refreshIncome)
	Players.LocalPlayer:GetAttributeChangedSignal("OwnsGarage"):Connect(refreshIncome)
	-- Сменили язык: заголовок и вкладки строятся в open — открытое окно собираем заново
	ClientState.langChanged:Connect(function()
		if gui then
			QuestWindow.close()
			QuestWindow.open()
		end
	end)
	QuestRemotes.RequestQuestData:FireServer()
end

return QuestWindow
