--!strict
-- Окно «Команда» (3.3 + 3.5 + 3.7): найм, переезд студии, столы по этапам, легендарные,
-- навыки, перки и внешность сотрудников (кнопка ✏️), увольнение (два нажатия «Уволить»).
-- Клиент только показывает и просит; цену, этап, свободный стол и всё остальное проверяет сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StaffRemotes = require(ReplicatedStorage.Shared.StaffRemotes)
local Employees = require(ReplicatedStorage.Shared.Config.Employees)
local Skills = require(ReplicatedStorage.Shared.Config.Skills)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Expenses = require(ReplicatedStorage.Shared.Config.Expenses)
local StudioLayout = require(ReplicatedStorage.Shared.StudioLayout)
local ClientState = require(script.Parent.Parent.ClientState)
local StudioState = require(script.Parent.Parent.StudioState)
local Ui = require(script.Parent.Parent.Ui)

local MENU_SLOT = 2
local ROW_COLOR = Color3.fromRGB(44, 46, 66)
local DETAIL_COLOR = Color3.fromRGB(36, 38, 56)
local LOOK_FIELDS = { "shirt", "skin", "hat", "item" }
-- Мелкий текст карточек (роль, зарплата, условия этапа): фиксированный размер с переносом.
-- TextScaled ужимал длинную строку до 7–8 px (отчёт #2, п. 11)
local SMALL_TEXT = 16
local ROW_HEIGHT = 96
local STAGE_PANEL_HEIGHT = 132
local FIRE_CONFIRM_SECONDS = 5 -- сколько ждём второе нажатие «Уволить»

local TeamWindow = {}
local gui: ScreenGui? = nil
-- employeeId -> id стола ("" — ждёт стол), присылает сервер
local staff: { [string]: string } = {}
-- Навыки/перки/внешность и открытые легендарные — тоже с сервера
local info: { [string]: any } = {}
local unlocked: { [string]: boolean } = {}
local serverOffset = 0 -- os.time() сервера − клиента (перезарядка смены перка)
local expanded: string? = nil -- сотрудник, у которого открыта карточка ✏️
local scrollPosition = Vector2.zero
-- Первое нажатие «Уволить»: кого и когда (второе в течение FIRE_CONFIRM_SECONDS увольняет)
local fireArmed: string? = nil
local fireArmedAt = 0

local function studioLevel(data: any): number
	return math.clamp(tonumber(data.studioLevel) or 1, 1, #Stages)
end

-- Свободные столы на текущем этапе (для подсказки «Нет стола»)
local function deskCounts(data: any): (number, number)
	local desks = StudioLayout.visibleDesks(data.upgrades, studioLevel(data))
	local taken: { [string]: boolean } = {}
	for _, deskId in staff do
		taken[deskId] = true
	end
	local free = 0
	for _, desk in desks do
		if not taken[desk.id] then
			free += 1
		end
	end
	return free, #desks
end

local function upgradeName(id: string): string
	local upgrade = StudioLayout.get(id)
	if upgrade then
		local key = "upgrade_" .. upgrade.id
		return ClientState.localText(key, upgrade.name, Texts.en[key] or upgrade.name)
	end
	return id
end

local function specName(employee: Employees.Employee): string
	if employee.specialization then
		return ClientState.t("focus_" .. employee.specialization)
	end
	return ClientState.t("team_spec_all")
end

local render: () -> ()

local function buildStagePanel(parent: Instance, data: any, order: number)
	local panel = Instance.new("Frame")
	panel.BackgroundColor3 = ROW_COLOR
	panel.Size = UDim2.new(1, 0, 0, STAGE_PANEL_HEIGHT)
	panel.LayoutOrder = order
	Ui.corner(panel, 10)
	panel.Parent = parent

	local level = studioLevel(data)
	local current = Stages[level]
	local title = Ui.label(
		panel,
		ClientState.t("team_stage", { stage = ClientState.localName(current) }),
		28,
		Ui.titleFont
	)
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(1, -24, 0, 28)

	local nextStage = Stages[level + 1]
	if not nextStage then
		local done = Ui.label(panel, ClientState.t("team_max_stage"), 22, nil, Ui.colors.good)
		done.Position = UDim2.fromOffset(12, 40)
		done.Size = UDim2.new(1, -24, 0, 22)
		return
	end

	local parts = {}
	local ready = true
	if nextStage.requiresUpgrade then
		table.insert(
			parts,
			ClientState.t("team_req_upgrade", { name = upgradeName(nextStage.requiresUpgrade) })
		)
		ready = ready and data.upgrades[nextStage.requiresUpgrade] == true
	end
	if nextStage.gamesRequired > 0 then
		table.insert(
			parts,
			ClientState.t("team_req_games", { have = data.gamesReleased, need = nextStage.gamesRequired })
		)
		ready = ready and data.gamesReleased >= nextStage.gamesRequired
	end
	if nextStage.cost > 0 then
		table.insert(parts, ClientState.t("team_req_money", { price = Texts.money(nextStage.cost) }))
		ready = ready and data.cash >= nextStage.cost
	end
	local rent = Expenses.rentFor(nextStage.level)
	if rent > 0 then
		table.insert(parts, ClientState.t("team_rent", { amount = Texts.money(rent) }))
	end
	local line = ClientState.t("team_next", { stage = ClientState.localName(nextStage) })
	local nextLabel = Ui.label(panel, line .. "\n" .. table.concat(parts, " · "), 80, nil, Ui.colors.muted)
	-- Текст — в левых 60%, кнопка «Переезд» — в правых 35%: «Следующий этап…» не уходит
	-- под кнопку (отчёт #2, п. 13)
	nextLabel.TextScaled = false
	nextLabel.TextSize = SMALL_TEXT + 1
	nextLabel.TextWrapped = true
	nextLabel.TextYAlignment = Enum.TextYAlignment.Top
	nextLabel.ClipsDescendants = true
	nextLabel.Position = UDim2.fromOffset(12, 40)
	nextLabel.Size = UDim2.new(0.6, -12, 0, 84)

	local move = Ui.button(
		panel,
		ClientState.t("team_move"),
		if ready then Ui.colors.good else Ui.colors.locked,
		function()
			if ready then
				StaffRemotes.MoveStudio:FireServer()
			end
		end
	)
	move.AnchorPoint = Vector2.new(1, 0)
	move.Position = UDim2.new(1, -12, 0, 48)
	move.Size = UDim2.new(0.35, -12, 0, 48)
	if not ready then
		move.TextColor3 = Ui.colors.muted
	end
end

-- Столы по этапам: куплено / всего; прошлые этапы — «убраны» (сотрудники пересели)
local function buildDeskPanel(parent: Instance, data: any, order: number)
	local level = studioLevel(data)
	local lines = {}
	for _, stage in Stages do
		local bought, total = 0, 0
		for _, upgrade in Upgrades do
			if upgrade.desk and StudioLayout.deskStage(upgrade) == stage.level then
				total += 1
				if data.upgrades[upgrade.id] then
					bought += 1
				end
			end
		end
		local key = if stage.level < level
			then "team_desks_past"
			elseif stage.level == level then "team_desks_now"
			else "team_desks_future"
		table.insert(
			lines,
			ClientState.t(key, { stage = ClientState.localName(stage), bought = bought, total = total })
		)
	end
	local free, total = deskCounts(data)
	table.insert(lines, 1, ClientState.t("team_desks", { free = free, total = total }))
	local label = Ui.label(parent, table.concat(lines, "\n"), 22 * #lines, nil, Ui.colors.muted)
	label.TextScaled = false
	label.TextSize = 17
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.LayoutOrder = order
end

-- Настроение команды (MoodService): значение, цель и из чего сложилось — только при сотрудниках
local function buildMoodPanel(parent: Instance, order: number)
	local mood = StudioState.state.mood
	if not mood or not mood.active then
		return
	end
	local head = Ui.label(
		parent,
		ClientState.t("mood_title", { value = mood.value })
			.. "  "
			.. ClientState.t("mood_target", { value = mood.target }),
		28,
		Ui.titleFontFor(ClientState.lang),
		StudioState.moodColor(mood.value)
	)
	head.LayoutOrder = order
	local lines = StudioState.moodLines(mood)
	table.insert(lines, ClientState.t("mood_team_hint"))
	local label = Ui.label(parent, table.concat(lines, "\n"), 22 * #lines, nil, Ui.colors.muted)
	label.TextScaled = false
	label.TextSize = 17
	label.TextWrapped = true
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.LayoutOrder = order + 1
end

local function header(parent: Instance, text: string, order: number)
	local label = Ui.label(parent, text, 28, Ui.titleFont, Ui.colors.money)
	label.LayoutOrder = order
end

local function employeeLevel(employeeInfo: any): number
	local total = 0
	for _, key in Skills.keys do
		total += tonumber(employeeInfo.skills[key]) or 0
	end
	return total
end

local function smallButton(parent: Instance, text: string, color: Color3, onClick: () -> ()): TextButton
	local b = Ui.button(parent, text, color, onClick)
	if color == Ui.colors.locked then
		b.TextColor3 = Ui.colors.muted
	elseif color == Ui.colors.money then
		b.TextColor3 = Color3.fromRGB(40, 30, 0)
	end
	return b
end

-- Строка «название … кнопки справа» внутри карточки
local function detailLine(parent: Instance, text: string, order: number): Frame
	local line = Instance.new("Frame")
	line.BackgroundTransparency = 1
	line.Size = UDim2.new(1, 0, 0, 34)
	line.LayoutOrder = order
	line.Parent = parent
	local label = Ui.label(line, text, 24)
	label.Position = UDim2.fromOffset(0, 5)
	label.Size = UDim2.new(0.55, 0, 0, 24)
	return line
end

-- Карточка сотрудника: навыки (+), перки, внешность
local function buildDetails(parent: Instance, employee: Employees.Employee, data: any, order: number)
	local employeeInfo = info[employee.id]
	if type(employeeInfo) ~= "table" then
		return
	end
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = DETAIL_COLOR
	frame.Size = UDim2.new(1, -8, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	Ui.corner(frame, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame
	Ui.list(frame, 4)
	frame.Parent = parent

	local level = employeeLevel(employeeInfo)
	local n = 0
	local function nextOrder(): number
		n += 1
		return n
	end

	-- Навыки
	Ui.label(frame, ClientState.t("team_skills", { level = level }), 24, Ui.titleFont).LayoutOrder =
		nextOrder()
	for _, key in Skills.keys do
		local skill = tonumber(employeeInfo.skills[key]) or 0
		local dots = string.rep("●", skill) .. string.rep("○", Skills.maxLevel - skill)
		local line = detailLine(frame, ClientState.t("focus_" .. key) .. "  " .. dots, nextOrder())
		local text: string
		local color = Ui.colors.locked
		local price = 0
		if skill >= Skills.maxLevel then
			text = ClientState.t("team_skill_max")
		else
			price = Skills.skillCost(employee.stage, employee.legendary, skill)
			text = ClientState.t("team_skill_up", { price = Texts.money(price) })
			color = if data.cash >= price then Ui.colors.money else Ui.colors.locked
		end
		local button = smallButton(line, text, color, function()
			if skill < Skills.maxLevel and data.cash >= price then
				StaffRemotes.UpgradeSkill:FireServer(employee.id, key)
			end
		end)
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, 0, 0, 0)
		button.Size = UDim2.new(0.42, 0, 0, 32)
	end

	-- Перки
	local cooldownLeft = Skills.perkCooldown
		- ((os.time() + serverOffset) - (tonumber(employeeInfo.perkChangedAt) or 0))
	local changeCost = Skills.perkChangeCost(employee.stage, employee.legendary)
	Ui.label(frame, ClientState.t("team_perks"), 24, Ui.titleFont).LayoutOrder = nextOrder()
	for slot = 1, Skills.slots(employee.legendary) do
		local current = employeeInfo.perks[slot]
		local currentPerk = if type(current) == "string" then Skills.perk(current) else nil
		local slotText = ClientState.t("team_perk_slot", {
			n = slot,
			perk = if currentPerk
				then ClientState.localText("perk_" .. currentPerk.id, currentPerk.name, currentPerk.nameEn)
				else ClientState.t("team_perk_empty"),
		})
		local hint = if not currentPerk
			then ClientState.t("team_perk_free")
			elseif cooldownLeft > 0 then ClientState.t(
				"team_perk_cooldown",
				{ sec = math.ceil(cooldownLeft) }
			)
			else ClientState.t("team_perk_change", { price = Texts.money(changeCost) })
		local slotLabel = Ui.label(frame, slotText .. " · " .. hint, 22, nil, Ui.colors.muted)
		slotLabel.LayoutOrder = nextOrder()

		local grid = Instance.new("Frame")
		grid.BackgroundTransparency = 1
		grid.Size = UDim2.new(1, 0, 0, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.LayoutOrder = nextOrder()
		local layout = Instance.new("UIGridLayout")
		-- Два столбца: в четырёх описание перка ужималось до нечитаемого
		layout.CellSize = UDim2.new(0.5, -6, 0, 60)
		layout.CellPadding = UDim2.fromOffset(6, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid
		grid.Parent = frame
		for i, perk in Skills.perks do
			local name = ClientState.localText("perk_" .. perk.id, perk.name, perk.nameEn)
			local desc = ClientState.t("perk_" .. perk.id .. "_desc")
			local isCurrent = currentPerk ~= nil and currentPerk.id == perk.id
			local inOtherSlot = not isCurrent and table.find(employeeInfo.perks, perk.id) ~= nil
			local open = level >= perk.minLevel
			local canPay = currentPerk == nil or (cooldownLeft <= 0 and data.cash >= changeCost)
			local usable = open and not isCurrent and not inOtherSlot and canPay
			local text = if open
				then name .. "\n" .. desc
				else ClientState.t("team_perk_locked", { name = name, level = perk.minLevel })
			local color = if isCurrent
				then Ui.colors.good
				elseif usable then Ui.colors.primary
				else Ui.colors.locked
			local button = smallButton(grid, text, color, function()
				if usable then
					StaffRemotes.SetPerk:FireServer(employee.id, slot, perk.id)
				end
			end)
			button.LayoutOrder = i
		end
	end

	-- Внешность (бесплатно)
	Ui.label(frame, ClientState.t("team_look"), 24, Ui.titleFont).LayoutOrder = nextOrder()
	local limits: { [string]: { min: number, max: number } } = {
		shirt = { min = 0, max = #Skills.shirts },
		skin = { min = 1, max = #Skills.skins },
		hat = { min = 1, max = #Skills.hats },
		item = { min = 1, max = #Skills.items },
	}
	for _, field in LOOK_FIELDS do
		local value = tonumber(employeeInfo.look[field]) or limits[field].min
		local valueText: string
		if field == "shirt" then
			valueText = if value == 0 then ClientState.t("look_default") else tostring(value)
		elseif field == "skin" then
			valueText = tostring(value)
		elseif field == "hat" then
			valueText = ClientState.t("hat_" .. (Skills.hats[value] or "none"))
		else
			valueText = ClientState.t("item_" .. (Skills.items[value] or "none"))
		end
		local line = detailLine(frame, ClientState.t("look_" .. field) .. ": " .. valueText, nextOrder())
		-- Образец цвета у футболки и кожи
		if field == "shirt" or field == "skin" then
			local swatch = Instance.new("Frame")
			swatch.Size = UDim2.fromOffset(24, 24)
			swatch.AnchorPoint = Vector2.new(1, 0)
			swatch.Position = UDim2.new(1, -96, 0, 5)
			swatch.BackgroundColor3 = if field == "skin"
				then Skills.skins[value] or Skills.skins[1]
				elseif value > 0 then Skills.shirts[value]
				else Employees.shirtColors[employee.specialization or "all"]
			Ui.corner(swatch, 6)
			swatch.Parent = line
		end
		local span = limits[field].max - limits[field].min + 1
		for i, step in { -1, 1 } do
			local b = smallButton(line, if step < 0 then "◀" else "▶", Ui.colors.primary, function()
				local nextValue = (value - limits[field].min + step) % span + limits[field].min
				StaffRemotes.SetLook:FireServer(employee.id, field, nextValue)
			end)
			b.AnchorPoint = Vector2.new(1, 0)
			b.Position = UDim2.new(1, if i == 1 then -44 else 0, 0, 0)
			b.Size = UDim2.fromOffset(40, 32)
		end
	end
end

local function buildRow(
	parent: Instance,
	employee: Employees.Employee,
	data: any,
	freeDesks: number,
	anyDesk: boolean,
	order: number
)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = ROW_COLOR
	row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	row.LayoutOrder = order
	Ui.corner(row, 10)
	row.Parent = parent

	local swatch = Instance.new("Frame")
	local look = info[employee.id] and info[employee.id].look
	local shirt = if look and (tonumber(look.shirt) or 0) > 0 then Skills.shirts[look.shirt] else nil
	swatch.BackgroundColor3 = shirt or Employees.shirtColors[employee.specialization or "all"]
	swatch.Size = UDim2.new(0, 8, 1, -16)
	swatch.Position = UDim2.fromOffset(8, 8)
	Ui.corner(swatch, 4)
	swatch.Parent = row

	local name = Ui.label(
		row,
		ClientState.localText("employee_" .. employee.id, employee.name, employee.nameEn),
		26,
		Ui.titleFont
	)
	name.Position = UDim2.fromOffset(24, 6)
	name.Size = UDim2.new(0.62, -84, 0, 26)
	local role = ClientState.localText("employee_" .. employee.id .. "_role", employee.role, employee.roleEn)
	local details =
		ClientState.t("team_multiplier", { mult = employee.multiplier, spec = specName(employee) })
	-- Зарплата: у нанятого — с учётом вкачанных навыков, у кандидата — стартовая
	local employeeSkills = info[employee.id] and info[employee.id].skills
	details ..= " · " .. ClientState.t("team_salary", {
		amount = Texts.money(
			Expenses.salary(employee, if type(employeeSkills) == "table" then employeeSkills else nil)
		),
	})
	local deskId = staff[employee.id]
	if deskId == "" then
		details ..= " · " .. ClientState.t("team_waiting")
	elseif deskId then
		details ..= " · " .. ClientState.t("team_seated", { desk = upgradeName(deskId) })
	end
	local sub = Ui.label(row, role .. " · " .. details, 54, nil, Ui.colors.muted)
	sub.TextScaled = false
	sub.TextSize = SMALL_TEXT
	sub.TextWrapped = true
	sub.TextYAlignment = Enum.TextYAlignment.Top
	sub.ClipsDescendants = true
	sub.Position = UDim2.fromOffset(24, 36)
	sub.Size = UDim2.new(0.62, -84, 0, 54)

	local text: string
	local color = Ui.colors.locked
	local canHire = false
	if deskId then
		text, color = ClientState.t("team_hired"), Ui.colors.good
	elseif employee.legendary and not unlocked[employee.id] then
		-- Как получить: квест, геймпасс; без условия (robo) — «скоро»
		text = if employee.unlockReward
			then ClientState.t("team_how_ghost")
			elseif employee.unlockPass then ClientState.t("team_how_legend")
			else ClientState.t("team_soon")
	elseif studioLevel(data) < employee.stage then
		local stage = Stages[employee.stage]
		text = ClientState.t("team_locked", { stage = if stage then ClientState.localName(stage) else "?" })
	elseif freeDesks <= 0 and not (employee.legendary and anyDesk) then
		text = ClientState.t("team_no_desk")
	else
		text = if employee.cost <= 0
			then ClientState.t("team_hire_free")
			else ClientState.t("team_hire", { price = Texts.money(employee.cost) })
		canHire = data.cash >= employee.cost
		color = if canHire then Ui.colors.money else Ui.colors.locked
	end
	local button = Ui.button(row, text, color, function()
		if canHire then
			StaffRemotes.HireEmployee:FireServer(employee.id)
		end
	end)
	if deskId then
		-- Нанятый: сверху статус, снизу «Уволить»
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -60, 0, 6)
		button.Size = UDim2.new(0.38, -10, 0, 40)
	else
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		button.Size = UDim2.new(0.38, -10, 0, 44)
	end
	if canHire then
		button.TextColor3 = Color3.fromRGB(40, 30, 0)
	elseif color == Ui.colors.locked then
		button.TextColor3 = Ui.colors.muted
	end

	if deskId then
		local armed = fireArmed == employee.id and os.clock() - fireArmedAt <= FIRE_CONFIRM_SECONDS
		local refund = Employees.refundFor(employee)
		local fireText = if not armed
			then ClientState.t("team_fire")
			elseif refund > 0 then ClientState.t("team_fire_confirm", { price = Texts.money(refund) })
			else ClientState.t("team_fire_confirm_free")
		local fire = Ui.button(row, fireText, if armed then Ui.colors.bad else Ui.colors.locked, function()
			local now = os.clock()
			if fireArmed == employee.id and now - fireArmedAt <= FIRE_CONFIRM_SECONDS then
				fireArmed = nil
				StaffRemotes.FireEmployee:FireServer(employee.id)
				return
			end
			-- Первое нажатие: просим подтвердить; через FIRE_CONFIRM_SECONDS кнопка остывает
			fireArmed = employee.id
			fireArmedAt = now
			local stamp = now
			render()
			task.delay(FIRE_CONFIRM_SECONDS, function()
				if fireArmed == employee.id and fireArmedAt == stamp then
					fireArmed = nil
					render()
				end
			end)
		end)
		fire.AnchorPoint = Vector2.new(1, 0)
		fire.Position = UDim2.new(1, -60, 0, 50)
		fire.Size = UDim2.new(0.38, -10, 0, 40)

		local edit = Ui.button(
			row,
			"✏️",
			if expanded == employee.id then Ui.colors.primary else Ui.colors.panel,
			function()
				expanded = if expanded == employee.id then nil else employee.id
				render()
			end
		)
		edit.AnchorPoint = Vector2.new(1, 0.5)
		edit.Position = UDim2.new(1, -10, 0.5, 0)
		edit.Size = UDim2.fromOffset(44, 44)
		if expanded == employee.id then
			buildDetails(parent, employee, data, order + 1)
		end
	end
end

render = function()
	if not gui then
		return
	end
	local data = ClientState.data
	if not data then
		return
	end
	local old = gui:FindFirstChild("Window")
	if old then
		local oldBody = old:FindFirstChild("Body")
		if oldBody and oldBody:IsA("ScrollingFrame") then
			scrollPosition = oldBody.CanvasPosition
		end
		old:Destroy()
	end

	local window = Ui.window(gui, "Window", Vector2.new(680, 680))
	local title = Ui.label(window, ClientState.t("team_title"), 36, Ui.titleFont)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 36)
	local close = Ui.button(window, ClientState.t("create_close"), Ui.colors.locked, function()
		TeamWindow.close()
	end)
	close.Size = UDim2.fromOffset(40, 40)
	close.Position = UDim2.new(1, -52, 0, 8)

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(16, 56)
	body.Size = UDim2.new(1, -32, 1, -72)
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 6
	Ui.list(body, 8)
	body.Parent = window

	buildStagePanel(body, data, 1)
	buildDeskPanel(body, data, 2)
	buildMoodPanel(body, 3)
	local free, total = deskCounts(data)
	local anyDesk = total > 0
	-- Сотрудники по этапам, легендарные — отдельной группой в конце
	local order = 10
	for _, stage in Stages do
		local any = false
		for _, employee in Employees.list do
			if not employee.legendary and employee.stage == stage.level then
				if not any then
					header(body, ClientState.localName(stage), order)
					order += 10
					any = true
				end
				buildRow(body, employee, data, free, anyDesk, order)
				order += 10
			end
		end
	end
	header(body, ClientState.t("team_legendary"), order)
	order += 10
	for _, employee in Employees.list do
		if employee.legendary then
			buildRow(body, employee, data, free, anyDesk, order)
			order += 10
		end
	end
	task.defer(function()
		if body.Parent then
			body.CanvasPosition = scrollPosition
		end
	end)
end

function TeamWindow.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "TeamWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	scrollPosition = Vector2.zero
	Ui.windowOpened()
	render()
	StudioState.request()
end

function TeamWindow.close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

function TeamWindow.start()
	Ui.menuButton(MENU_SLOT, "👥", function()
		if gui then
			TeamWindow.close()
		else
			TeamWindow.open()
		end
	end, "menu_team")
	StaffRemotes.StaffChanged.OnClientEvent:Connect(function(newStaff: any, extra: any)
		if type(newStaff) ~= "table" then
			return
		end
		staff = newStaff
		if type(extra) == "table" then
			info = if type(extra.info) == "table" then extra.info else {}
			unlocked = if type(extra.unlocked) == "table" then extra.unlocked else {}
			if type(extra.now) == "number" then
				serverOffset = extra.now - os.time()
			end
		end
		if expanded and not staff[expanded] then
			expanded = nil
		end
		render()
	end)
	ClientState.changed:Connect(function()
		render()
	end)
	StudioState.changed:Connect(function()
		render()
	end)
end

return TeamWindow
