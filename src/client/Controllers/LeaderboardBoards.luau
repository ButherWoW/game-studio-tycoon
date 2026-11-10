--!strict
-- Содержимое физических досок лидеров (детали ставит LeaderboardBoardService): заголовок и топ-10
-- из QuestRemotes.LeaderboardData на языке игрока. Рисуем SurfaceGui на лицевой стороне доски.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestRemotes = require(ReplicatedStorage.Shared.QuestRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)

local TAG = "LeaderboardBoard"
local ROWS = 10
local TITLE_KEYS = { best = "leaders_best", games = "leaders_games", fans = "fans_leaders" }
local PIXELS = 50 -- PixelsPerStud

type Entry = { name: string, value: number }
type Data = { available: boolean?, best: { Entry }?, games: { Entry }?, fans: { Entry }? }

local LeaderboardBoards = {}

local data: Data? = nil
local guis: { [BasePart]: SurfaceGui } = {}

local function label(
	parent: Instance,
	text: string,
	y: number,
	h: number,
	color: Color3,
	align: Enum.TextXAlignment
): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(0.92, h)
	l.Position = UDim2.fromScale(0.04, y)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextXAlignment = align
	l.Text = text
	l.Parent = parent
	return l
end

local function valueText(value: number): string
	return if value >= 1000 then Texts.money(value):sub(2) else tostring(value)
end

local function render(board: BasePart, gui: SurfaceGui)
	gui:ClearAllChildren()
	local kind = board:GetAttribute("Kind")
	local key = if type(kind) == "string" then TITLE_KEYS[kind] else nil
	if not key then
		return
	end
	label(gui, ClientState.t(key), 0.02, 0.09, Color3.fromRGB(255, 214, 90), Enum.TextXAlignment.Center)
	local entries = if data and type(kind) == "string" then (data :: any)[kind] else nil
	if not data or data.available ~= true then
		label(
			gui,
			ClientState.t("leaders_unavailable"),
			0.45,
			0.07,
			Color3.fromRGB(170, 175, 190),
			Enum.TextXAlignment.Center
		)
		return
	end
	if type(entries) ~= "table" or #entries == 0 then
		label(
			gui,
			ClientState.t("leaders_empty"),
			0.45,
			0.07,
			Color3.fromRGB(170, 175, 190),
			Enum.TextXAlignment.Center
		)
		return
	end
	for i = 1, math.min(ROWS, #entries) do
		local e = entries[i]
		local color = if i == 1 then Color3.fromRGB(255, 214, 90) else Color3.fromRGB(235, 238, 250)
		local y = 0.13 + (i - 1) * 0.086
		label(gui, string.format("%d. %s", i, tostring(e.name)), y, 0.07, color, Enum.TextXAlignment.Left)
		label(gui, valueText(tonumber(e.value) or 0), y, 0.07, color, Enum.TextXAlignment.Right)
	end
end

local function attach(board: Instance)
	if not board:IsA("BasePart") or guis[board] then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Adornee = board
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Parent = board
	guis[board] = gui
	render(board, gui)
end

local function renderAll()
	for board, gui in guis do
		if board.Parent then
			render(board, gui)
		else
			guis[board] = nil
		end
	end
end

function LeaderboardBoards.start()
	for _, board in CollectionService:GetTagged(TAG) do
		attach(board)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(attach)
	QuestRemotes.LeaderboardData.OnClientEvent:Connect(function(incoming)
		if type(incoming) == "table" then
			data = incoming :: any
			renderAll()
		end
	end)
	ClientState.langChanged:Connect(renderAll)
	-- Данные приходят раз в 2 минуты и по запросу: просим при входе
	QuestRemotes.RequestQuestData:FireServer()
end

return LeaderboardBoards
