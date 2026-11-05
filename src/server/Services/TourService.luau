--!strict
-- Экскурсии по студиям, лайки и глобальные рейтинги (Config/Tours, окно — TourWindow).
--   * «Посетить»: перенос к воротам чужой студии (проверка на сервере, кулдаун, не во время погони).
--   * «👍 Нравится»: стоя на чужом участке или из списка после Tours.likeAfterSeconds на нём;
--     один лайк от посетителя студии в UTC-день, свою нельзя. Владелец вышел — лайк копится
--     и уходит одним UpdateAsync в DataStore Likes_v1, при следующем входе сливается в профиль.
--   * Рейтинги (OrderedDataStore): лайки недели LikesWeekly_<weekId>, стоимость студии
--     StudioValue_v1, лучший хит недели BestHit_<weekId>. Запись — не чаще Tours.writeSeconds
--     на игрока и только изменённого; топ-50 читается раз в Tours.readSeconds на сервер.
--   * Награда недели: при первом входе новой недели топ-10 лайков прошлой — минуты дохода и ⭐.
-- Атрибуты игрока: Likes, LikesWeek, WeeklyStar. Все вызовы DataStore — в pcall.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage.Shared
local Tours = require(Shared.Config.Tours)
local Upgrades = require(Shared.Config.Upgrades)
local Stages = require(Shared.Config.Stages)
local TourRemotes = require(Shared.TourRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local RewardService = require(script.Parent.RewardService)

local TICK = 1 -- шаг учёта «сколько стоит на чужом участке», с
local WRITE_CHECK = 30
local REQUEST_COOLDOWN = 1
local LIKE_COOLDOWN = 1
-- Участок: перед воротами (+Z) ещё FRONT_MARGIN studs — туда ставит «Посетить»
local FRONT_MARGIN = 7
local PLOT_HEIGHT = 80 -- три этажа офиса и крыша
local HOME_OUTSIDE = 4 -- как в PlotService.sendHome
local HOME_HEIGHT = 3.5

type Likes = { total: number, week: { weekId: number, count: number } }
type TourData = {
	day: number,
	given: { [string]: boolean },
	rewardWeek: number,
	badgeWeeklyStar: boolean,
	starWeek: number,
	hit: { weekId: number, value: number },
}
type Entry = { userId: number, name: string, value: number }
type Boards = { available: boolean, weekId: number, likes: { Entry }, value: { Entry }, hit: { Entry } }
type Recent = { userId: number, name: string, studio: string, stage: number }
type Written = { weekId: number, likes: number, value: number, hit: number, at: number }

local TourService = {}

-- ===== Хранилища =====

local queueStore: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("Likes_v1")
	end)
	if ok then
		queueStore = result
	else
		warn("[TourService] DataStore Likes_v1 недоступен:", result)
	end
end

local ordered: { [string]: OrderedDataStore } = {}
local function orderedStore(name: string): OrderedDataStore?
	local cached = ordered[name]
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if not ok then
		return nil
	end
	ordered[name] = result
	return result
end

local function likesStoreName(weekId: number): string
	return "LikesWeekly_" .. weekId
end
local function hitStoreName(weekId: number): string
	return "BestHit_" .. weekId
end
local VALUE_STORE = "StudioValue_v1"

-- ===== Состояние сервера =====

local visitSeconds: { [Player]: { [number]: number } } = {} -- посетитель -> userId владельца -> секунды
local recent: { [Player]: { Recent } } = {} -- посещённые студии вышедших владельцев
local lastVisit: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
local lastLike: { [Player]: number } = {}
local pendingLikes: { [number]: number } = {} -- владелец вышел: userId -> лайков в очереди
local written: { [number]: Written } = {}
local pendingWrite: { [number]: boolean } = {}
local names: { [number]: string } = {}
local boards: Boards = { available = false, weekId = Tours.weekId(), likes = {}, value = {}, hit = {} }
-- Топ-10 лайков прошлой недели: weekId -> userId -> место (читается один раз на сервер)
local lastWeekTop: { [number]: { [number]: number } } = {}
local parkRows: { TextLabel } = {}

local function num(value: any): number
	local n = tonumber(value)
	return if n and n == n and n >= 0 and n < math.huge then math.floor(n) else 0
end

-- ===== Профиль =====

local function likesOf(profile: DataService.Profile): Likes
	local p = profile :: any
	local raw = if type(p.likes) == "table" then p.likes else {}
	local week = if type(raw.week) == "table" then raw.week else {}
	local current = Tours.weekId()
	local likes: Likes = {
		total = num(raw.total),
		week = if num(week.weekId) == current
			then { weekId = current, count = num(week.count) }
			else { weekId = current, count = 0 },
	}
	p.likes = likes
	return likes
end

local function tourOf(profile: DataService.Profile): TourData
	local p = profile :: any
	local raw = if type(p.tours) == "table" then p.tours else {}
	local today = Tours.dayId()
	local given: { [string]: boolean } = {}
	if num(raw.day) == today and type(raw.given) == "table" then
		for key, value in raw.given do
			if type(key) == "string" and value == true then
				given[key] = true
			end
		end
	end
	local hit = if type(raw.hit) == "table" then raw.hit else {}
	local data: TourData = {
		day = today,
		given = given,
		rewardWeek = num(raw.rewardWeek),
		badgeWeeklyStar = raw.badgeWeeklyStar == true,
		starWeek = num(raw.starWeek),
		hit = { weekId = num(hit.weekId), value = num(hit.value) },
	}
	p.tours = data
	return data
end

local function studioNameOf(player: Player, profile: DataService.Profile): string
	local name = (profile :: any).studioName
	return if type(name) == "string" and name ~= "" then name else "Studio " .. player.DisplayName
end

-- Стоимость студии: купленные апгрейды + этажи + деньги
local function studioValue(profile: DataService.Profile): number
	local total = math.max(num(profile.cash), 0)
	for _, upgrade in Upgrades do
		if profile.upgrades[upgrade.id] then
			total += math.max(upgrade.cost, 0)
		end
	end
	for _, stage in Stages do
		if stage.level <= profile.studioLevel then
			total += math.max(stage.cost, 0)
		end
	end
	return math.min(math.floor(total), Tours.valueCap)
end

local function hitValue(data: TourData): number
	return if data.hit.weekId == Tours.weekId() then data.hit.value else 0
end

-- ===== Табличка «👍 N» у вывески =====

local function signText(count: number): string
	return "👍 " .. count
end

local function applySign(player: Player)
	local plot = PlotService.getPlot(player)
	local profile = DataService.get(player)
	if not plot or not profile then
		return
	end
	local count = likesOf(profile).total
	local old = plot:FindFirstChild("LikesSign")
	if not PlotService.ownsGarage(player) then
		if old then
			old:Destroy()
		end
		return
	end
	if old then
		for _, label in old:GetDescendants() do
			if label:IsA("TextLabel") then
				label.Text = signText(count)
			end
		end
		return
	end
	-- Модель: PlotService.rebuild сносит её вместе с остальными, plotChanged ставит заново
	local model = Instance.new("Model")
	model.Name = "LikesSign"
	local board = Instance.new("Part")
	board.Name = "Board"
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.CanTouch = false
	board.Size = Vector3.new(Tours.signSize.X, Tours.signSize.Y, 0.4)
	board.Color = Color3.fromRGB(28, 26, 40)
	board.Material = Enum.Material.SmoothPlastic
	board.CFrame = plot.CFrame * Tours.signOffset
	board.Parent = model
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Name = "Likes"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(61, 220, 132)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = signText(count)
		label.Parent = gui
	end
	model.Parent = plot
end

-- ===== Доска «Студии недели» в парке =====

local function buildParkBoard()
	local spot = Tours.parkBoard
	local park = workspace:FindFirstChild("StartPark")
	if not spot or not park then
		return
	end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local center = if spawn and spawn:IsA("BasePart")
		then Vector3.new(spawn.Position.X, 0, spawn.Position.Z)
		else Vector3.zero
	local model = Instance.new("Model")
	model.Name = "LikesBoard"
	local height, width = 9, 7
	local board = Instance.new("Part")
	board.Name = "Board"
	board.Anchored = true
	board.Size = Vector3.new(width, height, 0.5)
	board.Color = Color3.fromRGB(28, 26, 40)
	board.Material = Enum.Material.SmoothPlastic
	local base = CFrame.new(center + spot.position) * CFrame.Angles(0, math.rad(spot.yaw), 0)
	board.CFrame = base * CFrame.new(0, 2 + height / 2, 0)
	board.Parent = model
	for _, x in { -width / 2 + 0.5, width / 2 - 0.5 } do
		local post = Instance.new("Part")
		post.Anchored = true
		post.Size = Vector3.new(0.4, 2, 0.4)
		post.Color = Color3.fromRGB(60, 60, 65)
		post.Material = Enum.Material.Metal
		post.CFrame = base * CFrame.new(x, 1, 0)
		post.Parent = model
	end
	-- Лицо модели — +Z (как у моделей парка): грань Back
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Parent = board
	-- Раскладка — в рамке во всю доску (UIPadding работает только внутри GuiObject)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = holder
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = holder
	local rows = spot.rows
	local rowHeight = 1 / (rows + 2.5)
	local title = Instance.new("TextLabel")
	title.Name = "SignText"
	title.Size = UDim2.fromScale(1, rowHeight * 1.5)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 201, 60)
	title.Text = "👍 Студии недели"
	-- Перевод — StartParkController по TextKey
	title:SetAttribute("TextKey", "tour_board_title")
	title.LayoutOrder = 0
	title.Parent = holder
	parkRows = {}
	for i = 1, rows do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.Size = UDim2.fromScale(1, rowHeight)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamMedium
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if i <= 3 then Color3.fromRGB(255, 201, 60) else Color3.new(1, 1, 1)
		row.Text = ""
		row.LayoutOrder = i
		row.Parent = holder
		table.insert(parkRows, row)
	end
	model.Parent = park
end

local function refreshParkBoard()
	for i, row in parkRows do
		local entry = boards.likes[i]
		row.Text = if entry then string.format("%d. %s — 👍 %d", i, entry.name, entry.value) else ""
	end
end

-- ===== Имена для рейтингов =====

local function resolveNames(ids: { number })
	local missing = {}
	for _, userId in ids do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			names[userId] = player.DisplayName
		elseif not names[userId] then
			table.insert(missing, userId)
		end
	end
	if #missing == 0 then
		return
	end
	-- Одним запросом до 200 имён (не тратит бюджет DataStore)
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info) == "table" and type(info.Id) == "number" then
				local display = info.DisplayName
				names[info.Id] = if type(display) == "string" and display ~= ""
					then display
					else info.Username
			end
		end
	end
	for _, userId in missing do
		if not names[userId] then
			names[userId] = "#" .. userId
		end
	end
end

local function readTop(name: string, size: number): { Entry }?
	local store = orderedStore(name)
	if not store then
		return nil
	end
	local ok, result = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, size):GetCurrentPage()
	end)
	if not ok then
		warn("[TourService] Чтение топа не удалось:", name, result)
		return nil
	end
	local entries: { Entry } = {}
	for _, item in result :: any do
		local userId = tonumber(item.key)
		local value = num(item.value)
		if userId and value > 0 then
			table.insert(entries, { userId = userId, name = "", value = value })
		end
	end
	return entries
end

local function refreshBoards()
	local weekId = Tours.weekId()
	local likes = readTop(likesStoreName(weekId), Tours.topSize)
	local value = readTop(VALUE_STORE, Tours.topSize)
	local hit = readTop(hitStoreName(weekId), Tours.topSize)
	if not likes and not value and not hit then
		boards = { available = false, weekId = weekId, likes = {}, value = {}, hit = {} }
	else
		local ids = {}
		for _, list in { likes or {}, value or {}, hit or {} } do
			for _, entry in list do
				table.insert(ids, entry.userId)
			end
		end
		resolveNames(ids)
		for _, list in { likes or {}, value or {}, hit or {} } do
			for _, entry in list do
				entry.name = names[entry.userId] or ("#" .. entry.userId)
			end
		end
		boards =
			{ available = true, weekId = weekId, likes = likes or {}, value = value or {}, hit = hit or {} }
	end
	refreshParkBoard()
	TourRemotes.TourBoards:FireAllClients(boards)
end

-- ===== Запись в рейтинги =====

local function snapshot(player: Player): Written?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	return {
		weekId = Tours.weekId(),
		likes = likesOf(profile).week.count,
		value = studioValue(profile),
		hit = hitValue(tourOf(profile)),
		at = 0,
	}
end

local function setOrdered(name: string, userId: number, value: number)
	local store = orderedStore(name)
	if not store then
		return
	end
	local ok, err = pcall(function()
		(store :: OrderedDataStore):SetAsync(tostring(userId), value)
	end)
	if not ok then
		warn("[TourService] Запись в рейтинг не удалась:", name, err)
	end
end

-- Записать изменившееся, если с прошлой записи прошло Tours.writeSeconds; иначе при выходе —
-- отложить до конца интервала
local function maybeWrite(userId: number, snap: Written, deferIfEarly: boolean)
	if userId <= 0 then
		return
	end
	local w = written[userId]
	local sameWeek = w ~= nil and w.weekId == snap.weekId
	local likesChanged = snap.likes > 0 and not (sameWeek and w.likes == snap.likes)
	local hitChanged = snap.hit > 0 and not (sameWeek and w.hit == snap.hit)
	local valueChanged = not (w and w.value == snap.value)
	if not likesChanged and not hitChanged and not valueChanged then
		return
	end
	local now = os.clock()
	local wait = if w then w.at + Tours.writeSeconds - now else 0
	if wait > 0 then
		if deferIfEarly and not pendingWrite[userId] then
			pendingWrite[userId] = true
			task.delay(wait, function()
				pendingWrite[userId] = nil
				maybeWrite(userId, snap, false)
			end)
		end
		return
	end
	-- Отмечаем до yield, чтобы параллельный вызов не записал второй раз
	written[userId] =
		{ weekId = snap.weekId, likes = snap.likes, value = snap.value, hit = snap.hit, at = now }
	if likesChanged then
		setOrdered(likesStoreName(snap.weekId), userId, snap.likes)
	end
	if hitChanged then
		setOrdered(hitStoreName(snap.weekId), userId, snap.hit)
	end
	if valueChanged then
		setOrdered(VALUE_STORE, userId, snap.value)
	end
end

-- ===== Лайки =====

local function setAttributes(player: Player, profile: DataService.Profile)
	local likes = likesOf(profile)
	player:SetAttribute("Likes", likes.total)
	player:SetAttribute("LikesWeek", likes.week.count)
	player:SetAttribute("WeeklyStar", tourOf(profile).badgeWeeklyStar)
end

local function noteAchievement(player: Player, amount: number)
	local module = script.Parent:FindFirstChild("AchievementService")
	if module and module:IsA("ModuleScript") then
		pcall((require(module) :: any).note, player, "likesReceived", amount)
	end
end

-- Владельцу на этом сервере: в профиль, табличку, атрибуты и тост
local function addLikes(owner: Player, profile: DataService.Profile, amount: number, fromName: string?)
	local likes = likesOf(profile)
	likes.total += amount
	likes.week.count += amount
	setAttributes(owner, profile)
	applySign(owner)
	noteAchievement(owner, amount)
	TourRemotes.TourNotice:FireClient(owner, { kind = "liked", name = fromName, count = amount })
end

-- Владелец вышел: в очередь, её сбрасывает flushQueue
local function queueLike(userId: number, amount: number)
	pendingLikes[userId] = (pendingLikes[userId] or 0) + amount
end

local function flushQueue()
	local store = queueStore
	if not store then
		pendingLikes = {}
		return
	end
	local batch = pendingLikes
	pendingLikes = {}
	local weekId = Tours.weekId()
	for userId, amount in batch do
		-- Владелец успел вернуться на этот сервер — сразу в профиль
		local owner = Players:GetPlayerByUserId(userId)
		local profile = owner and DataService.get(owner)
		if owner and profile then
			addLikes(owner, profile, amount, nil)
			continue
		end
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(tostring(userId), function(old: any): any
				local record = if type(old) == "table" then old else {}
				local sameWeek = num(record.weekId) == weekId
				return {
					total = num(record.total) + amount,
					weekId = weekId,
					week = (if sameWeek then num(record.week) else 0) + amount,
				}
			end)
		end)
		if ok then
			-- Лайки недели видны в рейтинге и без входа владельца; при входе профиль запишет то же число
			local weekly = orderedStore(likesStoreName(weekId))
			if weekly then
				pcall(function()
					(weekly :: OrderedDataStore):IncrementAsync(tostring(userId), amount)
				end)
			end
		else
			warn("[TourService] Очередь лайков не записалась:", userId, err)
			queueLike(userId, amount)
		end
	end
end

-- Вход: забрать лайки, накопленные, пока владельца не было
local function mergeQueued(player: Player, profile: DataService.Profile)
	local userId = player.UserId
	local held = pendingLikes[userId]
	if held then
		pendingLikes[userId] = nil
		addLikes(player, profile, held, nil)
	end
	local store = queueStore
	if not store or userId <= 0 then
		return
	end
	-- Сначала дешёвое чтение: у большинства очередь пустая
	local okRead, current = pcall(function()
		return (store :: DataStore):GetAsync(tostring(userId))
	end)
	if not okRead or type(current) ~= "table" or num((current :: any).total) <= 0 then
		return
	end
	local taken: any = nil
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(tostring(userId), function(old: any): any
			taken = old
			return { total = 0, weekId = Tours.weekId(), week = 0 }
		end)
	end)
	if not ok then
		warn("[TourService] Очередь лайков не прочиталась:", userId, err)
		return
	end
	if type(taken) ~= "table" or not player.Parent or DataService.get(player) ~= profile then
		return
	end
	local total = num(taken.total)
	if total <= 0 then
		return
	end
	local likes = likesOf(profile)
	local week = if num(taken.weekId) == likes.week.weekId then math.min(num(taken.week), total) else 0
	likes.total += total
	likes.week.count += week
	setAttributes(player, profile)
	applySign(player)
	noteAchievement(player, total)
	TourRemotes.TourNotice:FireClient(player, { kind = "likedOffline", count = total })
	task.spawn(DataService.save, player)
end

-- ===== Награда недели =====

local function lastWeekRank(weekId: number, userId: number): (boolean, number?)
	local top = lastWeekTop[weekId]
	if not top then
		local entries = readTop(likesStoreName(weekId), Tours.weeklyTop)
		if not entries then
			return false, nil
		end
		top = {}
		for i, entry in entries do
			(top :: any)[entry.userId] = i
		end
		lastWeekTop[weekId] = top
	end
	return true, (top :: any)[userId]
end

local function checkWeeklyReward(player: Player, profile: DataService.Profile, lastWeekCount: number)
	local data = tourOf(profile)
	local current = Tours.weekId()
	if data.rewardWeek >= current then
		return
	end
	if lastWeekCount <= 0 then
		data.rewardWeek = current
		return
	end
	local ok, rank = lastWeekRank(current - 1, player.UserId)
	-- Рейтинг не прочитался — попробуем при следующем входе
	if not ok or not player.Parent or DataService.get(player) ~= profile then
		return
	end
	data = tourOf(profile)
	if data.rewardWeek >= current then
		return
	end
	data.rewardWeek = current
	if not rank then
		return
	end
	data.badgeWeeklyStar = true
	data.starWeek = current - 1
	local money = RewardService.incomeForMinutes(player, profile, Tours.weeklyRewardMinutes)
	RewardService.grant(player, { incomeMinutes = Tours.weeklyRewardMinutes })
	setAttributes(player, profile)
	TourRemotes.TourNotice:FireClient(player, { kind = "weeklyStar", rank = rank, money = money })
	task.spawn(DataService.save, player)
end

-- ===== Где стоит игрок =====

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Владелец участка, на котором (или у ворот которого) стоит точка
local function ownerAt(position: Vector3): Player?
	for _, player in Players:GetPlayers() do
		local plot = PlotService.getPlot(player)
		if plot then
			local p = plot.CFrame:PointToObjectSpace(position)
			local hx, hz = plot.Size.X / 2, plot.Size.Z / 2
			if
				math.abs(p.X) <= hx
				and p.Z >= -hz
				and p.Z <= hz + FRONT_MARGIN
				and p.Y > -5
				and p.Y < PLOT_HEIGHT
			then
				return player
			end
		end
	end
	return nil
end

local function standingAt(visitor: Player): Player?
	local root = rootOf(visitor)
	return if root then ownerAt(root.Position) else nil
end

local function inChase(player: Player): boolean
	local hits = script.Parent:FindFirstChild("HitService")
	if hits and hits:IsA("ModuleScript") then
		local ok, busy = pcall((require(hits) :: any).inChase, player)
		return ok and busy == true
	end
	return false
end

-- ===== Список для окна =====

local function canLikeFrom(visitor: Player, userId: number): boolean
	local seconds = visitSeconds[visitor]
	return (seconds and (seconds[userId] or 0) >= Tours.likeAfterSeconds) == true
end

local function sendList(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = tourOf(profile)
	local here = standingAt(player)
	local studios = {}
	for _, other in Players:GetPlayers() do
		local otherProfile = DataService.get(other)
		if otherProfile then
			local likes = likesOf(otherProfile)
			local own = other == player
			table.insert(studios, {
				userId = other.UserId,
				name = other.DisplayName,
				studio = studioNameOf(other, otherProfile),
				stage = otherProfile.studioLevel,
				garage = PlotService.ownsGarage(other),
				likes = likes.total,
				likesWeek = likes.week.count,
				vip = other:GetAttribute("IsVip") == true,
				star = tourOf(otherProfile).badgeWeeklyStar,
				own = own,
				liked = data.given[tostring(other.UserId)] == true,
				canLike = not own and (here == other or canLikeFrom(player, other.UserId)),
			})
		end
	end
	local recentList = {}
	for _, item in recent[player] or {} do
		table.insert(recentList, {
			userId = item.userId,
			name = item.name,
			studio = item.studio,
			stage = item.stage,
			liked = data.given[tostring(item.userId)] == true,
		})
	end
	local likes = likesOf(profile)
	TourRemotes.TourList:FireClient(player, {
		studios = studios,
		recent = recentList,
		me = {
			likes = likes.total,
			likesWeek = likes.week.count,
			value = studioValue(profile),
			hit = hitValue(data),
		},
	})
end

-- ===== Обработчики =====

local function onRequest(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	sendList(player)
	TourRemotes.TourBoards:FireClient(player, boards)
end

local function onVisit(player: Player, userId: any)
	if type(userId) ~= "number" or userId ~= userId then
		return
	end
	local now = os.clock()
	if (lastVisit[player] or 0) + Tours.visitCooldown > now then
		TourRemotes.TourNotice:FireClient(player, { kind = "visit", ok = false, reason = "cooldown" })
		return
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target or target == player then
		TourRemotes.TourNotice:FireClient(player, { kind = "visit", ok = false, reason = "gone" })
		return
	end
	local plot = PlotService.getPlot(target)
	if not plot or not PlotService.ownsGarage(target) then
		TourRemotes.TourNotice:FireClient(player, { kind = "visit", ok = false, reason = "nogarage" })
		return
	end
	-- Во время кражи хита не телепортируем: и вор, и жертва сбили бы погоню
	if inChase(player) then
		TourRemotes.TourNotice:FireClient(player, { kind = "visit", ok = false, reason = "chase" })
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	lastVisit[player] = now
	-- Сидящего сначала поднимаем: иначе SeatWeld тянет персонажа обратно к стулу
	local seat = humanoid.SeatPart
	if seat then
		humanoid.Sit = false
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	-- Как PlotService.sendHome: перед воротами, лицом к студии
	character:PivotTo(
		plot.CFrame * CFrame.new(0, plot.Size.Y / 2 + HOME_HEIGHT, plot.Size.Z / 2 + HOME_OUTSIDE)
	)
	TourRemotes.TourNotice:FireClient(player, { kind = "visit", ok = true, name = target.DisplayName })
end

local function onLike(player: Player, userId: any)
	if type(userId) ~= "number" or userId ~= userId or userId <= 0 or userId % 1 ~= 0 then
		return
	end
	local now = os.clock()
	if (lastLike[player] or 0) + LIKE_COOLDOWN > now then
		return
	end
	lastLike[player] = now
	local profile = DataService.get(player)
	if not profile or userId == player.UserId then
		return
	end
	-- Лайкают только игроки со своим гаражом: альты из парка не накручивают недельный топ
	if not PlotService.ownsGarage(player) then
		TourRemotes.TourNotice:FireClient(player, { kind = "like", ok = false, reason = "garage" })
		return
	end
	local owner = Players:GetPlayerByUserId(userId)
	local ownerName: string? = nil
	if owner then
		ownerName = owner.DisplayName
	else
		for _, item in recent[player] or {} do
			if item.userId == userId then
				ownerName = item.name
			end
		end
	end
	local allowed = (owner ~= nil and standingAt(player) == owner) or canLikeFrom(player, userId)
	-- Пустой участок без гаража лайкать не за что
	if owner and not PlotService.ownsGarage(owner) then
		allowed = false
	end
	if not allowed or not ownerName then
		TourRemotes.TourNotice:FireClient(player, { kind = "like", ok = false, reason = "visit" })
		return
	end
	local data = tourOf(profile)
	local key = tostring(userId)
	if data.given[key] then
		TourRemotes.TourNotice:FireClient(
			player,
			{ kind = "like", ok = false, reason = "already", name = ownerName }
		)
		return
	end
	data.given[key] = true
	local ownerProfile = owner and DataService.get(owner)
	if owner and ownerProfile then
		addLikes(owner, ownerProfile, 1, player.DisplayName)
	else
		queueLike(userId, 1)
	end
	TourRemotes.TourNotice:FireClient(player, { kind = "like", ok = true, name = ownerName, userId = userId })
	sendList(player)
end

-- DevelopmentService.release: лучший хит недели — оценка, потом очки игры
function TourService.onGameReleased(player: Player, info: any)
	local profile = DataService.get(player)
	if not profile or type(info) ~= "table" then
		return
	end
	local score = math.clamp(num(info.score), 0, 10)
	if score <= 0 then
		return
	end
	local factor = Tours.hitScoreFactor
	local value = score * factor + math.min(num(info.points), factor - 1)
	local data = tourOf(profile)
	local weekId = Tours.weekId()
	if data.hit.weekId ~= weekId or value > data.hit.value then
		data.hit = { weekId = weekId, value = value }
	end
end

-- ===== Вход и выход =====

local function onProfileLoaded(player: Player, profile: DataService.Profile)
	-- Лайки прошлой недели — до того, как likesOf обнулит неделю
	local raw = (profile :: any).likes
	local lastWeekCount = 0
	if type(raw) == "table" and type(raw.week) == "table" and num(raw.week.weekId) == Tours.weekId() - 1 then
		lastWeekCount = num(raw.week.count)
	end
	-- Новый игрок или первый вход с этой системой: награду ждать не за что
	local tours = (profile :: any).tours
	if type(tours) ~= "table" then
		tourOf(profile).rewardWeek = Tours.weekId()
	end
	setAttributes(player, profile)
	applySign(player)
	mergeQueued(player, profile)
	if player.Parent and DataService.get(player) == profile then
		checkWeeklyReward(player, profile, lastWeekCount)
	end
end

local function onPlayerRemoving(player: Player)
	local snap = snapshot(player)
	if snap then
		maybeWrite(player.UserId, snap, true)
	end
	-- Владелец ушёл: его посетители ещё могут лайкнуть из списка «Недавно»
	local profile = DataService.get(player)
	for visitor, seconds in visitSeconds do
		if visitor ~= player and (seconds[player.UserId] or 0) >= Tours.likeAfterSeconds and profile then
			local list = recent[visitor] or {}
			table.insert(list, 1, {
				userId = player.UserId,
				name = player.DisplayName,
				studio = studioNameOf(player, profile),
				stage = profile.studioLevel,
			})
			while #list > Tours.recentLimit do
				table.remove(list)
			end
			recent[visitor] = list
		end
	end
	visitSeconds[player] = nil
	recent[player] = nil
	lastVisit[player] = nil
	lastRequest[player] = nil
	lastLike[player] = nil
end

function TourService.start()
	TourRemotes.TourRequest.OnServerEvent:Connect(onRequest)
	TourRemotes.TourVisit.OnServerEvent:Connect(onVisit)
	TourRemotes.TourLike.OnServerEvent:Connect(onLike)
	DataService.onProfileLoaded(onProfileLoaded)
	-- PlayerRemoving DataService закрывает профиль в том же кадре: снимок берём до yield
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	PlotService.plotChanged:Connect(function(player: Player)
		applySign(player)
	end)
	buildParkBoard()

	-- Сколько посетители стоят на чужих участках (для лайка из списка)
	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, player in Players:GetPlayers() do
				local owner = standingAt(player)
				if owner and owner ~= player then
					local seconds = visitSeconds[player]
					if not seconds then
						seconds = {}
						visitSeconds[player] = seconds
					end
					seconds[owner.UserId] = math.min((seconds[owner.UserId] or 0) + TICK, 3600)
				end
			end
		end
	end)

	-- Запись рейтингов и очередь лайков вышедшим
	task.spawn(function()
		local lastFlush = os.clock()
		while true do
			task.wait(WRITE_CHECK)
			for _, player in Players:GetPlayers() do
				local snap = snapshot(player)
				if snap then
					task.spawn(maybeWrite, player.UserId, snap, false)
				end
			end
			if os.clock() - lastFlush >= Tours.queueFlushSeconds and next(pendingLikes) then
				lastFlush = os.clock()
				task.spawn(flushQueue)
			end
		end
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(refreshBoards)
			if not ok then
				warn("[TourService] Рейтинги не обновились:", err)
			end
			task.wait(Tours.readSeconds)
		end
	end)

	-- Сервер закрывается: лайки вышедшим владельцам не должны пропасть
	game:BindToClose(function()
		if next(pendingLikes) then
			flushQueue()
		end
	end)
end

return TourService
