--!strict
-- Сейф в парке у фонтана (7.16, Config/Safe). 6-значный код знает только владелец игры:
-- он задаёт код командой в чате (/safe set …, /safe clear, /safe status — синтаксис в Config/Safe).
-- Код, приз, лимит и срок лежат в DataStore SafeCode_v1 (ключ recordKey) и расходятся по серверам
-- через MessagingService (+ перечитывание раз в refreshSeconds). В репозитории, Config и на клиенте
-- кода нет: клиент видит только атрибуты модели SafeState ("off" | "on" | "empty") и SafeCash.
-- Игрок вводит код на клавиатуре (SafeWindow), сервер проверяет: рядом с сейфом, не чаще
-- triesPerMinute / triesPerHour (попытки — в профиле, смена сервера их не обнуляет), один приз
-- на игрока за код (profile.safe.claimed[id]), глобальный лимит победителей — счётчик UpdateAsync.
-- Приз — деньги (RewardService.noteNonEarned + addCash, аналитика: источник SafeService → "safe").
-- Модель: ServerStorage(.Upgrades).ParkSafe (Door с Hinge, Keypad, Indicator) или запасная из деталей.
-- Сервис стартует до StartParkService (по алфавиту): сейф попадает в препятствия для картриджей.

local DataStoreService = game:GetService("DataStoreService")
local GroupService = game:GetService("GroupService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage.Shared
local Safe = require(Shared.Config.Safe)
local StartPark = require(Shared.Config.StartPark)
local Texts = require(Shared.Config.Texts)
local SafeRemotes = require(Shared.SafeRemotes)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)

local MODEL_NAME = "ParkSafe"
local COMMAND_COOLDOWN = 1
local OFF_COLOR = Color3.fromRGB(150, 30, 30)

type Record = {
	id: string, -- меняется вместе с кодом: «один приз на код» и счётчик победителей — по нему
	code: string,
	cash: number,
	limit: number, -- 0 — без лимита
	untilTime: number?, -- unix-время конца, nil — бессрочно
	setBy: number,
	setAt: number,
}

type SafeData = { tries: { number }, claimed: { [string]: number } }

local SafeService = {}
local record: Record? = nil
local winners = 0 -- победителей текущего кода (по всем серверам, насколько знаем)
local store: DataStore? = nil
local model: Model? = nil
local keypad: BasePart? = nil
local signLabel: TextLabel? = nil
local owners: { [number]: boolean } = {}
local busy: { [Player]: boolean } = {}
local lastCommand: { [Player]: number } = {}

-- ===== Запись =====

local function cleanRecord(raw: any): Record?
	if type(raw) ~= "table" then
		return nil
	end
	local code, id = raw.code, raw.id
	if type(code) ~= "string" or #code ~= Safe.codeLength or not code:match("^%d+$") then
		return nil
	end
	if type(id) ~= "string" or id == "" or #id > 64 then
		return nil
	end
	local cash = tonumber(raw.cash)
	local limit = tonumber(raw.limit) or 0
	if not cash or cash ~= cash or cash <= 0 or cash > Safe.maxCash then
		return nil
	end
	local untilTime = tonumber(raw.untilTime)
	return {
		id = id,
		code = code,
		cash = math.floor(cash),
		limit = math.clamp(math.floor(limit), 0, Safe.maxLimit),
		untilTime = untilTime,
		setBy = tonumber(raw.setBy) or 0,
		setAt = tonumber(raw.setAt) or 0,
	}
end

-- "off" — кода нет или срок вышел, "empty" — лимит победителей исчерпан, "on" — можно вводить
local function stateName(): string
	local current = record
	if not current or (current.untilTime and os.time() > current.untilTime) then
		return "off"
	end
	if current.limit > 0 and winners >= current.limit then
		return "empty"
	end
	return "on"
end

local function applyState()
	local m = model
	if not m then
		return
	end
	local state = stateName()
	local current = record
	m:SetAttribute("SafeState", state)
	m:SetAttribute("SafeCash", if current then current.cash else Safe.defaultCash)
	-- Текст по-русски; клиент (SafeController) переводит по атрибутам
	local label = signLabel
	if label then
		label.Text = if state == "on"
			then string.format(
				"🔐 Введи код — приз %s",
				Texts.money(if current then current.cash else 0)
			)
			elseif state == "empty" then "Пусто — жди новый код"
			else "Скоро здесь будет приз"
	end
end

local function winnersKey(id: string): string
	return Safe.winnersPrefix .. id
end

local function readWinners(id: string): number?
	local ds = store
	if not ds then
		return nil
	end
	local ok, value = pcall(function()
		return ds:GetAsync(winnersKey(id))
	end)
	if not ok then
		warn("[SafeService] GetAsync winners failed:", value)
		return nil
	end
	return math.max(math.floor(tonumber(value) or 0), 0)
end

-- Новая запись (из DataStore, сообщения или своей команды). announce — баннер «новый приз» всем на сервере
local function adopt(incoming: Record?, countKnown: number?, announce: boolean)
	local previous = record
	local changed = (previous and previous.id) ~= (incoming and incoming.id)
	record = incoming
	if changed then
		winners = 0
	end
	if incoming then
		local count = countKnown
		if count == nil and changed then
			count = readWinners(incoming.id)
		end
		-- Пока читали счётчик, запись могла смениться ещё раз
		if record ~= incoming then
			return
		end
		if count then
			winners = math.max(winners, count)
		end
	end
	applyState()
	if announce and changed and incoming and stateName() == "on" then
		for _, player in Players:GetPlayers() do
			SafeRemotes.SafeNotice:FireClient(player, { kind = "new", cash = incoming.cash })
		end
	end
end

local function loadRecord()
	local ds = store
	if not ds then
		return
	end
	local ok, value = pcall(function()
		return ds:GetAsync(Safe.recordKey)
	end)
	if not ok then
		warn("[SafeService] GetAsync record failed:", value)
		return
	end
	local incoming = cleanRecord(value)
	local current = record
	if incoming and current and incoming.id == current.id then
		-- Тот же код: обновить приз/лимит/срок и счётчик победителей
		record = incoming
		local count = readWinners(incoming.id)
		if count then
			winners = math.max(winners, count)
		end
		applyState()
	else
		-- Код сменился, а сообщение не дошло: баннер всё равно нужен (но не при старте сервера)
		adopt(incoming, nil, current ~= nil)
	end
end

local function publish(message: { [string]: any })
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(Safe.topic, message)
		end)
		if not ok then
			warn("[SafeService] PublishAsync failed:", err)
		end
	end)
end

local function onMessage(message: any)
	local data = type(message) == "table" and message.Data
	if type(data) ~= "table" then
		return
	end
	if data.kind == "set" then
		local incoming = cleanRecord(data.record)
		if not incoming then
			return
		end
		local current = record
		if current and current.id == incoming.id then
			record = incoming
			applyState()
		else
			adopt(incoming, if data.fresh == true then 0 else nil, true)
		end
	elseif data.kind == "clear" then
		adopt(nil, nil, false)
	elseif data.kind == "winners" then
		local current = record
		local count = tonumber(data.count)
		if current and data.id == current.id and count then
			winners = math.max(winners, math.floor(count))
			applyState()
		end
	end
end

-- ===== Профиль =====

local function safeData(profile: DataService.Profile): SafeData
	local p = profile :: any
	local data = p.safe
	if type(data) ~= "table" then
		data = {}
		p.safe = data
	end
	if type(data.tries) ~= "table" then
		data.tries = {}
	end
	if type(data.claimed) ~= "table" then
		data.claimed = {}
	end
	return data :: SafeData
end

-- Сколько секунд ждать до следующей попытки (0 — можно). Старше часа — выбрасываем
local function throttle(data: SafeData, now: number): number
	local kept = {}
	for _, at in data.tries do
		if type(at) == "number" and at > now - 3600 and at <= now then
			table.insert(kept, at)
		end
	end
	table.sort(kept)
	data.tries = kept
	if #kept >= Safe.triesPerHour then
		return kept[#kept - Safe.triesPerHour + 1] + 3600 - now
	end
	local inMinute = {}
	for _, at in kept do
		if at > now - 60 then
			table.insert(inMinute, at)
		end
	end
	if #inMinute >= Safe.triesPerMinute then
		return inMinute[#inMinute - Safe.triesPerMinute + 1] + 60 - now
	end
	return 0
end

-- ===== Попытка =====

local function analytics(player: Player, field: string)
	local module = script.Parent:FindFirstChild("AnalyticsService")
	if module and module:IsA("ModuleScript") then
		pcall((require(module) :: any).logLiveOps, player, "safe", 1, field)
	end
end

local function reply(player: Player, reason: string, extra: { [string]: any }?)
	local payload: { [string]: any } = { reason = reason }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	SafeRemotes.SafeResult:FireClient(player, payload)
end

local function nearSafe(player: Player): boolean
	local part = keypad
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return part ~= nil
		and root ~= nil
		and root:IsA("BasePart")
		and (root.Position - part.Position).Magnitude <= Safe.maxTryDistance
end

-- Вернуть занятое место победителя (UpdateAsync −1), если приз так и не выдали
local function releaseWinner(id: string)
	local ds = store
	if not ds then
		return
	end
	task.spawn(function()
		local count: number? = nil
		local ok, err = pcall(function()
			ds:UpdateAsync(winnersKey(id), function(old: any)
				local n = math.max(math.floor(tonumber(old) or 0), 0)
				if n <= 0 then
					return nil
				end
				count = n - 1
				return count
			end)
		end)
		if not ok then
			warn("[SafeService] UpdateAsync winners release failed:", err)
			return
		end
		-- Счётчик этого сервера — точное значение из хранилища (другие узнают при перечитывании)
		local current = record
		if count and current and current.id == id then
			winners = count
			applyState()
		end
	end)
end

local function onTry(player: Player, digits: any)
	if busy[player] then
		return
	end
	if type(digits) ~= "string" or #digits ~= Safe.codeLength or not digits:match("^%d+$") then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if not nearSafe(player) then
		reply(player, "far")
		return
	end
	local current = record
	local state = stateName()
	if not current or state ~= "on" then
		reply(player, state)
		return
	end
	local data = safeData(profile)
	if data.claimed[current.id] ~= nil then
		reply(player, "used")
		return
	end
	local now = os.time()
	local wait = throttle(data, now)
	if wait > 0 then
		reply(player, "slow", { wait = math.ceil(wait) })
		analytics(player, "slow")
		return
	end
	table.insert(data.tries, now)
	if digits ~= current.code then
		reply(player, "wrong")
		analytics(player, "wrong")
		return
	end

	-- Верный код: место в лимите победителей (глобально, UpdateAsync)
	local ds = store
	if not ds then
		reply(player, "error")
		return
	end
	busy[player] = true
	local full = false
	local count = 0
	local ok, err = pcall(function()
		ds:UpdateAsync(winnersKey(current.id), function(old: any)
			local n = math.max(math.floor(tonumber(old) or 0), 0)
			full = current.limit > 0 and n >= current.limit
			if full then
				count = n
				return nil -- лимит исчерпан: не пишем
			end
			count = n + 1
			return count
		end)
	end)
	busy[player] = nil
	if not ok then
		warn("[SafeService] UpdateAsync winners failed:", err)
		-- Сбой хранилища — не вина игрока: попытку не засчитываем
		table.remove(data.tries)
		reply(player, "error")
		return
	end
	if record and record.id == current.id then
		winners = math.max(winners, count)
		applyState()
	end
	if full then
		publish({ kind = "winners", id = current.id, count = count })
		reply(player, "empty")
		analytics(player, "empty")
		return
	end
	-- Игрок мог выйти, пока ждали хранилище: приз не выдан — место в лимите возвращаем
	-- (claimed не отмечен, при следующем входе он может ввести код снова)
	if not player.Parent or DataService.get(player) ~= profile then
		releaseWinner(current.id)
		return
	end
	data.claimed[current.id] = now
	-- Не заработок за игру: в задания «заработай» не идёт
	RewardService.noteNonEarned(player, current.cash)
	DataService.addCash(player, current.cash)
	reply(player, "ok", { cash = current.cash })
	analytics(player, "ok")
	if current.limit > 0 and count >= current.limit then
		publish({ kind = "winners", id = current.id, count = count })
	end
	-- Разовая награда: сохраняем сразу
	task.spawn(DataService.save, player)
end

-- ===== Команды владельца =====

local function isOwner(player: Player): boolean
	return owners[player.UserId] == true
end

local function resolveOwners()
	for _, id in Safe.ownerUserIds do
		owners[id] = true
	end
	if game.CreatorType == Enum.CreatorType.User then
		if game.CreatorId > 0 then
			owners[game.CreatorId] = true
		end
	elseif game.CreatorId > 0 then
		local ok, info = pcall(function()
			return GroupService:GetGroupInfoAsync(game.CreatorId)
		end)
		local owner = ok and type(info) == "table" and (info :: any).Owner
		local ownerId = type(owner) == "table" and tonumber(owner.Id)
		if ownerId then
			owners[ownerId] = true
		elseif not ok then
			warn("[SafeService] GetGroupInfoAsync failed:", info)
		end
	end
end

local function adminReply(player: Player, text: string)
	SafeRemotes.SafeNotice:FireClient(player, { kind = "admin", text = text })
end

-- 500000, 500k, 1.5m
local function parseCash(raw: string): number?
	local number, suffix = raw:lower():match("^(%d+%.?%d*)([km]?)$")
	local value = tonumber(number)
	if not value then
		return nil
	end
	value *= if suffix == "k" then 1_000 elseif suffix == "m" then 1_000_000 else 1
	value = math.floor(value)
	return if value > 0 and value <= Safe.maxCash then value else nil
end

-- 2026-11-12 (до конца дня UTC) или 2026-11-12T18:00 (UTC)
local function parseUntil(raw: string): number?
	local y, mo, d, h, mi = raw:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt_](%d%d):(%d%d)$")
	if not y then
		y, mo, d = raw:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	end
	local year, month, day = tonumber(y), tonumber(mo), tonumber(d)
	if not year or not month or not day or month < 1 or month > 12 or day < 1 or day > 31 then
		return nil
	end
	local hour = if h then tonumber(h) else 23
	local minute = if mi then tonumber(mi) else 59
	local second = if h then 0 else 59
	if not hour or not minute or hour > 23 or minute > 59 then
		return nil
	end
	local ok, time = pcall(function()
		return DateTime.fromUniversalTime(year, month, day, hour, minute, second).UnixTimestamp
	end)
	return if ok and type(time) == "number" then time else nil
end

local function describe(current: Record?): string
	if not current then
		return "Сейф пуст: кода нет"
	end
	local limit = if current.limit > 0 then tostring(current.limit) else "∞"
	local untilText = if current.untilTime
		then DateTime.fromUnixTimestamp(current.untilTime):FormatUniversalTime("YYYY-MM-DD HH:mm", "en-us")
			.. " UTC"
		else "бессрочно"
	return string.format(
		"Код %s · приз %s · победителей %d/%s · до %s · сейчас: %s",
		current.code,
		Texts.money(current.cash),
		winners,
		limit,
		untilText,
		stateName()
	)
end

local function commandSet(player: Player, args: { string })
	local code = args[3]
	if type(code) ~= "string" or #code ~= Safe.codeLength or not code:match("^%d+$") then
		adminReply(
			player,
			"Нужен код из "
				.. Safe.codeLength
				.. " цифр: /safe set 482913 cash=500000 limit=100"
		)
		return
	end
	local cash, limit, untilTime = Safe.defaultCash, Safe.defaultLimit, nil :: number?
	for i = 4, #args do
		local key, value = args[i]:match("^(%a+)=(.+)$")
		key = key and key:lower()
		if key == "cash" then
			local parsed = parseCash(value)
			if not parsed then
				adminReply(
					player,
					"Не понял cash=" .. tostring(value) .. " (пример: 500000, 500k, 20m)"
				)
				return
			end
			cash = parsed
		elseif key == "limit" then
			local parsed = tonumber(value)
			if not parsed or parsed < 0 or parsed > Safe.maxLimit or parsed ~= math.floor(parsed) then
				adminReply(
					player,
					"Не понял limit=" .. tostring(value) .. " (целое, 0 — без лимита)"
				)
				return
			end
			limit = parsed
		elseif key == "until" then
			local parsed = parseUntil(value)
			if not parsed or parsed <= os.time() then
				adminReply(
					player,
					"Не понял until=" .. tostring(value) .. " (дата в будущем: 2026-11-12)"
				)
				return
			end
			untilTime = parsed
		else
			adminReply(player, "Неизвестный параметр: " .. args[i])
			return
		end
	end
	local ds = store
	if not ds then
		adminReply(player, "DataStore недоступен (в Studio включи API Services)")
		return
	end
	-- Тот же код — та же запись: счётчик победителей и «уже получил» сохраняются
	local current = record
	local fresh = not current or current.code ~= code
	local incoming: Record = {
		id = if fresh or not current then HttpService:GenerateGUID(false) else current.id,
		code = code,
		cash = cash,
		limit = limit,
		untilTime = untilTime,
		setBy = player.UserId,
		setAt = os.time(),
	}
	local ok, err = pcall(function()
		ds:SetAsync(Safe.recordKey, incoming)
	end)
	if not ok then
		adminReply(player, "Не сохранилось: " .. tostring(err))
		return
	end
	if fresh then
		adopt(incoming, 0, true)
	else
		record = incoming
		applyState()
	end
	publish({ kind = "set", record = incoming, fresh = fresh })
	adminReply(player, "Готово. " .. describe(record))
end

local function commandClear(player: Player)
	local ds = store
	if not ds then
		adminReply(player, "DataStore недоступен (в Studio включи API Services)")
		return
	end
	local ok, err = pcall(function()
		ds:RemoveAsync(Safe.recordKey)
	end)
	if not ok then
		adminReply(player, "Не удалилось: " .. tostring(err))
		return
	end
	adopt(nil, nil, false)
	publish({ kind = "clear" })
	adminReply(
		player,
		"Код убран: сейф показывает «Скоро здесь будет приз»"
	)
end

local function onCommand(player: Player, text: string)
	-- Чужим — тишина: о команде не рассказываем
	if not isOwner(player) or type(text) ~= "string" or #text > 200 then
		return
	end
	local now = os.clock()
	if (lastCommand[player] or 0) + COMMAND_COOLDOWN > now then
		return
	end
	lastCommand[player] = now
	local args = {}
	for word in text:gmatch("%S+") do
		table.insert(args, word)
	end
	local sub = (args[2] or ""):lower()
	if sub == "set" then
		commandSet(player, args)
	elseif sub == "clear" then
		commandClear(player)
	elseif sub == "status" then
		adminReply(player, describe(record))
	else
		adminReply(
			player,
			"/safe set 482913 cash=500000 limit=100 until=2026-11-12 · /safe clear · /safe status"
		)
	end
end

-- Панель владельца (SafeAdminPanel): поля проверяем здесь заново и прогоняем через ту же
-- логику, что и /safe. Не владелец — тишина
local FIELD_PATTERN = "^[%w%.%-:]*$"
local function onAdmin(player: Player, payload: any)
	if not isOwner(player) or type(payload) ~= "table" then
		return
	end
	local action = payload.action
	if action == "clear" or action == "status" then
		onCommand(player, "/safe " .. action)
		return
	end
	if action ~= "set" then
		return
	end
	local parts = { "/safe", "set" }
	local code = payload.code
	if type(code) ~= "string" or #code ~= Safe.codeLength or not code:match("^%d+$") then
		adminReply(player, "Нужен код из " .. Safe.codeLength .. " цифр")
		return
	end
	table.insert(parts, code)
	for _, field in { "cash", "limit", "until" } do
		local value = payload[field]
		if value ~= nil then
			if type(value) ~= "string" or #value > 32 or not value:match(FIELD_PATTERN) then
				adminReply(player, "Не понял поле " .. field)
				return
			end
			if value ~= "" then
				table.insert(parts, field .. "=" .. value)
			end
		end
	end
	onCommand(player, table.concat(parts, " "))
end

-- Атрибут SafeAdmin: клиент показывает кнопку 🔐 панели только владельцам (решает сервер)
local function markOwner(player: Player)
	if isOwner(player) then
		player:SetAttribute("SafeAdmin", true)
	end
end

local function setupCommand()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		-- В старом чате «/safe …» ушло бы в общий чат вместе с кодом: команду не включаем
		warn("[SafeService] TextChatService is off: /safe command disabled")
		return
	end
	local command = Instance.new("TextChatCommand")
	command.Name = "SafeCommand"
	command.PrimaryAlias = "/safe"
	command.Triggered:Connect(function(source: TextSource, text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player then
			onCommand(player, text)
		end
	end)
	command.Parent = TextChatService
end

-- ===== Модель =====

local function template(): Model?
	local found = ServerStorage:FindFirstChild(MODEL_NAME)
	if not found then
		local upgrades = ServerStorage:FindFirstChild("Upgrades")
		found = upgrades and upgrades:FindFirstChild(MODEL_NAME)
	end
	return if found and found:IsA("Model") then found else nil
end

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	center: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = CFrame.new(center)
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Запасной сейф ≈ 4.4 × 4.9 × 4.4: лицо +Z, pivot — центр основания
local function buildFallback(): Model
	local m = Instance.new("Model")
	m.Name = MODEL_NAME
	local steel = Color3.fromRGB(70, 76, 88)
	local dark = Color3.fromRGB(38, 40, 48)
	local brass = Color3.fromRGB(200, 160, 60)
	block(m, "Base", Vector3.new(4.4, 0.3, 4.4), Vector3.new(0, 0.15, 0), dark, Enum.Material.Metal)
	local body = block(m, "Body", Vector3.new(4, 4.6, 4), Vector3.new(0, 2.6, 0), steel, Enum.Material.Metal)
	m.PrimaryPart = body
	-- Дверца на петле слева: Hinge — ось, Panel и штурвал поворачиваются вокруг неё (SafeController)
	local door = Instance.new("Model")
	door.Name = "Door"
	door.Parent = m
	block(door, "Hinge", Vector3.new(0.3, 3.6, 0.3), Vector3.new(-1.8, 2.6, 2.1), dark, Enum.Material.Metal)
	block(
		door,
		"Panel",
		Vector3.new(2.7, 3.6, 0.2),
		Vector3.new(-0.45, 2.6, 2.1),
		steel,
		Enum.Material.DiamondPlate
	)
	local wheel = block(
		door,
		"Wheel",
		Vector3.new(0.2, 1.3, 1.3),
		Vector3.new(-0.45, 2.6, 2.3),
		brass,
		Enum.Material.Metal
	)
	wheel.Shape = Enum.PartType.Cylinder
	wheel.CFrame = CFrame.new(-0.45, 2.6, 2.3) * CFrame.Angles(0, math.rad(90), 0)
	for _, angle in { 0, 60, 120 } do
		local spoke = block(
			door,
			"Spoke",
			Vector3.new(0.12, 1.7, 0.12),
			Vector3.new(-0.45, 2.6, 2.42),
			brass,
			Enum.Material.Metal
		)
		spoke.CFrame = CFrame.new(-0.45, 2.6, 2.42) * CFrame.Angles(0, 0, math.rad(angle))
	end
	-- Клавиатура и лампочка справа от дверцы
	local pad = block(
		m,
		"Keypad",
		Vector3.new(0.9, 1.4, 0.15),
		Vector3.new(1.45, 2.4, 2.07),
		dark,
		Enum.Material.SmoothPlastic
	)
	-- Лицо модели +Z — у детали это грань Back
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.LightInfluence = 0
	gui.Parent = pad
	local keys = Instance.new("TextLabel")
	keys.Size = UDim2.fromScale(1, 1)
	keys.BackgroundTransparency = 1
	keys.Font = Enum.Font.GothamBold
	keys.TextScaled = true
	keys.TextColor3 = Color3.fromRGB(220, 230, 240)
	keys.Text = "1 2 3\n4 5 6\n7 8 9\n✱ 0 #"
	keys.Parent = gui
	block(
		m,
		"Indicator",
		Vector3.new(0.5, 0.25, 0.15),
		Vector3.new(1.45, 3.45, 2.07),
		OFF_COLOR,
		Enum.Material.Neon
	)
	-- Детали не мешают ходить вокруг: корпус и основание сталкиваются, мелочь — нет
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			if d.Name ~= "Body" and d.Name ~= "Base" then
				d.CanCollide = false
			end
		end
	end
	m.WorldPivot = CFrame.new()
	return m
end

local function spawnCenter(): Vector3
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	return if spawn and spawn:IsA("BasePart")
		then Vector3.new(spawn.Position.X, 0, spawn.Position.Z)
		else Vector3.zero
end

-- Место свободно: в объёме над землёй (с 0.6 stud — без травы и тропинок) нет чужих деталей
local function isFree(cframe: CFrame, ignore: Instance): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore }
	local size = Safe.footprint
	local parts = workspace:GetPartBoundsInBox(cframe * CFrame.new(0, 0.6 + size.Y / 2, 0), size, params)
	for _, p in parts do
		if p.Transparency < 1 or p.CanCollide then
			return false
		end
	end
	return true
end

-- У фонтана: смещение от фонтана как в раскладке (фонтан могли подвинуть в Studio); без фонтана — запасная точка
local function basePlacement(): (Vector3, number)
	local fountain = workspace:FindFirstChild("Fountain", true)
	if fountain and fountain:IsA("Model") then
		local offset = Safe.landscapePosition - StartPark.landscapeFountain.position
		local at = fountain:GetPivot().Position
		return Vector3.new(at.X, 0, at.Z) + offset, Safe.landscapeYaw
	end
	return spawnCenter() + Safe.fallbackPosition, Safe.fallbackYaw
end

local function place(m: Model)
	local position, yaw = basePlacement()
	local center = spawnCenter()
	local function at(p: Vector3): CFrame
		return CFrame.new(p) * CFrame.Angles(0, math.rad(yaw), 0)
	end
	local chosen = at(position)
	if not isFree(chosen, m) then
		local found = false
		for ring = 1, Safe.searchRings do
			for i = 0, 7 do
				local angle = math.rad(i * 45)
				local candidate = position
					+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * (ring * Safe.searchStep)
				-- Не ближе к спавну, чем площадка 16×16
				if (candidate - center).Magnitude > 12 and isFree(at(candidate), m) then
					chosen = at(candidate)
					found = true
					break
				end
			end
			if found then
				break
			end
		end
		if not found then
			warn("[SafeService] No free spot near the fountain: placing at the default point")
		end
	end
	m:PivotTo(chosen)
end

-- Табличка над сейфом (BillboardGui, текст ставит applyState и переводит клиент)
local function addSign(m: Model)
	local cframe, size = m:GetBoundingBox()
	local anchor = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "SignAnchor"
	attachment.Parent = anchor
	attachment.WorldPosition = cframe.Position + Vector3.new(0, size.Y / 2 + 1.4, 0)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SafeSign"
	gui.Adornee = attachment
	gui.Size = UDim2.fromScale(9, 1.4)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Parent = attachment
	local label = Instance.new("TextLabel")
	label.Name = "SignText"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 90)
	label.TextStrokeColor3 = Color3.fromRGB(40, 30, 0)
	label.TextStrokeTransparency = 0.2
	label.Text = "Скоро здесь будет приз"
	label.Parent = gui
	signLabel = label
end

local function ensureModel()
	local park = workspace:FindFirstChild("StartPark")
	if not park then
		warn("[SafeService] workspace.StartPark not found: safe is disabled")
		return
	end
	-- Поставлен в Studio руками — не двигаем
	local existing = park:FindFirstChild(MODEL_NAME)
	local m: Model
	if existing and existing:IsA("Model") then
		m = existing
	else
		local source = template()
		if source then
			m = source:Clone()
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
				elseif d:IsA("Script") then
					d:Destroy()
				end
			end
		else
			m = buildFallback()
		end
		m.Name = MODEL_NAME
		place(m)
		m.Parent = park
	end
	model = m
	local pad = m:FindFirstChild("Keypad", true)
	if pad and pad:IsA("Model") then
		pad = pad.PrimaryPart or pad:FindFirstChildWhichIsA("BasePart", true)
	end
	if not (pad and pad:IsA("BasePart")) then
		pad = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	end
	keypad = if pad and pad:IsA("BasePart") then pad else nil
	local indicator = m:FindFirstChild("Indicator", true)
	if indicator and indicator:IsA("BasePart") then
		indicator.Color = OFF_COLOR
		indicator.Material = Enum.Material.Neon
	end
	addSign(m)
	local target = keypad
	if target then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Ввести код"
		prompt.ObjectText = "Сейф"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Safe.promptDistance
		prompt.RequiresLineOfSight = false
		-- Перевод — StartParkController (сейф лежит в workspace.StartPark)
		prompt:SetAttribute("ActionKey", "safe_prompt")
		prompt:SetAttribute("ObjectKey", "safe_object")
		prompt.Triggered:Connect(function(player: Player)
			local profile = DataService.get(player)
			local current = record
			if profile then
				local claimed = current ~= nil and safeData(profile).claimed[current.id] ~= nil
				SafeRemotes.SafeOpen:FireClient(player, { claimed = claimed })
			end
		end)
		prompt.Parent = target
	end
	applyState()
end

function SafeService.start()
	ensureModel()
	SafeRemotes.SafeTry.OnServerEvent:Connect(onTry)
	SafeRemotes.SafeAdmin.OnServerEvent:Connect(onAdmin)
	Players.PlayerAdded:Connect(markOwner)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		lastCommand[player] = nil
	end)
	setupCommand()

	local okStore, result = pcall(function()
		return DataStoreService:GetDataStore(Safe.dataStore)
	end)
	if okStore then
		store = result
	else
		warn("[SafeService] DataStore unavailable:", result)
	end
	task.spawn(function()
		resolveOwners()
		for _, player in Players:GetPlayers() do
			markOwner(player)
		end
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(Safe.topic, onMessage)
		end)
		if not ok then
			warn("[SafeService] SubscribeAsync failed:", err)
		end
		while true do
			loadRecord()
			-- Срок кода мог выйти: перерисовать табличку
			applyState()
			task.wait(Safe.refreshSeconds)
		end
	end)
end

return SafeService
