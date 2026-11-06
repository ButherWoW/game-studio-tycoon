--!strict
-- Своя консоль, платформы и стример на клиенте (ConsoleService, StreamerService): снимок с сервера,
-- строка «Платформа» в окне «Создать игру», вкладка «🎮 Консоль» окна «Студия» (цепочка этапов:
-- чек-лист оборудования и навыков, таймер с полосой, ускорение за Robux) и строка
-- «🎥 Назначить стримером» в карточке сотрудника. Не контроллер: общий модуль окон.
-- Решения (цены, доля рынка, донаты) — на сервере, клиент только показывает и просит.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
-- ConsoleRemotes грузим в своём потоке (ниже): модуль нужен HUD/«Создать игру», а require ждёт сервер
-- без таймаута (аудит P2-20). До загрузки запросы откладываются, кнопки ничего не шлют
local consoleRemotes: typeof(require(Shared.ConsoleRemotes))? = nil
local Console = require(Shared.Config.Console)
local Platforms = require(Shared.Config.Platforms)
local Features = require(Shared.Config.Features)
local Employees = require(Shared.Config.Employees)
local Texts = require(Shared.Config.Texts)
local UnlockRules = require(Shared.UnlockRules)
local Images = require(Shared.Config.Images)
local ArtIcon = require(script.Parent.ArtIcon)
local ClientState = require(script.Parent.ClientState)
local RobuxPrice = require(script.Parent.RobuxPrice)
local Ui = require(script.Parent.Ui)

local ROW_COLOR = Color3.fromRGB(44, 46, 66)
local ROW_HEIGHT = 72
local PICKER_HEIGHT = 40

local ConsoleClient = {}

ConsoleClient.state = { platforms = { pc = true }, console = {}, streamer = {} } :: any
-- Платформа следующей игры (сервер всё равно проверит, открыта ли она)
ConsoleClient.selectedPlatform = "pc"

-- Разница часов сервера и клиента (os.time), из последнего снимка: таймер этапа консоли
local clockOffset = 0

local changed = Instance.new("BindableEvent")
ConsoleClient.changed = changed.Event

local function console(): any
	local value = ConsoleClient.state.console
	return if type(value) == "table" then value else {}
end

local function streamer(): any
	local value = ConsoleClient.state.streamer
	return if type(value) == "table" then value else {}
end

function ConsoleClient.platformOpen(id: string): boolean
	local open = ConsoleClient.state.platforms
	return type(open) == "table" and open[id] == true
end

local function onState(state: any)
	if type(state) ~= "table" then
		return
	end
	if type(state.platforms) ~= "table" then
		state.platforms = { pc = true }
	end
	ConsoleClient.state = state
	local c = state.console
	if type(c) == "table" and type(c.now) == "number" then
		clockOffset = c.now - os.time()
	end
	if not ConsoleClient.platformOpen(ConsoleClient.selectedPlatform) then
		ConsoleClient.selectedPlatform = "pc"
	end
	changed:Fire()
end

local requestWanted = false
function ConsoleClient.request()
	local remotes = consoleRemotes
	if remotes then
		remotes.ConsoleRequest:FireServer()
	else
		requestWanted = true
	end
end

task.spawn(function()
	local remotes = require(Shared.ConsoleRemotes)
	consoleRemotes = remotes
	remotes.ConsoleState.OnClientEvent:Connect(onState)
	if requestWanted then
		requestWanted = false
		remotes.ConsoleRequest:FireServer()
	end
end)

-- Для перерисовки окна «Создать игру»: что поменялось в строке платформ
function ConsoleClient.key(): string
	local parts = { ConsoleClient.selectedPlatform }
	for _, id in Platforms.order do
		table.insert(parts, if ConsoleClient.platformOpen(id) then "1" else "0")
	end
	return table.concat(parts, ",")
end

function ConsoleClient.streamerId(): string?
	local id = streamer().employeeId
	return if type(id) == "string" then id else nil
end

local function employeeName(id: string): string
	local employee = Employees.get(id)
	if not employee then
		return id
	end
	return ClientState.localText("employee_" .. id, employee.name, employee.nameEn)
end

local function text(parent: Instance, value: string, order: number, color: Color3?)
	local label = Ui.label(parent, value, 22, Enum.Font.GothamMedium, color or Ui.colors.muted)
	label.TextScaled = false
	label.TextSize = 17
	label.TextWrapped = true
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, -8, 0, 22)
	label.LayoutOrder = order
end

-- ===== Окно «Создать игру»: строка платформ =====

-- Строка «Платформа» (LayoutOrder с order, занимает 3 места). showHint — причина замка крупно
function ConsoleClient.buildPicker(
	parent: Instance,
	order: number,
	genreId: string?,
	showHint: (string) -> ()
)
	Ui.label(parent, ClientState.t("platform_label"), 22, nil, Ui.colors.muted).LayoutOrder = order
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, PICKER_HEIGHT)
	row.LayoutOrder = order + 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	row.Parent = parent
	-- «Своя консоль» в строке — с обновлением «Своя консоль» (Config/Features); до него ПК и телефоны
	local shown: { string } = {}
	for _, id in Platforms.order do
		local def = Platforms.get(id)
		if not (def and def.needsConsole) or Features.isReleased("platforms") then
			table.insert(shown, id)
		end
	end
	for i, id in shown do
		local open = ConsoleClient.platformOpen(id)
		local selected = ConsoleClient.selectedPlatform == id
		local def = Platforms.get(id)
		-- Иконка Астры (Images.platforms, V23) вместо эмодзи платформы; 0 — эмодзи как раньше
		local imageId = Images.platforms[id] or 0
		local caption = (if def and imageId <= 0 then def.icon .. " " else "")
			.. ClientState.t("platform_" .. id)
		local b = Ui.button(
			row,
			if open then caption else "🔒 " .. caption,
			if selected then Ui.colors.good elseif open then Ui.colors.primary else Ui.colors.locked,
			function()
				if not open then
					-- Платформа с условием (телефоны) — причина из UnlockRules, иначе готовый текст
					local reason: string? = nil
					if def and def.requires then
						local item: any = { requires = def.requires }
						reason = UnlockRules.firstReason(ClientState.lang, item, ClientState.data)
					end
					showHint(
						if reason
							then ClientState.t("platform_" .. id) .. " · " .. reason
							else "🔒 " .. ClientState.t("platform_lock_" .. id)
					)
					return
				end
				if ConsoleClient.selectedPlatform ~= id then
					ConsoleClient.selectedPlatform = id
					changed:Fire()
				end
			end
		)
		b.Size = UDim2.new(1 / #shown, -6, 1, 0)
		b.LayoutOrder = i
		ArtIcon.prefix(b, "", imageId, PICKER_HEIGHT - 12)
		if not open then
			b.TextColor3 = Ui.colors.muted
		end
	end
	-- Что даёт выбранная платформа в выбранном жанре
	local platform = Platforms.get(ConsoleClient.selectedPlatform)
	if platform and genreId and platform.id ~= "pc" then
		local mult = Platforms.genreMultiplier(platform, genreId)
		if platform.needsConsole then
			mult *= 1 + (tonumber(console().share) or 0) * Console.shareRevenueBonus
		end
		local info = ClientState.t("platform_info", { mult = string.format("%.2f", mult) })
		if platform.scoreBonus > 0 then
			info ..= " · " .. ClientState.t("platform_bonus", { bonus = platform.scoreBonus })
		end
		local label = Ui.label(
			parent,
			info,
			20,
			Enum.Font.GothamMedium,
			if mult >= 1 then Ui.colors.good else Ui.colors.bad
		)
		label.LayoutOrder = order + 2
	end
end

-- ===== Окно «Студия»: вкладка «🎮 Консоль» =====

local function row(
	parent: Instance,
	order: number,
	icon: string,
	title: string,
	description: string
): (Frame, TextLabel, TextLabel)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = ROW_COLOR
	frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	frame.LayoutOrder = order
	Ui.corner(frame, 10)
	local iconLabel = Ui.label(frame, icon, ROW_HEIGHT, Ui.titleFont)
	iconLabel.Size = UDim2.new(0, 56, 1, 0)
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	local titleLabel = Ui.label(frame, title, 26, Ui.titleFontFor(ClientState.lang))
	titleLabel.Position = UDim2.fromOffset(60, 8)
	titleLabel.Size = UDim2.new(0.66, -64, 0, 26)
	local descLabel = Ui.label(frame, description, 20, Enum.Font.GothamMedium, Ui.colors.muted)
	descLabel.Position = UDim2.fromOffset(60, 40)
	descLabel.Size = UDim2.new(0.66, -64, 0, 20)
	frame.Parent = parent
	return frame, iconLabel, descLabel
end

local function rowButton(frame: Frame, caption: string, color: Color3, onClick: () -> ()): TextButton
	local b = Ui.button(frame, caption, color, onClick)
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -8, 0.5, 0)
	b.Size = UDim2.new(0.3, 0, 0, 44)
	return b
end

-- ===== Таймер этапа: живой отсчёт без пересборки окна =====

local timers: { { label: TextLabel, bar: Frame, endsAt: number, duration: number, name: string? } } = {}

local function clock(seconds: number): string
	local s = math.max(math.floor(seconds), 0)
	local h = s // 3600
	local m = (s % 3600) // 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s % 60)
	end
	return string.format("%d:%02d", m, s % 60)
end

local function secondsLeft(endsAt: number): number
	return math.max(endsAt - (os.time() + clockOffset), 0)
end

local function updateTimer(timer: any)
	local left = secondsLeft(timer.endsAt)
	timer.label.Text = if timer.name
		then ClientState.t("cons_running", { time = clock(left), name = timer.name })
		else ClientState.t("cons_running_solo", { time = clock(left) })
	local done = if timer.duration > 0 then 1 - left / timer.duration else 1
	timer.bar.Size = UDim2.fromScale(math.clamp(done, 0, 1), 1)
end

task.spawn(function()
	while true do
		task.wait(1)
		for i = #timers, 1, -1 do
			local timer = timers[i]
			if timer.label.Parent == nil then
				table.remove(timers, i)
			else
				updateTimer(timer)
			end
		end
	end
end)

-- Кнопка «👥 Команда» в чек-листе: окно «Команда» подписывается (TeamWindow.start)
local openTeam = Instance.new("BindableEvent")
ConsoleClient.openTeamRequested = openTeam.Event

local function skillName(skill: string): string
	return ClientState.t("focus_" .. skill)
end

local function equipmentName(item: any): string
	return item.icon .. " " .. ClientState.t("cons_equip_" .. item.id)
end

local equipmentById: { [string]: any } = {}
for _, item in Console.equipment do
	equipmentById[item.id] = item
end

-- Строка чек-листа: текст слева, необязательная кнопка справа
local function checkLine(
	parent: Instance,
	order: number,
	value: string,
	good: boolean,
	button: { caption: string, color: Color3, onClick: () -> () }?
)
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, -8, 0, 36)
	frame.LayoutOrder = order
	local label =
		Ui.label(frame, value, 36, Enum.Font.GothamMedium, if good then Ui.colors.good else Ui.colors.bad)
	label.TextScaled = false
	label.TextSize = 16
	label.TextWrapped = true
	label.Position = UDim2.fromOffset(12, 0)
	label.Size = UDim2.new(if button then 0.7 else 1, -16, 1, 0)
	if button then
		local b = Ui.button(frame, button.caption, button.color, button.onClick)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -8, 0.5, 0)
		b.Size = UDim2.new(0.28, 0, 0, 32)
	end
	frame.Parent = parent
end

local function buyEquipmentButton(
	item: any,
	cash: number,
	free: boolean
): { caption: string, color: Color3, onClick: () -> () }
	local affordable = free or cash >= item.cost
	return {
		caption = Texts.money(item.cost),
		color = if affordable then Ui.colors.money else Ui.colors.locked,
		onClick = function()
			if affordable then
				local remotes = consoleRemotes
				if remotes then
					remotes.ConsoleEquip:FireServer(item.id)
				end
			end
		end,
	}
end

local function prompt(productId: number)
	if productId > 0 then
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
	end
end

-- Ускорение за Robux: −5 мин, −30 мин (скрыт, если осталось ≤ 5 мин), завершить этап
local function speedPicker(parent: Instance, order: number, left: number)
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, -8, 0, PICKER_HEIGHT)
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	local shown = {}
	for _, item in Console.speedups do
		if item.seconds == nil or item.seconds < 30 * 60 or left > Console.speed30MinLeft then
			table.insert(shown, item)
		end
	end
	for i, item in shown do
		local soon = item.productId <= 0
		local caption = ClientState.t("cons_speed_" .. item.id)
			.. " · "
			.. (
				if soon
					then ClientState.t("shop_soon")
					else "R$" .. RobuxPrice.of(item.productId, item.robuxPrice)
			)
		local b = Ui.button(frame, caption, if soon then Ui.colors.locked else Ui.colors.good, function()
			prompt(item.productId)
		end)
		b.Size = UDim2.new(1 / #shown, -6, 1, 0)
		b.LayoutOrder = i
	end
	frame.Parent = parent
end

local function buildConsole(body: Instance, start: number): number
	local c = console()
	local order = start
	local function nextOrder(): number
		order += 1
		return order
	end
	local heading =
		Ui.label(body, ClientState.t("console_title"), 30, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	heading.LayoutOrder = nextOrder()
	ArtIcon.prefix(heading, "🎮", Images.platforms.console, 28)
	if c.launched == true then
		text(
			body,
			ClientState.t("console_launched", { share = string.format("%.1f", tonumber(c.share) or 0) }),
			nextOrder(),
			Ui.colors.good
		)
		text(
			body,
			ClientState.t("console_royalty", {
				amount = Texts.money(tonumber(c.royaltyPerMinute) or 0),
				license = Texts.money(tonumber(c.licensePerMinute) or 0),
			}),
			nextOrder(),
			Ui.colors.money
		)
		text(
			body,
			ClientState.t("console_earned", { amount = Texts.money(tonumber(c.earned) or 0) }),
			nextOrder()
		)
		text(body, ClientState.t("console_share_hint"), nextOrder())
		return order
	end
	if c.unlocked ~= true then
		text(body, ClientState.t("console_locked"), nextOrder())
	end
	text(body, ClientState.t("cons_chain_hint"), nextOrder())
	local credit = tonumber(c.credit) or 0
	local skips = tonumber(c.skips) or 0
	if credit > 0 or skips > 0 then
		text(
			body,
			ClientState.t("cons_credit", { minutes = math.floor(credit / 60), skips = skips }),
			nextOrder(),
			Ui.colors.good
		)
	end
	local done = tonumber(c.stage) or 0
	local isRunning = c.running == true
	local cash = if ClientState.data then ClientState.data.cash else 0
	local free = c.free == true
	local owned = if type(c.equipment) == "table" then c.equipment else {}
	local check = if type(c.nextStage) == "table" then c.nextStage else nil
	local total = #Console.stages
	for i, stage in Console.stages do
		local title = string.format("%d/%d %s", i, total, ClientState.t("cons_stage_" .. stage.id))
		local isNext = i == done + 1
		local info = ClientState.t("cons_info", {
			minutes = stage.minutes,
			skill = if stage.skill then skillName(stage.skill) else "",
			level = stage.level,
		})
		local desc = if i <= done then ClientState.t("cons_done") else info
		local frame, iconLabel, descLabel = row(body, nextOrder(), stage.icon, title, desc)
		ArtIcon.replace(iconLabel, Images.consoleStages[stage.id] or 0)
		if i <= done then
			rowButton(frame, "✓", Ui.colors.good, function() end)
		elseif isNext and isRunning then
			rowButton(frame, "⏳", Ui.colors.primary, function() end)
			-- Полоса прогресса по низу строки
			local track = Instance.new("Frame")
			track.BackgroundColor3 = Color3.fromRGB(28, 30, 44)
			track.BorderSizePixel = 0
			track.Position = UDim2.new(0, 60, 1, -10)
			track.Size = UDim2.new(0.66, -64, 0, 6)
			Ui.corner(track, 3)
			track.Parent = frame
			local bar = Instance.new("Frame")
			bar.BackgroundColor3 = Ui.colors.good
			bar.BorderSizePixel = 0
			bar.Size = UDim2.fromScale(0, 1)
			Ui.corner(bar, 3)
			bar.Parent = track
			descLabel.Position = UDim2.fromOffset(60, 34)
			local timer = {
				label = descLabel,
				bar = bar,
				endsAt = tonumber(c.endsAt) or 0,
				duration = tonumber(c.duration) or 0,
				name = if type(c.worker) == "string" then employeeName(c.worker) else nil,
			}
			updateTimer(timer)
			table.insert(timers, timer)
			text(body, ClientState.t("cons_speed_hint"), nextOrder())
			speedPicker(body, nextOrder(), secondsLeft(timer.endsAt))
		elseif isNext and check then
			local canStart = c.unlocked == true and check.ready == true and (free or cash >= stage.cost)
			local b = rowButton(
				frame,
				Texts.money(stage.cost),
				if canStart then Ui.colors.money else Ui.colors.locked,
				function()
					if canStart then
						local remotes = consoleRemotes
						if remotes then
							remotes.ConsoleStage:FireServer()
						end
					end
				end
			)
			b.TextColor3 = if canStart then Color3.fromRGB(40, 30, 0) else Ui.colors.muted
			-- Чек-лист: оборудование, сотрудник, деньги
			for _, id in stage.equipment do
				local item = equipmentById[id]
				if item then
					local have = owned[id] == true
					checkLine(
						body,
						nextOrder(),
						ClientState.t(
							if have then "cons_check_equip_ok" else "cons_check_equip_no",
							{ name = equipmentName(item) }
						),
						have,
						if have or c.unlocked ~= true then nil else buyEquipmentButton(item, cash, free)
					)
				end
			end
			if stage.skill then
				local team = {
					caption = ClientState.t("cons_team"),
					color = Ui.colors.primary,
					onClick = function()
						openTeam:Fire()
					end,
				}
				local vars = {
					skill = skillName(stage.skill),
					level = stage.level,
					have = tonumber(check.bestLevel) or 0,
					name = "",
				}
				if type(check.workerId) == "string" then
					vars.name = employeeName(check.workerId)
					checkLine(body, nextOrder(), ClientState.t("cons_check_skill_ok", vars), true)
				elseif check.skillOk == true then
					-- Studio: навыки не требуются
					checkLine(body, nextOrder(), "✅ " .. skillName(stage.skill), true)
				elseif type(check.bestId) == "string" then
					vars.name = employeeName(check.bestId)
					checkLine(body, nextOrder(), ClientState.t("cons_check_skill_no", vars), false, team)
				else
					checkLine(body, nextOrder(), ClientState.t("cons_check_skill_none", vars), false, team)
				end
			end
			if not free and cash < stage.cost then
				checkLine(
					body,
					nextOrder(),
					ClientState.t("cons_check_cash", { price = Texts.money(stage.cost) }),
					false
				)
			end
		else
			local b = rowButton(frame, "🔒", Ui.colors.locked, function() end)
			b.TextColor3 = Ui.colors.muted
		end
	end
	-- Всё оборудование: можно купить заранее, стоит на 3-м этаже
	Ui.label(
		body,
		ClientState.t("cons_equipment_title"),
		26,
		Ui.titleFontFor(ClientState.lang),
		Ui.colors.money
	).LayoutOrder =
		nextOrder()
	for _, item in Console.equipment do
		local have = owned[item.id] == true
		local usedBy = {}
		for _, stage in Console.stages do
			if table.find(stage.equipment, item.id) then
				table.insert(usedBy, ClientState.t("cons_stage_" .. stage.id))
			end
		end
		local frame = row(
			body,
			nextOrder(),
			item.icon,
			ClientState.t("cons_equip_" .. item.id),
			if have
				then ClientState.t("cons_equip_owned")
				else ClientState.t("cons_equip_for", { stages = table.concat(usedBy, ", ") })
		)
		if have then
			rowButton(frame, "✓", Ui.colors.good, function() end)
		elseif c.unlocked == true then
			local buy = buyEquipmentButton(item, cash, free)
			local b = rowButton(frame, buy.caption, buy.color, buy.onClick)
			b.TextColor3 = if buy.color == Ui.colors.money then Color3.fromRGB(40, 30, 0) else Ui.colors.muted
		else
			local b = rowButton(frame, "🔒", Ui.colors.locked, function() end)
			b.TextColor3 = Ui.colors.muted
		end
	end
	return order
end

local function buildStreamer(body: Instance, start: number)
	local s = streamer()
	local order = start
	local function nextOrder(): number
		order += 1
		return order
	end
	Ui.label(body, ClientState.t("streamer_title"), 30, Ui.titleFontFor(ClientState.lang), Ui.colors.money).LayoutOrder =
		nextOrder()
	if s.allowed ~= true then
		text(body, ClientState.t("streamer_locked"), nextOrder())
		return
	end
	local id = ConsoleClient.streamerId()
	if not id then
		text(body, ClientState.t("streamer_none"), nextOrder())
		text(body, ClientState.t("streamer_hint"), nextOrder())
		return
	end
	local frame = row(
		body,
		nextOrder(),
		"🎥",
		ClientState.t("streamer_info", { name = employeeName(id) }),
		ClientState.t("streamer_hype", { hype = s.hype or 0, bonus = s.hypeBonus or 0 })
	)
	rowButton(frame, ClientState.t("streamer_unassign"), Ui.colors.locked, function()
		local remotes = consoleRemotes
		if remotes then
			remotes.StreamerAssign:FireServer(false)
		end
	end)
	if s.strike == true then
		text(body, ClientState.t("streamer_strike"), nextOrder(), Ui.colors.bad)
	end
	text(
		body,
		ClientState.t("streamer_income", {
			amount = Texts.money(tonumber(s.perMinute) or 0),
			earned = Texts.money(tonumber(s.earned) or 0),
		}),
		nextOrder(),
		Ui.colors.money
	)
	text(body, ClientState.t("streamer_hint"), nextOrder())
end

-- Содержимое вкладки «🎮 Консоль» в прокрутке окна «Студия»
function ConsoleClient.buildTab(body: Instance)
	local order = buildConsole(body, 0)
	buildStreamer(body, order + 10)
end

-- ===== Окно «Команда»: строка в карточке сотрудника =====

function ConsoleClient.streamerButton(parent: Instance, employeeId: string, order: number)
	if streamer().allowed ~= true or not Features.isReleased("streamer") then
		return
	end
	local isStreamer = ConsoleClient.streamerId() == employeeId
	local b = Ui.button(
		parent,
		if isStreamer then ClientState.t("streamer_unassign") else ClientState.t("streamer_assign"),
		if isStreamer then Ui.colors.locked else Ui.colors.primary,
		function()
			local remotes = consoleRemotes
			if remotes then
				remotes.StreamerAssign:FireServer(if isStreamer then false else employeeId)
			end
		end
	)
	b.Size = UDim2.new(1, 0, 0, 34)
	b.LayoutOrder = order
end

-- Пометка в строке сотрудника: «🎥 стримит»
function ConsoleClient.streamerTag(employeeId: string): string?
	if not Features.isReleased("streamer") then
		return nil
	end
	return if ConsoleClient.streamerId() == employeeId then ClientState.t("streamer_tag") else nil
end

return ConsoleClient
