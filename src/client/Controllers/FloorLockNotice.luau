--!strict
-- Закрытый этаж у лифта (отчёт v71, №3: владелец не нашёл, как открыть 2-й этаж).
-- Лифт ничего не делал на подсказке с 🔒: теперь нажатие показывает карточку с условиями этажа
-- (деньги, игры, интерьер и столы — из Config/Stages и снимка окна «Студия»), с отметками ✓/✗,
-- кнопкой «Построить» (когда всё готово) и «Открыть Студию». Покупку проверяет сервер (tryBuy).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Features = require(Shared.Config.Features)
local Texts = require(Shared.Config.Texts)
local StudioLayout = require(Shared.StudioLayout)
local ClientState = require(script.Parent.Parent.ClientState)
local StudioState = require(script.Parent.Parent.StudioState)
local Ui = require(script.Parent.Parent.Ui)
local StudioWindow = require(script.Parent.StudioWindow)

local player = Players.LocalPlayer

local WINDOW_SIZE = Vector2.new(520, 400)
local COOLDOWN = 1.5 -- секунд: подсказка лифта нажимается быстро, окно не должно мигать
local MARK_OK, MARK_NO = "✓", "✗"

local FloorLockNotice = {}
local gui: ScreenGui? = nil
local lastShown = 0
local shownFloor = 0

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

local function onOwnPlot(instance: Instance): boolean
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild(tostring(player:GetAttribute("PlotName")))
	return plot ~= nil and instance:IsDescendantOf(plot)
end

-- Предложение переезда на этаж из снимка окна «Студия» (причина замка считает сервер)
local function stageOffer(level: number): StudioState.Offer?
	for _, offer in StudioState.state.offers do
		if offer.stage == level then
			return offer
		end
	end
	return nil
end

local function lockedByInterior(offer: StudioState.Offer?): boolean
	local lock = offer and offer.lock
	return lock == "studio_lock_interior" or lock == "studio_lock_staff"
end

local function line(parent: Instance, text: string, done: boolean?, order: number)
	local color = if done == true
		then Ui.colors.good
		elseif done == false then Ui.colors.text
		else Ui.colors.muted
	local label = Ui.label(parent, text, 40, Enum.Font.GothamMedium, color)
	label.TextWrapped = true
	Ui.minText(label, 14)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = order
end

local function show(floor: number, refresh: boolean)
	local stage = StudioLayout.floorStage(floor)
	local data = ClientState.data
	if not stage or not data then
		return
	end
	close()
	if not refresh then
		StudioState.request()
	end
	shownFloor = floor
	local screen = Instance.new("ScreenGui")
	screen.Name = "FloorLockNotice"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 22
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened(close)

	local window = Ui.window(screen, "Window", WINDOW_SIZE)
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	Ui.list(body, 8)
	body.Parent = window

	local floorName = StudioLayout.floorName(ClientState.lang, floor)
	local title = Ui.label(
		body,
		ClientState.t("floorlock_title", { floor = floorName }),
		40,
		Ui.titleFontFor(ClientState.lang),
		Ui.colors.money
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 1

	if not Features.stageReleased(stage.level) then
		-- Этаж выходит обновлением по средам (Config/Features): деньги и игры не помогут
		local soon = Ui.label(
			body,
			ClientState.t("upd_soon", { days = Features.daysUntil(Features.stages[stage.level]) }),
			30,
			Enum.Font.GothamMedium
		)
		soon.TextXAlignment = Enum.TextXAlignment.Center
		soon.LayoutOrder = 2
	else
		local cash = tonumber(data.cash) or 0
		local games = tonumber(data.gamesReleased) or 0
		local offer = stageOffer(stage.level)
		local enoughMoney = cash >= stage.cost
		local enoughGames = games >= stage.gamesRequired
		local interiorReady = offer ~= nil and not lockedByInterior(offer)
		line(
			body,
			ClientState.t("floorlock_money", {
				mark = if enoughMoney then MARK_OK else MARK_NO,
				have = Texts.money(cash),
				need = Texts.money(stage.cost),
			}),
			enoughMoney,
			2
		)
		line(
			body,
			ClientState.t("floorlock_games", {
				mark = if enoughGames then MARK_OK else MARK_NO,
				have = games,
				need = stage.gamesRequired,
			}),
			enoughGames,
			3
		)
		line(
			body,
			ClientState.t("floorlock_ready", { mark = if interiorReady then MARK_OK else MARK_NO }),
			interiorReady,
			4
		)
		line(body, ClientState.t("floorlock_where"), nil, 5)
		if offer and offer.lock == "build_lock_building" then
			line(body, "🏗️ " .. ClientState.t("build_lock_building"), nil, 6)
		end
	end

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 52)
	buttons.LayoutOrder = 60
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.Padding = UDim.new(0, 10)
	row.Parent = buttons
	buttons.Parent = body

	-- «Построить» — когда сервер не видит причин для замка и денег хватает; платит и проверяет сервер
	local offer = stageOffer(stage.level)
	local canBuild = Features.stageReleased(stage.level)
		and offer ~= nil
		and offer.lock == nil
		and (tonumber(data.cash) or 0) >= stage.cost
	if canBuild and offer then
		local build = Ui.button(
			buttons,
			ClientState.t("floorlock_build", { price = Texts.money(stage.cost) }),
			Ui.colors.good,
			function()
				close()
				Remotes.BuyUpgrade:FireServer(offer.id)
			end
		)
		build.Size = UDim2.new(0.5, 0, 1, 0)
	end
	local open = Ui.button(buttons, ClientState.t("floorlock_open"), Ui.colors.primary, function()
		close()
		StudioWindow.open()
	end)
	open.Size = UDim2.new(if canBuild then 0.3 else 0.6, 0, 1, 0)
	Ui.button(buttons, ClientState.t("create_close"), Ui.colors.locked, close).Size = UDim2.new(0.16, 0, 1, 0)
end

function FloorLockNotice.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt:GetAttribute("FloorArrow") ~= "🔒" or not onOwnPlot(prompt) then
			return
		end
		local floor = tonumber(prompt:GetAttribute("FloorTarget"))
		if not floor or os.clock() - lastShown < COOLDOWN then
			return
		end
		lastShown = os.clock()
		local ok, err = pcall(show, math.floor(floor), false)
		if not ok then
			warn("[FloorLockNotice] show failed:", err)
		end
	end)
	-- Ответ сервера с причиной замка пришёл (или купили/переехали): перерисовываем открытую карточку
	StudioState.changed:Connect(function()
		if not gui then
			return
		end
		if StudioLayout.floorsUnlocked(StudioState.state.studioLevel) >= shownFloor then
			close()
		else
			pcall(show, shownFloor, true)
		end
	end)
end

return FloorLockNotice
