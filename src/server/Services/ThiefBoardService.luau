--!strict
-- «😈 Главные воры»: статистика краж в профиле, топ сервера (живой), глобальный топ-10
-- (OrderedDataStore «TopThieves_v1» по steals) и титул лидеру сервера.
-- Статистику меняет HitService и зовёт ThiefBoardService.changed(player).
-- Лидер сервера — атрибут ReplicatedStorage «TopThiefUserId», титул над головой рисует клиент.
-- Все вызовы DataStore — в pcall: в Studio без API Services глобальный топ «недоступен».

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HitCartridges = require(ReplicatedStorage.Shared.Config.HitCartridges)
local HitRemotes = require(ReplicatedStorage.Shared.HitRemotes)
local DataService = require(script.Parent.DataService)

export type Stats = { steals: number, stolenIncome: number, caught: number, catches: number }
type Row = { userId: number, name: string, steals: number, catches: number }
type Global = { available: boolean, rows: { Row } }
type Written = { steals: number, at: number }

local WRITE_CHECK = 10
local REQUEST_COOLDOWN = 1

local ThiefBoardService = {}

local store: OrderedDataStore? = nil
do
	local ok, err = pcall(function()
		store = DataStoreService:GetOrderedDataStore("TopThieves_v1")
	end)
	if not ok then
		warn("[ThiefBoardService] OrderedDataStore недоступен:", err)
	end
end

local global: Global = { available = false, rows = {} }
local serverRows: { Row } = {}
-- Последняя запись в глобальный топ по UserId: переживает выход игрока
local written: { [number]: Written } = {}
local pendingWrite: { [number]: boolean } = {}
local names: { [number]: string } = {}
local lastRequest: { [Player]: number } = {}
local broadcastQueued = false

local function num(value: any): number
	local n = tonumber(value)
	return if n and n == n and n >= 0 and n < math.huge then math.floor(n) else 0
end

-- Статистика вора в профиле, с ленивой инициализацией и защитой от мусора в сохранении
function ThiefBoardService.stats(profile: DataService.Profile): Stats
	local p = profile :: any
	local raw = p.thief
	if type(raw) ~= "table" then
		raw = {}
	end
	local stats: Stats = {
		steals = num(raw.steals),
		stolenIncome = num(raw.stolenIncome),
		caught = num(raw.caught),
		catches = num(raw.catches),
	}
	p.thief = stats
	return stats
end

local function payload(): any
	return { server = serverRows, global = global }
end

local function rebuildServer()
	local rows: { Row } = {}
	for _, player in Players:GetPlayers() do
		local profile = DataService.get(player)
		if profile then
			local stats = ThiefBoardService.stats(profile)
			table.insert(rows, {
				userId = player.UserId,
				name = player.DisplayName,
				steals = stats.steals,
				catches = stats.catches,
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.steals ~= b.steals then
			return a.steals > b.steals
		end
		if a.catches ~= b.catches then
			return a.catches > b.catches
		end
		return a.userId < b.userId
	end)
	serverRows = rows
	-- Титул только тому, кто реально что-то украл
	local top = rows[1]
	ReplicatedStorage:SetAttribute("TopThiefUserId", if top and top.steals > 0 then top.userId else nil)
end

-- Несколько изменений за кадр — одна рассылка
local function broadcast()
	if broadcastQueued then
		return
	end
	broadcastQueued = true
	task.defer(function()
		broadcastQueued = false
		rebuildServer()
		HitRemotes.ThiefBoard:FireAllClients(payload())
	end)
end

function ThiefBoardService.changed(_player: Player)
	broadcast()
end

-- Запись в глобальный топ не чаще boardWriteInterval на игрока и только если число изменилось
local function maybeWrite(userId: number, steals: number, deferIfEarly: boolean)
	local ordered = store
	if not ordered or userId <= 0 or steals <= 0 then
		return
	end
	local w = written[userId]
	if w and w.steals == steals then
		return
	end
	local now = os.clock()
	local wait = if w then w.at + HitCartridges.boardWriteInterval - now else 0
	if wait > 0 then
		if deferIfEarly and not pendingWrite[userId] then
			pendingWrite[userId] = true
			task.delay(wait, function()
				pendingWrite[userId] = nil
				maybeWrite(userId, steals, false)
			end)
		end
		return
	end
	-- Отмечаем до yield, чтобы параллельный вызов не записал второй раз
	written[userId] = { steals = steals, at = now }
	local ok, err = pcall(function()
		ordered:SetAsync(tostring(userId), steals)
	end)
	if not ok then
		warn("[ThiefBoardService] Запись не удалась:", err)
	end
end

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName
	end
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and type(result) == "string" then result else "#" .. userId
	names[userId] = name
	return name
end

local function refreshGlobal()
	local ordered = store
	if not ordered then
		global = { available = false, rows = {} }
		return
	end
	local ok, page = pcall(function()
		return ordered:GetSortedAsync(false, HitCartridges.boardSize):GetCurrentPage()
	end)
	if not ok then
		warn("[ThiefBoardService] Чтение топа не удалось:", page)
		global = { available = false, rows = {} }
		return
	end
	local rows: { Row } = {}
	for _, item in page :: any do
		local userId = tonumber(item.key)
		if userId then
			-- «Поймал воров» в OrderedDataStore нет: берём из профиля, если игрок здесь
			local player = Players:GetPlayerByUserId(userId)
			local profile = player and DataService.get(player)
			table.insert(rows, {
				userId = userId,
				name = nameOf(userId),
				steals = num(item.value),
				catches = if profile then ThiefBoardService.stats(profile).catches else 0,
			})
		end
	end
	global = { available = true, rows = rows }
end

local function onPlayerAdded(player: Player)
	-- Профиль грузится асинхронно в DataService
	while player.Parent and not DataService.get(player) do
		task.wait(0.5)
	end
	if player.Parent then
		broadcast()
	end
end

function ThiefBoardService.start()
	HitRemotes.RequestThiefBoard.OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
			return
		end
		lastRequest[player] = now
		HitRemotes.ThiefBoard:FireClient(player, payload())
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		local profile = DataService.get(player)
		if profile then
			task.spawn(maybeWrite, player.UserId, ThiefBoardService.stats(profile).steals, true)
		end
		-- Игрок ещё в списке Players: пересобираем после его ухода
		task.delay(1, broadcast)
	end)

	task.spawn(function()
		while true do
			task.wait(WRITE_CHECK)
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile then
					task.spawn(maybeWrite, player.UserId, ThiefBoardService.stats(profile).steals, false)
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			refreshGlobal()
			HitRemotes.ThiefBoard:FireAllClients(payload())
			task.wait(HitCartridges.boardReadInterval)
		end
	end)
end

return ThiefBoardService
