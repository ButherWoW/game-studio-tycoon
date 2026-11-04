--!strict
-- Окно «Исследования» (шаг 3.4): ОИ игрока и три ветки дерева.
-- Клиент только показывает и просит сервер; проверки ОИ и зависимостей — на сервере.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Research = require(ReplicatedStorage.Shared.Config.Research)
local ResearchRemotes = require(ReplicatedStorage.Shared.ResearchRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local MENU_SLOT = 1
local CARD_HEIGHT = 112

local ResearchWindow = {}

local gui: ScreenGui? = nil
-- Последнее состояние с сервера
local points = 0
local owned: { [string]: boolean } = {}
-- Позиции прокрутки колонок, чтобы перерисовка после покупки не сбрасывала их
local scrollPositions: { [string]: Vector2 } = {}

local render: () -> ()

local function nodeText(node: Research.Node): (string, string)
	local key = "research_" .. node.id
	return ClientState.localText(key, node.name, node.nameEn),
		ClientState.localText(key .. "_desc", node.description, node.descriptionEn)
end

local function requiredNames(node: Research.Node): string
	local names = {}
	for _, id in node.requires do
		local req = Research.byId[id]
		if req and not owned[id] then
			table.insert(names, (nodeText(req)))
		end
	end
	return table.concat(names, ", ")
end

local function buildCard(parent: Instance, node: Research.Node, order: number)
	local isOwned = owned[node.id] == true
	local available = not isOwned and Research.requirementsMet(node, owned)
	local affordable = available and points >= node.cost

	local card = Instance.new("Frame")
	card.Name = node.id
	card.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
	card.Size = UDim2.new(1, -8, 0, CARD_HEIGHT)
	card.LayoutOrder = order
	Ui.corner(card, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = if isOwned
		then Ui.colors.good
		elseif affordable then Ui.colors.primary
		else Ui.colors.stroke
	stroke.Parent = card

	local name, description = nodeText(node)
	local genreId = node.effect.unlockGenre
	local data = ClientState.data
	if not isOwned and genreId and data and data.unlockedGenres and data.unlockedGenres[genreId] then
		description ..= " " .. ClientState.t("research_genre_owned")
	end

	local title = Ui.label(
		card,
		name,
		24,
		Ui.titleFont,
		if available or isOwned then Ui.colors.text else Ui.colors.muted
	)
	title.Position = UDim2.fromOffset(10, 6)
	title.Size = UDim2.new(1, -90, 0, 24)

	local cost =
		Ui.label(card, ClientState.t("research_cost", { cost = node.cost }), 20, nil, Ui.colors.money)
	cost.Position = UDim2.new(1, -84, 0, 8)
	cost.Size = UDim2.fromOffset(74, 20)
	cost.TextXAlignment = Enum.TextXAlignment.Right

	local desc = Ui.label(card, description, 34, Enum.Font.GothamMedium, Ui.colors.muted)
	desc.Position = UDim2.fromOffset(10, 32)
	desc.Size = UDim2.new(1, -20, 0, 34)
	desc.TextWrapped = true

	local bottom = UDim2.new(1, -20, 0, 34)
	local bottomPos = UDim2.new(0, 10, 1, -40)
	if isOwned then
		local status = Ui.label(card, ClientState.t("research_owned"), 26, Ui.titleFont, Ui.colors.good)
		status.Size = bottom
		status.Position = bottomPos
	elseif not available then
		local status = Ui.label(
			card,
			ClientState.t("research_requires", { names = requiredNames(node) }),
			26,
			nil,
			Ui.colors.muted
		)
		status.Size = bottom
		status.Position = bottomPos
	else
		local text = if affordable
			then ClientState.t("research_buy", { cost = node.cost })
			else ClientState.t("research_need", { cost = node.cost })
		local button = Ui.button(
			card,
			text,
			if affordable then Ui.colors.primary else Ui.colors.locked,
			function()
				if owned[node.id] or points < node.cost then
					return
				end
				ResearchRemotes.BuyResearch:FireServer(node.id)
			end
		)
		button.Size = bottom
		button.Position = bottomPos
		if not affordable then
			button.TextColor3 = Ui.colors.muted
		end
	end

	card.Parent = parent
end

local function buildColumn(parent: Instance, branch: Research.Branch, order: number)
	local column = Instance.new("Frame")
	column.Name = branch
	column.BackgroundTransparency = 1
	column.Size = UDim2.new(1 / 3, -8, 1, 0)
	column.LayoutOrder = order

	local header = Ui.label(column, ClientState.t("research_branch_" .. branch), 28, Ui.titleFont)
	header.TextXAlignment = Enum.TextXAlignment.Center

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 34)
	list.Size = UDim2.new(1, 0, 1, -34)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	Ui.list(list, 8)
	list.Parent = column

	for i, node in Research.branchNodes(branch) do
		buildCard(list, node, i)
	end
	column.Parent = parent

	local saved = scrollPositions[branch]
	if saved then
		list.CanvasPosition = saved
	end
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		scrollPositions[branch] = list.CanvasPosition
	end)
end

render = function()
	local screen = gui
	if not screen then
		return
	end
	local old = screen:FindFirstChild("Window")
	if old then
		old:Destroy()
	end

	local window = Ui.window(screen, "Window", Vector2.new(900, 640))

	local title = Ui.label(window, ClientState.t("research_title"), 36, Ui.titleFont)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(0.5, -16, 0, 36)

	local pointsLabel = Ui.label(
		window,
		ClientState.t("research_points", { points = points }),
		30,
		Ui.titleFont,
		Ui.colors.money
	)
	pointsLabel.Position = UDim2.new(0.5, 0, 0, 13)
	pointsLabel.Size = UDim2.new(0.5, -72, 0, 30)
	pointsLabel.TextXAlignment = Enum.TextXAlignment.Right

	local close = Ui.button(window, "✕", Ui.colors.locked, function()
		ResearchWindow.close()
	end)
	close.Size = UDim2.fromOffset(40, 40)
	close.Position = UDim2.new(1, -52, 0, 8)

	local hint = Ui.label(window, ClientState.t("research_hint"), 18, Enum.Font.GothamMedium, Ui.colors.muted)
	hint.Position = UDim2.fromOffset(16, 50)
	hint.Size = UDim2.new(1, -32, 0, 18)

	local columns = Instance.new("Frame")
	columns.BackgroundTransparency = 1
	columns.Position = UDim2.fromOffset(16, 78)
	columns.Size = UDim2.new(1, -24, 1, -90)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = columns
	columns.Parent = window

	for i, branch in Research.BRANCHES do
		buildColumn(columns, branch, i)
	end
end

function ResearchWindow.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "ResearchWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()
	ResearchRemotes.RequestResearch:FireServer()
	render()
end

function ResearchWindow.close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

function ResearchWindow.start()
	ResearchRemotes.ResearchChanged.OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then
			return
		end
		points = if type(state.points) == "number" then state.points else 0
		owned = if type(state.owned) == "table" then state.owned else {}
		render()
	end)

	-- Профиль на сервере грузится асинхронно: просим состояние, когда пришли первые данные
	local requested = false
	local function requestOnce()
		if not requested and ClientState.data then
			requested = true
			ResearchRemotes.RequestResearch:FireServer()
		end
	end
	requestOnce()
	ClientState.changed:Connect(function()
		requestOnce()
		-- Открытые жанры могли поменяться — обновить пометки «жанр уже открыт»
		render()
	end)

	Ui.menuButton(MENU_SLOT, "🔬", function()
		if gui then
			ResearchWindow.close()
		else
			ResearchWindow.open()
		end
	end)
end

return ResearchWindow
