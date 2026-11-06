--!strict
-- «Игра недели» между серверами (Config/Gotw, вкладка в окне 📊 — GotwPanel).
--   * Каждый релиз (DevelopmentService → onGameReleased) сравнивается с лучшей игрой недели
--     игрока (profile.gotw): сначала оценка, потом доход. Лучшая уходит в OrderedDataStore
--     GOTW_<isoWeek> (userId -> Gotw.value) и детали — в DataStore GotwEntries_v1.
--   * Запись пачками: раз в Gotw.flushSeconds не больше Gotw.writeBatch игроков, каждый не чаще
--     Gotw.writeSeconds; при выходе игрока и в BindToClose — сразу. Все вызовы DataStore в pcall.
--   * Топ-10 текущей недели читается раз в Gotw.readSeconds; детали — только изменившихся строк.
--   * Смена недели: топ-10 прошлой недели читается один раз; победитель при входе (или сразу,
--     если он онлайн) получает минуты дохода, временный титул gotw_winner (TitleService — одна
--     общая табличка, место из атрибута GotwRank) и статуэтку
--     на полке хитов (HitService.refreshShelf) до конца недели.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gotw = require(Shared.Config.Gotw)
local GotwRemotes = require(Shared.GotwRemotes)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local FeatureReleaseService = require(script.Parent.FeatureReleaseService)

export type Entry = {
	player: string, -- имя автора (DisplayName на момент релиза)
	studio: string,
	name: string,
	genreId: string,
	score: number,
	revenue: number,
}
export type Row = {
	rank: number,
	userId: number,
	value: number,
	player: string,
	studio: string,
	name: string,
	genreId: string,
	score: number,
	revenue: number,
}
type Pending = { userId: number, weekId: number, value: number, entry: Entry }
type Board = { weekId: number, available: boolean, rows: { Row } }

local CLOSE_TIMEOUT = 20
local WEEK_CHECK = 30
local MAX_TEXT = 200

local GotwService = {}

local entryStore: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("GotwEntries_v1")
	end)
	if ok then
		entryStore = result
	else
		warn("[GotwService] DataStore GotwEntries_v1 недоступен:", result)
	end
end

local ordered: { [string]: OrderedDataStore } = {}
local function orderedStore(weekId: number): OrderedDataStore?
	local name = Gotw.storeName(weekId)
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

-- ===== Состояние сервера =====

local pending: { [number]: Pending } = {}
local lastWrite: { [number]: number } = {} -- userId -> os.clock последней записи
local entryCache: { [string]: { value: number, entry: Entry } } = {}
local board: Board = { weekId = Gotw.weekId(), available = false, rows = {} }
local lastWeek: Board = { weekId = -1, available = false, rows = {} }
local lastRequest: { [Player]: number } = {}
local trophyShown: { [Player]: boolean } = {}

local function num(value: any): number
	local n = tonumber(value)
	return if n and n == n and n >= 0 and n < math.huge then n else 0
end

local function text(value: any): string
	return if type(value) == "string" and #value <= MAX_TEXT then value else "?"
end

local function studioNameOf(player: Player, profile: DataService.Profile): string
	local name = (profile :: any).studioName
	return if type(name) == "string" and name ~= "" then name else "Studio " .. player.DisplayName
end

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

-- ===== Чтение =====

local function readEntry(weekId: number, userId: number, value: number): Entry?
	local key = Gotw.entryKey(weekId, userId)
	local cached = entryCache[key]
	if cached and cached.value == value then
		return cached.entry
	end
	local store = entryStore
	if not store then
		return nil
	end
	local ok, result = pcall(function()
		return (store :: DataStore):GetAsync(key)
	end)
	if not ok then
		warn("[GotwService] Чтение игры недели не удалось:", key, result)
		return if cached then cached.entry else nil
	end
	if type(result) ~= "table" then
		return nil
	end
	local raw = result :: any
	local entry: Entry = {
		player = text(raw.player),
		studio = text(raw.studio),
		name = text(raw.name),
		genreId = text(raw.genreId),
		score = math.min(num(raw.score), 10),
		revenue = num(raw.revenue),
	}
	entryCache[key] = { value = value, entry = entry }
	return entry
end

-- Топ недели weekId; nil — OrderedDataStore не ответил
local function readBoard(weekId: number): { Row }?
	local store = orderedStore(weekId)
	if not store then
		return nil
	end
	local ok, page = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, Gotw.topSize):GetCurrentPage()
	end)
	if not ok then
		warn("[GotwService] Чтение топа не удалось:", Gotw.storeName(weekId), page)
		return nil
	end
	local rows: { Row } = {}
	for _, item in page :: any do
		local userId = tonumber(item.key)
		local value = num(item.value)
		if userId and value > 0 then
			local entry = readEntry(weekId, userId, value)
			local score = value // Gotw.scoreFactor
			table.insert(rows, {
				rank = #rows + 1,
				userId = userId,
				value = value,
				player = if entry then entry.player else "#" .. userId,
				studio = if entry then entry.studio else "?",
				name = if entry then entry.name else "?",
				genreId = if entry then entry.genreId else "",
				score = if entry then entry.score else score,
				revenue = if entry then entry.revenue else value - score * Gotw.scoreFactor,
			})
		end
	end
	return rows
end

-- ===== Клиенту =====

local function mineOf(profile: DataService.Profile?): any
	local g = profile and (profile :: any).gotw
	if type(g) ~= "table" or g.week ~= Gotw.weekId() or g.value <= 0 then
		return nil
	end
	return { name = g.name, genreId = g.genreId, score = g.score, revenue = g.revenue }
end

local function payloadFor(player: Player): any
	return {
		available = board.available,
		weekKey = Gotw.weekKey(board.weekId),
		endsAt = Gotw.weekEndsAt(board.weekId),
		rows = board.rows,
		last = if lastWeek.weekId == board.weekId - 1 then lastWeek.rows else {},
		mine = mineOf(DataService.get(player)),
	}
end

local function sendBoard(player: Player)
	if player.Parent then
		GotwRemotes.GotwBoard:FireClient(player, payloadFor(player))
	end
end

local function broadcast()
	for _, player in Players:GetPlayers() do
		sendBoard(player)
	end
end

-- ===== Запись =====

local function writePending(p: Pending)
	local store = orderedStore(p.weekId)
	if store then
		local ok, err = pcall(function()
			(store :: OrderedDataStore):SetAsync(tostring(p.userId), p.value)
		end)
		if not ok then
			warn("[GotwService] Запись в топ не удалась:", p.userId, err)
			-- Не перетираем более свежую запись, которая могла появиться за время yield
			if not pending[p.userId] then
				pending[p.userId] = p
			end
			return
		end
	end
	local entries = entryStore
	if entries then
		local ok, err = pcall(function()
			(entries :: DataStore):SetAsync(Gotw.entryKey(p.weekId, p.userId), p.entry)
		end)
		if not ok then
			warn("[GotwService] Запись игры недели не удалась:", p.userId, err)
		end
	end
	entryCache[Gotw.entryKey(p.weekId, p.userId)] = { value = p.value, entry = p.entry }
end

-- Записать изменённых: без force — пачкой и с интервалом на игрока
local function flush(force: boolean)
	local now = os.clock()
	local batch: { Pending } = {}
	for userId, p in pending do
		if not force and #batch >= Gotw.writeBatch then
			break
		end
		if force or (lastWrite[userId] or -math.huge) + Gotw.writeSeconds <= now then
			table.insert(batch, p)
		end
	end
	-- Снимаем из очереди до yield: новый релиз во время записи снова попадёт в pending
	for _, p in batch do
		pending[p.userId] = nil
		lastWrite[p.userId] = now
	end
	for _, p in batch do
		writePending(p)
	end
end

-- Лучшая игра игрока сразу в таблице этого сервера (до следующего чтения из DataStore)
local function mergeLocal(userId: number, value: number, entry: Entry)
	if board.weekId ~= Gotw.weekId() then
		return
	end
	local rows = board.rows
	for i = #rows, 1, -1 do
		if rows[i].userId == userId then
			if rows[i].value >= value then
				return
			end
			table.remove(rows, i)
		end
	end
	table.insert(rows, {
		rank = 0,
		userId = userId,
		value = value,
		player = entry.player,
		studio = entry.studio,
		name = entry.name,
		genreId = entry.genreId,
		score = entry.score,
		revenue = entry.revenue,
	})
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	while #rows > Gotw.topSize do
		table.remove(rows)
	end
	for i, row in rows do
		row.rank = i
	end
	board.available = true
end

-- name уже отфильтрован TextService в DevelopmentService
function GotwService.onGameReleased(
	player: Player,
	info: { name: string, genreId: string, score: number, revenue: number }
)
	local profile = DataService.get(player)
	if not profile or player.UserId <= 0 then
		return
	end
	local g = profile.gotw
	local weekId = Gotw.weekId()
	if g.week ~= weekId then
		g.week = weekId
		g.value = 0
		g.name = ""
		g.genreId = ""
		g.score = 0
		g.revenue = 0
	end
	local score = math.clamp(math.floor(num(info.score)), 0, 10)
	local revenue = math.floor(num(info.revenue))
	local value = Gotw.value(score, revenue)
	if value <= g.value then
		return
	end
	g.value = value
	g.name = text(info.name)
	g.genreId = text(info.genreId)
	g.score = score
	g.revenue = revenue
	local entry: Entry = {
		player = player.DisplayName,
		studio = studioNameOf(player, profile),
		name = g.name,
		genreId = g.genreId,
		score = score,
		revenue = revenue,
	}
	pending[player.UserId] = { userId = player.UserId, weekId = weekId, value = value, entry = entry }
	mergeLocal(player.UserId, value, entry)
end

-- ===== Награда и титул =====

-- Титул и статуэтка: действуют до titleUntil / trophyUntil
local function applyTitle(player: Player, profile: DataService.Profile)
	local g = profile.gotw
	local now = os.time()
	local rank = if g.titleUntil > now and g.titleRank > 0 then g.titleRank else 0
	-- Место для таблички титула (TitleTags); сам титул — общий временный gotw_winner.
	-- grant идемпотентен: уже действующий титул только продлевается (без тоста)
	player:SetAttribute("GotwRank", if rank > 0 then rank else nil)
	if rank > 0 then
		local titles = optional("TitleService")
		if titles and type(titles.grant) == "function" then
			pcall(titles.grant, player, "gotw_winner", g.titleUntil)
		end
	end
	local trophy = g.trophyUntil > now
	if trophyShown[player] ~= trophy then
		trophyShown[player] = trophy
		local hits = optional("HitService")
		if hits and type(hits.refreshShelf) == "function" then
			pcall(hits.refreshShelf, player)
		end
	end
end

local function checkReward(player: Player, profile: DataService.Profile)
	local g = profile.gotw
	local current = Gotw.weekId()
	-- Топ прошлой недели ещё не прочитан (или DataStore недоступен) — проверим позже
	if g.rewardWeek < current and lastWeek.weekId == current - 1 and lastWeek.available then
		g.rewardWeek = current
		local rank: number? = nil
		for _, row in lastWeek.rows do
			if row.userId == player.UserId then
				rank = row.rank
				break
			end
		end
		if rank then
			local minutes = Gotw.rewardMinutes[rank] or Gotw.rewardMinutes[#Gotw.rewardMinutes]
			local money = RewardService.incomeForMinutes(player, profile, minutes)
			RewardService.grant(player, { incomeMinutes = minutes })
			g.titleRank = rank
			g.titleUntil = Gotw.weekEndsAt(current)
			g.trophyUntil = Gotw.weekEndsAt(current)
			GotwRemotes.GotwNotice:FireClient(player, { kind = "winner", rank = rank, money = money })
			task.spawn(DataService.save, player)
		end
	end
	applyTitle(player, profile)
end

local function checkAll()
	for _, player in Players:GetPlayers() do
		local profile = DataService.get(player)
		if profile then
			checkReward(player, profile)
		end
	end
end

-- ===== Обновления =====

local function refreshLastWeek()
	local wanted = Gotw.weekId() - 1
	if lastWeek.weekId == wanted and lastWeek.available then
		return
	end
	local rows = readBoard(wanted)
	lastWeek = { weekId = wanted, available = rows ~= nil, rows = rows or {} }
	if rows then
		checkAll()
	end
end

local function refreshBoard()
	local weekId = Gotw.weekId()
	local rows = readBoard(weekId)
	if rows then
		board = { weekId = weekId, available = true, rows = rows }
		-- Свои ещё не записанные лучшие игры этого сервера — поверх прочитанного
		for userId, p in pending do
			if p.weekId == weekId then
				mergeLocal(userId, p.value, p.entry)
			end
		end
	elseif board.weekId ~= weekId then
		board = { weekId = weekId, available = false, rows = {} }
	end
	broadcast()
end

-- Топ прошлой недели для Зала славы (HallOfFameService); nil — ещё не прочитан
function GotwService.lastWeekRows(): { Row }?
	if lastWeek.weekId == Gotw.weekId() - 1 and lastWeek.available then
		return lastWeek.rows
	end
	return nil
end

-- ===== Remotes и жизненный цикл =====

local function onRequest(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + Gotw.requestCooldown > now then
		return
	end
	lastRequest[player] = now
	sendBoard(player)
end

local function onPlayerRemoving(player: Player)
	lastRequest[player] = nil
	trophyShown[player] = nil
	-- Последний шанс записать лучшую игру этого игрока с этого сервера
	local p = pending[player.UserId]
	if p then
		pending[player.UserId] = nil
		lastWrite[player.UserId] = os.clock()
		task.spawn(writePending, p)
	end
end

local function startNow()
	GotwRemotes.GotwRequest.OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	DataService.onProfileLoaded(function(player: Player, profile: DataService.Profile)
		checkReward(player, profile)
		sendBoard(player)
	end)

	task.spawn(function()
		refreshLastWeek()
		refreshBoard()
		local nextRead = os.clock() + Gotw.readSeconds
		local nextFlush = os.clock() + Gotw.flushSeconds
		local knownWeek = Gotw.weekId()
		while true do
			task.wait(WEEK_CHECK)
			local ok, err = pcall(function()
				local now = os.clock()
				if Gotw.weekId() ~= knownWeek then
					-- Новая неделя: дописать хвост прошлой, прочитать её итоги, наградить онлайн
					knownWeek = Gotw.weekId()
					flush(true)
					refreshLastWeek()
					refreshBoard()
					checkAll()
					nextRead = now + Gotw.readSeconds
				end
				if now >= nextFlush then
					nextFlush = now + Gotw.flushSeconds
					flush(false)
				end
				if now >= nextRead then
					nextRead = now + Gotw.readSeconds
					refreshLastWeek()
					refreshBoard()
				end
			end)
			if not ok then
				warn("[GotwService] loop failed:", err)
			end
		end
	end)

	game:BindToClose(function()
		local batch: { Pending } = {}
		for _, p in pending do
			table.insert(batch, p)
		end
		pending = {}
		local left = #batch
		for _, p in batch do
			task.spawn(function()
				pcall(writePending, p)
				left -= 1
			end)
		end
		local deadline = os.clock() + CLOSE_TIMEOUT
		while left > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

-- Обновления по средам (Config/Features): до выхода системы «gotw» сервис спит — remotes
-- заглушены, циклы и обработчики не запущены; вышла (в т. ч. пока сервер работает) — startNow()
function GotwService.start()
	FeatureReleaseService.mute("gotw", {
		GotwRemotes.GotwRequest,
	})
	FeatureReleaseService.whenReleased("gotw", "GotwService", startNow)
end

return GotwService
