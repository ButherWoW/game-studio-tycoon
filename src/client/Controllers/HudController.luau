--!strict
-- HUD: деньги, число игр, активная реклама, роялти, прогресс разработки (строка на каждый
-- проект, с кнопкой «⚡ Закончить»), тумблер «Авто-релиз» и кнопка «Создать игру».

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PaidRemotes = require(ReplicatedStorage.Shared.PaidRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local StudioState = require(script.Parent.Parent.StudioState)
local ClientState = require(script.Parent.Parent.ClientState)
local DevState = require(script.Parent.Parent.DevState)
local StaffPower = require(script.Parent.Parent.StaffPower)
local Ui = require(script.Parent.Parent.Ui)
local CreateGameWindow = require(script.Parent.CreateGameWindow)
local OfferClient = require(script.Parent.Parent.OfferClient)

local HudController = {}

local PLATE_WIDTH = Ui.HUD_PLATE_WIDTH -- боковое меню на тач-экране не заходит под плашки (Ui)
local ROW_HEIGHT = 40 -- шаг между плашками
local FIRST_PROGRESS_Y = 92
-- Переезд/пересборка комнаты: сервер заново сажает игрока за ПК — окно само не открываем
-- столько секунд (отчёт #2, п. 7)
local REBUILD_QUIET_SECONDS = 4

local function plate(parent: Instance, y: number): TextLabel
	local l = Ui.label(parent, "", 34, Ui.titleFontFor(ClientState.lang))
	l.TextXAlignment = Enum.TextXAlignment.Center
	-- Сверху по центру: слева окно чата Roblox (перекрывает HUD и забирает клики),
	-- справа список игроков с leaderstats
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Size = UDim2.fromOffset(PLATE_WIDTH, 34)
	l.Position = UDim2.new(0.5, 0, 0, y)
	l.BackgroundTransparency = 0.25
	l.BackgroundColor3 = Ui.colors.panel
	Ui.corner(l, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = l
	return l
end

type Row = { label: TextLabel, finish: TextButton, projectId: number? }
type Progress = { percent: number, paused: boolean, remaining: number? }

-- Купили заряд кнопкой «⚡ Закончить сейчас»: потратить его на этот проект, когда сервер выдаст
local FINISH_AFTER_PURCHASE_SECONDS = 60

function HudController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local cash = plate(gui, 12)
	cash.TextColor3 = Ui.colors.money
	local info = plate(gui, 52)
	-- Настроение команды (MoodService, атрибут TeamMood): только когда есть сотрудники;
	-- строки прогресса разработки тогда сдвигаются на строку ниже
	local mood = plate(gui, FIRST_PROGRESS_Y)
	mood.Visible = false
	-- Мощность команды (StaffPower) — пока идёт разработка и есть сотрудники: «👥 ⚡ +45% · ⭐ +0.4 · ☕ 2»
	local power = plate(gui, FIRST_PROGRESS_Y)
	power.Visible = false
	local function progressTop(): number
		return FIRST_PROGRESS_Y
			+ (if mood.Visible then ROW_HEIGHT else 0)
			+ (if power.Visible then ROW_HEIGHT else 0)
	end

	-- Прогресс по id проекта (из DevelopmentProgress)
	local progressById: { [number]: Progress } = {}
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
		finish.Position = UDim2.new(0.5, PLATE_WIDTH / 2 + 8, 0, y)
		finish.Size = UDim2.fromOffset(150, 34)
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
			row.finish.Position = UDim2.new(0.5, PLATE_WIDTH / 2 + 8, 0, y)
			if project and progress then
				row.label.Font = font
				local text: string
				if progress.paused then
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
				row.label.TextColor3 = if progress.paused then Ui.colors.bad else Ui.colors.text
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
		-- Плашки тренда/выставки — сразу под последней видимой строкой HUD
		Ui.setBannerTop(progressTop() + shown * ROW_HEIGHT + 2)
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
		cash.Font, info.Font = font, font

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
		cash.Text = (if shown < 0 then "-" else "")
			.. ClientState.t("hud_cash", { cash = Texts.money(math.abs(shown)):sub(2) })
		cash.TextColor3 = if shown < 0 then Ui.colors.bad else Ui.colors.money
		local line = ClientState.t("hud_games", { count = data.gamesReleased })
		if data.activeAd and data.activeAd.expiresAt > os.time() then
			line ..= "  ·  " .. ClientState.t("hud_ad", { percent = math.floor(data.activeAd.bonus * 100) })
		end
		if DevState.royaltyPerMinute > 0 then
			line ..= "  ·  " .. ClientState.t(
				"hud_royalty",
				{ amount = Texts.money(DevState.royaltyPerMinute) }
			)
		end
		-- Расходы студии (ExpensesService): зарплаты + аренда, и забастовка, если нечем платить
		local player = Players.LocalPlayer
		local expenses = tonumber(player:GetAttribute("ExpensesPerMinute")) or 0
		if expenses > 0 then
			line ..= "  ·  " .. ClientState.t("hud_expenses", { amount = Texts.money(expenses) })
		end
		local debt = tonumber(player:GetAttribute("LoanDebt")) or 0
		if debt > 0 then
			line ..= "  ·  " .. ClientState.t("hud_debt", { amount = Texts.money(debt) })
		end
		local strike = player:GetAttribute("StaffStrike") == true
		if strike then
			-- Плашка одна (ниже строки прогресса): пока бастуют — показываем только это
			line = ClientState.t("hud_strike")
		end
		info.Text = line
		info.TextColor3 = if strike then Ui.colors.bad else Ui.colors.text
		local moodValue = tonumber(player:GetAttribute("TeamMood"))
		local moodShown = moodValue ~= nil
		mood.Font = font
		if moodValue then
			mood.Text = ClientState.t("hud_mood", { value = moodValue })
			mood.TextColor3 = StudioState.moodColor(moodValue)
		end
		if mood.Visible ~= moodShown then
			mood.Visible = moodShown
			renderProgress()
		end
		local staffPower = StaffPower.power
		local powerShown = moodShown and staffPower ~= nil and #DevState.projects > 0
		power.Font = font
		power.Position = UDim2.new(0.5, 0, 0, FIRST_PROGRESS_Y + (if moodShown then ROW_HEIGHT else 0))
		if staffPower then
			power.Text = StaffPower.compact(staffPower)
			power.TextColor3 = if staffPower.breaks > 0 then Ui.colors.money else Ui.colors.text
		end
		if power.Visible ~= powerShown then
			power.Visible = powerShown
			renderProgress()
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
		progressById[data.id] = {
			percent = math.floor(data.progress * 100),
			paused = data.paused == true,
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
