--!strict
-- Обучение по ходу игры (Config/Guides): в игре много систем, и о них рассказываем постепенно —
-- одна карточка «Как это работает» (иконка, заголовок, 3 пункта, «Понятно») за раз:
--   * кнопка меню нажата впервые — карточку этой системы сразу поверх её окна;
--   * авто-карточки (Guides.list[].when) — по условию прогресса, через PopupQueue, не раньше
--     Guides.sessionDelaySeconds после входа и не чаще одной в Guides.autoGapSeconds (считая и
--     карточки из меню); во время туториала и пока открыты окна — ждут;
--   * приставы — когда они впервые пришли (атрибут BailiffsActive).
-- «Понятно» → GuideRemotes.GuideSeen (сервер помнит, атрибут GuidesSeen). Окно «📖 Справочник»
-- (слот Guides.bookSlot) — все прочитанные и уже доступные карточки, перечитать любую.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Guides = require(ReplicatedStorage.Shared.Config.Guides)
local Unlocks = require(ReplicatedStorage.Shared.Config.Unlocks)
local GuideRemotes = require(ReplicatedStorage.Shared.GuideRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local PopupQueue = require(script.Parent.Parent.PopupQueue)
local FeatureGate = require(script.Parent.FeatureGate)

local CARD_ORDER = 30 -- над окнами меню (10) и магазином (20): карточка объясняет открытое окно
local BOOK_ORDER = 12
local CARD_WIDTH = 480
local LINE_HEIGHT = 58
local QUEUE_KEY = "guide"

local player = Players.LocalPlayer
local GuideController = {}

local card: ScreenGui? = nil
local cardGuide: Guides.Guide? = nil
local cardMarks = false -- открытая карточка — первое знакомство: «Понятно» скажет серверу
local book: ScreenGui? = nil
local shownThisSession: { [string]: boolean } = {}
local lastShownAt = -math.huge -- os.clock() последней карточки (любой)
local startedAt = os.clock()

-- Что сервер помнит как прочитанное (nil — ещё не прислал: ничего не показываем сами)
local function readSeen(): { [string]: boolean }?
	local raw = player:GetAttribute(Guides.SEEN_ATTRIBUTE)
	if type(raw) ~= "string" then
		return nil
	end
	local set: { [string]: boolean } = {}
	for id in raw:gmatch("[^,]+") do
		set[id] = true
	end
	return set
end

local function isSeen(id: string): boolean
	local seen = readSeen()
	return shownThisSession[id] == true or (seen ~= nil and seen[id] == true)
end

local function stage(): number?
	local data = ClientState.data
	if type(data) ~= "table" then
		return nil
	end
	return Unlocks.stageOf({
		ownsGarage = player:GetAttribute("OwnsGarage") == true,
		studioLevel = tonumber(data.studioLevel) or 1,
		gamesReleased = tonumber(data.gamesReleased) or 0,
		hitsReleased = tonumber(data.hitsReleased) or 0,
		rebirths = tonumber(data.rebirths) or 0,
	})
end

-- Условие авто-карточки выполнено сейчас (карточка без when — только по событию / из справочника)
local function conditionMet(guide: Guides.Guide): boolean
	local when = guide.when
	if not when then
		return false
	end
	local current = stage()
	if current == nil then
		return false
	end
	local data = ClientState.data :: any
	if when.stage and current < when.stage then
		return false
	end
	if when.games and (tonumber(data.gamesReleased) or 0) < when.games then
		return false
	end
	if when.feature and not FeatureGate.isOpen(when.feature) then
		return false
	end
	return true
end

-- Карточку можно открыть из справочника: прочитана или система уже доступна игроку
local function available(guide: Guides.Guide): boolean
	if isSeen(guide.id) then
		return true
	end
	if guide.menuSlot then
		local feature = Unlocks.menuFeature(guide.menuSlot)
		return feature == nil or FeatureGate.isOpen(feature)
	end
	return conditionMet(guide)
end

local function closeCard()
	if card then
		card:Destroy()
		card = nil
		cardGuide = nil
		cardMarks = false
		Ui.windowClosed()
	end
end

local function title(guide: Guides.Guide): string
	return guide.icon .. " " .. ClientState.t("guide_" .. guide.id .. "_title")
end

-- Карточка поверх всего. markSeen — первое знакомство (сервер запоминает по «Понятно»)
local function showCard(guide: Guides.Guide, markSeen: boolean)
	closeCard()
	shownThisSession[guide.id] = true
	lastShownAt = os.clock()
	PopupQueue.remove(QUEUE_KEY)

	local screen = Instance.new("ScreenGui")
	screen.Name = "GuideCard"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = CARD_ORDER
	screen.Parent = player:WaitForChild("PlayerGui")
	card = screen
	cardGuide = guide
	cardMarks = markSeen
	Ui.windowOpened()

	local window = Ui.window(screen, "Window", Vector2.new(CARD_WIDTH, 120 + 3 * LINE_HEIGHT + 70))
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(18, 14)
	body.Size = UDim2.new(1, -36, 1, -28)
	local layout = Ui.list(body, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	body.Parent = window

	local head = Ui.label(body, title(guide), 40, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	head.TextXAlignment = Enum.TextXAlignment.Center
	head.LayoutOrder = 1
	for i = 1, 3 do
		local line = Ui.label(
			body,
			"• " .. ClientState.t("guide_" .. guide.id .. "_" .. i),
			LINE_HEIGHT,
			Enum.Font.GothamMedium
		)
		line.TextScaled = false
		line.TextSize = 19
		line.TextWrapped = true
		line.TextYAlignment = Enum.TextYAlignment.Top
		line.LayoutOrder = 1 + i
	end
	local ok = Ui.button(body, ClientState.t("guide_ok"), Ui.colors.primary, function()
		if markSeen then
			GuideRemotes.GuideSeen:FireServer(guide.id)
		end
		closeCard()
	end)
	ok.Size = UDim2.new(0.55, 0, 0, 52)
	ok.LayoutOrder = 10
end

-- ===== Справочник =====

local function closeBook()
	if book then
		book:Destroy()
		book = nil
		Ui.windowClosed()
	end
end

local function openBook()
	closeBook()
	local screen = Instance.new("ScreenGui")
	screen.Name = "GuideBook"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = BOOK_ORDER
	screen.Parent = player:WaitForChild("PlayerGui")
	book = screen
	Ui.windowOpened(closeBook) -- окно меню: закрывает другое открытое окно меню

	local window = Ui.window(screen, "Window", Vector2.new(520, 560))
	local head = Ui.label(window, "📖 " .. ClientState.t("guide_book_title"), 40, Ui.titleFontFor(ClientState.lang))
	head.Position = UDim2.fromOffset(18, 10)
	head.Size = UDim2.new(1, -90, 0, 40)
	local x = Ui.button(window, "✕", Ui.colors.bad, closeBook)
	Ui.headerClose(x)
	local hint = Ui.label(window, ClientState.t("guide_book_hint"), 22, Enum.Font.GothamMedium, Ui.colors.muted)
	hint.Position = UDim2.fromOffset(18, 56)
	hint.Size = UDim2.new(1, -36, 0, 22)

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(14, 86)
	scroll.Size = UDim2.new(1, -28, 1, -100)
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	Ui.list(scroll, 6)
	scroll.Parent = window

	local count = 0
	for index, guide in Guides.list do
		if not available(guide) then
			continue
		end
		count += 1
		local fresh = not isSeen(guide.id)
		local text = title(guide) .. (if fresh then "  🆕" else "")
		local row = Ui.button(scroll, text, if fresh then Ui.colors.primary else Ui.colors.stroke, function()
			showCard(guide, fresh)
		end)
		row.Size = UDim2.new(1, -10, 0, 46)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = index
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.Parent = row
	end
	if count == 0 then
		local empty = Ui.label(scroll, ClientState.t("guide_book_empty"), 30, Enum.Font.GothamMedium, Ui.colors.muted)
		empty.TextXAlignment = Enum.TextXAlignment.Center
	end
end

-- ===== Когда показывать =====

local function quiet(): boolean
	return card ~= nil or player:GetAttribute("TutorialActive") == true
end

local function gapPassed(): boolean
	return os.clock() - lastShownAt >= Guides.autoGapSeconds
		and os.clock() - startedAt >= Guides.sessionDelaySeconds
end

-- Первая непрочитанная авто-карточка, условие которой выполнено (по порядку Guides.list)
local function nextAuto(): Guides.Guide?
	if readSeen() == nil then
		return nil
	end
	for _, guide in Guides.list do
		if guide.when and not isSeen(guide.id) and conditionMet(guide) then
			return guide
		end
	end
	return nil
end

local function pushAuto(guide: Guides.Guide)
	PopupQueue.push(QUEUE_KEY, function()
		-- Пока ждали очередь, могли прочитать в справочнике или показать другую
		if not quiet() and not isSeen(guide.id) then
			showCard(guide, true)
		end
	end)
end

local function tick()
	if quiet() or not gapPassed() then
		return
	end
	local guide = nextAuto()
	if guide then
		pushAuto(guide)
	end
end

local function onMenu(slot: number)
	if slot == Guides.bookSlot then
		return
	end
	local guide = Guides.forSlot(slot)
	if not guide or isSeen(guide.id) or readSeen() == nil or player:GetAttribute("TutorialActive") == true then
		return
	end
	-- После окна системы (оно открывается в этом же нажатии), чтобы карточка легла сверху
	task.defer(function()
		if not card then
			showCard(guide, true)
		end
	end)
end

function GuideController.start()
	Ui.menuButton(Guides.bookSlot, "📖", function()
		if book then
			closeBook()
		else
			openBook()
		end
	end, "menu_guides")
	Ui.menuClicked:Connect(onMenu)

	-- Приставы приходят редко и пугают: объясняем в момент прихода, без паузы между карточками
	player:GetAttributeChangedSignal("BailiffsActive"):Connect(function()
		local bailiffs = Guides.get("bailiffs")
		if bailiffs and player:GetAttribute("BailiffsActive") == true and not isSeen("bailiffs") then
			pushAuto(bailiffs)
		end
	end)

	ClientState.langChanged:Connect(function()
		local guide = cardGuide
		if guide then
			showCard(guide, cardMarks)
		end
		if book then
			openBook()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Guides.checkSeconds)
			local ok, err = pcall(tick)
			if not ok then
				warn("[GuideController] tick failed:", err)
			end
		end
	end)
end

return GuideController
