--!strict
-- Заказы дня: 5 заказов «жанр + минимальная оценка → деньги» на доске у участка (Config/Orders).
-- Заказы нового дня (00:00 UTC) раскладываются один раз по seed (день + UserId): перезаход их не
-- перебрасывает. Выпущена игра нужного жанра с оценкой не ниже минимальной — заказ выполнен, награда
-- сразу (RewardService.grant, минуты дохода). Оценка ниже — заказ остаётся, можно переделать.
-- Данные: (profile :: any).orders = { day, list = { { genreId, minScore, done } } }.
-- Доску (деталь OrderBoard рядом с каждым участком) создаёт этот сервис, надписи рисует клиент
-- (Controllers/OrderBoardController) на языке игрока.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Orders = require(Shared.Config.Orders)
local Genres = require(Shared.Config.Genres)
local OrderRemotes = require(Shared.OrderRemotes)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local PlotService = require(script.Parent.PlotService)

local DAY_SECONDS = 86400
local REQUEST_COOLDOWN = 1
local DAY_CHECK_SECONDS = 60

type Order = { genreId: string, minScore: number, done: boolean }
type OrderData = { day: number, list: { Order } }

local OrderService = {}
local lastRequest: { [Player]: number } = {}

local function today(): number
	return os.time() // DAY_SECONDS
end

local function sortedUnlockedGenres(profile: DataService.Profile): { string }
	local list = {}
	for id in Genres do
		if profile.unlockedGenres[id] then
			table.insert(list, id)
		end
	end
	table.sort(list)
	return list
end

-- Новый набор на день: жанры разные, пока хватает открытых, иначе повторяются; seed — день и игрок
local function roll(player: Player, profile: DataService.Profile, day: number): OrderData
	local rng = Random.new(day * 100_003 + player.UserId * 7 + 13)
	local genres = sortedUnlockedGenres(profile)
	if #genres == 0 then
		genres = { "action" }
	end
	for i = #genres, 2, -1 do
		local j = rng:NextInteger(1, i)
		genres[i], genres[j] = genres[j], genres[i]
	end
	local scores = Orders.scoresFor(profile.studioLevel)
	local list: { Order } = {}
	for n = 1, Orders.perDay do
		table.insert(list, {
			genreId = genres[(n - 1) % #genres + 1],
			minScore = scores[n] or scores[#scores],
			done = false,
		})
	end
	return { day = day, list = list }
end

-- Текущие заказы; в новый день UTC (или битые данные) — новые
local function data(player: Player, profile: DataService.Profile): OrderData
	local p = profile :: any
	local d = p.orders
	local valid = type(d) == "table" and d.day == today() and type(d.list) == "table" and #d.list > 0
	if valid then
		for _, order in d.list do
			if type(order) ~= "table" or not Genres[order.genreId] or type(order.minScore) ~= "number" then
				valid = false
				break
			end
		end
	end
	if not valid then
		d = roll(player, profile, today())
		p.orders = d
	end
	return d :: OrderData
end

local function push(player: Player, completed: number?)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local d = data(player, profile)
	local list = {}
	for _, order in d.list do
		table.insert(list, {
			genreId = order.genreId,
			minScore = order.minScore,
			done = order.done == true,
			-- Сколько денег принесёт заказ сейчас (доход студии растёт — сумма тоже)
			cash = RewardService.incomeForMinutes(player, profile, Orders.rewardFor(order.minScore)),
		})
	end
	OrderRemotes.OrderState:FireClient(player, {
		day = d.day,
		endsAt = (d.day + 1) * DAY_SECONDS,
		list = list,
		completed = completed,
	})
end

-- Игра выпущена (DevelopmentService.release): подходящий заказ с наибольшей минимальной оценкой
-- закрываем и платим; не дотянули — ничего не происходит, заказ ждёт
function OrderService.onGameReleased(player: Player, info: any)
	if type(info) ~= "table" or type(info.genreId) ~= "string" or type(info.score) ~= "number" then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local d = data(player, profile)
	local pick: number? = nil
	for index, order in d.list do
		if
			not order.done
			and order.genreId == info.genreId
			and info.score >= order.minScore
			and (pick == nil or order.minScore > d.list[pick].minScore)
		then
			pick = index
		end
	end
	if not pick then
		return
	end
	local order = d.list[pick]
	order.done = true
	RewardService.grant(player, { incomeMinutes = Orders.rewardFor(order.minScore) })
	push(player, pick)
end

local function onRequest(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	push(player)
end

-- Где стоит доска: в офисе (этап 2+) — на задней стене 1-го этажа, в гараже — рядом с участком.
-- Решаем по профилю, а не по именам моделей: модель могла ещё не собраться (владелец 10.11:
-- доска торчала у стены снаружи). Пока гаража нет — доски нет вовсе (владелец 10.11)
local function boardCFrame(plot: BasePart, inOffice: boolean): CFrame
	local size = Orders.board.size
	if inOffice then
		return plot.CFrame
			* CFrame.new(Orders.board.officeOffset)
			* CFrame.Angles(0, math.rad(Orders.board.officeYaw or 0), 0)
	end
	local offset = Orders.board.offset
	return plot.CFrame * CFrame.new(offset.X, plot.Size.Y / 2 + size.Y / 2, offset.Z)
end

local function createBoard(plot: BasePart, cframe: CFrame)
	local board = Instance.new("Part")
	board.Name = "OrderBoard"
	board.Anchored = true
	board.CanCollide = true
	board.CanQuery = false
	board.CanTouch = false
	board.Size = Orders.board.size
	board.Color = Color3.fromRGB(32, 36, 52)
	board.Material = Enum.Material.SmoothPlastic
	board.CFrame = cframe
	board:SetAttribute("OrderBoard", true)
	board.Parent = plot
end

-- Доска игрока: нет гаража — убрать; есть — создать и поставить на место (офис/гараж)
local function syncBoard(player: Player)
	local plot = PlotService.getPlot(player)
	local profile = DataService.get(player)
	if not plot or not plot:IsA("BasePart") or not profile then
		return
	end
	local board = plot:FindFirstChild("OrderBoard")
	if not PlotService.ownsGarage(player) then
		if board then
			board:Destroy()
		end
		return
	end
	local cframe = boardCFrame(plot, profile.studioLevel >= 2)
	if board and board:IsA("BasePart") then
		if board.CFrame ~= cframe then
			board.CFrame = cframe
		end
	else
		createBoard(plot, cframe)
	end
end

function OrderService.start()
	OrderRemotes.RequestOrders.OnServerEvent:Connect(onRequest)
	DataService.onProfileLoaded(function(player: Player, _profile: DataService.Profile)
		push(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
	-- Доска появляется с гаражом и переезжает в офис вместе со студией; сверяем по событию и раз в 3 с
	PlotService.plotChanged:Connect(syncBoard)
	DataService.onProfileLoaded(function(player: Player, _profile: DataService.Profile)
		task.delay(1, syncBoard, player)
	end)
	task.spawn(function()
		while true do
			task.wait(3)
			for _, player in Players:GetPlayers() do
				syncBoard(player)
			end
		end
	end)
	-- Новый день UTC: новые заказы тем, кто в игре
	task.spawn(function()
		while true do
			task.wait(DAY_CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				local p = if profile then (profile :: any).orders else nil
				if profile and type(p) == "table" and p.day ~= today() then
					push(player)
				end
			end
		end
	end)
end

return OrderService
