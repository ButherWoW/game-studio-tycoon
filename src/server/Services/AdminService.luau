--!strict
-- Админ-панель владельца (Config/Admin, клиент Controllers/AdminPanel, remotes AdminRemotes).
-- Кто владелец — OwnerAccess (как у сейфа). Атрибут AdminPanel на игроке — только подсказка клиенту
-- нарисовать кнопку 🛠; каждый вызов AdminRequest заново проверяет владельца, частоту (Config/Admin
-- minInterval / burst), типы и диапазоны аргументов. Не владелец — nil без объяснений.
--
-- Действия (args — таблица, target — UserId игрока на этом сервере):
--   Игрок (только на себе): cash { amount ± }, points { amount ± } (ОИ), stage { level 1..4 },
--     finish { kind: dev | build | research | training | all } — закончить таймеры.
--   Время: contentDay { day | clear } — день контента (волны и обновления по средам) на весь сервер:
--     только Studio / закрытый сервер, где одни владельцы (ContentDrops.adminDayAllowed);
--     testServer — телепорт себя на новый закрытый сервер (ReserveServer).
--   Контент: event { id | "golden" | "stop", minutes } — событие дня / золотой час на этом сервере
--     (хорошие события для всех; при других игроках на сервере — с подтверждением).
--   Модерация: view { target } (только чтение), teleport { target } (себя к игроку), kick { target,
--     reason }, ban { target, days (0 — навсегда), reason }, unban { userId }, reset { target }.
--   Сервер: announce { text } — плашка всем (фильтр Roblox + TextSafe); players, status — для окна.
-- Кик, бан и сброс профиля — в два шага: первый вызов возвращает confirm-токен (живёт
-- Admin.confirmSeconds, годится только для того же действия и того же игрока), второй — с ним.
-- Владельцев нельзя кикнуть, забанить или сбросить (кроме сброса самого себя).
-- Каждое выполненное действие: warn в Output сервера + AnalyticsService (AdminAction, поле — действие).
-- Бан: DataStore Admin.banStore, проверка при входе. Debug-флаги и StudioDebug здесь не используются.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage.Shared
local Admin = require(Shared.Config.Admin)
local ContentDrops = require(Shared.Config.ContentDrops)
local DailyEvents = require(Shared.Config.DailyEvents)
local Stages = require(Shared.Config.Stages)
local TextSafe = require(Shared.TextSafe)
local AdminRemotes = require(Shared.AdminRemotes)
local BroadcastText = require(script.Parent.BroadcastText)
local DataService = require(script.Parent.DataService)
local OwnerAccess = require(script.Parent.OwnerAccess)
local PlotService = require(script.Parent.PlotService)
local RewardService = require(script.Parent.RewardService)

type Reply = { ok: boolean, text: string, confirm: string?, data: any? }
type Ctx = { player: Player, args: { [string]: any }, confirmed: string? }
type Pending = { token: string, action: string, key: string, expires: number }
type Handler = (ctx: Ctx) -> Reply

local MAX_ARGS = 8
local EVENT_ATTRIBUTES = { "AdminEventId", "AdminEventStartsAt", "AdminEventEndsAt" }
local GOLDEN_ATTRIBUTES = { "AdminGoldenStartsAt", "AdminGoldenEndsAt" }
-- Готовые ответы без записи в лог: окно опрашивает их при открытии и переключении вкладок
local QUIET = { players = true, status = true }

local AdminService = {}

local handlers: { [string]: Handler } = {}
local pending: { [Player]: Pending } = {}
local lastAt: { [Player]: number } = {}
local recent: { [Player]: { number } } = {}
local banStore: DataStore? = nil

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, service = pcall(require, module)
	return if ok then service else nil
end

local function call(name: string, fnName: string, ...: any): any
	local service = optional(name)
	local fn = service and service[fnName]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn("[AdminService] " .. name .. "." .. fnName .. " failed:", result)
		return nil
	end
	return result
end

local function reply(ok: boolean, text: string, data: any?): Reply
	return { ok = ok, text = text, data = data }
end

-- ===== Проверка аргументов =====

-- Целое конечное число в [min, max], иначе nil
local function int(value: any, min: number, max: number): number?
	if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < min or value > max then
		return nil
	end
	return value
end

-- Строка из панели: не длиннее maxLength символов, без невидимых символов (TextSafe), не пустая
local function cleanText(value: any, maxLength: number): string?
	if type(value) ~= "string" or #value > maxLength * 4 then
		return nil
	end
	local text = TextSafe.clean(value)
	if not text or text == "" then
		return nil
	end
	local length = utf8.len(text)
	if not length or length > maxLength then
		return nil
	end
	return text
end

-- Игрок на этом сервере по UserId из args.target
local function targetOf(args: { [string]: any }): Player?
	local userId = int(args.target, 1, 2 ^ 53)
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

local function onlyOwnersHere(): boolean
	for _, other in Players:GetPlayers() do
		if not OwnerAccess.isOwner(other) then
			return false
		end
	end
	return true
end

local function who(player: Player): string
	return player.Name .. " (" .. player.UserId .. ")"
end

-- Нужен второй шаг: вернуть токен, если ctx ещё не подтверждён именно для key
local function confirmGate(ctx: Ctx, action: string, key: string, text: string): Reply?
	if ctx.confirmed == key then
		return nil
	end
	local token = HttpService:GenerateGUID(false)
	pending[ctx.player] =
		{ token = token, action = action, key = key, expires = os.clock() + Admin.confirmSeconds }
	return {
		ok = true,
		confirm = token,
		text = text .. " Нажми «Подтвердить» в течение " .. Admin.confirmSeconds .. " с.",
	}
end

-- ===== Лог =====

local function logAction(player: Player, field: string, details: string)
	local suffix = if details ~= "" then ": " .. details else ""
	warn("[AdminService] " .. who(player) .. " → " .. field .. suffix)
	call("AnalyticsService", "logLiveOps", player, "admin", 1, field)
end

-- ===== Игрок (на себе) =====

handlers.cash = function(ctx: Ctx): Reply
	local amount = int(ctx.args.amount, -Admin.maxCash, Admin.maxCash)
	local profile = DataService.get(ctx.player)
	if not amount or amount == 0 then
		return reply(false, "Сумма — целое число, не 0, до " .. Admin.maxCash)
	elseif not profile then
		return reply(false, "Профиль ещё не загрузился")
	end
	if amount > 0 then
		DataService.addCash(ctx.player, amount)
		RewardService.noteNonEarned(ctx.player, amount)
	else
		-- Забираем не больше, чем есть (долг панелью не создаём)
		profile.cash = math.max(profile.cash + amount, math.min(profile.cash, 0))
		DataService.replicate(ctx.player)
	end
	logAction(ctx.player, if amount > 0 then "cash_give" else "cash_take", tostring(amount))
	return reply(true, "Баланс: $" .. math.floor(profile.cash))
end

handlers.points = function(ctx: Ctx): Reply
	local amount = int(ctx.args.amount, -Admin.maxResearchPoints, Admin.maxResearchPoints)
	local profile = DataService.get(ctx.player)
	local research = profile and profile.research
	if not amount or amount == 0 then
		return reply(false, "ОИ — целое число, не 0, до " .. Admin.maxResearchPoints)
	elseif type(research) ~= "table" then
		return reply(false, "Профиль ещё не загрузился")
	end
	research.points = math.max(math.floor(research.points + amount), 0)
	call("ResearchService", "sync", ctx.player)
	logAction(ctx.player, if amount > 0 then "points_give" else "points_take", tostring(amount))
	return reply(true, "ОИ: " .. research.points)
end

handlers.stage = function(ctx: Ctx): Reply
	local level = int(ctx.args.level, 1, #Stages)
	local profile = DataService.get(ctx.player)
	if not level then
		return reply(false, "Этап — от 1 до " .. #Stages)
	elseif not profile then
		return reply(false, "Профиль ещё не загрузился")
	end
	local p = profile :: any
	p.ownsGarage = true
	profile.upgrades.desk1 = true
	-- Офис — апгрейд office (Stages[2].requiresUpgrade); без него rebuild вернёт студию в гараж
	profile.upgrades.office = if level >= 2 then true else nil
	profile.construction = nil
	profile.studioLevel = level
	ctx.player:SetAttribute("OwnsGarage", true)
	PlotService.rebuild(ctx.player)
	DataService.replicate(ctx.player)
	task.spawn(DataService.save, ctx.player)
	logAction(ctx.player, "stage", tostring(level))
	return reply(true, "Этап: " .. Stages[profile.studioLevel].name)
end

local FINISH_KINDS = { dev = true, build = true, research = true, training = true, all = true }

local function finishTimers(player: Player, kind: string): { string }
	local profile = DataService.get(player)
	if not profile then
		return {}
	end
	local done: { string } = {}
	local now = os.time()
	if kind == "dev" or kind == "all" then
		-- «Выпустить раньше» на 100%: очки за оставшееся время, релиз — на следующем тике разработки
		local count = call("DevelopmentService", "rushProjects", player, 1)
		call("DevelopmentService", "pushState", player)
		if type(count) == "number" and count > 0 then
			table.insert(done, "разработка ×" .. count)
		end
	end
	if kind == "build" or kind == "all" then
		-- ConstructionService раз в секунду видит конец срока и переносит студию
		local construction = PlotService.construction(player)
		if construction then
			construction.endsAt = now
			DataService.replicate(player)
			table.insert(done, "стройка")
		end
	end
	if kind == "research" or kind == "all" then
		local research = profile.research
		local active = if type(research) == "table" then research.active else nil
		if active then
			active.endsAt = now
			table.insert(done, "исследование")
		end
	end
	if kind == "training" or kind == "all" then
		-- StaffService.trainingTick раз в секунду доучивает тех, у кого endAt <= сейчас
		local training = (profile :: any).training
		local count = 0
		if type(training) == "table" then
			for _, entry in training do
				local valid = type(entry) == "table"
					and type(entry.startAt) == "number"
					and type(entry.endAt) == "number"
				if valid then
					entry.startAt = math.min(entry.startAt, now)
					entry.endAt = now
					count += 1
				end
			end
		end
		if count > 0 then
			table.insert(done, "обучение ×" .. count)
		end
	end
	return done
end

handlers.finish = function(ctx: Ctx): Reply
	local kind = ctx.args.kind
	if type(kind) ~= "string" or not FINISH_KINDS[kind] then
		return reply(false, "Не понял, какой таймер")
	end
	local done = finishTimers(ctx.player, kind)
	logAction(ctx.player, "finish_" .. kind, table.concat(done, ", "))
	if #done == 0 then
		return reply(true, "Нечего заканчивать")
	end
	return reply(true, "Готово (за 1–2 с): " .. table.concat(done, ", "))
end

-- ===== Время и контент =====

handlers.contentDay = function(ctx: Ctx): Reply
	if not ContentDrops.adminDayAllowed() then
		return reply(false, "Только на тестовом сервере (кнопка «Тестовый сервер») или в Studio")
	elseif not onlyOwnersHere() then
		return reply(false, "На сервере есть игроки — день контента менять нельзя")
	end
	if ctx.args.clear == true then
		ReplicatedStorage:SetAttribute("AdminContentDay", nil)
		logAction(ctx.player, "contentDay", "clear")
		return reply(true, "День контента — по календарю. Уже запущенные системы работают до перезахода")
	end
	local day = int(ctx.args.day, 0, Admin.maxContentDay)
	if not day then
		return reply(false, "День — от 0 до " .. Admin.maxContentDay)
	end
	ReplicatedStorage:SetAttribute("AdminContentDay", day)
	logAction(ctx.player, "contentDay", tostring(day))
	return reply(true, "День " .. day .. ": волны сразу, обновления по средам — в течение минуты")
end

handlers.testServer = function(ctx: Ctx): Reply
	if RunService:IsStudio() then
		return reply(false, "В Studio телепорт не работает — день контента меняется прямо здесь")
	end
	local ok, code = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not ok or type(code) ~= "string" then
		warn("[AdminService] ReserveServer failed:", code)
		return reply(false, "Не удалось создать сервер, попробуй ещё раз")
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	local okTeleport, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { ctx.player }, options)
	end)
	if not okTeleport then
		warn("[AdminService] TeleportAsync failed:", err)
		return reply(false, "Телепорт не удался, попробуй ещё раз")
	end
	logAction(ctx.player, "testServer", "")
	return reply(true, "Телепорт на закрытый сервер…")
end

local function clearAttributes(names: { string })
	for _, name in names do
		ReplicatedStorage:SetAttribute(name, nil)
	end
end

handlers.event = function(ctx: Ctx): Reply
	local id = ctx.args.id
	if id == "stop" then
		clearAttributes(EVENT_ATTRIBUTES)
		clearAttributes(GOLDEN_ATTRIBUTES)
		logAction(ctx.player, "event_stop", "")
		return reply(true, "События из панели остановлены — дальше по расписанию")
	end
	if type(id) ~= "string" or (id ~= "golden" and not DailyEvents.get(id)) then
		return reply(false, "Нет такого события")
	end
	local minutes = int(ctx.args.minutes, 1, Admin.maxEventMinutes)
	if not minutes then
		return reply(false, "Минуты — от 1 до " .. Admin.maxEventMinutes)
	end
	if not onlyOwnersHere() then
		local gate = confirmGate(
			ctx,
			"event",
			id .. "|" .. minutes,
			"Событие получат все игроки сервера (" .. #Players:GetPlayers() .. ")."
		)
		if gate then
			return gate
		end
	end
	local now = os.time()
	if id == "golden" then
		ReplicatedStorage:SetAttribute("AdminGoldenStartsAt", now)
		ReplicatedStorage:SetAttribute("AdminGoldenEndsAt", now + minutes * 60)
	else
		ReplicatedStorage:SetAttribute("AdminEventId", id)
		ReplicatedStorage:SetAttribute("AdminEventStartsAt", now)
		ReplicatedStorage:SetAttribute("AdminEventEndsAt", now + minutes * 60)
	end
	logAction(ctx.player, "event_" .. id, minutes .. " min")
	return reply(true, "Запущено на " .. minutes .. " мин (начнётся за секунду)")
end

-- ===== Модерация =====

local function profileView(target: Player): { { string } }
	local profile = DataService.get(target)
	local rows: { { string } } = {
		{ "Игрок", target.DisplayName .. " (@" .. target.Name .. ")" },
		{ "UserId", tostring(target.UserId) },
		{ "Аккаунт", target.AccountAge .. " дн." },
	}
	if not profile then
		table.insert(rows, { "Профиль", "ещё не загрузился" })
		return rows
	end
	local staff = (profile :: any).staff
	local employees = 0
	if type(staff) == "table" then
		for _ in staff do
			employees += 1
		end
	end
	local stage = Stages[profile.studioLevel]
	local research = profile.research
	for _, row in
		{
			{ "Деньги", "$" .. math.floor(profile.cash) },
			{ "Этап", if stage then stage.name else tostring(profile.studioLevel) },
			{ "Rebirth", tostring(profile.rebirths) },
			{ "Игр выпущено", tostring(profile.gamesReleased) },
			{ "Лучшая оценка", tostring(profile.bestScore) },
			{ "Хитов", tostring(profile.hitsReleased) },
			{ "Фанаты", tostring(profile.fans) },
			{ "ОИ", tostring(if type(research) == "table" then research.points else 0) },
			{ "Сотрудники", tostring(employees) },
			{ "Стройка", if profile.construction then "идёт" else "нет" },
		}
	do
		table.insert(rows, row)
	end
	return rows
end

handlers.view = function(ctx: Ctx): Reply
	local target = targetOf(ctx.args)
	if not target then
		return reply(false, "Игрока нет на сервере")
	end
	logAction(ctx.player, "view", who(target))
	return reply(true, "Профиль " .. target.Name, profileView(target))
end

handlers.teleport = function(ctx: Ctx): Reply
	local target = targetOf(ctx.args)
	if not target or target == ctx.player then
		return reply(false, "Выбери другого игрока на сервере")
	end
	local mine = ctx.player.Character
	local theirs = target.Character
	local root = theirs and theirs:FindFirstChild("HumanoidRootPart")
	if not mine or not root or not root:IsA("BasePart") then
		return reply(false, "Персонаж ещё не появился")
	end
	mine:PivotTo(root.CFrame * CFrame.new(0, 0, 4))
	logAction(ctx.player, "teleport", who(target))
	return reply(true, "Ты рядом с " .. target.Name)
end

-- Цель модерации: не владелец (себя — только для сброса профиля)
local function moderationTarget(ctx: Ctx, allowSelf: boolean): (Player?, string?)
	local target = targetOf(ctx.args)
	if not target then
		return nil, "Игрока нет на сервере"
	elseif target == ctx.player then
		return if allowSelf then target else nil, if allowSelf then nil else "Себя нельзя"
	elseif OwnerAccess.isOwner(target) then
		return nil, "Владельца нельзя"
	end
	return target, nil
end

-- Причина для игрока: TextSafe + фильтр Roblox; пусто или фильтр недоступен — без причины
local function reasonOf(ctx: Ctx): string
	if ctx.args.reason == nil or ctx.args.reason == "" then
		return ""
	end
	local text = cleanText(ctx.args.reason, Admin.reasonMaxLength)
	return if text then BroadcastText.filter(text, ctx.player.UserId) or "" else ""
end

handlers.kick = function(ctx: Ctx): Reply
	local target, err = moderationTarget(ctx, false)
	if not target then
		return reply(false, err or "Нельзя")
	end
	local gate = confirmGate(ctx, "kick", tostring(target.UserId), "Кикнуть " .. target.Name .. "?")
	if gate then
		return gate
	end
	local reason = reasonOf(ctx)
	logAction(ctx.player, "kick", who(target) .. (if reason ~= "" then " — " .. reason else ""))
	target:Kick("Ты отключён администратором." .. (if reason ~= "" then " Причина: " .. reason else ""))
	return reply(true, target.Name .. " кикнут")
end

local function banMessage(reason: string, untilAt: number): string
	local text = "Ты заблокирован в этой игре"
	if untilAt > 0 then
		local date = DateTime.fromUnixTimestamp(untilAt):FormatUniversalTime("YYYY-MM-DD HH:mm", "en-us")
		text ..= " до " .. date .. " UTC"
	end
	return text .. "." .. (if reason ~= "" then " Причина: " .. reason else "")
end

local function banKey(userId: number): string
	return Admin.banKeyPrefix .. userId
end

handlers.ban = function(ctx: Ctx): Reply
	local target, err = moderationTarget(ctx, false)
	if not target then
		return reply(false, err or "Нельзя")
	end
	local days = int(ctx.args.days, 0, Admin.maxBanDays)
	if not days then
		return reply(false, "Срок — от 0 (навсегда) до " .. Admin.maxBanDays .. " дн.")
	end
	local store = banStore
	if not store then
		return reply(false, "DataStore недоступен — бан не сохранится")
	end
	local label = if days == 0 then "навсегда" else days .. " дн."
	local question = "Забанить " .. target.Name .. " (" .. label .. ")?"
	local gate = confirmGate(ctx, "ban", target.UserId .. "|" .. days, question)
	if gate then
		return gate
	end
	local reason = reasonOf(ctx)
	local untilAt = if days == 0 then 0 else os.time() + days * 86400
	local record = { reason = reason, untilAt = untilAt, by = ctx.player.UserId, at = os.time() }
	local ok, saveErr = pcall(function()
		store:SetAsync(banKey(target.UserId), record, { target.UserId })
	end)
	if not ok then
		warn("[AdminService] ban save failed:", saveErr)
		return reply(false, "Не удалось сохранить бан, попробуй ещё раз")
	end
	local why = if reason ~= "" then " — " .. reason else ""
	logAction(ctx.player, "ban", who(target) .. " " .. label .. why)
	target:Kick(banMessage(reason, untilAt))
	return reply(true, target.Name .. " забанен (" .. label .. ")")
end

handlers.unban = function(ctx: Ctx): Reply
	local userId = int(ctx.args.userId, 1, 2 ^ 53)
	local store = banStore
	if not userId then
		return reply(false, "Нужен UserId — целое число")
	elseif not store then
		return reply(false, "DataStore недоступен")
	end
	local ok, err = pcall(function()
		store:RemoveAsync(banKey(userId))
	end)
	if not ok then
		warn("[AdminService] unban failed:", err)
		return reply(false, "Не удалось снять бан, попробуй ещё раз")
	end
	logAction(ctx.player, "unban", tostring(userId))
	return reply(true, "Бан снят: " .. userId)
end

handlers.reset = function(ctx: Ctx): Reply
	local target, err = moderationTarget(ctx, true)
	if not target then
		return reply(false, err or "Нельзя")
	end
	local gate = confirmGate(
		ctx,
		"reset",
		tostring(target.UserId),
		"Сбросить ВЕСЬ прогресс " .. target.Name .. " (деньги, студия, заряды за Robux)? Игрока отключит."
	)
	if gate then
		return gate
	end
	if not DataService.resetOnLeave(target) then
		return reply(false, "Профиль не загружен")
	end
	logAction(ctx.player, "reset", who(target))
	target:Kick("Прогресс сброшен администратором. Зайди снова — начнёшь с начала.")
	return reply(true, "Профиль " .. target.Name .. " сброшен")
end

-- ===== Сервер =====

handlers.announce = function(ctx: Ctx): Reply
	local text = cleanText(ctx.args.text, Admin.announceMaxLength)
	if not text then
		return reply(false, "Текст — от 1 до " .. Admin.announceMaxLength .. " символов")
	end
	local filtered = BroadcastText.filter(text, ctx.player.UserId)
	if not filtered or filtered == "" then
		return reply(false, "Фильтр Roblox недоступен, попробуй позже")
	end
	AdminRemotes.AdminAnnounce:FireAllClients({ text = filtered, seconds = Admin.announceSeconds })
	logAction(ctx.player, "announce", filtered)
	return reply(true, "Отправлено: " .. filtered)
end

handlers.players = function(_ctx: Ctx): Reply
	local list = {}
	for _, other in Players:GetPlayers() do
		table.insert(list, {
			userId = other.UserId,
			name = other.Name,
			displayName = other.DisplayName,
			owner = OwnerAccess.isOwner(other),
		})
	end
	table.sort(list, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return reply(true, "Игроков: " .. #list, list)
end

handlers.status = function(_ctx: Ctx): Reply
	return reply(true, "", {
		contentDay = ReplicatedStorage:GetAttribute("AdminContentDay"),
		-- По календарю, без сдвига из панели
		realDay = math.max((os.time() - ContentDrops.launchAt) // 86400, 0),
		contentAllowed = ContentDrops.adminDayAllowed(),
		onlyOwners = onlyOwnersHere(),
		studio = RunService:IsStudio(),
		eventId = ReplicatedStorage:GetAttribute("AdminEventId"),
		eventEndsAt = ReplicatedStorage:GetAttribute("AdminEventEndsAt"),
		goldenEndsAt = ReplicatedStorage:GetAttribute("AdminGoldenEndsAt"),
		now = os.time(),
	})
end

-- ===== Вход в remote =====

-- Частота: minInterval между запросами и не больше burst за burstWindow
local function throttled(player: Player): boolean
	local now = os.clock()
	if (lastAt[player] or 0) + Admin.minInterval > now then
		return true
	end
	local list = recent[player] or {}
	while #list > 0 and now - list[1] > Admin.burstWindow do
		table.remove(list, 1)
	end
	if #list >= Admin.burst then
		recent[player] = list
		return true
	end
	table.insert(list, now)
	recent[player] = list
	lastAt[player] = now
	return false
end

-- Аргументы — плоская таблица со строковыми ключами и простыми значениями
local function cleanArgs(raw: any): { [string]: any }?
	if raw == nil then
		return {}
	elseif type(raw) ~= "table" then
		return nil
	end
	local args: { [string]: any } = {}
	local count = 0
	for key, value in raw do
		count += 1
		local kind = type(value)
		if
			count > MAX_ARGS
			or type(key) ~= "string"
			or #key > 16
			or (kind ~= "string" and kind ~= "number" and kind ~= "boolean")
		then
			return nil
		end
		args[key] = value
	end
	return args
end

local function onRequest(player: Player, action: any, rawArgs: any): Reply?
	-- Владельца проверяем на каждый вызов: атрибуту клиента не верим
	if not OwnerAccess.isOwner(player) then
		return nil
	end
	if throttled(player) then
		return reply(false, "Слишком часто — подожди секунду")
	end
	local handler = if type(action) == "string" and #action <= 24 then handlers[action] else nil
	local args = cleanArgs(rawArgs)
	if not handler or not args then
		return reply(false, "Не понял запрос")
	end
	-- Токен подтверждения: только тот, что выдан этому игроку для этого же действия, и не просрочен
	local ctx: Ctx = { player = player, args = args, confirmed = nil }
	local token = args.confirm
	if token ~= nil then
		local entry = pending[player]
		pending[player] = nil
		if not entry or type(token) ~= "string" or entry.token ~= token or entry.action ~= action then
			return reply(false, "Подтверждение не подошло — начни заново")
		elseif os.clock() > entry.expires then
			return reply(false, "Подтверждение устарело — нажми ещё раз")
		end
		ctx.confirmed = entry.key
	end
	local ok, result = pcall(handler, ctx)
	if not ok then
		warn("[AdminService] " .. tostring(action) .. " failed:", result)
		return reply(false, "Ошибка на сервере (см. Output)")
	end
	if not QUIET[action] and not result.ok then
		warn("[AdminService] " .. who(player) .. " ✗ " .. tostring(action) .. ": " .. result.text)
	end
	return result
end

-- ===== Бан при входе =====

local function checkBan(player: Player)
	local store = banStore
	if not store or OwnerAccess.isOwner(player) then
		return
	end
	local ok, record = pcall(function()
		return store:GetAsync(banKey(player.UserId))
	end)
	if not ok then
		-- Сбой DataStore: пускаем (лучше пропустить бан, чем не пустить всех)
		warn("[AdminService] ban check failed:", record)
		return
	end
	if type(record) ~= "table" then
		return
	end
	local untilAt = tonumber(record.untilAt) or 0
	if untilAt ~= 0 and untilAt <= os.time() then
		return
	end
	local reason = if type(record.reason) == "string" and #record.reason <= 1000 then record.reason else ""
	if player.Parent then
		warn("[AdminService] banned player joined, kicked:", who(player))
		player:Kick(banMessage(reason, untilAt))
	end
end

local function onPlayerAdded(player: Player)
	task.spawn(checkBan, player)
	-- День контента из панели — только пока на сервере одни владельцы. Пришёл кто-то ещё (на закрытый
	-- сервер так не попасть, но на всякий случай) — сдвиг снимаем. Список владельцев группы мог ещё
	-- не загрузиться — даём ему пару секунд
	if ReplicatedStorage:GetAttribute("AdminContentDay") ~= nil then
		task.delay(3, function()
			if player.Parent and not OwnerAccess.isOwner(player) then
				ReplicatedStorage:SetAttribute("AdminContentDay", nil)
				warn("[AdminService] non-owner joined, AdminContentDay cleared:", who(player))
			end
		end)
	end
end

function AdminService.start()
	local okStore, result = pcall(function()
		return DataStoreService:GetDataStore(Admin.banStore)
	end)
	if okStore then
		banStore = result
	else
		warn("[AdminService] Ban DataStore unavailable:", result)
	end
	AdminRemotes.AdminRequest.OnServerInvoke = onRequest
	OwnerAccess.onOwner(function(player: Player)
		player:SetAttribute("AdminPanel", true)
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		lastAt[player] = nil
		recent[player] = nil
	end)
end

return AdminService
