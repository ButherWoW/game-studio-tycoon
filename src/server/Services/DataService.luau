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
local Debug = require(ReplicatedStorage.Shared.Config.Debug)
local Bailiffs = require(ReplicatedStorage.Shared.Config.Bailiffs)
local Research = require(ReplicatedStorage.Shared.Config.Research)

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
	-- Для условий открытия жанров/тем (shared/UnlockRules): игр по жанрам и хитов за всё время
	genreGames: { [string]: number },
	hitsReleased: number,
	strikeTipSeen: boolean?, -- закрыл подсказку о первой забастовке (StaffService)
	-- Наставничество (StaffService, Config/Mentoring): mentorId -> menteeId; пары проверяет StaffService
	mentoring: { [string]: string },
	activeAd: { bonus: number, expiresAt: number }?,
	-- Купленные за Robux разовые эффекты (ShopService): заряды и конец действия кофе
	boosts: { instantFinish: number, patch: number, coffeeUntil: number },
	-- Постеры (PosterService): купленные и какой висит на каком месте стены (slotId -> posterId)
	posters: { owned: { [string]: boolean }, equipped: { [string]: string } },
	-- Достижения (AchievementService): получено, счётчики, сочетания; Rebirth не сбрасывает
	achievements: {
		done: { [string]: number },
		stats: { [string]: number },
		combos: { [string]: boolean },
		backfilled: boolean?,
	},
	-- Декор студии (DecorService): купленное по ключу "<id>@<этаж>"
	decor: { owned: { [string]: boolean } },
	-- Скины сотрудников (SkinService): открытые стили и кто что носит (employeeId -> skinId).
	-- Rebirth не сбрасывает owned; assigned чистится по нанятым
	skins: { owned: { [string]: boolean }, assigned: { [string]: string } },
	-- Предложения доната (OfferService): первый вход (таймер стартового набора), куплен ли он, значок
	offers: { firstJoin: number, starterBought: boolean, starterShown: boolean, starterBadge: boolean },
	-- Промокоды (CodeService): код -> os.time() активации
	codes: { [string]: number },
	-- Маскоты (MascotService): открытые и надетый. Rebirth не сбрасывает
	mascots: { owned: { [string]: boolean }, equipped: string? },
	-- Стиль мебели студии (FurnitureStyleService, Config/FurnitureStyles): открытые и выбранный.
	-- Косметика, Rebirth не сбрасывает; формат чистит StyleModels.data при загрузке
	furniture: { owned: { [string]: boolean }, selected: string },
	-- Отделка студии (InteriorFinishService, Config/InteriorFinishes): пол/стены/окна оболочек этапов.
	-- Отдельно от стиля мебели; косметика, Rebirth не сбрасывает; формат чистит StyleModels.finishData
	interior: { owned: { [string]: boolean }, selected: string },
	-- Франшизы и контракты (FranchiseService, ContractService, RivalService); формат проверяют сервисы
	franchises: any?,
	contracts: any?,
	rivals: any?,
	-- Своя консоль и стример (ConsoleService, StreamerService); формат проверяют сервисы
	console: any?,
	streamer: any?,
	-- Дерево перков Rebirth (RebirthPerkService, Config/RebirthPerks): уровни веток и
	-- использован ли бесплатный сброс. Звёзды = rebirths − цена купленного. Rebirth не сбрасывает
	rebirthPerks: { levels: { [string]: number }, respecUsed: boolean },
	-- Исследования (ResearchService, Config/Research): ОИ, изученные узлы, активный таймер лаборатории
	-- и кредиты ускорений за Robux. Rebirth не сбрасывает (кроме открытия жанра/темы за $)
	research: Research.Data,
	-- Титулы над головой (TitleService, Config/Titles): открытые (id -> os.time) и выбранный
	titles: {
		owned: { [string]: number },
		selected: string?,
		expires: { [string]: number }?, -- временные титулы: id -> os.time конца
		restore: string?, -- выбор игрока до временного титула
	},
	-- Настройки игрока (SettingsService, Config/Settings): громкость, «меньше эффектов» и т.п.
	-- Сырые данные: читать только через Settings.sanitize
	settings: { [string]: any },
	-- «Игра недели» (GotwService): лучшая игра недели weekId, неделя последней проверки награды,
	-- место титула (0 — нет) и до какого os.time держатся титул и статуэтка на полке
	gotw: {
		week: number,
		value: number,
		name: string,
		genreId: string,
		score: number,
		revenue: number,
		rewardWeek: number,
		titleRank: number,
		titleUntil: number,
		trophyUntil: number,
	},
	-- Последняя выпущенная игра (для рекламных щитов, BillboardService); имя уже отфильтровано
	lastGame: { name: string, genreId: string, score: number }?,
	-- Стройка следующего этапа (PlotService, Config/Construction): stage — studioLevel после стройки,
	-- времена — os.time(); cost — сколько заплачено (для истории/аналитики, возврата нет)
	construction: { stage: number, startedAt: number, endsAt: number, cost: number }?,
	-- Постепенное открытие систем (FeatureUnlockService, Config/Unlocks): какие системы игрок уже
	-- видел открытыми (больше не прячутся) и разметил ли сервер старое сохранение (init)
	features: { seen: { [string]: boolean }, init: boolean },
	processedReceipts: { [string]: boolean },
	receiptLog: { string }, -- порядок квитанций, чтобы удалять самые старые
	lastLogout: number,
	-- График контента (ContentDropService, Config/ContentDrops): номер последней волны, про которую
	-- игрок видел «Что нового». nil — ещё не ставили (новичок/старое сохранение: ставится тихо)
	contentDropSeen: number?,
}

local function defaultGotw()
	return {
		week = 0,
		value = 0,
		name = "",
		genreId = "",
		score = 0,
		revenue = 0,
		rewardWeek = 0,
		titleRank = 0,
		titleUntil = 0,
		trophyUntil = 0,
	}
end

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
-- Финальная запись при выходе: если write (3 попытки) не прошёл — ещё раунды с растущей паузой,
-- пока укладываемся в CLOSE_WRITE_BUDGET от начала выхода (меньше CLOSE_TIMEOUT)
local CLOSE_RETRY_ROUNDS = 3
local CLOSE_RETRY_BACKOFF = { 1, 2, 4 }
local CLOSE_WRITE_BUDGET = 16 -- новый раунд не начинаем позже: сам write длится до ~7 с

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
		genreGames = {},
		hitsReleased = 0,
		strikeTipSeen = false,
		mentoring = {},
		activeAd = nil,
		boosts = { instantFinish = 0, patch = 0, coffeeUntil = 0 },
		posters = { owned = {}, equipped = {} },
		achievements = { done = {}, stats = {}, combos = {} },
		decor = { owned = {} },
		skins = { owned = {}, assigned = {} },
		offers = { firstJoin = os.time(), starterBought = false, starterShown = false, starterBadge = false },
		codes = {},
		mascots = { owned = {}, equipped = nil },
		furniture = { owned = { classic = true }, selected = "classic" },
		interior = { owned = { classic = true }, selected = "classic" },
		franchises = { list = {}, candidates = {}, nextId = 1 },
		contracts = { done = 0, failed = 0 },
		rivals = { minutes = 0, passed = {} },
		console = {
			v = 2,
			stage = 0,
			endsAt = 0,
			equipment = {},
			credit = 0,
			skips = 0,
			share = 0,
			earned = 0,
		},
		streamer = { hype = 0, earned = 0, scores = {} },
		rebirthPerks = { levels = {}, respecUsed = false },
		research = Research.defaultData(),
		titles = { owned = {}, selected = nil },
		settings = {},
		gotw = defaultGotw(),
		features = { seen = {}, init = false },
		lastGame = nil,
		construction = nil,
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
-- если её уже держит другой сервер (наша метка протухла и профиль забрали).
-- Второе значение — true, если запись отменена из-за чужой метки (повторять бессмысленно)
local function write(userId: number, profile: Profile, release: boolean): (boolean, boolean)
	if not store then
		return false, false
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
				return false, true
			end
			return true, false
		end
		lastErr = err
		task.wait(attempt)
	end
	warn("[DataService] Save failed for", userId, lastErr)
	return false, false
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

-- NaN и ±inf в cash ломают профиль навсегда (NaN < x всегда false — trySpend «списал» бы NaN,
-- и сохранение запишет мусор). Любая сумма из формул/DataStore проходит эту проверку
local function isFiniteAmount(amount: any): boolean
	return type(amount) == "number" and amount == amount and amount > -math.huge and amount < math.huge
end

-- Неотрицательное конечное число из сохранения, иначе 0
local function savedNumber(value: any): number
	return if isFiniteAmount(value) and value >= 0 then value else 0
end

local function savedText(value: any, maxLength: number): string
	return if type(value) == "string" and #value <= maxLength then value else ""
end

-- «Игра недели»: поля по одному, мусор из сохранения — в значения по умолчанию
local function validGotw(raw: any): any
	local gotw = defaultGotw()
	if type(raw) ~= "table" then
		return gotw
	end
	for _, field in
		{ "week", "value", "score", "revenue", "rewardWeek", "titleRank", "titleUntil", "trophyUntil" }
	do
		(gotw :: any)[field] = savedNumber(raw[field])
	end
	gotw.name = savedText(raw.name, 200)
	gotw.genreId = savedText(raw.genreId, 40)
	gotw.score = math.min(gotw.score, 10)
	gotw.titleRank = math.min(math.floor(gotw.titleRank), 10)
	return gotw
end

local function validLastGame(raw: any): { name: string, genreId: string, score: number }?
	if
		type(raw) ~= "table"
		or type(raw.name) ~= "string"
		or #raw.name > 200
		or type(raw.genreId) ~= "string"
		or #raw.genreId > 40
		or not isFiniteAmount(raw.score)
	then
		return nil
	end
	return { name = raw.name, genreId = raw.genreId, score = math.clamp(raw.score, 0, 10) }
end

-- Стройка из сохранения: числа конечные, этап 2..4. Соответствие текущему этапу проверяет PlotService
local function validConstruction(
	raw: any
): { stage: number, startedAt: number, endsAt: number, cost: number }?
	if
		type(raw) ~= "table"
		or not isFiniteAmount(raw.stage)
		or not isFiniteAmount(raw.startedAt)
		or not isFiniteAmount(raw.endsAt)
	then
		return nil
	end
	local stage = math.floor(raw.stage)
	if stage < 2 or stage > 4 then
		return nil
	end
	return { stage = stage, startedAt = raw.startedAt, endsAt = raw.endsAt, cost = savedNumber(raw.cost) }
end

-- Доход релиза прячется из таблицы лидеров, пока в окне релиза не открылась оценка (отчёт #2, п. 6)
local loadedCallbacks: { (Player, Profile) -> () } = {}
local leaderstatsHold: { [Player]: { amount: number, untilAt: number } } = {}

-- Размер команды (staff ведёт StaffService) — для условий открытия на клиенте
local function employeeCount(p: Profile): number
	local staff = (p :: any).staff
	local count = 0
	if type(staff) == "table" then
		for _ in staff do
			count += 1
		end
	end
	return count
end

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
		genreGames = p.genreGames,
		hitsReleased = p.hitsReleased,
		employees = employeeCount(p),
		activeAd = p.activeAd,
		construction = p.construction,
	})
	local leaderstats = player:FindFirstChild("leaderstats")
	local cashValue = leaderstats and leaderstats:FindFirstChild("Cash") :: NumberValue?
	if cashValue then
		local hold = leaderstatsHold[player]
		if hold and os.clock() >= hold.untilAt then
			leaderstatsHold[player] = nil
			hold = nil
		end
		-- Баланс бывает в минусе (долг, Config/Bailiffs): минус показываем как есть, не нулём
		cashValue.Value = if hold then math.max(p.cash - hold.amount, math.min(p.cash, 0)) else p.cash
	end
end

-- Показать amount в таблице лидеров только через seconds (вызывает DevelopmentService при релизе)
function DataService.holdLeaderstats(player: Player, amount: number, seconds: number)
	-- Профиль уже закрыт (вышел): запись осталась бы в таблице навсегда
	if not profiles[player] or not isFiniteAmount(amount) or not isFiniteAmount(seconds) then
		return
	end
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
	if p and isFiniteAmount(amount) then
		p.cash += amount
		DataService.replicate(player)
	end
end

function DataService.trySpend(player: Player, amount: number): boolean
	local p = profiles[player]
	if not p or not isFiniteAmount(amount) or amount < 0 or p.cash < amount then
		return false
	end
	p.cash -= amount
	DataService.replicate(player)
	return true
end

-- Обязательный расход (аренда, зарплата — ExpensesService): списывается и в минус, но не ниже
-- −limit (овердрафт, Config/Bailiffs). Возвращает, сколько списано (остальное сверх лимита — нет).
-- trySpend при минусе по-прежнему отказывает: покупки в долг невозможны
function DataService.charge(player: Player, amount: number, limit: number): number
	local p = profiles[player]
	if not p or not isFiniteAmount(amount) or amount <= 0 or not isFiniteAmount(limit) then
		return 0
	end
	local charged = math.max(math.min(amount, p.cash + math.max(limit, 0)), 0)
	if charged > 0 then
		p.cash -= charged
		DataService.replicate(player)
	end
	return charged
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
		ok = (write(player.UserId, p, false))
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
		local startedAt = os.clock()
		acquire(player.UserId)
		p.lastLogout = os.time()
		local ok, stolen = write(player.UserId, p, true)
		-- Не записалось (сбой DataStore, не чужая метка): ещё несколько раундов с паузой,
		-- пока хватает времени BindToClose — иначе прогресс с последнего автосейва пропадёт
		local round = 0
		while not ok and not stolen and round < CLOSE_RETRY_ROUNDS do
			round += 1
			local pause = CLOSE_RETRY_BACKOFF[round] or 4
			if os.clock() - startedAt + pause >= CLOSE_WRITE_BUDGET then
				break
			end
			task.wait(pause)
			ok, stolen = write(player.UserId, p, true)
		end
		if not ok and not stolen then
			warn("[DataService] Final save failed for", player.UserId, "after", round, "retry rounds")
		end
		busy[player.UserId] = nil
	end
	profiles[player] = nil
	states[player] = nil
end

local function onPlayerAdded(player: Player)
	local userId = player.UserId
	-- Перезашёл на этот же сервер: ждём, пока допишется сохранение прошлой сессии
	acquire(userId)
	-- Studio с тестовыми деньгами: боевой профиль не трогаем совсем (ни чтения с меткой сессии,
	-- ни записи) — иначе тест доливал $999 999 в настоящее сохранение игрока
	local testCash = RunService:IsStudio() and (Debug.studioStartCash or 0) > 0
	local status, result
	if testCash then
		status, result =
			"error",
			"Studio test cash: профиль не загружается и не сохраняется"
	else
		status, result = load(userId)
	end
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
		if type(profile.genreGames) ~= "table" then
			profile.genreGames = {}
		end
		-- Наставничество: только строки ≤ 64 символов; остальное (уволенные, младше/старше) чистит
		-- StaffService.getMentoring по правилам Config/Mentoring
		local mentoring: { [string]: string } = {}
		if type(profile.mentoring) == "table" then
			for mentorId, menteeId in profile.mentoring :: any do
				if
					type(mentorId) == "string"
					and type(menteeId) == "string"
					and #mentorId <= 64
					and #menteeId <= 64
				then
					mentoring[mentorId] = menteeId
				end
			end
		end
		profile.mentoring = mentoring
		-- Старые сохранения без счётчика хитов: считаем свои картриджи на полке
		if type(profile.hitsReleased) ~= "number" then
			local own = 0
			local hits = (profile :: any).hits
			if type(hits) == "table" then
				for _, hit in hits do
					if type(hit) == "table" and hit.creatorId == userId then
						own += 1
					end
				end
			end
			profile.hitsReleased = own
		end
		profile.gotw = validGotw(profile.gotw)
		profile.lastGame = validLastGame(profile.lastGame)
		profile.construction = validConstruction(profile.construction)
		-- Сохранения до защиты addCash/trySpend могли получить NaN или ±inf: с ними trySpend
		-- пропускал любые траты бесплатно. Чиним при загрузке
		if not isFiniteAmount(profile.cash) then
			profile.cash = 0
		end
		-- Минус (долг, Config/Bailiffs) — не глубже самого большого лимита овердрафта
		profile.cash = math.max(profile.cash, -Bailiffs.maxLimit())
		-- Перки Rebirth и титулы: битый формат — заново, неизвестные id (ветки/титулы из будущих
		-- версий или убранные из конфига) не удаляем — только числа/строки нужного типа
		local perks: any = profile.rebirthPerks
		if type(perks) ~= "table" then
			perks = {}
			profile.rebirthPerks = perks
		end
		if type(perks.levels) ~= "table" then
			perks.levels = {}
		end
		for id, level in perks.levels do
			if type(id) ~= "string" or type(level) ~= "number" or level ~= level or level < 0 then
				perks.levels[id] = nil
			end
		end
		perks.respecUsed = perks.respecUsed == true
		-- Исследования: изученное остаётся, битый таймер/кредиты — по умолчанию (Research.sanitize)
		profile.research = Research.sanitize(profile.research)
		local titles: any = profile.titles
		if type(titles) ~= "table" then
			titles = {}
			profile.titles = titles
		end
		if type(titles.owned) ~= "table" then
			titles.owned = {}
		end
		for id, at in titles.owned do
			if type(id) ~= "string" then
				titles.owned[id] = nil
			elseif type(at) ~= "number" then
				titles.owned[id] = os.time()
			end
		end
		if type(titles.selected) ~= "string" or #titles.selected > 64 then
			titles.selected = nil
		end
		-- Временные титулы (TitleService.grant с untilAt): срок — число, иначе титул снимаем
		if titles.expires ~= nil then
			if type(titles.expires) ~= "table" then
				titles.expires = nil
			else
				for id, untilAt in titles.expires do
					if type(id) ~= "string" or type(untilAt) ~= "number" then
						titles.expires[id] = nil
						titles.owned[id] = nil
					end
				end
			end
		end
		if type(titles.restore) ~= "string" or #titles.restore > 64 then
			titles.restore = nil
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
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile)
	end
end

-- Вызвать callback(player, profile) для каждого загруженного профиля: уже загруженных — сразу,
-- новых — после загрузки. Для атрибутов из профиля без опроса и угадывания задержек
function DataService.onProfileLoaded(callback: (Player, Profile) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		if player.Parent then
			task.spawn(callback, player, profile)
		end
	end
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
