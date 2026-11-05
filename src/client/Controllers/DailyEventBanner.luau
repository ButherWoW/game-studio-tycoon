--!strict
-- «События дня» (DailyEventService, Config/DailyEvents): плашка в общем стеке под HUD
-- (Ui.bannerStack, LayoutOrder 5, как хакатон). За 2 минуты — «Через 1:59: событие», во время —
-- событие с таймером и таблицей сервера (жуки, гранты инвестора, лидеры блиц-джема), отдельной
-- строкой — «Золотой час». Между событиями — тонкая строка «Дальше: … в 18:30»; нажатие на плашку
-- открывает расписание: ближайшие события, золотой час и «Ночная смена» (хакатон, Config/Hackathon).
-- Тосты сервера (DailyEventToast): поймал жука, грант, итоги; ping = true — со звуком (пинг за 2 мин).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local DailyEventRemotes = require(Shared.DailyEventRemotes)
local DailyEvents = require(Shared.Config.DailyEvents)
local Hackathon = require(Shared.Config.Hackathon)
local Genres = require(Shared.Config.Genres)
local Topics = require(Shared.Config.Topics)
local Images = require(Shared.Config.Images)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local SoundController = require(script.Parent.SoundController)

local BANNER_WIDTH = 400
local LINE_HEIGHT = 28
local BOARD_HEIGHT = 22
local IDLE_WIDTH = 300
local IDLE_HEIGHT = 22
local ROW_HEIGHT = 22
local SCHEDULE_ROWS = 6
local TOAST_HEIGHT = 32
local TOAST_WIDTH = 420
local TOAST_SECONDS = 4
local EVENT_COLOR = Color3.fromRGB(255, 140, 60)
local GOLDEN_COLOR = Color3.fromRGB(230, 170, 30)
-- devent_banner.png 1600×300 (Images.dailyEvents.banner): над плашкой события
local ART_HEIGHT = BANNER_WIDTH * 300 // 1600

local DailyEventBanner = {}

type Board = { id: string?, top: { { name: string, value: number } }?, left: number?, mine: number? }
local board: Board = {}

local function now(): number
	return math.floor(workspace:GetServerTimeNow())
end

local function clock(seconds: number): string
	seconds = math.max(seconds, 0)
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Местное время игрока (os.date без «!» на клиенте — часовой пояс устройства)
local function localTime(t: number): string
	return os.date("%H:%M", t)
end

local function eventName(id: string): string
	local event = DailyEvents.get(id)
	local icon = if event then event.icon .. " " else ""
	return icon .. ClientState.t("devent_name_" .. id)
end

local function genreName(id: any): string
	local genre = if type(id) == "string" then Genres[id] else nil
	return if genre then ClientState.localName(genre) else "?"
end

local function topicName(id: any): string
	local topic = if type(id) == "string" then Topics[id] else nil
	return if topic then ClientState.localName(topic) else "?"
end

-- Описание эффекта (жанр критиков, тема блиц-джема — из атрибутов слота)
local function eventDesc(id: string, genreId: any, topicId: any): string
	return ClientState.t("devent_desc_" .. id, { genre = genreName(genreId), topic = topicName(topicId) })
end

local function showToast(stack: Frame, payload: any)
	if type(payload) ~= "table" or type(payload.key) ~= "string" then
		return
	end
	local vars = if type(payload.vars) == "table" then table.clone(payload.vars) else {}
	if type(payload.eventId) == "string" then
		vars.name = eventName(payload.eventId)
	end
	local old = stack:FindFirstChild("DailyEventToast")
	if old then
		old:Destroy()
	end
	local toast = Ui.label(
		stack,
		ClientState.t(payload.key, vars),
		TOAST_HEIGHT,
		Ui.titleFontFor(ClientState.lang),
		Ui.colors.money
	)
	toast.Name = "DailyEventToast"
	toast.LayoutOrder = 6
	toast.Size = UDim2.fromOffset(TOAST_WIDTH, TOAST_HEIGHT)
	toast.BackgroundTransparency = 0.1
	toast.BackgroundColor3 = Ui.colors.panel
	toast.TextXAlignment = Enum.TextXAlignment.Center
	Ui.corner(toast, 10)
	if payload.ping == true then
		SoundController.play("unlock")
	end
	task.delay(TOAST_SECONDS, function()
		if toast.Parent then
			toast:Destroy()
		end
	end)
end

-- Строка таблицы события под плашкой; "" — нечего показывать
local function boardText(): string
	local id = board.id
	if not id then
		return ""
	end
	if id == "investors" then
		return ClientState.t("devent_board_investors", { left = board.left or 0 })
	end
	if id ~= "bugHunt" and id ~= "blitzJam" then
		return ""
	end
	local parts = {}
	for i, row in board.top or {} do
		table.insert(parts, `{i}. {row.name} ({row.value})`)
	end
	local list = if #parts > 0 then table.concat(parts, "  ") else ClientState.t("devent_board_empty")
	return ClientState.t("devent_board_" .. id, { list = list, mine = board.mine or 0 })
end

local function line(parent: Instance, name: string, height: number, width: number, color: Color3): TextLabel
	local label = Ui.label(parent, "", height, Ui.titleFontFor(ClientState.lang), Ui.colors.text)
	label.Name = name
	label.Size = UDim2.fromOffset(width, height)
	label.BackgroundTransparency = 0.2
	label.BackgroundColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Center
	Ui.corner(label, 10)
	return label
end

-- Расписание: ближайшие события, золотой час и хакатон по времени начала
local function fillSchedule(frame: Frame)
	for _, child in frame:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local t = now()
	type Row = { at: number, text: string, live: boolean }
	local rows: { Row } = {}
	for _, slot in DailyEvents.upcoming(SCHEDULE_ROWS, t) do
		table.insert(rows, {
			at = slot.startsAt,
			text = eventName(slot.id) .. " — " .. eventDesc(slot.id, slot.genreId, slot.topicId),
			live = t >= slot.startsAt and t < slot.endsAt,
		})
	end
	local golden = DailyEvents.goldenWindow(t)
	table.insert(rows, {
		at = golden.startsAt,
		text = "🌟 " .. ClientState.t("devent_name_golden") .. " — " .. ClientState.t(
			"devent_desc_golden",
			{ x = DailyEvents.golden.revenueMultiplier }
		),
		live = t >= golden.startsAt and t < golden.endsAt,
	})
	local hackathon = Hackathon.window(t)
	table.insert(rows, {
		at = hackathon.startsAt,
		text = "🌙 " .. ClientState.t("devent_name_nightShift") .. " — " .. ClientState.t(
			"devent_desc_nightShift",
			{ x = Hackathon.speedMultiplier }
		),
		live = t >= hackathon.startsAt and t < hackathon.endsAt,
	})
	table.sort(rows, function(a, b)
		return a.at < b.at
	end)
	local title =
		Ui.label(frame, ClientState.t("devent_schedule_title"), ROW_HEIGHT, Ui.titleFontFor(ClientState.lang))
	title.LayoutOrder = 0
	title.TextXAlignment = Enum.TextXAlignment.Center
	for i, row in rows do
		local when = if row.live then ClientState.t("devent_schedule_now") else localTime(row.at)
		local label = Ui.label(
			frame,
			when .. "  " .. row.text,
			ROW_HEIGHT,
			nil,
			if row.live then Ui.colors.money else Ui.colors.text
		)
		label.LayoutOrder = i
	end
end

function DailyEventBanner.start()
	local stack = Ui.bannerStack()
	local holder = Instance.new("Frame")
	holder.Name = "DailyEventBanner"
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = 5
	holder.Size = UDim2.fromOffset(BANNER_WIDTH, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.Parent = stack
	local layout = Ui.list(holder, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local artId = Images.dailyEvents.banner
	local art: ImageLabel? = nil
	if artId > 0 then
		local image = Instance.new("ImageLabel")
		image.Name = "Art"
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromOffset(BANNER_WIDTH, ART_HEIGHT)
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = "rbxassetid://" .. artId
		image.LayoutOrder = 0
		image.Visible = false
		Ui.corner(image, 10)
		image.Parent = holder
		art = image
	end

	-- Плашка события — кнопка: открывает и закрывает расписание
	local eventLine = Instance.new("TextButton")
	eventLine.Name = "Event"
	eventLine.AutoButtonColor = true
	eventLine.TextScaled = true
	eventLine.TextColor3 = Ui.colors.text
	eventLine.BackgroundTransparency = 0.2
	eventLine.BackgroundColor3 = EVENT_COLOR
	eventLine.LayoutOrder = 1
	Ui.corner(eventLine, 10)
	-- Слева место под иконку события (devent_<id>.png), справа столько же — текст по центру
	local linePadding = Instance.new("UIPadding")
	linePadding.PaddingLeft = UDim.new(0, LINE_HEIGHT)
	linePadding.PaddingRight = UDim.new(0, LINE_HEIGHT)
	linePadding.Parent = eventLine
	eventLine.Parent = holder
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(LINE_HEIGHT - 4, LINE_HEIGHT - 4)
	icon.Position = UDim2.fromOffset(4 - LINE_HEIGHT, 2)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = false
	icon.Parent = eventLine

	local boardLine = line(holder, "Board", BOARD_HEIGHT, BANNER_WIDTH, Ui.colors.panel)
	boardLine.LayoutOrder = 2
	boardLine.Font = Ui.bodyFont
	local goldenLine = line(holder, "Golden", LINE_HEIGHT, BANNER_WIDTH, GOLDEN_COLOR)
	goldenLine.LayoutOrder = 3

	local schedule = Instance.new("Frame")
	schedule.Name = "Schedule"
	schedule.BackgroundColor3 = Ui.colors.panel
	schedule.BackgroundTransparency = 0.1
	schedule.Size = UDim2.fromOffset(BANNER_WIDTH, 0)
	schedule.AutomaticSize = Enum.AutomaticSize.Y
	schedule.LayoutOrder = 4
	schedule.Visible = false
	Ui.corner(schedule, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = schedule
	Ui.list(schedule, 2)
	schedule.Parent = holder
	local scheduleBuiltAt = 0

	eventLine.Activated:Connect(function()
		schedule.Visible = not schedule.Visible
		if schedule.Visible then
			fillSchedule(schedule)
			scheduleBuiltAt = os.clock()
		end
	end)

	DailyEventRemotes.DailyEventToast.OnClientEvent:Connect(function(payload)
		showToast(stack, payload)
	end)
	DailyEventRemotes.DailyEventBoard.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		board = {
			id = if type(payload.id) == "string" then payload.id else nil,
			top = if type(payload.top) == "table" then payload.top else nil,
			left = tonumber(payload.left),
			mine = tonumber(payload.mine),
		}
	end)
	DailyEventRemotes.RequestDailyEvent:FireServer()

	task.spawn(function()
		while true do
			local t = now()
			local font = Ui.titleFontFor(ClientState.lang)
			local id = ReplicatedStorage:GetAttribute("DailyEventId")
			local startsAt = ReplicatedStorage:GetAttribute("DailyEventStartsAt")
			local endsAt = ReplicatedStorage:GetAttribute("DailyEventEndsAt")
			local announce = tonumber(ReplicatedStorage:GetAttribute("DailyEventAnnounce")) or 120
			local active = ReplicatedStorage:GetAttribute("DailyEventActive") == true
			local genreId = ReplicatedStorage:GetAttribute("DailyEventGenre")
			local topicId = ReplicatedStorage:GetAttribute("DailyEventTopic")
			local mode = "idle"
			if type(id) == "string" and type(startsAt) == "number" and type(endsAt) == "number" then
				local name = eventName(id)
				local desc = eventDesc(id, genreId, topicId)
				if active then
					mode = "active"
					eventLine.Text =
						ClientState.t("devent_active", { name = name, desc = desc, time = clock(endsAt - t) })
				elseif t < startsAt and startsAt - t <= announce then
					mode = "soon"
					eventLine.Text =
						ClientState.t("devent_soon", { name = name, desc = desc, time = clock(startsAt - t) })
				else
					eventLine.Text =
						ClientState.t("devent_next", { name = name, clock = localTime(startsAt) })
				end
				local imageId = Images.dailyEvents[id] or 0
				icon.Visible = mode ~= "idle" and imageId > 0
				if imageId > 0 then
					icon.Image = "rbxassetid://" .. imageId
				end
			end
			-- Между событиями плашка тоньше и прозрачнее — не спорит с остальными
			local idle = mode == "idle"
			eventLine.Font = if idle then Ui.bodyFont else font
			eventLine.Size = if idle
				then UDim2.fromOffset(IDLE_WIDTH, IDLE_HEIGHT)
				else UDim2.fromOffset(BANNER_WIDTH, LINE_HEIGHT)
			eventLine.BackgroundTransparency = if idle then 0.5 else 0.2
			eventLine.BackgroundColor3 = if idle then Ui.colors.panel else EVENT_COLOR
			eventLine.Visible = type(id) == "string"
			if art then
				art.Visible = not idle
			end
			local boardString = if active then boardText() else ""
			boardLine.Text = boardString
			boardLine.Visible = boardString ~= ""

			local gStarts = ReplicatedStorage:GetAttribute("DailyGoldenStartsAt")
			local gEnds = ReplicatedStorage:GetAttribute("DailyGoldenEndsAt")
			local gAnnounce = tonumber(ReplicatedStorage:GetAttribute("DailyGoldenAnnounce")) or 120
			local gX = ReplicatedStorage:GetAttribute("DailyGoldenMultiplier") or 2
			local gActive = ReplicatedStorage:GetAttribute("DailyGoldenActive") == true
			local goldenVisible = false
			if type(gStarts) == "number" and type(gEnds) == "number" then
				goldenLine.Font = font
				if gActive then
					goldenVisible = true
					goldenLine.Text =
						ClientState.t("devent_golden_active", { x = gX, time = clock(gEnds - t) })
				elseif t < gStarts and gStarts - t <= gAnnounce then
					goldenVisible = true
					goldenLine.Text =
						ClientState.t("devent_golden_soon", { x = gX, time = clock(gStarts - t) })
				end
			end
			goldenLine.Visible = goldenVisible

			-- Открытое расписание обновляем раз в 10 с («сейчас» и время)
			if schedule.Visible and os.clock() - scheduleBuiltAt > 10 then
				fillSchedule(schedule)
				scheduleBuiltAt = os.clock()
			end
			task.wait(1)
		end
	end)
end

return DailyEventBanner
