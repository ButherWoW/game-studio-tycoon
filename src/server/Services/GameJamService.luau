--!strict
-- Еженедельный гейм-джем (Config/GameJam). Игра по теме недели (жанр + тема) — заявка:
-- лучший результат игрока пишется в OrderedDataStore GameJam_<weekId> (оценка, тайбрейк — доход),
-- не чаще раза в 2 минуты и только если результат улучшился. Топ-100 читается раз в 5 минут.
-- profile.gameJam = { week, best, claims, flags, last } — награда за неделю с заявкой выдаётся
-- при входе (или в игре), когда неделя кончилась и серверы дописали результаты.
-- Все вызовы DataStore — в pcall: без API Services (Studio) джем работает без топа.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameJam = require(ReplicatedStorage.Shared.Config.GameJam)
local LiveOpsRemotes = require(ReplicatedStorage.Shared.LiveOpsRemotes)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)

type JamData = {
	week: number, -- неделя последней заявки (-1 — не участвовал)
	best: number, -- закодированный лучший результат этой недели (GameJam.encode)
	claims: { [string]: boolean }, -- недели с заявкой, награда за которые ещё не выдана
	flags: { [string]: boolean }, -- эксклюзивные отметки (jamTop10, jamTop100)
	last: { week: number, tier: string, rank: number }?, -- итог прошлого джема для окна
}
type Pending = { week: number, value: number, lastWrite: number }
type TopEntry = { name: string, score: number, userId: number }

local GameJamService = {}

local CHECK_SECONDS = 10
local REQUEST_COOLDOWN = 2
-- В Studio — быстрее, чтобы проверить топ и награды без ожидания
local STUDIO_SETTLE = 10

local stores: { [number]: OrderedDataStore } = {}
local storesFailed = false
-- Несохранённые улучшения по UserId (переживают выход игрока)
local pending: { [number]: Pending } = {}
local lastWrite: { [number]: number } = {}
-- Топ текущей недели (рассылается клиентам) и итоговые топы прошлых недель (для наград)
local currentTop: { TopEntry } = {}
local topAvailable = false
local topWeek = -1
local finalTops: { [number]: { [number]: number } } = {} -- неделя -> userId -> место
local names: { [number]: string } = {}
local lastRequest: { [Player]: number } = {}
local rewarding: { [Player]: boolean } = {}

local function storeFor(week: number): OrderedDataStore?
	if storesFailed then
		return nil
	end
	local existing = stores[week]
	if existing then
		return existing
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(GameJam.storePrefix .. GameJam.weekId(week))
	end)
	if not ok then
		storesFailed = true
		warn("[GameJamService] OrderedDataStore недоступен:", result)
		return nil
	end
	stores[week] = result
	return result
end

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end

local function logAnalytics(player: Player, event: string, value: number, field: string?)
	local analytics = optional("AnalyticsService")
	if analytics and type(analytics.logLiveOps) == "function" then
		pcall(analytics.logLiveOps, player, event, value, field)
	end
end

local function dataOf(profile: DataService.Profile): JamData
	local p = profile :: any
	local j = p.gameJam
	if type(j) ~= "table" then
		j = { week = -1, best = 0, claims = {}, flags = {} }
		p.gameJam = j
	end
	j.week = tonumber(j.week) or -1
	j.best = tonumber(j.best) or 0
	if type(j.claims) ~= "table" then
		j.claims = {}
	end
	if type(j.flags) ~= "table" then
		j.flags = {}
	end
	if type(j.last) ~= "table" then
		j.last = nil
	end
	return j :: JamData
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and type(result) == "string" then result else "#" .. userId
	names[userId] = name
	return name
end

-- Записать результат: только если он лучше уже записанного (UpdateAsync)
local function write(userId: number, entry: Pending): boolean
	local store = storeFor(entry.week)
	if not store then
		return true -- писать некуда: не копим
	end
	local ok, err = pcall(function()
		store:UpdateAsync(tostring(userId), function(old: any): any
			if type(old) == "number" and old >= entry.value then
				return nil
			end
			return entry.value
		end)
	end)
	if not ok then
		warn("[GameJamService] Запись результата не удалась:", userId, err)
	end
	return ok
end

local function flush(force: boolean)
	local now = os.clock()
	-- Снимок: запись ждёт DataStore, а за это время могут прийти новые заявки
	local due: { number } = {}
	for userId in pending do
		if force or now - (lastWrite[userId] or -math.huge) >= GameJam.writeInterval then
			table.insert(due, userId)
		end
	end
	for _, userId in due do
		local entry = pending[userId]
		if entry then
			pending[userId] = nil
			lastWrite[userId] = now
			if not write(userId, entry) and not pending[userId] then
				pending[userId] = entry -- повторим в следующий раз
			end
		end
	end
end

local function readTop(week: number): { any }?
	local store = storeFor(week)
	if not store then
		return nil
	end
	local ok, result = pcall(function()
		return store:GetSortedAsync(false, GameJam.topSize):GetCurrentPage()
	end)
	if not ok then
		warn("[GameJamService] Чтение топа не удалось:", result)
		return nil
	end
	return result :: any
end

local function statePayload(player: Player): any
	local week = GameJam.weekIndex()
	local genreId, topicId = GameJam.theme(week)
	local profile = DataService.get(player)
	local j = if profile then dataOf(profile) else nil
	local best = if j and j.week == week then j.best else 0
	local score, revenue = GameJam.decode(best)
	local rank: number? = nil
	for i, e in currentTop do
		if e.userId == player.UserId then
			rank = i
			break
		end
	end
	local top = {}
	for i, e in currentTop do
		top[i] = { name = e.name, score = e.score }
	end
	return {
		weekId = GameJam.weekId(week),
		genreId = genreId,
		topicId = topicId,
		endsAt = GameJam.weekEndsAt(week),
		available = topAvailable,
		best = if best > 0 then { score = score, revenue = revenue } else nil,
		rank = rank,
		top = top,
		last = j and j.last,
		flags = j and j.flags,
	}
end

function GameJamService.sendState(player: Player)
	if player.Parent then
		LiveOpsRemotes.JamState:FireClient(player, statePayload(player))
	end
end

local function refreshTop()
	local week = GameJam.weekIndex()
	if week ~= topWeek then
		topWeek = week
		currentTop = {}
	end
	local page = readTop(week)
	topAvailable = page ~= nil
	if page then
		local list: { TopEntry } = {}
		for _, item in page do
			local userId = tonumber(item.key)
			local value = tonumber(item.value)
			if userId and value then
				local score = GameJam.decode(value)
				table.insert(list, { name = nameOf(userId), score = score, userId = userId })
			end
		end
		currentTop = list
	end
	for _, player in Players:GetPlayers() do
		task.spawn(GameJamService.sendState, player)
	end
end

-- Место игрока в итоговом топе недели: ok = false — топ прочитать не удалось; rank nil — не в топе
local function finalRank(week: number, userId: number): (boolean, number?)
	local ranks = finalTops[week]
	if not ranks then
		local page = readTop(week)
		if not page then
			return false, nil
		end
		local built: { [number]: number } = {}
		for i, item in page do
			local id = tonumber(item.key)
			if id then
				built[id] = i
			end
		end
		finalTops[week] = built
		ranks = built
	end
	return true, (ranks :: { [number]: number })[userId]
end

-- Награда за одну неделю с заявкой (неделя кончилась, результаты дописаны)
local function rewardWeek(player: Player, profile: DataService.Profile, j: JamData, week: number)
	-- Свой несохранённый результат той недели — сначала дописать
	local own = pending[player.UserId]
	if own and own.week == week then
		pending[player.UserId] = nil
		write(player.UserId, own)
	end
	local ok: boolean, rank: number? = true, nil
	if not storesFailed and storeFor(week) then
		ok, rank = finalRank(week, player.UserId)
	end
	if not ok then
		return -- DataStore не ответил: попробуем позже
	end
	local key = tostring(week)
	if not player.Parent or DataService.get(player) ~= profile or not j.claims[key] then
		return
	end
	local tier = GameJam.tierFor(rank)
	local reward = GameJam.rewards[tier]
	j.claims[key] = nil
	j.last = { week = week, tier = tier, rank = rank or 0 }
	if reward.flag then
		j.flags[reward.flag] = true
	end
	RewardService.grant(player, { incomeMinutes = reward.incomeMinutes })
	-- Достижение, если AchievementService знает такой счётчик (лишний счётчик безвреден)
	local achievements = optional("AchievementService")
	if achievements and type(achievements.note) == "function" then
		pcall(achievements.note, player, "jam_" .. tier, 1)
	end
	LiveOpsRemotes.LiveOpsToast:FireClient(player, {
		key = "jam_toast_reward_" .. tier,
		vars = { rank = rank or 0, minutes = reward.incomeMinutes },
	})
	GameJamService.sendState(player)
	task.spawn(DataService.save, player)
end

-- Награды за прошлые недели с заявкой, если они кончились и серверы дописали результаты
local function maybeReward(player: Player)
	if rewarding[player] then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local j = dataOf(profile)
	local current = GameJam.weekIndex()
	local settle = if RunService:IsStudio() then STUDIO_SETTLE else GameJam.settleSeconds
	local due: { number } = {}
	for key in j.claims do
		local week = tonumber(key)
		if not week then
			j.claims[key] = nil
		elseif week < current and os.time() >= GameJam.weekEndsAt(week) + settle then
			table.insert(due, week)
		end
	end
	if #due == 0 then
		return
	end
	table.sort(due)
	rewarding[player] = true
	for _, week in due do
		local ok, err = pcall(rewardWeek, player, profile, j, week)
		if not ok then
			warn("[GameJamService] Награда за джем не выдана:", player.UserId, week, err)
		end
	end
	rewarding[player] = nil
end

-- DevelopmentService.release: игра по теме недели — заявка в джем
function GameJamService.onGameReleased(
	player: Player,
	info: { genreId: string, topicId: string, score: number, revenue: number }
)
	local profile = DataService.get(player)
	if not profile or type(info) ~= "table" then
		return
	end
	local week = GameJam.weekIndex()
	local genreId, topicId = GameJam.theme(week)
	if info.genreId ~= genreId or info.topicId ~= topicId then
		return
	end
	local j = dataOf(profile)
	if j.week ~= week then
		-- Первая заявка недели: награду за неё выдадим после конца недели
		j.week = week
		j.best = 0
		j.claims[tostring(week)] = true
	end
	local value = GameJam.encode(tonumber(info.score) or 0, tonumber(info.revenue) or 0)
	if value <= j.best then
		return
	end
	local firstEntry = j.best == 0
	j.best = value
	pending[player.UserId] = { week = week, value = value, lastWrite = 0 }
	logAnalytics(player, "jamSubmit", tonumber(info.score) or 0, if firstEntry then "first" else "improved")
	LiveOpsRemotes.LiveOpsToast:FireClient(player, {
		key = if firstEntry then "jam_toast_entered" else "jam_toast_improved",
		vars = { score = tonumber(info.score) or 0 },
	})
	GameJamService.sendState(player)
end

-- Тема недели (для других сервисов): жанр, тема, id недели
function GameJamService.currentTheme(): (string, string, string)
	local week = GameJam.weekIndex()
	local genreId, topicId = GameJam.theme(week)
	return genreId, topicId, GameJam.weekId(week)
end

function GameJamService.start()
	LiveOpsRemotes.RequestSeason.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
			return
		end
		lastRequest[player] = now
		GameJamService.sendState(player)
	end)
	DataService.onProfileLoaded(function(player)
		names[player.UserId] = player.DisplayName
		maybeReward(player)
		GameJamService.sendState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		rewarding[player] = nil
	end)
	-- Запись результатов, награды тем, кто в игре на смене недели
	task.spawn(function()
		local sinceTop = math.huge
		while true do
			pcall(flush, false)
			sinceTop += CHECK_SECONDS
			if sinceTop >= GameJam.topRefreshSeconds or topWeek ~= GameJam.weekIndex() then
				sinceTop = 0
				local ok, err = pcall(refreshTop)
				if not ok then
					warn("[GameJamService] refreshTop failed:", err)
				end
			end
			for _, player in Players:GetPlayers() do
				task.spawn(maybeReward, player)
			end
			task.wait(CHECK_SECONDS)
		end
	end)
	game:BindToClose(function()
		pcall(flush, true)
	end)
end

return GameJamService
