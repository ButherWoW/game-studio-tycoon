--!strict
-- HUD: верхняя строка (деньги + значки: фанаты студии, игры, реклама, роялти, расходы, долг, забастовка,
-- настроение, мощность команды; нажатие на значок — подсказка с полным текстом), прогресс
-- разработки (строка на каждый проект, с кнопкой «⚡ Закончить»), тумблер «Авто-релиз» и кнопка
-- «Создать игру». Плашки событий — в лотке справа (Ui.bannerStack, Config/Hud).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PaidRemotes = require(ReplicatedStorage.Shared.PaidRemotes)
local Hud = require(ReplicatedStorage.Shared.Config.Hud)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local StudioState = require(script.Parent.Parent.StudioState)
local ClientState = require(script.Parent.Parent.ClientState)
local DevState = require(script.Parent.Parent.DevState)
local StaffPower = require(script.Parent.Parent.StaffPower)
local Ui = require(script.Parent.Parent.Ui)
local CreateGameWindow = require(script.Parent.CreateGameWindow)
local OfferClient = require(script.Parent.Parent.OfferClient)

local HudController = {}

-- Верхняя строка сверху по центру (отзыв владельца 06.11: деньги, «Игр», настроение и мощность
-- были отдельными большими плашками и закрывали студию). Сверху слева чат Roblox, справа список
-- игроков; ScreenGui с ScreenInsets по умолчанию — y 0 уже под верхней панелью Roblox
local TOP_Y = 6
local BAR_HEIGHT = Hud.topBarHeight
local BAR_WIDTH = Ui.HUD_PLATE_WIDTH -- боковое меню на тач-экране не заходит под строку (Ui)
local CASH_TEXT = if Ui.touch then 22 else 24
local CHIP_TEXT = if Ui.touch then 15 else 16
local CHIP_HEIGHT = BAR_HEIGHT - 8
local CASH_SHORT_FROM = 100000000 -- деньги от $100 млн — коротко: «$123.4M»
-- Строки прогресса разработки — под верхней строкой, узкие
local PROGRESS_WIDTH = 300
local PROGRESS_HEIGHT = 26
local ROW_HEIGHT = PROGRESS_HEIGHT + 4 -- шаг между строками
local FIRST_PROGRESS_Y = TOP_Y + BAR_HEIGHT + 4
local FINISH_WIDTH = 130
-- Переезд/пересборка комнаты: сервер заново сажает игрока за ПК — окно само не открываем
-- столько секунд (отчёт #2, п. 7)
local REBUILD_QUIET_SECONDS = 4

local function plate(parent: Instance, y: number): TextLabel
	local l = Ui.label(parent, "", PROGRESS_HEIGHT, Ui.titleFontFor(ClientState.lang))
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Size = UDim2.fromOffset(PROGRESS_WIDTH, PROGRESS_HEIGHT)
	l.Position = UDim2.new(0.5, 0, 0, y)
	l.BackgroundTransparency = 0.25
	l.BackgroundColor3 = Ui.colors.panel
	Ui.corner(l, 8)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.Parent = l
	return l
end

-- Коротко для значков: $3 786, $12.3K, $4.5M, $1.2B
local function shortMoney(amount: number): string
	local a = math.abs(amount)
	local text: string
	if a >= 1e9 then
		text = string.format("%.1fB", a / 1e9)
	elseif a >= 1e6 then
		text = string.format("%.1fM", a / 1e6)
	elseif a >= 1e5 then
		text = string.format("%.0fK", a / 1e3)
	elseif a >= 1e4 then
		text = string.format("%.1fK", a / 1e3)
	else
		return Texts.money(a)
	end
	return "$" .. (string.gsub(text, "%.0([KMB])$", "%1"))
end

type Row = { label: TextLabel, finish: TextButton, projectId: number? }
type Progress = { percent: number, paused: boolean, remaining: number?, hintUntil: number? }
type Chip = { button: TextButton, detail: string }

-- Подсказка «Пауза — сядь за компьютер»: коротко (на PAUSE_HINT_SECONDS) и не чаще раза в
-- PAUSE_HINT_COOLDOWN секунд; в остальное время строка паузы выглядит как обычный прогресс
local PAUSE_HINT_SECONDS = 4
local PAUSE_HINT_COOLDOWN = 60

-- Купили заряд кнопкой «⚡ Закончить сейчас»: потратить его на этот проект, когда сервер выдаст
local FINISH_AFTER_PURCHASE_SECONDS = 60

function HudController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- ===== Верхняя строка: деньги и значки =====
	local bar = Instance.new("Frame")
	bar.Name = "TopBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, TOP_Y)
	bar.Size = UDim2.fromOffset(0, BAR_HEIGHT)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundColor3 = Ui.colors.panel
	bar.BackgroundTransparency = 0.25
	bar.ClipsDescendants = true
	Ui.corner(bar, 10)
	local barLimit = Instance.new("UISizeConstraint")
	barLimit.MaxSize = Vector2.new(BAR_WIDTH, BAR_HEIGHT)
	barLimit.Parent = bar
	local barPadding = Instance.new("UIPadding")
	barPadding.PaddingLeft = UDim.new(0, 10)
	barPadding.PaddingRight = UDim.new(0, 10)
	barPadding.Parent = bar
	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Padding = UDim.new(0, 6)
	barLayout.Parent = bar
	bar.Parent = gui

	local cash = Instance.new("TextLabel")
	cash.Name = "Cash"
	cash.BackgroundTransparency = 1
	cash.Size = UDim2.new(0, 0, 1, 0)
	cash.AutomaticSize = Enum.AutomaticSize.X
	cash.TextSize = CASH_TEXT
	cash.TextColor3 = Ui.colors.money
	cash.Font = Ui.titleFontFor(ClientState.lang)
	cash.Text = ""
	cash.LayoutOrder = 0
	cash.Parent = bar

	-- Подсказка под строкой: полный текст значка, пока не нажали ещё раз или Hud.popoverSeconds
	local popover = Ui.label(gui, "", 0)
	popover.Name = "Popover"
	popover.TextScaled = false
	popover.TextSize = 16
	popover.TextWrapped = true
	popover.TextXAlignment = Enum.TextXAlignment.Center
	popover.AnchorPoint = Vector2.new(0.5, 0)
	popover.Position = UDim2.new(0.5, 0, 0, TOP_Y + BAR_HEIGHT + 4)
	popover.Size = UDim2.fromOffset(PROGRESS_WIDTH, 0)
	popover.AutomaticSize = Enum.AutomaticSize.Y
	popover.BackgroundColor3 = Ui.colors.panel
	popover.BackgroundTransparency = 0.05
	popover.ZIndex = 5
	popover.Visible = false
	Ui.corner(popover, 8)
	local popoverPadding = Instance.new("UIPadding")
	popoverPadding.PaddingLeft = UDim.new(0, 8)
	popoverPadding.PaddingRight = UDim.new(0, 8)
	popoverPadding.PaddingTop = UDim.new(0, 5)
	popoverPadding.PaddingBottom = UDim.new(0, 5)
	popoverPadding.Parent = popover
	local popoverOwner: Chip? = nil
	local popoverToken = 0
	local function togglePopover(chip: Chip)
		popoverToken += 1
		if popover.Visible and popoverOwner == chip then
			popover.Visible = false
			popoverOwner = nil
			return
		end
		popoverOwner = chip
		popover.Font = Ui.bodyFont
		popover.Text = chip.detail
		popover.Visible = true
		local token = popoverToken
		task.delay(Hud.popoverSeconds, function()
			if popoverToken == token then
				popover.Visible = false
				popoverOwner = nil
			end
		end)
	end

	local function makeChip(name: string, order: number): Chip
		local b = Instance.new("TextButton")
		b.Name = name
		b.AutoButtonColor = true
		b.BackgroundColor3 = Ui.colors.stroke
		b.BackgroundTransparency = 0.35
		b.TextColor3 = Ui.colors.text
		b.Font = Ui.bodyFont
		b.TextSize = CHIP_TEXT
		b.Size = UDim2.fromOffset(0, CHIP_HEIGHT)
		b.AutomaticSize = Enum.AutomaticSize.X
		b.LayoutOrder = order
		b.Visible = false
		Ui.corner(b, 8)
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 6)
		padding.PaddingRight = UDim.new(0, 6)
		padding.Parent = b
		b.Parent = bar
		local chip: Chip = { button = b, detail = "" }
		b.Activated:Connect(function()
			togglePopover(chip)
		end)
		return chip
	end
	-- Фанаты студии (FansService, Config/Fans) — сразу за деньгами
	local fansChip = makeChip("Fans", 1)
	local gamesChip = makeChip("Games", 2)
	local strikeChip = makeChip("Strike", 3)
	local expensesChip = makeChip("Expenses", 4)
	local debtChip = makeChip("Debt", 5)
	local adChip = makeChip("Ad", 6)
	local royaltyChip = makeChip("Royalty", 7)
	-- Настроение команды (MoodService, атрибут TeamMood): только когда есть сотрудники
	local moodChip = makeChip("Mood", 8)
	-- Мощность команды (StaffPower) — пока идёт разработка и есть сотрудники
	local powerChip = makeChip("Power", 9)
	local function setChip(chip: Chip, shown: boolean, text: string?, detail: string?, color: Color3?)
		chip.button.Visible = shown
		if not shown then
			if popoverOwner == chip then
				popover.Visible = false
				popoverOwner = nil
			end
			return
		end
		chip.button.Text = text or ""
		chip.button.TextColor3 = color or Ui.colors.text
		chip.detail = detail or ""
		if popoverOwner == chip and popover.Visible then
			popover.Text = chip.detail
		end
	end

	-- Изменение фанатов последних релизов, пока окно релиза не раскрыло оценку
	local fansHidden = 0

	local function progressTop(): number
		return FIRST_PROGRESS_Y
	end

	-- Прогресс по id проекта (из DevelopmentProgress)
	local progressById: { [number]: Progress } = {}
	local lastPauseHint = -math.huge
	local rows: { Row } = {}
	local pendingFinish: { id: number, untilAt: number }? = nil

	local function usePendingFinish()
		local pending = pendingFinish
		if not pending or DevState.instantFinish <= 0 then
			return
		end
		pendingFinish = nil
		if os.clock() < pending.untilAt then
			PaidRemotes.InstantFinish:FireServer(pending.id)
		end
	end

	local function getRow(index: number): Row
		local row = rows[index]
		if row then
			return row
		end
		local y = progressTop() + (index - 1) * ROW_HEIGHT
		local label = plate(gui, y)
		label.Visible = false
		local newRow: Row
		local finish = Ui.button(gui, "", Ui.colors.money, function()
			local id = newRow.projectId
			if id and DevState.instantFinish > 0 then
				PaidRemotes.InstantFinish:FireServer(id)
			elseif id then
				-- Зарядов нет — предложение купить (Config/Offers.longDev) и сразу потратить
				OfferClient.buyInstantFinish(function()
					pendingFinish = { id = id, untilAt = os.clock() + FINISH_AFTER_PURCHASE_SECONDS }
					usePendingFinish()
				end)
			end
		end)
		finish.Name = "InstantFinishButton"
		finish.TextColor3 = Color3.fromRGB(40, 30, 0)
		finish.AnchorPoint = Vector2.new(0, 0)
		finish.Position = UDim2.new(0.5, PROGRESS_WIDTH / 2 + 6, 0, y)
		finish.Size = UDim2.fromOffset(FINISH_WIDTH, PROGRESS_HEIGHT)
		finish.Visible = false
		newRow = { label = label, finish = finish, projectId = nil }
		rows[index] = newRow
		return newRow
	end

	local function renderProgress()
		local font = Ui.titleFontFor(ClientState.lang)
		local list = DevState.projects
		local count = math.max(#list, #rows)
		local shown = 0
		for i = 1, count do
			local row = getRow(i)
			local project = list[i]
			local progress = project and progressById[project.id]
			row.projectId = if project then project.id else nil
			row.label.Visible = project ~= nil and progress ~= nil
			if row.label.Visible then
				shown = i
			end
			row.finish.Visible = false
			local y = progressTop() + (i - 1) * ROW_HEIGHT
			row.label.Position = UDim2.new(0.5, 0, 0, y)
			row.finish.Position = UDim2.new(0.5, PROGRESS_WIDTH / 2 + 6, 0, y)
			if project and progress then
				row.label.Font = font
				local text: string
				local showPause = progress.paused and os.clock() < (progress.hintUntil or 0)
				if showPause then
					text = ClientState.t("hud_paused")
				elseif #list > 1 then
					text = ClientState.t(
						"hud_developing_named",
						{ name = project.name, percent = progress.percent }
					)
				else
					text = ClientState.t("hud_developing", { percent = progress.percent })
				end
				row.label.Text = text
				row.label.TextColor3 = if showPause then Ui.colors.bad else Ui.colors.text
				-- «Мгновенно закончить» — только если есть заряды и не на ноутбуке в парке.
				-- Зарядов нет, а ждать ещё долго — «⚡ Закончить сейчас» за Robux
				local charges = DevState.instantFinish > 0
				local offer = not charges
					and not progress.paused
					and OfferClient.longDevOffer(progress.remaining)
				row.finish.Visible = (charges or offer) and not project.laptop
				row.finish.Text = if charges
					then ClientState.t("hud_instant_finish", { count = DevState.instantFinish })
					else OfferClient.longDevText()
				if offer and not project.laptop then
					OfferClient.trackOnce("longDev_" .. project.id, "longDev", "shown")
				end
			end
		end
		-- Полоса объявлений плашек (Ui.bannerStack) — под последней видимой строкой HUD
		Ui.setHudBottom(progressTop() + shown * ROW_HEIGHT)
	end

	local create = Ui.button(gui, ClientState.t("hud_create"), Ui.colors.money, function()
		-- Игру делают за компьютером: сначала сесть за свой стол
		if ClientState.atPc() then
			CreateGameWindow.open()
		end
	end)
	create.Name = "CreateGameButton" -- по имени его находит туториал
	create.TextColor3 = Color3.fromRGB(40, 30, 0)
	create.AnchorPoint = Vector2.new(0.5, 1)
	create.Position = UDim2.new(0.5, 0, 1, -24)
	create.Size = UDim2.fromOffset(260, 56)

	-- Тумблер геймпасса «Авто-релиз»: справа от «Создать игру»
	local autoRelease = Ui.button(gui, "", Ui.colors.panel, function()
		PaidRemotes.SetAutoRelease:FireServer(not DevState.autoReleaseOn)
	end)
	autoRelease.Name = "AutoReleaseToggle"
	autoRelease.AnchorPoint = Vector2.new(0, 1)
	autoRelease.Position = UDim2.new(0.5, 140, 1, -30)
	autoRelease.Size = UDim2.fromOffset(170, 44)
	autoRelease.Visible = false

	local function refresh()
		-- Язык мог смениться: тексты и шрифт, которые не зависят от данных
		local seated = ClientState.atPc()
		local slots = DevState.slots
		create.Text = if not seated
			then ClientState.t("hud_sit")
			elseif slots > 1 then ClientState.t(
				"hud_create_slots",
				{ busy = DevState.busy, slots = slots }
			)
			else ClientState.t("hud_create")
		create.BackgroundColor3 = if seated then Ui.colors.money else Ui.colors.locked
		create.TextColor3 = if seated then Color3.fromRGB(40, 30, 0) else Ui.colors.text
		local font = Ui.titleFontFor(ClientState.lang)
		cash.Font = font

		autoRelease.Visible = DevState.autoReleaseOwned
		autoRelease.Text = ClientState.t(if DevState.autoReleaseOn then "hud_auto_on" else "hud_auto_off")
		autoRelease.BackgroundColor3 = if DevState.autoReleaseOn then Ui.colors.good else Ui.colors.locked

		renderProgress()
		local data = ClientState.data
		if not data then
			return
		end
		-- Доход релиза появляется вместе с оценкой в окне релиза, а не раньше (отчёт #2, п. 6)
		-- Минус (долг, Config/Bailiffs) — красным: «-$ 4 200»
		local shown = ClientState.displayCash()
		local cashText = if math.abs(shown) >= CASH_SHORT_FROM
			then shortMoney(shown):sub(2)
			else Texts.money(math.abs(shown)):sub(2)
		cash.Text = (if shown < 0 then "-" else "") .. ClientState.t("hud_cash", { cash = cashText })
		cash.TextColor3 = if shown < 0 then Ui.colors.bad else Ui.colors.money
		-- Фанаты: «👥 12.3K», в подсказке — точное число и бонус к продажам (Formulas.fanMultiplier)
		-- Изменение за релиз прячем до раскрытия оценки (как деньги): иначе значок спойлерит оценку
		local fans = math.max(math.floor((tonumber(data.fans) or 0) - fansHidden), 0)
		local fansBonus = math.floor((Formulas.fanMultiplier(fans) - 1) * 100 + 0.5)
		setChip(
			fansChip,
			true,
			"👥 " .. shortMoney(fans):sub(2),
			ClientState.t("fans_hud", { count = Texts.money(fans):sub(2), percent = fansBonus }),
			Ui.colors.good
		)
		local games = ClientState.t("hud_games", { count = data.gamesReleased })
		setChip(gamesChip, true, "🎮 " .. tostring(data.gamesReleased), games)
		local adOn = data.activeAd ~= nil and data.activeAd.expiresAt > os.time()
		local adPercent = if adOn then math.floor(data.activeAd.bonus * 100) else 0
		setChip(adChip, adOn, "📣 +" .. adPercent .. "%", ClientState.t("hud_ad", { percent = adPercent }))
		local royalty = DevState.royaltyPerMinute
		setChip(
			royaltyChip,
			royalty > 0,
			"📚 +" .. shortMoney(royalty),
			ClientState.t("hud_royalty", { amount = Texts.money(royalty) }),
			Ui.colors.good
		)
		-- Расходы студии (ExpensesService): зарплаты + аренда, и забастовка, если нечем платить.
		-- Красным — когда в минус: забастовка, долг, деньги ниже нуля или расходы больше дохода
		-- в минуту (OfferClient.state.incomePerMinute — оценка сервера, + роялти)
		local player = Players.LocalPlayer
		local expenses = tonumber(player:GetAttribute("ExpensesPerMinute")) or 0
		local debt = tonumber(player:GetAttribute("LoanDebt")) or 0
		local strike = player:GetAttribute("StaffStrike") == true
		local income = OfferClient.state.incomePerMinute + royalty
		local losing = strike or debt > 0 or shown < 0 or (income > 0 and expenses > income)
		setChip(
			expensesChip,
			expenses > 0,
			"💸 −" .. shortMoney(expenses),
			ClientState.t("hud_expenses", { amount = Texts.money(expenses) }),
			if losing then Ui.colors.bad else Ui.colors.muted
		)
		local debtText = ClientState.t("hud_debt", { amount = Texts.money(debt) })
		setChip(debtChip, debt > 0, "🏦 " .. shortMoney(debt), debtText, Ui.colors.bad)
		setChip(strikeChip, strike, "⚠️", ClientState.t("hud_strike"), Ui.colors.bad)
		local moodValue = tonumber(player:GetAttribute("TeamMood"))
		if moodValue then
			setChip(
				moodChip,
				true,
				"😊 " .. moodValue .. "%",
				ClientState.t("hud_mood", { value = moodValue }),
				StudioState.moodColor(moodValue)
			)
		else
			setChip(moodChip, false)
		end
		local staffPower = StaffPower.power
		if moodValue ~= nil and staffPower ~= nil and #DevState.projects > 0 then
			setChip(
				powerChip,
				true,
				"⚡ " .. StaffPower.percent(staffPower.speed),
				StaffPower.compact(staffPower),
				if staffPower.breaks > 0 then Ui.colors.money else Ui.colors.text
			)
		else
			setChip(powerChip, false)
		end
		-- «Создать игру» доступна, пока есть свободный слот
		create.Visible = DevState.hasFreeSlot()
	end

	ClientState.changed:Connect(refresh)
	Players.LocalPlayer:GetAttributeChangedSignal("ExpensesPerMinute"):Connect(refresh)
	Players.LocalPlayer:GetAttributeChangedSignal("StaffStrike"):Connect(refresh)
	Players.LocalPlayer:GetAttributeChangedSignal("LoanDebt"):Connect(refresh)
	Players.LocalPlayer:GetAttributeChangedSignal("TeamMood"):Connect(refresh)
	StaffPower.changed:Connect(refresh)
	DevState.changed:Connect(function()
		-- Проекты, которых больше нет, забываем
		local alive: { [number]: boolean } = {}
		for _, project in DevState.projects do
			alive[project.id] = true
		end
		for id in progressById do
			if not alive[id] then
				progressById[id] = nil
			end
		end
		refresh()
		usePendingFinish()
	end)
	refresh()
	DevState.request()

	Remotes.DevelopmentProgress.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" or type(data.id) ~= "number" or type(data.progress) ~= "number" then
			return
		end
		local previous = progressById[data.id]
		local paused = data.paused == true
		local hintUntil = if previous then previous.hintUntil else nil
		-- Подсказка — только в момент, когда игрок отошёл, и не чаще раза в минуту
		if paused and not (previous and previous.paused) and os.clock() - lastPauseHint >= PAUSE_HINT_COOLDOWN then
			lastPauseHint = os.clock()
			hintUntil = lastPauseHint + PAUSE_HINT_SECONDS
			task.delay(PAUSE_HINT_SECONDS + 0.1, renderProgress)
		end
		progressById[data.id] = {
			percent = math.floor(data.progress * 100),
			paused = paused,
			hintUntil = hintUntil,
			-- Пауза (встал из-за ПК) не присылает остаток — держим последний
			remaining = if type(data.remaining) == "number"
				then data.remaining
				else (progressById[data.id] or {} :: any).remaining,
		}
		renderProgress()
	end)

	Remotes.GameReleased.OnClientEvent:Connect(function(released)
		if type(released) == "table" and type(released.projectId) == "number" then
			progressById[released.projectId] = nil
			renderProgress()
		end
		local delta = if type(released) == "table" then math.floor(tonumber(released.fansDelta) or 0) else 0
		if delta ~= 0 then
			fansHidden += delta
			refresh()
			ClientState.afterReveal(function()
				fansHidden -= delta
				refresh()
			end)
		end
	end)

	-- Переезд или пересборка комнаты: этап сменился или кресло, на котором сидел, удалено
	local quietUntil = 0
	local lastLevel: number? = nil
	ClientState.changed:Connect(function()
		local data = ClientState.data
		local level = data and tonumber(data.studioLevel)
		if level and lastLevel and level ~= lastLevel then
			quietUntil = os.clock() + REBUILD_QUIET_SECONDS
		end
		lastLevel = level or lastLevel
	end)
	local currentSeat: Instance? = nil
	local function seatPart(): Instance?
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return humanoid and humanoid.SeatPart
	end

	-- Сел за свой компьютер — сразу открываем «Создать игру»; встал — кнопка подсказывает сесть.
	-- Не открываем поверх другого окна (команда, магазин…) и сразу после переезда
	ClientState.seatChanged:Connect(function(seated: boolean)
		refresh()
		if not seated then
			local old = currentSeat
			currentSeat = nil
			task.defer(function()
				if old and not old:IsDescendantOf(workspace) then
					quietUntil = os.clock() + REBUILD_QUIET_SECONDS
				end
			end)
			return
		end
		currentSeat = seatPart()
		if os.clock() < quietUntil or Ui.anyWindowOpen() then
			return
		end
		if DevState.hasFreeSlot() then
			CreateGameWindow.open()
		end
	end)
end

return HudController
