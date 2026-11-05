--!strict
-- Окно «Достижения» (кнопка меню — слот 14) и тост «🏆 Достижение: …» при получении.
-- Клиент только показывает присланное сервером: награды выдаются автоматически (AchievementService).
-- Вкладка «Титулы» (роадмап 7.21): выбор титула над головой; проверяет сервер (TitleService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementRemotes = require(ReplicatedStorage.Shared.AchievementRemotes)
local Achievements = require(ReplicatedStorage.Shared.Config.Achievements)
local Titles = require(ReplicatedStorage.Shared.Config.Titles)
local TitleRemotes = require(ReplicatedStorage.Shared.TitleRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local QuestWindow = require(script.Parent.QuestWindow)

local MENU_SLOT = 14
local ROW_HEIGHT = 84
local TITLE_ROW_HEIGHT = 64
local TITLES_TAB = "titles"
local TOAST_SECONDS = 3.5
local TIER_ICONS = { "🥉", "🥈", "🥇" }
-- Картинки медалей по уровню (Config/Images.medals); id 0 — эмодзи
local TIER_MEDALS = { "bronze", "silver", "gold" }

local player = Players.LocalPlayer

local AchievementWindow = {}

local gui: ScreenGui? = nil
local content: ScrollingFrame? = nil
local countLabel: TextLabel? = nil
local tabButtons: { [string]: TextButton } = {}
-- Категория достижений или TITLES_TAB
local tab: string = "studio"
local state: any = nil
-- Титулы с сервера: { owned = { [id]: true }, selected }
local titleState: any = nil

local function nameOf(a: Achievements.Achievement): string
	return ClientState.localText("ach_" .. a.id, a.name, a.nameEn)
end

local function amountText(a: Achievements.Achievement, value: number): string
	return if Achievements.moneyStats[a.stat] then Texts.money(value) else tostring(math.floor(value))
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

local function row(parent: Instance, order: number, a: Achievements.Achievement)
	local done = state and type(state.done) == "table" and state.done[a.id] ~= nil
	local secret = a.hidden == true and not done
	local value = if state and type(state.stats) == "table" then tonumber(state.stats[a.stat]) or 0 else 0
	value = math.min(value, a.target)

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = if done then Color3.fromRGB(40, 62, 52) else Color3.fromRGB(44, 46, 66)
	frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	frame.LayoutOrder = order
	Ui.corner(frame, 10)

	local icon = if secret then "❔" elseif a.tier then TIER_ICONS[a.tier] or "🏆" else "🏆"
	local iconLabel = Ui.label(frame, icon, 44)
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	iconLabel.Position = UDim2.fromOffset(6, 6)
	iconLabel.Size = UDim2.fromOffset(48, 44)
	local medalId = if not secret and a.tier then Images.medals[TIER_MEDALS[a.tier] or ""] or 0 else 0
	if medalId > 0 then
		iconLabel.Text = ""
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = "rbxassetid://" .. medalId
		image.ImageTransparency = if done then 0 else 0.45
		image.Parent = iconLabel
	end
	if not done then
		iconLabel.TextTransparency = 0.45
	end

	local title = Ui.label(
		frame,
		if secret then ClientState.t("ach_hidden") else nameOf(a),
		26,
		nil,
		if done then Ui.colors.good else Ui.colors.text
	)
	title.Position = UDim2.fromOffset(62, 6)
	title.Size = UDim2.new(0.62, -62, 0, 26)

	local descText = if secret
		then ClientState.t("ach_hidden_desc")
		else ClientState.localText("ach_" .. a.id .. "_desc", a.name, a.nameEn)
	local desc = Ui.label(frame, descText, 20, Enum.Font.GothamMedium, Ui.colors.muted)
	desc.Position = UDim2.fromOffset(62, 34)
	desc.Size = UDim2.new(0.62, -62, 0, 20)

	if not secret then
		local reward = Ui.label(
			frame,
			"🎁 " .. QuestWindow.describeReward(a.reward),
			18,
			Enum.Font.GothamMedium,
			Ui.colors.money
		)
		reward.Position = UDim2.fromOffset(62, 58)
		reward.Size = UDim2.new(0.62, -62, 0, 18)
	end

	-- Справа: «✓ Получено» или полоса прогресса «37 / 100»
	local right = Instance.new("Frame")
	right.BackgroundTransparency = 1
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.new(1, -10, 0.5, 0)
	right.Size = UDim2.new(0.36, -10, 0, 36)
	right.Parent = frame
	if done then
		local check = Ui.label(right, ClientState.t("ach_done"), 30, nil, Ui.colors.good)
		check.TextXAlignment = Enum.TextXAlignment.Center
		check.Position = UDim2.fromOffset(0, 3)
	elseif not secret then
		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = Ui.colors.locked
		bar.Size = UDim2.fromScale(1, 1)
		Ui.corner(bar, 8)
		bar.Parent = right
		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = Ui.colors.primary
		fill.Size = UDim2.fromScale(if a.target > 0 then value / a.target else 0, 1)
		Ui.corner(fill, 8)
		fill.Parent = bar
		local text = Ui.label(
			bar,
			ClientState.t(
				"quests_progress",
				{ progress = amountText(a, value), target = amountText(a, a.target) }
			),
			24
		)
		text.TextXAlignment = Enum.TextXAlignment.Center
		text.Position = UDim2.fromOffset(0, 6)
		text.ZIndex = 2
	end
	frame.Parent = parent
end

local function titleName(id: string): string
	return ClientState.t("title_" .. id)
end

-- Условие открытия титула для подсказки в строке
local function conditionText(title: Titles.Title): string
	local kind = Titles.condKind(title)
	local vars: { [string]: any } = {}
	if kind == "ach" then
		local a = Achievements.find(title.cond.achievement or "")
		local done = a and state and type(state.done) == "table" and state.done[a.id] ~= nil
		-- Скрытое достижение не раскрываем, пока не получено
		vars.name = if not a
			then "?"
			elseif a.hidden and not done then ClientState.t("ach_hidden")
			else nameOf(a)
	elseif kind == "rebirths" then
		vars.count = title.cond.rebirths
	end
	local text = ClientState.t("title_cond_" .. kind, vars)
	-- Временный титул (блиц-джем, «Игра недели»): сколько ещё часов действует
	local expires = titleState and type(titleState.expires) == "table" and titleState.expires
	local untilAt = expires and tonumber(expires[title.id])
	if untilAt then
		local hours = math.max(math.ceil((untilAt - workspace:GetServerTimeNow()) / 3600), 1)
		text ..= " · " .. ClientState.t("title_timed_left", { hours = hours })
	end
	return text
end

local function titleRow(parent: Instance, order: number, title: Titles.Title?)
	local owned = title == nil
		or (titleState and type(titleState.owned) == "table" and titleState.owned[title.id] == true)
	local selectedId = if titleState and type(titleState.selected) == "string"
		then titleState.selected
		else nil
	local selected = if title then selectedId == title.id else selectedId == nil

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = if selected then Color3.fromRGB(40, 62, 52) else Color3.fromRGB(44, 46, 66)
	frame.Size = UDim2.new(1, -8, 0, TITLE_ROW_HEIGHT)
	frame.LayoutOrder = order
	Ui.corner(frame, 10)

	local name = Ui.label(
		frame,
		if title then title.icon .. " " .. titleName(title.id) else "🚫 " .. ClientState.t("title_none"),
		28,
		Ui.titleFontFor(ClientState.lang),
		if title and owned then title.color elseif owned then Ui.colors.text else Ui.colors.muted
	)
	name.Position = UDim2.fromOffset(10, 4)
	name.Size = UDim2.new(1, -190, 0, 28)
	local desc = Ui.label(
		frame,
		if title then conditionText(title) else ClientState.t("title_hint"),
		22,
		Enum.Font.GothamMedium,
		Ui.colors.muted
	)
	desc.Position = UDim2.fromOffset(10, 36)
	desc.Size = UDim2.new(1, -190, 0, 22)

	local text = if selected
		then ClientState.t("title_picked")
		elseif owned then ClientState.t("title_pick")
		else "🔒 " .. ClientState.t("title_locked")
	local button = Ui.button(
		frame,
		text,
		if selected then Ui.colors.good elseif owned then Ui.colors.primary else Ui.colors.locked,
		function()
			if owned and not selected then
				TitleRemotes.SelectTitle:FireServer(if title then title.id else "")
			end
		end
	)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.fromOffset(170, 46)
	frame.Parent = parent
end

local function renderTitles(frame: ScrollingFrame)
	if titleState == nil then
		Ui.label(frame, ClientState.t("quests_loading"), 28, nil, Ui.colors.muted)
		return
	end
	titleRow(frame, 0, nil)
	-- Открытые — выше закрытых, внутри — порядок конфига
	local n = 0
	for pass = 1, 2 do
		for _, title in Titles.list do
			local isOwned = type(titleState.owned) == "table" and titleState.owned[title.id] == true
			if isOwned == (pass == 1) then
				n += 1
				titleRow(frame, n, title)
			end
		end
	end
end

local function doneCount(): (number, number)
	local done = 0
	local list = state and type(state.done) == "table" and state.done
	for _, a in Achievements.list do
		if list and list[a.id] then
			done += 1
		end
	end
	return done, #Achievements.list
end

local function render()
	local label = countLabel
	if label then
		local done, total = doneCount()
		label.Text = ClientState.t("ach_count", { done = done, total = total })
	end
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == tab then Ui.colors.primary else Ui.colors.locked
	end
	local frame = clearContent()
	if not frame then
		return
	end
	if tab == TITLES_TAB then
		renderTitles(frame)
		return
	end
	if state == nil then
		Ui.label(frame, ClientState.t("quests_loading"), 28, nil, Ui.colors.muted)
		return
	end
	local n = 0
	for _, a in Achievements.list do
		if a.category == tab then
			n += 1
			row(frame, n, a)
		end
	end
end

function AchievementWindow.close()
	if gui then
		gui:Destroy()
		gui = nil
		content = nil
		countLabel = nil
		tabButtons = {}
		Ui.windowClosed()
	end
end

function AchievementWindow.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "AchievementWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened(AchievementWindow.close) -- окно меню: закрывает другое открытое окно меню

	local window = Ui.window(screen, "Window", Vector2.new(680, 600))

	local title = Ui.label(window, "🏆 " .. ClientState.t("ach_title"), 40, Ui.titleFont)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(0.5, -16, 0, 40)
	local count = Ui.label(window, "", 26, nil, Ui.colors.money)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -64, 0, 17)
	count.Size = UDim2.new(0.5, -64, 0, 26)
	countLabel = count
	local close = Ui.button(window, "×", Ui.colors.bad, AchievementWindow.close)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Size = UDim2.fromOffset(40, 40)

	-- 7 вкладок (6 категорий + «Титулы») в два ряда по 4: в один ряд на телефоне нечитаемо мелко
	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(16, 58)
	tabs.Size = UDim2.new(1, -32, 0, 80)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / 4, -6, 0, 36)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = tabs
	tabs.Parent = window
	for i, name in Achievements.categories do
		local button = Ui.button(tabs, ClientState.t("ach_tab_" .. name), Ui.colors.locked, function()
			tab = name
			render()
		end)
		button.LayoutOrder = i
		tabButtons[name] = button
	end
	local titlesButton = Ui.button(
		tabs,
		"🎖️ " .. ClientState.t("title_tab"),
		Ui.colors.locked,
		function()
			tab = TITLES_TAB
			render()
		end
	)
	titlesButton.LayoutOrder = #Achievements.categories + 1
	tabButtons[TITLES_TAB] = titlesButton

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(16, 148)
	scroll.Size = UDim2.new(1, -32, 1, -160)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	Ui.list(scroll, 8)
	scroll.Parent = window
	content = scroll

	render()
	AchievementRemotes.RequestAchievements:FireServer()
	TitleRemotes.RequestTitles:FireServer()
end

-- ===== Тосты: по очереди, если получено несколько сразу =====

local queue: { { title: string, detail: string } } = {}
local showing = false

local function playSound()
	local module = script.Parent:FindFirstChild("SoundController")
	if module and module:IsA("ModuleScript") then
		pcall(function()
			(require(module) :: any).play("unlock")
		end)
	end
end

local function showNext()
	local item = table.remove(queue, 1)
	if not item then
		showing = false
		return
	end
	showing = true
	local screen = Instance.new("ScreenGui")
	screen.Name = "AchievementToast"
	-- Под окнами (10+), над HUD — как другие тосты
	screen.DisplayOrder = 5
	screen.ResetOnSpawn = false
	screen.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.3)
	panel.Size = UDim2.new(0.9, 0, 0, 70)
	panel.BackgroundColor3 = Ui.colors.panel
	panel.BackgroundTransparency = 0.1
	Ui.corner(panel, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.money
	stroke.Parent = panel
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(560, 70)
	limit.Parent = panel
	panel.Parent = screen

	local title = Ui.label(panel, item.title, 34, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Position = UDim2.new(0, 10, 0, 4)
	title.Size = UDim2.new(1, -20, 0, 34)
	if item.detail ~= "" then
		local detail = Ui.label(panel, item.detail, 22, Enum.Font.GothamMedium, Ui.colors.text)
		detail.TextXAlignment = Enum.TextXAlignment.Center
		detail.Position = UDim2.new(0, 10, 0, 40)
		detail.Size = UDim2.new(1, -20, 0, 22)
	end
	playSound()
	task.delay(TOAST_SECONDS, function()
		screen:Destroy()
		showNext()
	end)
end

local function toast(title: string, detail: string)
	table.insert(queue, { title = title, detail = detail })
	if not showing then
		showNext()
	end
end

local function onUnlocked(info: any)
	if type(info) ~= "table" then
		return
	end
	local reward = if type(info.reward) == "table" then QuestWindow.describeReward(info.reward) else ""
	if type(info.backfill) == "number" then
		toast(
			ClientState.t("ach_backfill", { count = info.backfill }),
			if reward ~= "" then ClientState.t("ach_reward", { reward = reward }) else ""
		)
		return
	end
	local a = if type(info.id) == "string" then Achievements.find(info.id) else nil
	if not a then
		return
	end
	toast(
		ClientState.t("ach_unlocked", { name = nameOf(a) }),
		ClientState.t("ach_reward", {
			reward = QuestWindow.describeReward(
				a.reward,
				if type(info.cash) == "number" then info.cash else nil
			),
		})
	)
end

function AchievementWindow.start()
	Ui.menuButton(MENU_SLOT, "🏆", function()
		if gui then
			AchievementWindow.close()
		else
			AchievementWindow.open()
		end
	end, "menu_achievements")
	AchievementRemotes.AchievementState.OnClientEvent:Connect(function(data)
		if type(data) == "table" then
			state = data
			if gui then
				render()
			end
		end
	end)
	AchievementRemotes.AchievementUnlocked.OnClientEvent:Connect(onUnlocked)
	TitleRemotes.TitleState.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then
			return
		end
		titleState = data
		if type(data.new) == "table" then
			for _, id in data.new do
				local title = if type(id) == "string" then Titles.byId[id] else nil
				if title then
					toast(ClientState.t("title_new", { name = title.icon .. " " .. titleName(id) }), "")
				end
			end
		end
		if gui then
			render()
		end
	end)
	-- Сменили язык: открытое окно собираем заново
	ClientState.langChanged:Connect(function()
		if gui then
			AchievementWindow.close()
			AchievementWindow.open()
		end
	end)
	AchievementRemotes.RequestAchievements:FireServer()
end

return AchievementWindow
