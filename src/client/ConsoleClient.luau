--!strict
-- Своя консоль, платформы и стример на клиенте (ConsoleService, StreamerService): снимок с сервера,
-- строка «Платформа» в окне «Создать игру», вкладка «🎮 Консоль» окна «Студия» и строка
-- «🎥 Назначить стримером» в карточке сотрудника. Не контроллер: общий модуль окон.
-- Решения (цены, доля рынка, донаты) — на сервере, клиент только показывает и просит.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ConsoleRemotes = require(Shared.ConsoleRemotes)
local Console = require(Shared.Config.Console)
local Platforms = require(Shared.Config.Platforms)
local Employees = require(Shared.Config.Employees)
local Texts = require(Shared.Config.Texts)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local ROW_COLOR = Color3.fromRGB(44, 46, 66)
local ROW_HEIGHT = 72
local PICKER_HEIGHT = 40

local ConsoleClient = {}

ConsoleClient.state = { platforms = { pc = true }, console = {}, streamer = {} } :: any
-- Платформа следующей игры (сервер всё равно проверит, открыта ли она)
ConsoleClient.selectedPlatform = "pc"

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

ConsoleRemotes.ConsoleState.OnClientEvent:Connect(function(state: any)
	if type(state) ~= "table" then
		return
	end
	if type(state.platforms) ~= "table" then
		state.platforms = { pc = true }
	end
	ConsoleClient.state = state
	if not ConsoleClient.platformOpen(ConsoleClient.selectedPlatform) then
		ConsoleClient.selectedPlatform = "pc"
	end
	changed:Fire()
end)

function ConsoleClient.request()
	ConsoleRemotes.ConsoleRequest:FireServer()
end

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
	for i, id in Platforms.order do
		local open = ConsoleClient.platformOpen(id)
		local selected = ConsoleClient.selectedPlatform == id
		local def = Platforms.get(id)
		local caption = (if def then def.icon .. " " else "") .. ClientState.t("platform_" .. id)
		local b = Ui.button(
			row,
			if open then caption else "🔒 " .. caption,
			if selected then Ui.colors.good elseif open then Ui.colors.primary else Ui.colors.locked,
			function()
				if not open then
					showHint("🔒 " .. ClientState.t("platform_lock_" .. id))
					return
				end
				if ConsoleClient.selectedPlatform ~= id then
					ConsoleClient.selectedPlatform = id
					changed:Fire()
				end
			end
		)
		b.Size = UDim2.new(1 / #Platforms.order, -6, 1, 0)
		b.LayoutOrder = i
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

local function row(parent: Instance, order: number, icon: string, title: string, description: string): Frame
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
	return frame
end

local function rowButton(frame: Frame, caption: string, color: Color3, onClick: () -> ()): TextButton
	local b = Ui.button(frame, caption, color, onClick)
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -8, 0.5, 0)
	b.Size = UDim2.new(0.3, 0, 0, 44)
	return b
end

local function buildConsole(body: Instance, start: number): number
	local c = console()
	local order = start
	local function nextOrder(): number
		order += 1
		return order
	end
	Ui.label(body, ClientState.t("console_title"), 30, Ui.titleFontFor(ClientState.lang), Ui.colors.money).LayoutOrder =
		nextOrder()
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
	local done = tonumber(c.stage) or 0
	local cash = if ClientState.data then ClientState.data.cash else 0
	for i, stage in Console.stages do
		local title = ClientState.t("console_stage_" .. stage.id)
		local desc: string
		if i <= done then
			desc = ClientState.t("console_stage_done")
		elseif i == done + 1 and c.started == true then
			desc = ClientState.t(
				"console_stage_progress",
				{ progress = c.progress or 0, need = c.need or stage.games }
			)
		else
			desc = ClientState.t(
				"console_stage_desc",
				{ games = if i == done + 1 then c.need or stage.games else stage.games }
			)
		end
		local frame = row(body, nextOrder(), stage.icon, title, desc)
		if i <= done then
			rowButton(frame, "✓", Ui.colors.good, function() end)
		elseif i == done + 1 and c.started == true then
			rowButton(frame, "⏳", Ui.colors.primary, function() end)
		else
			local canStart = i == done + 1 and c.unlocked == true and cash >= stage.cost
			local b = rowButton(
				frame,
				Texts.money(stage.cost),
				if canStart then Ui.colors.money else Ui.colors.locked,
				function()
					if canStart then
						ConsoleRemotes.ConsoleStage:FireServer()
					end
				end
			)
			b.TextColor3 = if canStart then Color3.fromRGB(40, 30, 0) else Ui.colors.muted
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
		ConsoleRemotes.StreamerAssign:FireServer(false)
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
	if streamer().allowed ~= true then
		return
	end
	local isStreamer = ConsoleClient.streamerId() == employeeId
	local b = Ui.button(
		parent,
		if isStreamer then ClientState.t("streamer_unassign") else ClientState.t("streamer_assign"),
		if isStreamer then Ui.colors.locked else Ui.colors.primary,
		function()
			ConsoleRemotes.StreamerAssign:FireServer(if isStreamer then false else employeeId)
		end
	)
	b.Size = UDim2.new(1, 0, 0, 34)
	b.LayoutOrder = order
end

-- Пометка в строке сотрудника: «🎥 стримит»
function ConsoleClient.streamerTag(employeeId: string): string?
	return if ConsoleClient.streamerId() == employeeId then ClientState.t("streamer_tag") else nil
end

return ConsoleClient
