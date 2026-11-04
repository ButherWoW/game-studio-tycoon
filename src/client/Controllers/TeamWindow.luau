--!strict
-- Окно «Команда» (3.3 + 3.5): найм сотрудников и переезд студии.
-- Клиент только показывает и просит; цену, этап, свободный стол проверяет сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StaffRemotes = require(ReplicatedStorage.Shared.StaffRemotes)
local Employees = require(ReplicatedStorage.Shared.Config.Employees)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local MENU_SLOT = 2
local ROW_COLOR = Color3.fromRGB(44, 46, 66)

local TeamWindow = {}
local gui: ScreenGui? = nil
-- employeeId -> id стола (апгрейда), присылает сервер
local staff: { [string]: string } = {}

local function deskCounts(data: any): (number, number)
	local total = 0
	for _, upgrade in Upgrades do
		if upgrade.desk == true and data.upgrades[upgrade.id] then
			total += 1
		end
	end
	local used = 0
	for _ in staff do
		used += 1
	end
	return math.max(total - used, 0), total
end

local function upgradeName(id: string): string
	for _, upgrade in Upgrades do
		if upgrade.id == id then
			return ClientState.localText("upgrade_" .. upgrade.id, upgrade.name, upgrade.name)
		end
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
	panel.Size = UDim2.new(1, 0, 0, 96)
	panel.LayoutOrder = order
	Ui.corner(panel, 10)
	panel.Parent = parent

	local level = math.clamp(tonumber(data.studioLevel) or 1, 1, #Stages)
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
	local line = ClientState.t("team_next", { stage = ClientState.localName(nextStage) })
	local info = Ui.label(panel, line .. "\n" .. table.concat(parts, " · "), 44, nil, Ui.colors.muted)
	info.Position = UDim2.fromOffset(12, 40)
	info.Size = UDim2.new(0.65, -12, 0, 44)

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
	move.AnchorPoint = Vector2.new(1, 0.5)
	move.Position = UDim2.new(1, -12, 0.5, 14)
	move.Size = UDim2.new(0.35, -12, 0, 44)
	if not ready then
		move.TextColor3 = Ui.colors.muted
	end
end

local function buildRow(
	parent: Instance,
	employee: Employees.Employee,
	data: any,
	freeDesks: number,
	order: number
)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = ROW_COLOR
	row.Size = UDim2.new(1, -8, 0, 64)
	row.LayoutOrder = order
	Ui.corner(row, 10)
	row.Parent = parent

	local swatch = Instance.new("Frame")
	swatch.BackgroundColor3 = Employees.shirtColors[employee.specialization or "all"]
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
	name.Size = UDim2.new(0.6, -24, 0, 26)
	local role = ClientState.localText("employee_" .. employee.id .. "_role", employee.role, employee.roleEn)
	local details =
		ClientState.t("team_multiplier", { mult = employee.multiplier, spec = specName(employee) })
	local sub = Ui.label(row, role .. " · " .. details, 20, nil, Ui.colors.muted)
	sub.Position = UDim2.fromOffset(24, 36)
	sub.Size = UDim2.new(0.6, -24, 0, 20)

	local text: string
	local color = Ui.colors.locked
	local canHire = false
	if staff[employee.id] then
		text, color = ClientState.t("team_hired"), Ui.colors.good
	elseif
		employee.legendary
		and not (employee.id == "robo" and Players.LocalPlayer:GetAttribute("RobotHire") == true)
	then
		text = ClientState.t("team_soon")
	elseif (tonumber(data.studioLevel) or 1) < employee.stage then
		local stage = Stages[employee.stage]
		text = ClientState.t("team_locked", { stage = if stage then ClientState.localName(stage) else "?" })
	elseif freeDesks <= 0 then
		text = ClientState.t("team_no_desk")
	else
		text = ClientState.t("team_hire", { price = Texts.money(employee.cost) })
		canHire = data.cash >= employee.cost
		color = if canHire then Ui.colors.money else Ui.colors.locked
	end
	local button = Ui.button(row, text, color, function()
		if canHire then
			StaffRemotes.HireEmployee:FireServer(employee.id)
		end
	end)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.new(0.4, -10, 0, 44)
	if canHire then
		button.TextColor3 = Color3.fromRGB(40, 30, 0)
	elseif color == Ui.colors.locked then
		button.TextColor3 = Ui.colors.muted
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
		old:Destroy()
	end

	local window = Ui.window(gui, "Window", Vector2.new(640, 640))
	local title = Ui.label(window, ClientState.t("team_title"), 36, Ui.titleFont)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 36)
	local close = Ui.button(window, ClientState.t("create_close"), Ui.colors.locked, function()
		TeamWindow.close()
	end)
	close.Size = UDim2.fromOffset(40, 40)
	close.Position = UDim2.new(1, -52, 0, 8)

	local body = Instance.new("ScrollingFrame")
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
	local free, total = deskCounts(data)
	Ui.label(body, ClientState.t("team_desks", { free = free, total = total }), 22, nil, Ui.colors.muted).LayoutOrder =
		2
	for i, employee in Employees.list do
		buildRow(body, employee, data, free, 2 + i)
	end
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
	Ui.windowOpened()
	render()
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
	end)
	StaffRemotes.StaffChanged.OnClientEvent:Connect(function(newStaff: any)
		if type(newStaff) == "table" then
			staff = newStaff
			render()
		end
	end)
	ClientState.changed:Connect(function()
		render()
	end)
end

return TeamWindow
