--!strict
-- Праздничные ивенты (шаг 4.9): плашка под трендом и выставкой, кнопка меню 🎉 (слот 9,
-- видна только во время ивента) и окно «Ивент»: условия, квест ивента, календарь подарков.
-- Всё решает сервер (HolidayService): клиент показывает присланное и просит «Забрать».

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Holidays = require(ReplicatedStorage.Shared.Config.Holidays)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local HolidayRemotes = require(ReplicatedStorage.Shared.HolidayRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local QuestWindow = require(script.Parent.QuestWindow)

local BANNER_Y = 222 -- под плашкой выставки (ExpoBanner, y = 180, высота 34)
local BANNER_HEIGHT = 32
local MENU_SLOT = 9
local TILE_COLUMNS = 7

local HolidayController = {}

local gui: ScreenGui? = nil
local body: ScrollingFrame? = nil
local state: any = nil

local function activeHoliday(): Holidays.Holiday?
	return Holidays.find(ReplicatedStorage:GetAttribute("HolidayId"))
end

local function formatLeft(seconds: number): string
	local s = math.max(math.floor(seconds), 0)
	if s >= 86_400 then
		return ClientState.t("holiday_time_days", { days = s // 86_400, hours = (s % 86_400) // 3600 })
	end
	return ClientState.t(
		"holiday_time_hours",
		{ hours = s // 3600, minutes = string.format("%02d", (s % 3600) // 60) }
	)
end

local function holidayName(holiday: Holidays.Holiday): string
	return ClientState.t("holiday_name_" .. holiday.id)
end

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		body = nil
		Ui.windowClosed()
	end
end

local function section(parent: Instance, order: number, height: number): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
	frame.Size = UDim2.new(1, -8, 0, height)
	frame.LayoutOrder = order
	Ui.corner(frame, 10)
	frame.Parent = parent
	return frame
end

local function renderQuest(parent: ScrollingFrame, holiday: Holidays.Holiday, order: number)
	local quest = holiday.quest
	local info = state and state.quest
	if not quest or type(info) ~= "table" then
		return
	end
	local frame = section(parent, order, 132)
	local title =
		Ui.label(frame, "⭐ " .. ClientState.t("holiday_quest_title"), 26, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(0.68, -12, 0, 26)
	local text = Ui.label(frame, ClientState.t("holiday_quest_" .. holiday.id, { target = quest.target }), 22)
	text.Position = UDim2.fromOffset(12, 36)
	text.Size = UDim2.new(0.68, -12, 0, 22)
	local rewardParts = { QuestWindow.describeReward(quest.reward) }
	if quest.cosmetic then
		table.insert(rewardParts, ClientState.t("holiday_cosmetic_" .. quest.cosmetic))
	end
	local reward = Ui.label(
		frame,
		"🎁 " .. table.concat(rewardParts, " + "),
		20,
		Enum.Font.GothamMedium,
		Ui.colors.money
	)
	reward.Position = UDim2.fromOffset(12, 64)
	reward.Size = UDim2.new(0.68, -12, 0, 20)
	local once =
		Ui.label(frame, ClientState.t("holiday_quest_once"), 18, Enum.Font.GothamMedium, Ui.colors.muted)
	once.Position = UDim2.fromOffset(12, 92)
	once.Size = UDim2.new(0.68, -12, 0, 18)

	local progress = tonumber(info.progress) or 0
	local target = tonumber(info.target) or quest.target
	local done = progress >= target
	local progressLabel = Ui.label(
		frame,
		ClientState.t("holiday_quest_progress", { progress = progress, target = target }),
		24,
		nil,
		if done then Ui.colors.good else Ui.colors.muted
	)
	progressLabel.TextXAlignment = Enum.TextXAlignment.Center
	progressLabel.AnchorPoint = Vector2.new(1, 0)
	progressLabel.Position = UDim2.new(1, -8, 0, 10)
	progressLabel.Size = UDim2.new(0.3, 0, 0, 24)
	local claimed = info.claimed == true
	local canClaim = done and not claimed
	local button = Ui.button(
		frame,
		ClientState.t(if claimed then "holiday_quest_claimed" else "holiday_quest_claim"),
		if canClaim then Ui.colors.good else Ui.colors.locked,
		function()
			if canClaim then
				HolidayRemotes.ClaimHolidayQuest:FireServer()
			end
		end
	)
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -8, 1, -10)
	button.Size = UDim2.new(0.3, 0, 0, 44)
end

local function renderCalendar(parent: ScrollingFrame, holiday: Holidays.Holiday, order: number)
	local gifts = holiday.calendar
	local info = state and state.calendar
	if not gifts or type(info) ~= "table" then
		return
	end
	local count = tonumber(info.count) or 0
	local rows = math.ceil(#gifts / TILE_COLUMNS)
	local tileHeight = 110
	local frame = section(parent, order, 40 + rows * (tileHeight + 6) + 86)
	local title =
		Ui.label(frame, ClientState.t("holiday_calendar_title"), 28, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(1, -24, 0, 28)

	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(8, 40)
	grid.Size = UDim2.new(1, -16, 0, rows * (tileHeight + 6))
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / TILE_COLUMNS, -6, 0, tileHeight)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	grid.Parent = frame
	for i, gift in gifts do
		local tile = Instance.new("Frame")
		tile.LayoutOrder = i
		tile.BackgroundColor3 = if i <= count
			then Ui.colors.locked
			elseif i == count + 1 and info.available then Ui.colors.primary
			else Color3.fromRGB(56, 58, 80)
		Ui.corner(tile, 8)
		local dayText = ClientState.t("holiday_calendar_day", { day = i })
			.. (if i <= count then " ✓" else "")
		local day = Ui.label(tile, dayText, 20, Ui.titleFontFor(ClientState.lang))
		day.TextXAlignment = Enum.TextXAlignment.Center
		day.Position = UDim2.fromOffset(4, 4)
		day.Size = UDim2.new(1, -8, 0, 20)
		local text = Ui.label(tile, QuestWindow.describeReward(gift), 80, Enum.Font.GothamMedium)
		text.TextXAlignment = Enum.TextXAlignment.Center
		text.TextYAlignment = Enum.TextYAlignment.Top
		text.TextWrapped = true
		text.Position = UDim2.fromOffset(4, 26)
		text.Size = UDim2.new(1, -8, 1, -30)
		tile.Parent = grid
	end

	local footerY = 40 + rows * (tileHeight + 6) + 4
	local hintText = if count >= #gifts
		then ClientState.t("holiday_calendar_done")
		elseif info.available then ClientState.t("holiday_calendar_hint")
		else ClientState.t("holiday_calendar_next", {
			time = formatLeft((tonumber(info.nextDayAt) or 0) - workspace:GetServerTimeNow()),
		})
	local hint = Ui.label(frame, hintText, 20, nil, Ui.colors.muted)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.Position = UDim2.fromOffset(12, footerY)
	hint.Size = UDim2.new(1, -24, 0, 20)
	if info.available and count < #gifts then
		local claim = Ui.button(
			frame,
			ClientState.t("holiday_calendar_claim", { day = count + 1 }),
			Ui.colors.good,
			function()
				HolidayRemotes.ClaimHolidayGift:FireServer()
			end
		)
		claim.AnchorPoint = Vector2.new(0.5, 0)
		claim.Position = UDim2.new(0.5, 0, 0, footerY + 26)
		claim.Size = UDim2.fromOffset(320, 50)
	end
end

local function render()
	local frame = body
	if not frame then
		return
	end
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local holiday = activeHoliday()
	if not holiday then
		Ui.label(frame, ClientState.t("holiday_none"), 28, nil, Ui.colors.muted)
		return
	end
	local endsAt = ReplicatedStorage:GetAttribute("HolidayEndsAt")
	local timeLeft = if type(endsAt) == "number"
		then formatLeft(endsAt - workspace:GetServerTimeNow())
		else "—"
	Ui.label(frame, ClientState.t("holiday_ends", { time = timeLeft }), 24, nil, Ui.colors.muted).LayoutOrder =
		1

	-- Условия: бонус и сезонные темы
	local rules = section(frame, 2, 0)
	rules.AutomaticSize = Enum.AutomaticSize.Y
	local inner = Instance.new("Frame")
	inner.BackgroundTransparency = 1
	inner.Position = UDim2.fromOffset(12, 8)
	inner.Size = UDim2.new(1, -24, 0, 0)
	inner.AutomaticSize = Enum.AutomaticSize.Y
	Ui.list(inner, 4)
	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = rules
	inner.Parent = rules
	Ui.label(inner, "📜 " .. ClientState.t("holiday_rules"), 26, Ui.titleFontFor(ClientState.lang)).LayoutOrder =
		0
	local perk = Ui.label(inner, "• " .. ClientState.t("holiday_perk_" .. holiday.id), 22)
	perk.LayoutOrder = 1
	local n = 2
	for _, topic in Topics do
		if topic.seasonal == holiday.id then
			local line = Ui.label(
				inner,
				"• " .. ClientState.t("holiday_seasonal_topic", { topic = ClientState.localName(topic) }),
				22
			)
			line.LayoutOrder = n
			n += 1
		end
	end

	renderQuest(frame, holiday, 3)
	renderCalendar(frame, holiday, 4)

	local cosmetics = state and state.cosmetics
	if type(cosmetics) == "table" then
		local names = {}
		for id in cosmetics do
			if type(id) == "string" then
				table.insert(names, ClientState.t("holiday_cosmetic_" .. id))
			end
		end
		if #names > 0 then
			table.sort(names)
			local owned = Ui.label(
				frame,
				ClientState.t("holiday_cosmetics_owned", { list = table.concat(names, ", ") }),
				22,
				nil,
				Ui.colors.money
			)
			owned.LayoutOrder = 5
		end
	end
end

local function open()
	if gui then
		return
	end
	local holiday = activeHoliday()
	if not holiday then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "HolidayWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local window = Ui.window(screen, "Window", Vector2.new(760, 620))
	local title =
		Ui.label(window, holiday.icon .. " " .. holidayName(holiday), 40, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 40)
	local closeButton = Ui.button(window, "✕", Ui.colors.bad, close)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 10)
	closeButton.Size = UDim2.fromOffset(40, 40)

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(16, 60)
	scroll.Size = UDim2.new(1, -32, 1, -72)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	Ui.list(scroll, 10)
	scroll.Parent = window
	body = scroll

	render()
	HolidayRemotes.RequestHolidayState:FireServer()

	-- Таймеры в окне: перерисовка раз в 30 с, пока окно открыто
	task.spawn(function()
		while gui == screen do
			task.wait(30)
			if gui == screen then
				render()
			end
		end
	end)
end

function HolidayController.start()
	local screen = Instance.new("ScreenGui")
	screen.Name = "HolidayBanner"
	screen.ResetOnSpawn = false
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local banner =
		Ui.label(screen, "", BANNER_HEIGHT, Ui.titleFontFor(ClientState.lang), Color3.fromRGB(255, 170, 60))
	banner.TextXAlignment = Enum.TextXAlignment.Center
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, BANNER_Y)
	banner.Size = UDim2.fromOffset(520, BANNER_HEIGHT)
	banner.BackgroundTransparency = 0.25
	banner.BackgroundColor3 = Ui.colors.panel
	banner.Visible = false
	Ui.corner(banner, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = banner

	local menu = Ui.menuButton(MENU_SLOT, "🎉", function()
		if gui then
			close()
		else
			open()
		end
	end)
	menu.Visible = false

	local function refresh()
		local holiday = activeHoliday()
		local endsAt = ReplicatedStorage:GetAttribute("HolidayEndsAt")
		menu.Visible = holiday ~= nil
		if not holiday or type(endsAt) ~= "number" then
			banner.Visible = false
			if gui then
				close()
			end
			return
		end
		banner.Visible = true
		banner.Font = Ui.titleFontFor(ClientState.lang)
		banner.Text = ClientState.t("holiday_banner", {
			icon = holiday.icon,
			name = holidayName(holiday),
			perk = ClientState.t("holiday_perk_" .. holiday.id),
			time = formatLeft(endsAt - workspace:GetServerTimeNow()),
		})
	end

	ReplicatedStorage:GetAttributeChangedSignal("HolidayId"):Connect(function()
		refresh()
		HolidayRemotes.RequestHolidayState:FireServer()
	end)
	HolidayRemotes.HolidayState.OnClientEvent:Connect(function(newState)
		if type(newState) == "table" then
			state = newState
			render()
		end
	end)
	-- Смена языка: перерисовать открытое окно (changed приходит и на каждое изменение денег —
	-- на них не перерисовываем, иначе кнопка «Забрать» пересоздавалась бы под курсором)
	local renderedLang = ClientState.lang
	ClientState.changed:Connect(function()
		if ClientState.lang ~= renderedLang then
			renderedLang = ClientState.lang
			if gui then
				render()
			end
		end
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)
	HolidayRemotes.RequestHolidayState:FireServer()
end

return HolidayController
