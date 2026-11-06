--!strict
-- Холдинги — объединения студий (Config/Holdings, клиент — HoldingPanel во вкладке «🏘 Студии»).
--   * Создать: этап не ниже офиса и Holdings.createCost денег; название — фильтр как у студии.
--   * Позвать игрока с сервера (любой участник), до Holdings.maxMembers; владелец может убрать.
--   * Запись холдинга — DataStore Holdings_v1 (ключ — id): name, owner, members, week, prev.
--     Все изменения — UpdateAsync; запись кэшируется на сервере и перечитывается раз в
--     Holdings.refreshSeconds. Очки недели копятся в памяти и уходят раз в Holdings.flushSeconds.
--   * Цели недели (Holdings.goals): каждому участнику минуты его дохода, один раз за цель
--     (profile.holding.claimed). Вступившему цели, уже взятые холдингом, не выдаются.
--   * Топ недели — OrderedDataStore HoldingsWeekly_<weekId> (ключ — id холдинга).
--   * Тег: атрибут игрока HoldingName (чат-тег ставит SocialController) и табличка над головой
--     (свой BillboardGui HoldingTag, выше VIP-таблички VipService).
-- Все вызовы DataStore — в pcall.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage.Shared
local Holdings = require(Shared.Config.Holdings)
local Tours = require(Shared.Config.Tours)
local CoopRemotes = require(Shared.CoopRemotes)
local TextSafe = require(Shared.TextSafe)
local WordFilter = require(Shared.WordFilter)
local DataService = require(script.Parent.DataService)
local FeatureReleaseService = require(script.Parent.FeatureReleaseService)

local STORE_NAME = "Holdings_v1"
local TAG_NAME = "HoldingTag"
local HEAD_WAIT = 10
local REQUEST_COOLDOWN = 1

type Member = { userId: number, name: string }
type Week = { id: number, points: number, games: number }
type Record = {
	v: number,
	id: string,
	name: string,
	owner: number,
	members: { Member },
	created: number,
	week: Week,
	prev: Week?,
	disbanded: boolean?,
}
type Cached = { record: Record?, fetchedAt: number }
type Invite = { id: number, from: Player, target: Player, holdingId: string, expiresAt: number }
type Entry = { id: string, name: string, value: number }

local HoldingService = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[HoldingService] DataStore " .. STORE_NAME .. " недоступен:", result)
	end
end

local cache: { [string]: Cached } = {}
local REFRESH_RETRY_SECONDS = 60
local refreshRetryAt: { [string]: number } = {} -- id -> os.clock(), раньше не перечитывать после сбоя
local memberOf: { [Player]: string } = {}
-- Незаписанные очки: id холдинга -> weekId -> очки. Неделя хранится вместе с очками: если flush
-- пришёлся на смену недели, очки прошлой уходят в record.prev (или выбрасываются, если её нет),
-- а не в новую неделю
type Pending = { points: number, games: number }
local pending: { [string]: { [number]: Pending } } = {}
local invites: { [number]: Invite } = {}
local nextInviteId = 0
local busy: { [Player]: boolean } = {}
local lastAction: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
local names: { [string]: string } = {} -- id -> название (для топа)
local board: { available: boolean, weekId: number, entries: { Entry } } =
	{ available = false, weekId = Tours.weekId(), entries = {} }

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end

local function logAnalytics(player: Player, stage: string)
	local analytics = optional("AnalyticsService")
	if analytics and type(analytics.logDepth) == "function" then
		pcall(analytics.logDepth, player, "holding", stage)
	end
end

local function num(value: any): number
	local n = tonumber(value)
	return if n and n == n and n >= 0 and n < math.huge then math.floor(n) else 0
end

local function notice(player: Player, data: { [string]: any })
	if player.Parent then
		CoopRemotes.HoldingNotice:FireClient(player, data)
	end
end

local function cooldownPassed(map: { [Player]: number }, player: Player, seconds: number): boolean
	local now = os.clock()
	if (map[player] or 0) + seconds > now then
		return false
	end
	map[player] = now
	return true
end

-- ===== Запись холдинга =====

local function readWeek(raw: any): Week?
	if type(raw) ~= "table" then
		return nil
	end
	return { id = num(raw.id), points = num(raw.points), games = num(raw.games) }
end

-- Запись из DataStore: проверяем поля, переводим неделю. nil — холдинга нет
local function sanitize(raw: any, id: string): Record?
	if type(raw) ~= "table" or raw.disbanded == true or type(raw.name) ~= "string" then
		return nil
	end
	local members: { Member } = {}
	if type(raw.members) == "table" then
		for _, m in raw.members do
			if type(m) == "table" and type(m.userId) == "number" then
				table.insert(members, { userId = m.userId, name = tostring(m.name or "?") })
			end
		end
	end
	if #members == 0 then
		return nil
	end
	local weekId = Tours.weekId()
	local week = readWeek(raw.week) or { id = weekId, points = 0, games = 0 }
	local prev = readWeek(raw.prev)
	if week.id ~= weekId then
		-- Новая неделя: прошлая остаётся для наград тем, кто зайдёт позже
		prev = if week.id == weekId - 1 then week else nil
		week = { id = weekId, points = 0, games = 0 }
	end
	if prev and prev.id ~= weekId - 1 then
		prev = nil
	end
	return {
		v = 1,
		id = id,
		name = raw.name,
		owner = if type(raw.owner) == "number" then raw.owner else members[1].userId,
		members = members,
		created = num(raw.created),
		week = week,
		prev = prev,
	}
end

local function remember(id: string, record: Record?)
	cache[id] = { record = record, fetchedAt = os.clock() }
	if record then
		names[id] = record.name
	end
end

local function load(id: string): (boolean, Record?)
	local s = store
	if not s then
		return false, nil
	end
	local ok, raw = pcall(function()
		return (s :: DataStore):GetAsync(id)
	end)
	if not ok then
		warn("[HoldingService] GetAsync failed:", raw)
		return false, nil
	end
	local record = sanitize(raw, id)
	remember(id, record)
	return true, record
end

-- UpdateAsync: change получает актуальную запись (или nil) и возвращает новую или nil (не писать).
-- change может вызываться несколько раз — без побочных эффектов
local function update(id: string, change: (Record?) -> Record?): (boolean, Record?)
	local s = store
	if not s then
		return false, nil
	end
	local written: Record? = nil
	local ok, err = pcall(function()
		(s :: DataStore):UpdateAsync(id, function(raw: any): any
			written = nil
			local result = change(sanitize(raw, id))
			written = result
			return result
		end)
	end)
	if not ok then
		warn("[HoldingService] UpdateAsync failed:", err)
		return false, nil
	end
	if written and (written :: any).disbanded then
		-- Распущен: для сервера холдинга больше нет
		remember(id, nil)
		return true, nil
	elseif written then
		remember(id, written)
	end
	return true, written
end

local function isMember(record: Record, userId: number): boolean
	for _, m in record.members do
		if m.userId == userId then
			return true
		end
	end
	return false
end

local function cachedRecord(id: string?): Record?
	local entry = if id then cache[id] else nil
	return if entry then entry.record else nil
end

-- ===== Профиль =====

type HoldingData = { id: string?, claimed: { [string]: number } }

local function dataOf(profile: DataService.Profile): HoldingData
	local p = profile :: any
	local raw = if type(p.holding) == "table" then p.holding else {}
	local claimed: { [string]: number } = {}
	local oldest = Tours.weekId() - 1
	if type(raw.claimed) == "table" then
		for key, value in raw.claimed do
			-- Храним только эту и прошлую неделю
			if type(key) == "string" and (tonumber(key) or 0) >= oldest then
				claimed[key] = num(value)
			end
		end
	end
	local data: HoldingData = { id = if type(raw.id) == "string" then raw.id else nil, claimed = claimed }
	p.holding = data
	return data
end

-- Недели записи для наград: прошлая (если есть), потом текущая. Явный список — без дыр от nil
local function weeksOf(record: Record): { Week }
	local list = {}
	if record.prev then
		table.insert(list, record.prev)
	end
	table.insert(list, record.week)
	return list
end

local function tierOf(points: number): number
	local tier = 0
	for i, goal in Holdings.goals do
		if points >= goal.points then
			tier = i
		end
	end
	return tier
end

-- Вступил в холдинг: уже взятые им цели не выдаём (иначе бегали бы по холдингам за наградами)
local function markClaimedOnJoin(data: HoldingData, record: Record)
	for _, week in weeksOf(record) do
		if week then
			local key = tostring(week.id)
			data.claimed[key] = math.max(data.claimed[key] or 0, tierOf(week.points))
		end
	end
end

-- Выдать участнику награды достигнутых целей (эта и прошлая неделя)
local function grantGoals(player: Player, record: Record)
	local profile = DataService.get(player)
	local RewardService = optional("RewardService")
	if not profile or not RewardService then
		return
	end
	local data = dataOf(profile)
	for _, week in weeksOf(record) do
		if week then
			local key = tostring(week.id)
			local tier = tierOf(week.points)
			local claimed = data.claimed[key] or 0
			for i = claimed + 1, tier do
				local minutes = Holdings.goals[i].minutes
				local okMoney, money = pcall(RewardService.incomeForMinutes, player, profile, minutes)
				pcall(RewardService.grant, player, { incomeMinutes = minutes })
				notice(
					player,
					{ kind = "goal", n = Holdings.goals[i].points, money = if okMoney then money else 0 }
				)
				logAnalytics(player, "goal_" .. i)
			end
			if tier > claimed then
				data.claimed[key] = tier
			end
		end
	end
end

-- ===== Тег над головой =====

local function setTag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local name = player:GetAttribute("HoldingName")
	local existing = head:FindFirstChild(TAG_NAME)
	if type(name) ~= "string" or name == "" then
		if existing then
			existing:Destroy()
		end
		return
	end
	local gui: BillboardGui
	if existing and existing:IsA("BillboardGui") then
		gui = existing
	else
		gui = Instance.new("BillboardGui")
		gui.Name = TAG_NAME
		gui.Adornee = head
		gui.Size = UDim2.fromScale(5, 0.8)
		gui.MaxDistance = Holdings.tagMaxDistance
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Holdings.tagColor
		label.TextStrokeColor3 = Color3.fromRGB(10, 30, 60)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = head
	end
	-- VIP-табличка (VipService) на высоте 3 — наша тогда выше
	local vip = player:GetAttribute("IsVip") == true
	gui.StudsOffset = Vector3.new(0, if vip then Holdings.tagOffsetVip else Holdings.tagOffset, 0)
	local label = gui:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = "[" .. name .. "]"
	end
end

local function applyMembership(player: Player, record: Record?)
	if record then
		memberOf[player] = record.id
		player:SetAttribute("HoldingName", record.name)
		player:SetAttribute("HoldingId", record.id)
	else
		memberOf[player] = nil
		player:SetAttribute("HoldingName", nil)
		player:SetAttribute("HoldingId", nil)
	end
	setTag(player)
end

-- ===== Состояние для клиента =====

local function onlineMembers(id: string): { Player }
	local list = {}
	for player, holdingId in memberOf do
		if holdingId == id and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

local function sendState(player: Player)
	if not player.Parent then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local id = memberOf[player]
	local record = cachedRecord(id)
	local holding: any = nil
	if id and record then
		local byWeek = pending[id]
		local extra = if byWeek then byWeek[record.week.id] else nil
		local points = record.week.points + (if extra then extra.points else 0)
		local games = record.week.games + (if extra then extra.games else 0)
		local members = {}
		for _, m in record.members do
			local online = Players:GetPlayerByUserId(m.userId)
			table.insert(members, {
				userId = m.userId,
				name = if online then online.DisplayName else m.name,
				online = online ~= nil,
				owner = m.userId == record.owner,
			})
		end
		local goals = {}
		local claimed = dataOf(profile).claimed[tostring(record.week.id)] or 0
		for i, goal in Holdings.goals do
			table.insert(goals, {
				points = goal.points,
				minutes = goal.minutes,
				reached = points >= goal.points,
				claimed = i <= claimed,
			})
		end
		holding = {
			id = id,
			name = record.name,
			isOwner = record.owner == player.UserId,
			members = members,
			max = Holdings.maxMembers,
			points = points,
			games = games,
			goals = goals,
		}
	end
	local entries = {}
	for _, entry in board.entries do
		table.insert(entries, { name = entry.name, value = entry.value, mine = entry.id == id })
	end
	CoopRemotes.HoldingState:FireClient(player, {
		holding = holding,
		cost = Holdings.createCost,
		minLevel = Holdings.minStudioLevel,
		levelOk = profile.studioLevel >= Holdings.minStudioLevel,
		board = entries,
		boardAvailable = board.available,
		weekLeft = Tours.weekLeft(),
	})
end

local function sendToHolding(id: string)
	for _, player in onlineMembers(id) do
		sendState(player)
	end
end

-- ===== Создание =====

local function newRecord(id: string, name: string, player: Player): Record
	return {
		v = 1,
		id = id,
		name = name,
		owner = player.UserId,
		members = { { userId = player.UserId, name = player.DisplayName } },
		created = os.time(),
		week = { id = Tours.weekId(), points = 0, games = 0 },
		prev = nil,
	}
end

local function onCreate(player: Player, raw: any)
	if type(raw) ~= "string" or #raw > Holdings.nameMax * 4 or busy[player] then
		return
	end
	if not cooldownPassed(lastAction, player, Holdings.actionCooldown) then
		return
	end
	local profile = DataService.get(player)
	if not profile or memberOf[player] or dataOf(profile).id then
		notice(player, { kind = "fail", reason = "already" })
		return
	end
	if profile.studioLevel < Holdings.minStudioLevel then
		notice(player, { kind = "fail", reason = "level" })
		return
	end
	if profile.cash < Holdings.createCost then
		notice(player, { kind = "fail", reason = "money" })
		return
	end
	local name = TextSafe.clean(raw)
	local length = name and utf8.len(name)
	if
		not name
		or not length
		or TextSafe.visibleLength(name) < Holdings.nameMin
		or length > Holdings.nameMax
	then
		notice(player, { kind = "fail", reason = "length" })
		return
	end
	if not WordFilter.isClean(name) then
		notice(player, { kind = "fail", reason = "filtered" })
		return
	end
	busy[player] = true
	local okFilter, filtered = pcall(function()
		local result = TextService:FilterStringAsync(name, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not okFilter or filtered ~= name then
		busy[player] = nil
		notice(player, { kind = "fail", reason = if okFilter then "filtered" else "error" })
		return
	end
	-- Пока ждали фильтр, игрок мог выйти или вступить в другой холдинг
	if not player.Parent or DataService.get(player) ~= profile or memberOf[player] or dataOf(profile).id then
		busy[player] = nil
		return
	end
	if not DataService.trySpend(player, Holdings.createCost) then
		busy[player] = nil
		notice(player, { kind = "fail", reason = "money" })
		return
	end
	local id = string.format("%d_%d", player.UserId, os.time())
	local record = newRecord(id, name, player)
	local ok, written = update(id, function(old: Record?): Record?
		return if old then nil else record
	end)
	busy[player] = nil
	if not ok or not written then
		-- Не записалось — деньги назад
		DataService.addCash(player, Holdings.createCost)
		notice(player, { kind = "fail", reason = "error" })
		return
	end
	local data = dataOf(profile)
	data.id = id
	markClaimedOnJoin(data, written)
	applyMembership(player, written)
	notice(player, { kind = "created", name = name })
	logAnalytics(player, "created")
	sendState(player)
	task.spawn(DataService.save, player)
end

-- ===== Приглашения =====

local function onInvite(player: Player, userId: any)
	if type(userId) ~= "number" or not cooldownPassed(lastAction, player, Holdings.actionCooldown) then
		return
	end
	local id = memberOf[player]
	local record = cachedRecord(id)
	local target = Players:GetPlayerByUserId(userId)
	if not id or not record then
		return
	end
	if not target or target == player then
		notice(player, { kind = "fail", reason = "gone" })
		return
	end
	local targetProfile = DataService.get(target)
	if not targetProfile or memberOf[target] or dataOf(targetProfile).id then
		notice(player, { kind = "fail", reason = "inHolding", name = target.DisplayName })
		return
	end
	if #record.members >= Holdings.maxMembers then
		notice(player, { kind = "fail", reason = "full" })
		return
	end
	for inviteId, invite in invites do
		if invite.from == player and invite.target == target then
			invites[inviteId] = nil
		end
	end
	nextInviteId += 1
	invites[nextInviteId] = {
		id = nextInviteId,
		from = player,
		target = target,
		holdingId = id,
		expiresAt = os.clock() + Holdings.inviteSeconds,
	}
	CoopRemotes.HoldingInvited:FireClient(target, {
		inviteId = nextInviteId,
		name = player.DisplayName,
		holding = record.name,
		seconds = Holdings.inviteSeconds,
	})
	notice(player, { kind = "sent", name = target.DisplayName })
end

local function onReply(player: Player, inviteId: any, accept: any)
	if type(inviteId) ~= "number" or busy[player] then
		return
	end
	local invite = invites[inviteId]
	if not invite or invite.target ~= player then
		return
	end
	invites[inviteId] = nil
	if invite.expiresAt < os.clock() then
		notice(player, { kind = "fail", reason = "expired" })
		return
	end
	if accept ~= true then
		notice(invite.from, { kind = "declined", name = player.DisplayName })
		return
	end
	local profile = DataService.get(player)
	if not profile or memberOf[player] or dataOf(profile).id then
		notice(player, { kind = "fail", reason = "already" })
		return
	end
	busy[player] = true
	local problem: string? = nil
	local ok, written = update(invite.holdingId, function(record: Record?): Record?
		problem = nil
		if not record then
			problem = "gone"
			return nil
		end
		if isMember(record, player.UserId) then
			return record
		end
		if #record.members >= Holdings.maxMembers then
			problem = "full"
			return nil
		end
		table.insert(record.members, { userId = player.UserId, name = player.DisplayName })
		return record
	end)
	busy[player] = nil
	if not ok or not written then
		notice(player, { kind = "fail", reason = problem or "error" })
		return
	end
	if not player.Parent or DataService.get(player) ~= profile then
		return
	end
	local data = dataOf(profile)
	data.id = invite.holdingId
	markClaimedOnJoin(data, written)
	applyMembership(player, written)
	for _, member in onlineMembers(invite.holdingId) do
		notice(member, { kind = "joined", name = player.DisplayName, holding = written.name })
	end
	logAnalytics(player, "joined")
	sendToHolding(invite.holdingId)
	task.spawn(DataService.save, player)
end

-- ===== Выход и исключение =====

-- Убрать userId из холдинга. Ушёл владелец — владельцем становится первый из оставшихся,
-- никого не осталось — холдинг распущен
local function removeMember(id: string, userId: number): (boolean, Record?)
	return update(id, function(record: Record?): Record?
		if not record or not isMember(record, userId) then
			return nil
		end
		for i, m in record.members do
			if m.userId == userId then
				table.remove(record.members, i)
				break
			end
		end
		if #record.members == 0 then
			local closed = record :: any
			closed.disbanded = true
			return closed
		end
		if record.owner == userId then
			record.owner = record.members[1].userId
		end
		return record
	end)
end

local function onLeave(player: Player)
	if busy[player] or not cooldownPassed(lastAction, player, Holdings.actionCooldown) then
		return
	end
	local profile = DataService.get(player)
	local id = memberOf[player] or (profile and dataOf(profile).id)
	if not profile or not id then
		return
	end
	busy[player] = true
	local ok = removeMember(id, player.UserId)
	busy[player] = nil
	if not ok then
		notice(player, { kind = "fail", reason = "error" })
		return
	end
	dataOf(profile).id = nil
	applyMembership(player, nil)
	notice(player, { kind = "left" })
	logAnalytics(player, "left")
	sendState(player)
	sendToHolding(id)
	task.spawn(DataService.save, player)
end

local function onKick(player: Player, userId: any)
	if type(userId) ~= "number" or userId == player.UserId then
		return
	end
	if not cooldownPassed(lastAction, player, Holdings.actionCooldown) then
		return
	end
	local id = memberOf[player]
	local record = cachedRecord(id)
	if not id or not record or record.owner ~= player.UserId or not isMember(record, userId) then
		return
	end
	local ok, written = update(id, function(current: Record?): Record?
		-- Убирать может только текущий владелец
		if not current or current.owner ~= player.UserId or not isMember(current, userId) then
			return nil
		end
		for i, m in current.members do
			if m.userId == userId then
				table.remove(current.members, i)
				break
			end
		end
		return current
	end)
	if not ok or not written then
		notice(player, { kind = "fail", reason = "error" })
		return
	end
	-- Участник на этом сервере — сразу; на другом — при его перечитывании записи
	local target = Players:GetPlayerByUserId(userId)
	if target and memberOf[target] == id then
		local profile = DataService.get(target)
		if profile then
			dataOf(profile).id = nil
		end
		applyMembership(target, nil)
		notice(target, { kind = "kicked", holding = written.name })
		sendState(target)
	end
	sendToHolding(id)
end

-- ===== Очки и цели =====

-- DevelopmentService.release: игра участника; info.coopWith — гость совместной игры
function HoldingService.onGameReleased(player: Player, info: any)
	local id = memberOf[player]
	-- Игры на ноутбуке в парке (35 с) очков не дают: иначе альты без гаража фармят цели недели
	if not id or (type(info) == "table" and info.laptop == true) then
		return
	end
	local weekId = Tours.weekId()
	local byWeek = pending[id]
	if not byWeek then
		byWeek = {}
		pending[id] = byWeek
	end
	local entry = (byWeek :: { [number]: Pending })[weekId]
	if not entry then
		entry = { points = 0, games = 0 };
		(byWeek :: { [number]: Pending })[weekId] = entry
	end
	entry.points += Holdings.pointsPerGame
	entry.games += 1
	local partner = if type(info) == "table" then info.coopWith else nil
	if typeof(partner) == "Instance" and partner:IsA("Player") and memberOf[partner] == id then
		entry.points += Holdings.pointsPerCoopGame
	end
	sendToHolding(id)
end

local function writeBoard(record: Record, week: Week?)
	local w = week or record.week
	local okStore, ordered = pcall(function()
		return DataStoreService:GetOrderedDataStore("HoldingsWeekly_" .. w.id)
	end)
	if not okStore then
		return
	end
	local ok, err = pcall(function()
		(ordered :: OrderedDataStore):SetAsync(record.id, w.points)
	end)
	if not ok then
		warn("[HoldingService] Топ не записался:", err)
	end
end

-- Сверить онлайн-участников с записью: убранных на другом сервере — снять; цели — выдать
local function reconcile(id: string, record: Record?)
	for _, player in onlineMembers(id) do
		if not record or not isMember(record, player.UserId) then
			local profile = DataService.get(player)
			if profile then
				dataOf(profile).id = nil
			end
			applyMembership(player, nil)
			notice(player, { kind = "kicked", holding = if record then record.name else "" })
		else
			if player:GetAttribute("HoldingName") ~= record.name then
				applyMembership(player, record)
			end
			grantGoals(player, record)
		end
		sendState(player)
	end
end

local function flushEntry(id: string, weekId: number, entry: Pending): boolean
	local points, games = entry.points, entry.games
	if points <= 0 and games <= 0 then
		return true
	end
	local ok, written = update(id, function(record: Record?): Record?
		if not record then
			return nil
		end
		-- sanitize уже перевёл запись на текущую неделю: очки прошлой — в prev, старше — никуда
		local target = if record.week.id == weekId
			then record.week
			elseif record.prev and record.prev.id == weekId then record.prev
			else nil
		if not target then
			return nil
		end
		target.points += points
		target.games += games
		return record
	end)
	if not ok then
		return false
	end
	-- Пока писали, могли прийти новые очки: вычитаем только записанное (или выброшенное)
	entry.points -= points
	entry.games -= games
	if written then
		if written.week.id == weekId then
			writeBoard(written)
		elseif written.prev and written.prev.id == weekId then
			writeBoard(written, written.prev)
		end
	end
	reconcile(id, written)
	return true
end

local function flush()
	-- Сначала список: flushEntry уступает (UpdateAsync), а новые релизы добавляют ключи в pending
	local jobs: { { id: string, weekId: number, entry: Pending } } = {}
	for id, byWeek in pending do
		for weekId, entry in byWeek do
			table.insert(jobs, { id = id, weekId = weekId, entry = entry })
		end
	end
	for _, job in jobs do
		flushEntry(job.id, job.weekId, job.entry)
		local byWeek = pending[job.id]
		if byWeek and byWeek[job.weekId] == job.entry and job.entry.points <= 0 and job.entry.games <= 0 then
			byWeek[job.weekId] = nil
			if next(byWeek) == nil then
				pending[job.id] = nil
			end
		end
	end
end

local function refresh()
	local ids: { [string]: boolean } = {}
	for _, id in memberOf do
		ids[id] = true
	end
	local now = os.clock()
	for id in ids do
		local entry = cache[id]
		local due = not entry or now - entry.fetchedAt >= Holdings.refreshSeconds
		if due and now >= (refreshRetryAt[id] or 0) then
			local ok, record = load(id)
			if ok then
				refreshRetryAt[id] = nil
				reconcile(id, record)
			else
				-- DataStore не ответил: refresh идёт каждые 5 с — без паузы это GetAsync на каждый
				-- холдинг 12 раз в минуту, пока сбой не пройдёт
				refreshRetryAt[id] = now + REFRESH_RETRY_SECONDS
			end
		end
	end
end

local function readBoard()
	local weekId = Tours.weekId()
	local okStore, ordered = pcall(function()
		return DataStoreService:GetOrderedDataStore("HoldingsWeekly_" .. weekId)
	end)
	if not okStore then
		board = { available = false, weekId = weekId, entries = {} }
		return
	end
	local ok, page = pcall(function()
		return (ordered :: OrderedDataStore):GetSortedAsync(false, Holdings.boardSize):GetCurrentPage()
	end)
	if not ok then
		warn("[HoldingService] Топ не прочитался:", page)
		board = { available = false, weekId = weekId, entries = {} }
		return
	end
	local entries: { Entry } = {}
	for _, item in page :: any do
		local id = tostring(item.key)
		local value = num(item.value)
		if value > 0 then
			if not names[id] then
				local okLoad, record = load(id)
				if okLoad and not record then
					names[id] = "" -- распущен: в топ не показываем
				end
			end
			local name = names[id]
			if name and name ~= "" then
				table.insert(entries, { id = id, name = name, value = value })
			end
		end
	end
	board = { available = true, weekId = weekId, entries = entries }
end

-- ===== Вход и выход =====

local function onProfileLoaded(player: Player, profile: DataService.Profile)
	local id = dataOf(profile).id
	if not id then
		sendState(player)
		return
	end
	local ok, record = load(id)
	if not player.Parent or DataService.get(player) ~= profile then
		return
	end
	if ok and (not record or not isMember(record, player.UserId)) then
		-- Холдинг распущен или игрока убрали, пока его не было
		dataOf(profile).id = nil
		notice(player, { kind = "kicked", holding = if record then record.name else "" })
	elseif ok and record then
		applyMembership(player, record)
		grantGoals(player, record)
	end
	-- Не прочиталось — попробуем при следующем входе; указатель в профиле не трогаем
	sendState(player)
end

local function watchTag(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			character:WaitForChild("Head", HEAD_WAIT)
			setTag(player)
		end)
	end)
	player:GetAttributeChangedSignal("IsVip"):Connect(function()
		setTag(player)
	end)
end

local function startNow()
	CoopRemotes.HoldingRequest.OnServerEvent:Connect(function(player)
		if cooldownPassed(lastRequest, player, REQUEST_COOLDOWN) then
			sendState(player)
		end
	end)
	CoopRemotes.HoldingCreate.OnServerEvent:Connect(onCreate)
	CoopRemotes.HoldingInvite.OnServerEvent:Connect(onInvite)
	CoopRemotes.HoldingReply.OnServerEvent:Connect(onReply)
	CoopRemotes.HoldingLeave.OnServerEvent:Connect(onLeave)
	CoopRemotes.HoldingKick.OnServerEvent:Connect(onKick)
	DataService.onProfileLoaded(onProfileLoaded)
	Players.PlayerAdded:Connect(watchTag)
	for _, player in Players:GetPlayers() do
		watchTag(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		memberOf[player] = nil
		busy[player] = nil
		lastAction[player] = nil
		lastRequest[player] = nil
		for inviteId, invite in invites do
			if invite.from == player or invite.target == player then
				invites[inviteId] = nil
			end
		end
	end)

	task.spawn(function()
		local lastFlush, lastBoard = os.clock(), -math.huge
		while true do
			task.wait(5)
			local now = os.clock()
			for inviteId, invite in invites do
				if invite.expiresAt < now then
					invites[inviteId] = nil
				end
			end
			if now - lastFlush >= Holdings.flushSeconds then
				lastFlush = now
				local ok, err = pcall(flush)
				if not ok then
					warn("[HoldingService] flush failed:", err)
				end
			end
			local okRefresh, errRefresh = pcall(refresh)
			if not okRefresh then
				warn("[HoldingService] refresh failed:", errRefresh)
			end
			if now - lastBoard >= Holdings.boardSeconds then
				lastBoard = now
				local ok, err = pcall(readBoard)
				if not ok then
					warn("[HoldingService] board failed:", err)
				end
			end
		end
	end)

	-- Сервер закрывается: очки недели не должны пропасть
	game:BindToClose(function()
		if next(pending) then
			pcall(flush)
		end
	end)
end

-- Обновления по средам (Config/Features): до выхода системы «holdings» сервис спит — remotes
-- заглушены, циклы и обработчики не запущены; вышла (в т. ч. пока сервер работает) — startNow()
function HoldingService.start()
	FeatureReleaseService.mute("holdings", {
		CoopRemotes.HoldingRequest,
		CoopRemotes.HoldingCreate,
		CoopRemotes.HoldingInvite,
		CoopRemotes.HoldingReply,
		CoopRemotes.HoldingLeave,
		CoopRemotes.HoldingKick,
	})
	FeatureReleaseService.whenReleased("holdings", "HoldingService", startNow)
end

return HoldingService
