--!strict
-- Доска заказов дня на участке (OrderService, Config/Orders): 5 строк «жанр · оценка не ниже · деньги»,
-- выполненные отмечены ✓. Надписи рисуются здесь, на клиенте, на языке игрока: SurfaceGui на детали
-- OrderBoard своего участка (чужие доски — только заголовок). Выполнил заказ — тост. Оценка ниже
-- минимальной ничего не отменяет: строка остаётся, игру можно переделать.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Genres = require(Shared.Config.Genres)
local Texts = require(Shared.Config.Texts)
local OrderRemotes = require(Shared.OrderRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local UnlockNotice = require(script.Parent.UnlockNotice)

local player = Players.LocalPlayer

local PIXELS_PER_STUD = 60
local TITLE_HEIGHT = 56
local ROW_HEIGHT = 56
local FOOT_HEIGHT = 36
local REFRESH_SECONDS = 20
local COLOR_PENDING = Color3.fromRGB(235, 238, 248)
local COLOR_DONE = Color3.fromRGB(110, 220, 130)

type OrderRow = { genreId: string, minScore: number, done: boolean, cash: number }
type State = { day: number, endsAt: number, list: { OrderRow } }

local OrderBoardController = {}

local state: State? = nil
local guis: { [BasePart]: SurfaceGui } = {}

local function genreName(genreId: string): string
	local genre = (Genres :: any)[genreId]
	return if genre then ClientState.localName(genre) else genreId
end

local function remaining(): string
	local current = state
	if not current then
		return ""
	end
	local left = math.max(current.endsAt - os.time(), 0)
	return string.format("%d:%02d", left // 3600, (left // 60) % 60)
end

local function label(
	parent: Instance,
	text: string,
	y: number,
	height: number,
	color: Color3,
	bold: boolean
): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(16, y)
	l.Size = UDim2.new(1, -32, 0, height)
	l.Font = if bold then Ui.titleFontFor(ClientState.lang) else Ui.bodyFont
	l.TextColor3 = color
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = height - 14
	limit.MinTextSize = 10
	limit.Parent = l
	return l
end

local function ownPlotName(): string?
	local name = player:GetAttribute("PlotName")
	return if type(name) == "string" then name else nil
end

-- Перерисовать надписи одной доски
local function render(board: BasePart, gui: SurfaceGui)
	for _, child in gui:GetChildren() do
		child:Destroy()
	end
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(32, 36, 52)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local title = label(frame, ClientState.t("order_title"), 4, TITLE_HEIGHT, Ui.colors.money, true)
	title.TextXAlignment = Enum.TextXAlignment.Center
	local plot = board.Parent
	local own = plot ~= nil and plot.Name == ownPlotName()
	local current = state
	if not own or not current then
		return
	end
	for index, row in current.list do
		local text = string.format(
			"%s%s · ★%d+ · %s",
			if row.done then "✓ " else "",
			genreName(row.genreId),
			row.minScore,
			Texts.money(row.cash)
		)
		label(
			frame,
			text,
			TITLE_HEIGHT + 8 + (index - 1) * ROW_HEIGHT,
			ROW_HEIGHT - 6,
			if row.done then COLOR_DONE else COLOR_PENDING,
			false
		)
	end
	local foot = label(
		frame,
		ClientState.t("order_reset", { time = remaining() }),
		TITLE_HEIGHT + 8 + #current.list * ROW_HEIGHT,
		FOOT_HEIGHT,
		Ui.colors.muted,
		false
	)
	foot.TextXAlignment = Enum.TextXAlignment.Center
end

local function attach(board: Instance)
	if not board:IsA("BasePart") or board.Name ~= "OrderBoard" or guis[board] then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "OrderBoardGui"
	gui.Adornee = board
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.MaxDistance = 120
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

function OrderBoardController.start()
	local plots = workspace:WaitForChild("Plots", 30)
	if plots then
		for _, plot in plots:GetChildren() do
			local board = plot:FindFirstChild("OrderBoard")
			if board then
				attach(board)
			end
		end
		plots.DescendantAdded:Connect(attach)
	end
	OrderRemotes.OrderState.OnClientEvent:Connect(function(info: any)
		if type(info) ~= "table" or type(info.list) ~= "table" then
			return
		end
		state = info :: any
		renderAll()
		local done = tonumber(info.completed)
		local row = if done then (info.list :: { any })[done] else nil
		if row then
			UnlockNotice.toast(ClientState.t("order_done", {
				genre = genreName(row.genreId),
				score = row.minScore,
				money = Texts.money(row.cash),
			}))
		end
	end)
	ClientState.langChanged:Connect(renderAll)
	player:GetAttributeChangedSignal("PlotName"):Connect(renderAll)
	OrderRemotes.RequestOrders:FireServer()
	-- Время до смены заказов тикает
	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			renderAll()
		end
	end)
end

return OrderBoardController
