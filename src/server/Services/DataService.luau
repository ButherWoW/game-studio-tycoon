--!strict
-- Загрузка/сохранение профиля игрока в DataStore.
-- Защита от двух сессий (#13 п.4): запись идёт только через UpdateAsync, в записи лежит
-- _session = { jobId, time } — какой сервер сейчас владеет профилем. Пока чужая метка
-- свежая (< SESSION_TIMEOUT), второй сервер профиль не берёт. Автосейв обновляет time,
-- выход снимает метку. Если сервер упал, метка протухает через SESSION_TIMEOUT.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

export type Profile = {
	cash: number,
	studioLevel: number,
	rebirths: number,
	upgrades: { [string]: boolean },
	unlockedGenres: { [string]: boolean },
	unlockedTopics: { [string]: boolean },
	gamesReleased: number,
	bestScore: number,
	-- Лучшая оценка с последнего Rebirth: по ней считаются награды «N минут дохода»
	runBestScore: number,
	-- Сочетания жанр/тема последних игр (Formulas.comboKey): штраф за повтор в оценке
	recentCombos: { string },
	activeAd: { bonus: number, expiresAt: number }?,
	-- Купленные за Robux разовые эффекты (ShopService): заряды и конец действия кофе
	boosts: { instantFinish: number, patch: number, coffeeUntil: number },
	processedReceipts: { [string]: boolean },
	receiptLog: { string }, -- порядок квитанций, чтобы удалять самые старые
	lastLogout: number,
}

type Session = { jobId: string, time: number }

-- Состояние загруженного профиля на этом сервере
type State = {
	persistent: boolean, -- false: DataStore недоступен (Studio без API) — не сохраняем
	closed: boolean, -- выход начат: обычные сохранения больше не пишем
}

local STORE_VERSION = "v1"
-- В неопубликованном плейсе или без «Studio Access to API Services» GetDataStore бросает ошибку.
-- Раньше это роняло весь сервер (пустой мир без HUD, отчёт #42) — теперь играем без сохранений
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("PlayerData_" .. STORE_VERSION)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore недоступен, сохранения выключены:", result)
	end
end
local AUTOSAVE_SECONDS = 60
local SESSION_TIMEOUT = 5 * 60 -- чужая метка старше — сервер, видимо, упал
local LOCK_ATTEMPTS = 3
local LOCK_RETRY_DELAY = 6
local CLOSE_TIMEOUT = 25 -- BindToClose даёт ~30 с

local LOCKED_KICK_MESSAGE =
	"Твоя студия ещё открыта на другом сервере. Подожди минуту и зайди снова — прогресс не потеряется."
local LOAD_FAILED_KICK_MESSAGE =
	"Не удалось загрузить сохранение. Попробуйте зайти ещё раз."

local function defaultProfile(): Profile
	return {
		cash = 100,
		studioLevel = 1,
		rebirths = 0,
		upgrades = {},
		unlockedGenres = { action = true, adventure = true, casual = true },
		unlockedTopics = { space = true, fantasy = true, zombies = true },
		gamesReleased = 0,
		bestScore = 0,
		runBestScore = 0,
		recentCombos = {},
		activeAd = nil,
		boosts = { instantFinish = 0, patch = 0, coffeeUntil = 0 },
		processedReceipts = {},
		receiptLog = {},
		lastLogout = os.time(),
	}
end

local DataService = {}
local profiles: { [Player]: Profile } = {}
local states: { [Player]: State } = {}
-- Идёт запись в DataStore по этому UserId. По UserId, а не Player: при перезаходе
-- на тот же сервер новый Player должен дождаться сохранения старого
local busy: { [number]: boolean } = {}

local function key(userId: number): string
	return "user_" .. userId
end

local function acquire(userId: number)
	while busy[userId] do
		task.wait(0.1)
	end
	busy[userId] = true
end

local function isForeignSession(session: any): boolean
	return type(session) == "table"
		and session.jobId ~= game.JobId
		and type(session.time) == "number"
		and os.time() - session.time < SESSION_TIMEOUT
end

-- Записать профиль, сохранив или сняв метку сессии. Не трогает запись,
-- если её уже держит другой сервер (наша метка протухла и профиль забрали)
local function write(userId: number, profile: Profile, release: boolean): boolean
	if not store then
		return false
	end
	local lastErr: any = nil
	for attempt = 1, 3 do
		local stolen = false
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key(userId), function(old: any): (any, { number }?)
				if type(old) == "table" and isForeignSession(old._session) then
					stolen = true
					return nil, nil -- отмена записи
				end
				local record = table.clone(profile) :: any
				record._session = if release then nil else { jobId = game.JobId, time = os.time() } :: Session
				return record, { userId }
			end)
		end)
		if ok then
			if stolen then
				warn("[DataService] Profile of", userId, "is owned by another server, save skipped")
				return false
			end
			return true
		end
		lastErr = err
		task.wait(attempt)
	end
	warn("[DataService] Save failed for", userId, lastErr)
	return false
end

-- Взять профиль с меткой сессии. "ok" + данные, "locked" — открыт на другом сервере,
-- "error" + текст — DataStore недоступен
local function load(userId: number): (string, any)
	if not store then
		return "error", "DataStore unavailable"
	end
	local lastErr: any = nil
	local attempt = 0
	while attempt < LOCK_ATTEMPTS do
		attempt += 1
		local locked = false
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(key(userId), function(old: any): (any, { number }?)
				-- Функция может вызываться несколько раз: флаг ставим заново каждый раз
				locked = type(old) == "table" and isForeignSession(old._session)
				if locked then
					return nil, nil
				end
				local record = if type(old) == "table" then old else {}
				record._session = { jobId = game.JobId, time = os.time() } :: Session
				return record, { userId }
			end)
		end)
		if ok and not locked then
			return "ok", result
		elseif ok then
			lastErr = nil
		else
			lastErr = result
		end
		if attempt < LOCK_ATTEMPTS then
			task.wait(if ok then LOCK_RETRY_DELAY else attempt)
		end
	end
	if lastErr ~= nil then
		return "error", tostring(lastErr)
	end
	return "locked", nil
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

-- Доход релиза прячется из таблицы лидеров, пока в окне релиза не открылась оценка (отчёт #2, п. 6)
local leaderstatsHold: { [Player]: { amount: number, untilAt: number } } = {}

-- Отправить клиенту публичный снимок данных (без квитанций)
function DataService.replicate(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	Remotes.DataChanged:FireClient(player, {
		cash = p.cash,
		studioLevel = p.studioLevel,
		rebirths = p.rebirths,
		upgrades = p.upgrades,
		unlockedGenres = p.unlockedGenres,
		unlockedTopics = p.unlockedTopics,
		gamesReleased = p.gamesReleased,
		bestScore = p.bestScore,
		runBestScore = p.runBestScore,
		activeAd = p.activeAd,
	})
	local leaderstats = player:FindFirstChild("leaderstats")
	local cashValue = leaderstats and leaderstats:FindFirstChild("Cash") :: NumberValue?
	if cashValue then
		local hold = leaderstatsHold[player]
		if hold and os.clock() >= hold.untilAt then
			leaderstatsHold[player] = nil
			hold = nil
		end
		cashValue.Value = if hold then math.max(p.cash - hold.amount, 0) else p.cash
	end
end

-- Показать amount в таблице лидеров только через seconds (вызывает DevelopmentService при релизе)
function DataService.holdLeaderstats(player: Player, amount: number, seconds: number)
	local current = leaderstatsHold[player]
	leaderstatsHold[player] = {
		amount = amount + (if current and os.clock() < current.untilAt then current.amount else 0),
		untilAt = os.clock() + seconds,
	}
	task.delay(seconds + 0.1, function()
		if player.Parent then
			DataService.replicate(player)
		end
	end)
end

function DataService.addCash(player: Player, amount: number)
	local p = profiles[player]
	if p then
		p.cash += amount
		DataService.replicate(player)
	end
end

function DataService.trySpend(player: Player, amount: number): boolean
	local p = profiles[player]
	if not p or amount < 0 or p.cash < amount then
		return false
	end
	p.cash -= amount
	DataService.replicate(player)
	return true
end

function DataService.save(player: Player): boolean
	local p = profiles[player]
	local state = states[player]
	if not p or not state or not state.persistent then
		return false
	end
	acquire(player.UserId)
	-- Пока ждали очередь, игрок мог начать выходить: финальную запись делает closeProfile
	local ok = false
	if not state.closed then
		p.lastLogout = os.time()
		ok = write(player.UserId, p, false)
	end
	busy[player.UserId] = nil
	return ok
end

-- Финальное сохранение со снятием метки. Повторный вызов (PlayerRemoving + BindToClose) — пустой
local function closeProfile(player: Player)
	leaderstatsHold[player] = nil
	local p = profiles[player]
	local state = states[player]
	if not p or not state or state.closed then
		return
	end
	state.closed = true
	if state.persistent then
		acquire(player.UserId)
		p.lastLogout = os.time()
		write(player.UserId, p, true)
		busy[player.UserId] = nil
	end
	profiles[player] = nil
	states[player] = nil
end

local function onPlayerAdded(player: Player)
	local userId = player.UserId
	-- Перезашёл на этот же сервер: ждём, пока допишется сохранение прошлой сессии
	acquire(userId)
	local status, result = load(userId)
	busy[userId] = nil

	local persistent = true
	if status == "locked" then
		player:Kick(LOCKED_KICK_MESSAGE)
		return
	elseif status == "error" then
		if RunService:IsStudio() then
			-- В Studio без доступа к API DataStore недоступен: играем без сохранений
			warn(
				"[DataService] DataStore недоступен в Studio, профиль не сохранится:",
				result
			)
			persistent = false
			result = nil
		else
			player:Kick(LOAD_FAILED_KICK_MESSAGE)
			return
		end
	end

	local profile = defaultProfile()
	if type(result) == "table" then
		for k, v in result :: any do
			if k ~= "_session" then
				(profile :: any)[k] = v
			end
		end
		-- Старые сохранения без runBestScore: до первого Rebirth это bestScore, после — с нуля
		if result.runBestScore == nil then
			profile.runBestScore = if profile.rebirths == 0 then profile.bestScore else 0
		end
		if type(profile.recentCombos) ~= "table" then
			profile.recentCombos = {}
		end
	end
	profiles[player] = profile
	states[player] = { persistent = persistent, closed = false }

	-- Вышел, пока грузились: метку уже поставили — сразу снимаем
	if not player.Parent then
		closeProfile(player)
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("NumberValue")
	cash.Name = "Cash"
	cash.Value = profile.cash
	cash.Parent = leaderstats
	leaderstats.Parent = player

	DataService.replicate(player)
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(closeProfile)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player in profiles do
				task.spawn(DataService.save, player)
			end
		end
	end)

	game:BindToClose(function()
		for player in profiles do
			task.spawn(closeProfile, player)
		end
		-- Ждём все записи, включая начатые из PlayerRemoving
		local deadline = os.clock() + CLOSE_TIMEOUT
		while (next(profiles) ~= nil or next(busy) ~= nil) and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return DataService
