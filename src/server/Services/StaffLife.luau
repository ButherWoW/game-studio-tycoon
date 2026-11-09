--!strict
-- Жизнь сотрудников на участке: перерывы по настроению (Config/Mood.breaks) и уход уволенного.
-- Один цикл на сервер: раз в секунду решает, кому отдохнуть; Heartbeat двигает только идущих NPC
-- (закреплённая модель, PivotTo по отрезкам с покачиванием — без физики и Humanoid:MoveTo).
-- Перерыв: встал → проход перед столом → место отдыха на том же этаже (кофемашина, кулер, зона
-- отдыха… или к другому отдыхающему поболтать) → облачко-эмодзи → обратно и сел. Пока на перерыве,
-- стол не даёт очков (StaffService.setBreak). Пересборка NPC (StaffService) зовёт reset.
-- Увольнение (StaffService.onFire → leave): NPC встаёт, в руках коробка, идёт к выходу и тает.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Mood = require(ReplicatedStorage.Shared.Config.Mood)
local StudioLayout = require(ReplicatedStorage.Shared.StudioLayout)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StaffService = require(script.Parent.StaffService)

local AISLE = 6.5 -- проход: столько studs перед столом (за креслом)
local STAND_OUT = 1.5 -- встал из кресла: шаг вперёд от места
local SPOT_FRONT = 3.5 -- место отдыха перед предметом
local PLOT_MARGIN = 4 -- к краю участка ближе не подходим
local WANDER_MIN, WANDER_MAX = 4, 10 -- без мест отдыха: прогулка вдоль прохода
local CHAT_DISTANCE = 2.6
-- Лёгкое покачивание корпуса на шаге (раньше 0.18 — NPC «прыгали»). Ноги и руки двигает клиент
-- (Controllers/NpcWalkAnimator) по атрибутам Walking и WalkSpeed; тут только лёгкий подъём
local BOB_HEIGHT = 0.06
local BOB_PER_SPEED = 0.9 -- рад/с на 1 stud/с скорости: два шага за период
local TURN_RATE = 9 -- как быстро NPC разворачивается к направлению ходьбы (1/с)
local WALK_TAG = "NpcWalker"
local LEAVE_TIME = 2.2 -- секунд на дорогу уволенного (быстрее обычного шага, если далеко)
local FADE_TIME = 0.6
-- Сколько NPC одновременно идут по всему серверу (Heartbeat двигает каждого PivotTo, это
-- реплицируется всем): 12 участков с большим офисом — без лимита десятки моделей каждый кадр
local MAX_WALKERS = 24
local LEAVE_FAILSAFE = 12 -- модель уволенного удаляется не позже
local BOX_COLOR = Color3.fromRGB(196, 152, 98)

type Walker = {
	player: Player,
	model: Model,
	plot: BasePart,
	path: { Vector3 }, -- точки пола в координатах участка
	index: number,
	pos: Vector3,
	dir: Vector3,
	face: Vector3, -- куда повёрнут модель сейчас (плавно догоняет dir)
	height: number,
	speed: number,
	clock: number,
	leaving: boolean,
	onDone: () -> (),
}

type Break = {
	model: Model,
	phase: string, -- "out" | "idle" | "back"
	untilT: number,
	duration: number,
	emote: string,
	path: { Vector3 },
	bubble: BillboardGui?,
	walker: Walker?,
}

local StaffLife = {}
local walkers: { Walker } = {}
local breaksOf: { [Player]: { [string]: Break } } = {}
local nextCheck: { [Player]: { [string]: number } } = {}
local leaving: { [Player]: { Model } } = {}
local rng = Random.new()

local function flat(v: Vector3, y: number): Vector3
	return Vector3.new(v.X, y, v.Z)
end

local function clampToPlot(plot: BasePart, v: Vector3): Vector3
	local hx = plot.Size.X / 2 - PLOT_MARGIN
	local hz = plot.Size.Z / 2 - PLOT_MARGIN
	return Vector3.new(math.clamp(v.X, -hx, hx), v.Y, math.clamp(v.Z, -hz, hz))
end

-- Облачко над головой (эмодзи — без языка, видят все)
local function bubble(model: Model, text: string): BillboardGui?
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "LifeBubble"
	gui.Size = UDim2.fromScale(3, 1.5)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.MaxDistance = 80
	gui.Adornee = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	-- Только значок без фона-квадрата: прозрачная подпись с тонкой обводкой
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.fromRGB(30, 30, 40)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.Parent = gui
	gui.Parent = head
	return gui
end

local function setBubble(record: Break, text: string?)
	if record.bubble then
		record.bubble:Destroy()
		record.bubble = nil
	end
	if text then
		record.bubble = bubble(record.model, text)
	end
end

-- Идёт ли NPC: клиент по этому качает суставы (тег и атрибуты реплицируются)
local function setWalking(model: Model, speed: number?)
	model:SetAttribute("WalkSpeed", speed or 0)
	model:SetAttribute("Walking", speed ~= nil)
	if speed ~= nil then
		CollectionService:AddTag(model, WALK_TAG)
	end
end

local function placeStanding(walker: Walker, bob: number)
	local cf = CFrame.lookAt(walker.pos, walker.pos + walker.face) + Vector3.new(0, walker.height + bob, 0)
	walker.model:PivotTo(walker.plot.CFrame * cf)
end

-- Повести модель по точкам пола (координаты участка); onDone — когда дошла
local function walk(
	player: Player,
	model: Model,
	plot: BasePart,
	path: { Vector3 },
	speed: number,
	isLeaving: boolean,
	onDone: () -> ()
): Walker
	local floorY = tonumber(model:GetAttribute("FloorY")) or 0
	local pivot = plot.CFrame:ToObjectSpace(model:GetPivot())
	local look = pivot.LookVector
	local walker: Walker = {
		player = player,
		model = model,
		plot = plot,
		path = path,
		index = 1,
		pos = Vector3.new(pivot.X, floorY, pivot.Z),
		dir = if Vector3.new(look.X, 0, look.Z).Magnitude > 0.01
			then Vector3.new(look.X, 0, look.Z).Unit
			else Vector3.new(0, 0, 1),
		face = Vector3.new(0, 0, 1),
		height = tonumber(model:GetAttribute("StandHeight")) or 3,
		speed = speed,
		clock = 0,
		leaving = isLeaving,
		onDone = onDone,
	}
	walker.face = walker.dir
	setWalking(model, speed)
	table.insert(walkers, walker)
	return walker
end

local function stopWalker(walker: Walker?)
	if not walker then
		return
	end
	local index = table.find(walkers, walker)
	if index then
		table.remove(walkers, index)
	end
	setWalking(walker.model, nil)
end

local function step(dt: number)
	for i = #walkers, 1, -1 do
		local walker = walkers[i]
		if not walker or not walker.model.Parent then
			table.remove(walkers, i)
			continue
		end
		local target = walker.path[walker.index]
		local delta = target - walker.pos
		local move = walker.speed * dt
		if delta.Magnitude <= move then
			walker.pos = target
			if delta.Magnitude > 0.01 then
				walker.dir = delta.Unit
			end
			walker.index += 1
			if walker.index > #walker.path then
				table.remove(walkers, i)
				setWalking(walker.model, nil)
				placeStanding(walker, 0)
				task.defer(walker.onDone)
				continue
			end
		else
			walker.dir = delta.Unit
			walker.pos += walker.dir * move
		end
		walker.clock += dt
		-- Плавный разворот: не щёлкает на углах пути
		local blend = math.min(dt * TURN_RATE, 1)
		local mixed = walker.face:Lerp(walker.dir, blend)
		if mixed.Magnitude > 0.01 then
			walker.face = mixed.Unit
		end
		placeStanding(walker, math.abs(math.sin(walker.clock * walker.speed * BOB_PER_SPEED)) * BOB_HEIGHT)
	end
end

-- Поставить стоящего NPC в точку pos (пол, координаты участка) лицом к toward
local function standAt(model: Model, plot: BasePart, pos: Vector3, toward: Vector3)
	local height = tonumber(model:GetAttribute("StandHeight")) or 3
	local look = flat(toward, pos.Y) - pos
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, 1)
	end
	model:PivotTo(plot.CFrame * (CFrame.lookAt(pos, pos + look.Unit) + Vector3.new(0, height, 0)))
end

-- Точки стола: где встаёт из-за стола и проход перед ним (координаты участка, Y — пол этажа)
local function deskPoints(model: Model): (Vector3?, Vector3?)
	local deskId = model:GetAttribute("DeskId")
	local seat = model:GetAttribute("SeatLocal")
	local desk = if type(deskId) == "string" then StudioLayout.get(deskId) else nil
	if not desk or typeof(seat) ~= "CFrame" then
		return nil, nil
	end
	local floorY = tonumber(model:GetAttribute("FloorY")) or 0
	local position = desk.position or Vector3.zero
	local rotation = CFrame.Angles(0, math.rad(desk.rotation or 0), 0)
	local forward = rotation:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local stand = flat((seat :: CFrame).Position, floorY) + forward * STAND_OUT
	local aisle = Vector3.new(position.X, floorY, position.Z) + forward * AISLE
	return stand, aisle
end

-- Куда пойти отдыхать: место на этом этаже, другой отдыхающий (поболтать) или прогулка по проходу
local function chooseSpot(
	player: Player,
	plot: BasePart,
	model: Model,
	aisle: Vector3,
	tier: Mood.BreakTier
): (Vector3, string)
	local floorY = aisle.Y
	local emote = tier.emotes[rng:NextInteger(1, #tier.emotes)]
	-- Поболтать с тем, кто уже стоит на перерыве
	local mine = breaksOf[player]
	if mine and rng:NextNumber() < tier.chat then
		for _, other in mine do
			if other.phase == "idle" and other.model ~= model and other.model.Parent then
				local otherPivot = plot.CFrame:ToObjectSpace(other.model:GetPivot())
				local otherPos = flat(otherPivot.Position, floorY)
				if math.abs((tonumber(other.model:GetAttribute("FloorY")) or 0) - floorY) < 1 then
					local side = otherPos + flat(otherPivot.LookVector, 0) * CHAT_DISTANCE
					setBubble(other, "💬")
					return clampToPlot(plot, side), "💬"
				end
			end
		end
	end
	local profile = DataService.get(player)
	local spots: { { pos: Vector3, emote: string } } = {}
	if profile then
		for id, spotEmote in Mood.breaks.spots do
			local upgrade = StudioLayout.get(id)
			local position = upgrade and upgrade.position
			if
				upgrade
				and position
				and profile.upgrades[id]
				and StudioLayout.isVisible(upgrade, profile.studioLevel)
				and math.abs(plot.Size.Y / 2 + position.Y - 0.5 - floorY) < 1
			then
				local rotation = CFrame.Angles(0, math.rad(upgrade.rotation or 0), 0)
				local front = Vector3.new(position.X, floorY, position.Z)
					+ rotation:VectorToWorldSpace(Vector3.new(0, 0, SPOT_FRONT))
				table.insert(spots, { pos = clampToPlot(plot, front), emote = spotEmote })
			end
		end
	end
	if #spots > 0 and rng:NextNumber() < 0.75 then
		local spot = spots[rng:NextInteger(1, #spots)]
		-- В хорошем настроении — эмодзи места, в плохом чаще ленивое из ряда
		return spot.pos, if rng:NextNumber() < 0.5 then spot.emote else emote
	end
	local side = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(WANDER_MIN, WANDER_MAX)
	return clampToPlot(plot, aisle + Vector3.new(side, 0, rng:NextNumber(-1, 1))), emote
end

local function endBreak(player: Player, employeeId: string, record: Break)
	setBubble(record, nil)
	stopWalker(record.walker)
	local mine = breaksOf[player]
	if mine and mine[employeeId] == record then
		mine[employeeId] = nil
	end
	StaffService.setBreak(player, employeeId, false)
end

-- Обход предметов (владелец 09.11: NPC заходили в текстуры объектов). Сетка свободных клеток на уровне
-- корпуса: клетка занята, если в ней есть деталь мебели/декора (любой CanCollide — NPC обходят и
-- декор без коллизии). Оболочки здания (огромные детали), невидимые коллайдеры и сами NPC не считаются.
-- Путь — A* по сетке, затем спрямление по линии видимости. Нет пути — старый прямой маршрут
local CELL = 1.5
local BODY_BOX = Vector3.new(1.7, 2.4, 1.7)
local BODY_LIFT = 2.7 -- центр коробки над полом (участок: пол этажа = floorY + 0.5)
local SHELL_SIZE = 30 -- деталь крупнее по любой стороне — стена/пол/потолок здания
local GRID_TTL = 15

type Grid = { floorY: number, built: number, cols: number, rows: number, blocked: { boolean } }
local grids: { [BasePart]: { [number]: Grid } } = {}

local function cellCenter(plot: BasePart, grid: Grid, col: number, row: number): Vector3
	local hx = plot.Size.X / 2 - PLOT_MARGIN
	local hz = plot.Size.Z / 2 - PLOT_MARGIN
	return Vector3.new(-hx + (col - 1) * CELL, grid.floorY, -hz + (row - 1) * CELL)
end

local function buildGrid(player: Player, plot: BasePart, floorY: number): Grid
	local hx = plot.Size.X / 2 - PLOT_MARGIN
	local hz = plot.Size.Z / 2 - PLOT_MARGIN
	local cols = math.floor(hx * 2 / CELL) + 1
	local rows = math.floor(hz * 2 / CELL) + 1
	local grid: Grid = { floorY = floorY, built = os.clock(), cols = cols, rows = rows, blocked = {} }
	local params = OverlapParams.new()
	local ignore: { Instance } = {}
	local folder = StaffService.npcFolder(player)
	if folder then
		table.insert(ignore, folder)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	for row = 1, rows do
		for col = 1, cols do
			local center = cellCenter(plot, grid, col, row)
			local cf = plot.CFrame * CFrame.new(center.X, floorY + BODY_LIFT, center.Z)
			local blocked = false
			for _, part in workspace:GetPartBoundsInBox(cf, BODY_BOX, params) do
				local big = math.max(part.Size.X, part.Size.Y, part.Size.Z) > SHELL_SIZE
				local ghost = part.Transparency >= 1 and not part.CanCollide
				if not big and not ghost and part ~= plot and not part:IsDescendantOf(Players) then
					blocked = true
					break
				end
			end
			grid.blocked[(row - 1) * cols + col] = blocked
		end
	end
	return grid
end

local function gridFor(player: Player, plot: BasePart, floorY: number): Grid
	local key = math.floor(floorY + 0.5)
	local perPlot = grids[plot] or {}
	grids[plot] = perPlot
	local grid = perPlot[key]
	if not grid or os.clock() - grid.built > GRID_TTL then
		grid = buildGrid(player, plot, floorY)
		perPlot[key] = grid
	end
	return grid
end

local function toCell(plot: BasePart, grid: Grid, v: Vector3): (number, number)
	local hx = plot.Size.X / 2 - PLOT_MARGIN
	local hz = plot.Size.Z / 2 - PLOT_MARGIN
	local col = math.clamp(math.floor((v.X + hx) / CELL + 0.5) + 1, 1, grid.cols)
	local row = math.clamp(math.floor((v.Z + hz) / CELL + 0.5) + 1, 1, grid.rows)
	return col, row
end

-- Маршрут между двумя точками пола (координаты участка) в обход предметов. Всегда возвращает
-- непустой список точек; при неудаче — просто конечную точку (прямая)
local function route(player: Player, plot: BasePart, from: Vector3, to: Vector3): { Vector3 }
	local ok, result = pcall(function()
		local grid = gridFor(player, plot, from.Y)
		local cols, rows = grid.cols, grid.rows
		local sc, sr = toCell(plot, grid, from)
		local gc, gr = toCell(plot, grid, to)
		-- Стартовая и конечная клетки с соседями свободны: стол и кресло рядом, но не поперёк пути
		local function isFree(col: number, row: number): boolean
			if col < 1 or row < 1 or col > cols or row > rows then
				return false
			end
			if math.abs(col - sc) <= 1 and math.abs(row - sr) <= 1 then
				return true
			end
			if math.abs(col - gc) <= 1 and math.abs(row - gr) <= 1 then
				return true
			end
			return not grid.blocked[(row - 1) * cols + col]
		end
		local function id(col: number, row: number): number
			return (row - 1) * cols + col
		end
		local function heuristic(col: number, row: number): number
			local dc, dr = math.abs(col - gc), math.abs(row - gr)
			return (dc + dr) + (1.4142 - 2) * math.min(dc, dr)
		end
		local gScore: { [number]: number } = { [id(sc, sr)] = 0 }
		local came: { [number]: number } = {}
		local open: { number } = { id(sc, sr) }
		local fScore: { [number]: number } = { [id(sc, sr)] = heuristic(sc, sr) }
		local closed: { [number]: boolean } = {}
		local found = false
		local guard = 0
		while #open > 0 and guard < 4000 do
			guard += 1
			local bestIndex = 1
			for i = 2, #open do
				if (fScore[open[i]] or math.huge) < (fScore[open[bestIndex]] or math.huge) then
					bestIndex = i
				end
			end
			local current = table.remove(open, bestIndex) :: number
			if current == id(gc, gr) then
				found = true
				break
			end
			closed[current] = true
			local col = (current - 1) % cols + 1
			local row = (current - 1) // cols + 1
			for dc = -1, 1 do
				for dr = -1, 1 do
					if dc == 0 and dr == 0 then
						continue
					end
					local nc, nr = col + dc, row + dr
					if not isFree(nc, nr) then
						continue
					end
					-- По диагонали не режем угол занятой клетки
					if dc ~= 0 and dr ~= 0 and (not isFree(col + dc, row) or not isFree(col, row + dr)) then
						continue
					end
					local nid = id(nc, nr)
					if closed[nid] then
						continue
					end
					local tentative = (gScore[current] or 0) + (if dc ~= 0 and dr ~= 0 then 1.4142 else 1)
					if tentative < (gScore[nid] or math.huge) then
						came[nid] = current
						gScore[nid] = tentative
						fScore[nid] = tentative + heuristic(nc, nr)
						if not table.find(open, nid) then
							table.insert(open, nid)
						end
					end
				end
			end
		end
		if not found then
			return { to }
		end
		local cells: { number } = {}
		local at: number? = id(gc, gr)
		while at do
			table.insert(cells, 1, at)
			at = came[at]
		end
		-- Спрямление: пропускаем промежуточные клетки, если до дальней видно по прямой
		local function clear(a: number, b: number): boolean
			local ac, ar = (a - 1) % cols + 1, (a - 1) // cols + 1
			local bc, br = (b - 1) % cols + 1, (b - 1) // cols + 1
			local steps = math.max(math.abs(bc - ac), math.abs(br - ar)) * 2
			for i = 1, steps do
				local t = i / steps
				local col = math.floor(ac + (bc - ac) * t + 0.5)
				local row = math.floor(ar + (br - ar) * t + 0.5)
				if not isFree(col, row) then
					return false
				end
			end
			return true
		end
		local points: { Vector3 } = {}
		local anchor = 1
		while anchor < #cells do
			local far = anchor + 1
			for j = #cells, anchor + 1, -1 do
				if clear(cells[anchor], cells[j]) then
					far = j
					break
				end
			end
			local col = (cells[far] - 1) % cols + 1
			local row = (cells[far] - 1) // cols + 1
			local center = cellCenter(plot, grid, col, row)
			table.insert(points, Vector3.new(center.X, from.Y, center.Z))
			anchor = far
		end
		if #points == 0 then
			return { to }
		end
		points[#points] = to
		return points
	end)
	if ok and type(result) == "table" then
		return result :: { Vector3 }
	end
	return { to }
end

local function startBreak(
	player: Player,
	plot: BasePart,
	model: Model,
	employeeId: string,
	tier: Mood.BreakTier
)
	local stand, aisle = deskPoints(model)
	if not stand or not aisle then
		return
	end
	local spot, emote = chooseSpot(player, plot, model, aisle, tier)
	-- Маршрут в обход мебели и декора (route); path[1] — первая точка, последняя — место отдыха
	local path = route(player, plot, stand, spot)
	local record: Break = {
		model = model,
		phase = "out",
		untilT = 0,
		duration = rng:NextNumber(tier.min, tier.max),
		emote = emote,
		path = path,
	}
	local mine = breaksOf[player] or {}
	breaksOf[player] = mine
	mine[employeeId] = record
	StaffService.setBreak(player, employeeId, true)
	StaffService.poseStanding(model)
	standAt(model, plot, stand, aisle)
	record.walker = walk(player, model, plot, path, Mood.breaks.walkSpeed, false, function()
		if mine[employeeId] ~= record or not model.Parent then
			return
		end
		record.walker = nil
		record.phase = "idle"
		record.untilT = os.clock() + record.duration
		setBubble(record, record.emote)
	end)
end

local function goBack(player: Player, plot: BasePart, employeeId: string, record: Break)
	record.phase = "back"
	setBubble(record, nil)
	local stand = deskPoints(record.model)
	-- Обратно тем же маршрутом: точки в обратном порядке и к столу
	local back: { Vector3 } = {}
	for i = #record.path - 1, 1, -1 do
		table.insert(back, record.path[i])
	end
	table.insert(back, stand or record.path[1])
	record.walker = walk(player, record.model, plot, back, Mood.breaks.walkSpeed, false, function()
		local mine = breaksOf[player]
		if not mine or mine[employeeId] ~= record then
			return
		end
		record.walker = nil
		if record.model.Parent then
			StaffService.sitBack(record.model, plot)
		end
		endBreak(player, employeeId, record)
	end)
end

-- «Пицца-пати» (DailyEventService): никто не уходит на перерыв; без модуля — как обычно
local function breaksPaused(): boolean
	local module = script.Parent:FindFirstChild("DailyEventService")
	if not module or not module:IsA("ModuleScript") then
		return false
	end
	local ok, value = pcall(function()
		return (require(module) :: any).noBreaks()
	end)
	return ok and value == true
end

local function schedule(player: Player)
	local folder = StaffService.npcFolder(player)
	local plot = PlotService.getPlot(player)
	local mood = tonumber(player:GetAttribute("TeamMood"))
	local mine = breaksOf[player] or {}
	breaksOf[player] = mine
	local now = os.clock()
	-- Кто отдохнул — обратно за стол; пропавшие модели — забываем
	local onBreak = 0
	for employeeId, record in mine do
		if not record.model.Parent then
			endBreak(player, employeeId, record)
		elseif record.phase == "idle" and now >= record.untilT and plot then
			goBack(player, plot, employeeId, record)
			onBreak += 1
		else
			onBreak += 1
		end
	end
	if not folder or not plot or not mood then
		return
	end
	local members = StaffService.activeStaff(player)
	local count = 0
	for _ in members do
		count += 1
	end
	if count == 0 then
		return
	end
	local limit = math.max(1, math.floor(count * Mood.breaks.maxShare))
	local checks = nextCheck[player] or {}
	nextCheck[player] = checks
	local tier = Mood.breakTier(mood)
	for employeeId in members do
		if mine[employeeId] then
			continue
		end
		local due = checks[employeeId]
		if not due then
			checks[employeeId] = now + rng:NextNumber(Mood.breaks.checkMin, Mood.breaks.checkMax)
		elseif now >= due then
			checks[employeeId] = now + rng:NextNumber(Mood.breaks.checkMin, Mood.breaks.checkMax)
			if
				onBreak < limit
				and #walkers < MAX_WALKERS
				and not breaksPaused()
				and rng:NextNumber() < tier.chance
			then
				local model = folder:FindFirstChild("Staff_" .. employeeId)
				if model and model:IsA("Model") and model:GetAttribute("SeatLocal") ~= nil then
					startBreak(player, plot, model, employeeId, tier)
					onBreak += 1
				end
			end
		end
	end
	-- Уволенных из расписания убираем
	for employeeId in checks do
		if not members[employeeId] then
			checks[employeeId] = nil
		end
	end
end

-- Пересборка NPC (StaffService): старые модели уходят, перерывы обрываются без пересадки
function StaffLife.reset(player: Player)
	local mine = breaksOf[player]
	if mine then
		for _, record in mine do
			stopWalker(record.walker)
			setBubble(record, nil)
		end
		-- Отложенные onDone увидят пустую таблицу и ничего не сделают
		table.clear(mine)
	end
	breaksOf[player] = nil
end

-- Уволенный: встаёт, коробка в руках, идёт к выходу (ворота гаража или лифт этажа) и тает.
-- Модель уже не в папке NPC: пересборка её не удалит
function StaffLife.leave(player: Player, model: Model, plot: BasePart)
	local employeeId = model:GetAttribute("EmployeeId")
	local mine = breaksOf[player]
	if type(employeeId) == "string" and mine and mine[employeeId] then
		local record = mine[employeeId]
		stopWalker(record.walker)
		setBubble(record, nil)
		mine[employeeId] = nil
	end
	local floorY = tonumber(model:GetAttribute("FloorY")) or 0
	local stand, aisle = deskPoints(model)
	local pivot = plot.CFrame:ToObjectSpace(model:GetPivot())
	stand = stand or flat(pivot.Position, floorY)
	aisle = aisle or stand
	model.Name = "Leaving_" .. tostring(employeeId)
	model.Parent = plot
	local list = {}
	for _, other in leaving[player] or {} do
		if other.Parent then
			table.insert(list, other)
		end
	end
	table.insert(list, model)
	leaving[player] = list
	StaffService.poseStanding(model)
	standAt(model, plot, stand :: Vector3, aisle :: Vector3)
	-- Коробка с вещами перед грудью
	local box = Instance.new("Part")
	box.Name = "Box"
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.Size = Vector3.new(1.6, 1.1, 1.1)
	box.Color = BOX_COLOR
	box.Material = Enum.Material.Cardboard
	box.CFrame = model:GetPivot() * CFrame.new(0, -0.2, -1.1)
	box.Parent = model
	bubble(model, "📦😢")
	-- Выход: на этажах офиса — лифт, в гараже и на 1-м этаже — к воротам (+Z)
	local exit = if floorY > 1
		then Vector3.new(StudioLayout.ELEVATOR.X, floorY, StudioLayout.ELEVATOR.Z)
		else Vector3.new((aisle :: Vector3).X, floorY, plot.Size.Z / 2 - 2)
	local path = { aisle :: Vector3, exit }
	local distance = ((aisle :: Vector3) - (stand :: Vector3)).Magnitude
		+ (exit - (aisle :: Vector3)).Magnitude
	local speed = math.max(Mood.breaks.walkSpeed, distance / LEAVE_TIME)
	local function vanish()
		if not model.Parent then
			return
		end
		for _, part in model:GetDescendants() do
			-- Детали и лицо (Decal) тают вместе
			local fades = (part:IsA("BasePart") and part.Transparency < 1) or part:IsA("Decal")
			if fades then
				TweenService:Create(part, TweenInfo.new(FADE_TIME), { Transparency = 1 }):Play()
			end
		end
		task.delay(FADE_TIME + 0.1, function()
			model:Destroy()
		end)
	end
	walk(player, model, plot, path, speed, true, vanish)
	task.delay(LEAVE_FAILSAFE, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

-- Чужой NPC (строители стройки, ConstructionService) идёт тем же шагом по точкам path (координаты
-- участка, Y — пол; у модели атрибут StandHeight). Общий лимит MAX_WALKERS: нет места — false,
-- NPC остаётся на месте. onDone — когда дошёл (модель удалена — не вызывается)
function StaffLife.walkTo(
	player: Player,
	model: Model,
	plot: BasePart,
	path: { Vector3 },
	speed: number,
	onDone: () -> ()
): boolean
	if #walkers >= MAX_WALKERS or #path == 0 then
		return false
	end
	model:SetAttribute("FloorY", path[1].Y)
	walk(player, model, plot, path, speed, false, onDone)
	return true
end

-- Остановить NPC (строители уходят со стройки): модель остаётся там, где стоит
function StaffLife.stopWalking(model: Model)
	for i = #walkers, 1, -1 do
		if walkers[i].model == model then
			table.remove(walkers, i)
		end
	end
	setWalking(model, nil)
end

function StaffLife.start()
	RunService.Heartbeat:Connect(function(dt: number)
		if #walkers > 0 then
			step(dt)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(schedule, player)
				if not ok then
					warn("[StaffLife] schedule failed:", err)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		StaffLife.reset(player)
		nextCheck[player] = nil
		for _, model in leaving[player] or {} do
			model:Destroy()
		end
		leaving[player] = nil
		for i = #walkers, 1, -1 do
			if walkers[i].player == player then
				table.remove(walkers, i)
			end
		end
	end)
end

return StaffLife
