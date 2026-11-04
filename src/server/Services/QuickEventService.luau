--!strict
-- Быстрые события разработки (Config/QuickEvents): «нажми в нужный момент».
-- Всё решает сервер: когда и какое событие, его параметры и время старта (GetServerTimeNow).
-- Клиент присылает только моменты нажатий; попадание считает сервер по тем же функциям
-- (QuickEvents.sweep / zoneGrade). Флагу «отлично» от клиента не верим — его и нет.
-- DevelopmentService вызывает: plan (старт игры), tick (тик разработки), finish (релиз —
-- сумма к оценке), cancel (Rebirth), noteActivity (игрок что-то нажал — не AFK).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuickEvents = require(ReplicatedStorage.Shared.Config.QuickEvents)
local QuickRemotes = require(ReplicatedStorage.Shared.QuickRemotes)
local DataService = require(script.Parent.DataService)

type Kind = QuickEvents.Kind
type Grade = QuickEvents.Grade
type Input = { action: string, at: number }

type Active = {
	id: number,
	projectId: number,
	kind: Kind,
	startedAt: number,
	leadIn: number,
	openAt: number, -- нажатия раньше не считаются
	expiresAt: number,
	zoneCenter: number,
	zoneWidth: number,
	phase: number,
	sequence: { string },
	inputs: { Input },
}

-- События одной игры: моменты (секунды разработки), сколько уже было, сумма эффектов
type Plan = { times: { number }, done: number, total: number, count: number }

local EXPIRY_CHECK = 0.2 -- секунд между проверками просроченных событий

local QuickEventService = {}
local plans: { [Player]: { [number]: Plan } } = {}
local active: { [Player]: Active } = {}
local lastKind: { [Player]: Kind } = {}
local ignoredStreak: { [Player]: number } = {}
local lastInput: { [Player]: number } = {}
local nextId = 0
local rng = Random.new()

local DIRECTIONS: { [string]: boolean } = {}
for _, direction in QuickEvents.directions do
	DIRECTIONS[direction] = true
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Время нажатия на сервере. Клиентскому времени верим, только если оно правдоподобно:
-- не позже получения и не раньше «получено − пинг − допуск». Иначе — оценка сервера
local function inputTime(player: Player, clientTime: any): number
	local now = serverNow()
	local okPing, rawPing = pcall(function()
		return player:GetNetworkPing()
	end)
	local ping = if okPing and type(rawPing) == "number" and rawPing == rawPing then rawPing else 0
	ping = math.clamp(ping, 0, QuickEvents.maxPing)
	local estimate = now - ping / 2
	if type(clientTime) ~= "number" or clientTime ~= clientTime then
		return estimate
	end
	-- Часы клиента синхронизированы с сервером не идеально: чуть «из будущего» допускаем
	if clientTime > now + QuickEvents.clockSkew or clientTime < now - ping - QuickEvents.latencyTolerance then
		return estimate
	end
	return math.min(clientTime, now)
end

local function logAnalytics(player: Player, kind: Kind, grade: Grade)
	local module = script.Parent:FindFirstChild("AnalyticsService")
	if not module or not module:IsA("ModuleScript") then
		return
	end
	local ok, err = pcall(function()
		local analytics = require(module) :: any
		if type(analytics.logQuickEvent) == "function" then
			analytics.logQuickEvent(player, kind, grade)
		end
	end)
	if not ok then
		warn("[QuickEventService] Analytics failed:", err)
	end
end

-- Достижения «идеальные быстрые события» (AchievementService, ленивый require)
local function noteAchievement(player: Player, grade: Grade)
	local module = script.Parent:FindFirstChild("AchievementService")
	if grade ~= "perfect" or not module or not module:IsA("ModuleScript") then
		return
	end
	local ok, err = pcall(function()
		(require(module) :: any).note(player, "qtePerfect", 1)
	end)
	if not ok then
		warn("[QuickEventService] Achievement failed:", err)
	end
end

local function clampedTotal(plan: Plan): number
	return math.clamp(plan.total, QuickEvents.totalMin, QuickEvents.totalMax)
end

-- ===== Оценка нажатий =====

local function presses(event: Active): { number }
	local list = {}
	for _, input in event.inputs do
		if input.action == "press" then
			table.insert(list, input.at)
		end
	end
	return list
end

local function gradeTiming(event: Active): Grade
	local at = presses(event)[1]
	if not at then
		return "ignored"
	end
	local value =
		QuickEvents.sweep(at - event.startedAt - event.leadIn, QuickEvents.timing.period, event.phase)
	return QuickEvents.zoneGrade(value, event.zoneCenter, event.zoneWidth)
end

-- Каждому удару — ближайшее неиспользованное нажатие; лишние нажатия снимают очки (против спама)
local function gradeRhythm(event: Active): Grade
	local taps = presses(event)
	if #taps == 0 then
		return "ignored"
	end
	local cfg = QuickEvents.rhythm
	local used: { [number]: boolean } = {}
	local points, matched = 0, 0
	for beat = 1, cfg.beats do
		local beatAt = event.startedAt + event.leadIn + (beat - 1) * cfg.interval
		local best: number? = nil
		local bestError = math.huge
		for index, at in taps do
			local err = math.abs(at - beatAt)
			if not used[index] and err < bestError then
				best, bestError = index, err
			end
		end
		if best and bestError <= cfg.goodWindow then
			used[best] = true
			matched += 1
			points += if bestError <= cfg.perfectWindow then 2 else 1
		end
	end
	points -= #taps - matched
	if points >= cfg.beats * 2 - 1 then
		return "perfect"
	elseif points >= cfg.beats then
		return "good"
	end
	return "miss"
end

local function gradeSequence(event: Active): Grade
	if #event.inputs == 0 then
		return "ignored"
	end
	local length = #event.sequence
	local correct = 0
	for index, expected in event.sequence do
		local input = event.inputs[index]
		if input and input.action == expected then
			correct += 1
		end
	end
	if correct == length then
		local last = event.inputs[length].at
		return if last - event.openAt <= QuickEvents.sequence.perfectSeconds then "perfect" else "good"
	elseif correct >= length - 1 then
		return "good"
	end
	return "miss"
end

local function gradeHold(event: Active): Grade
	local pressAt: number?, releaseAt: number? = nil, nil
	for _, input in event.inputs do
		if input.action == "press" and not pressAt then
			pressAt = input.at
		elseif input.action == "release" and pressAt and not releaseAt then
			releaseAt = input.at
		end
	end
	if not pressAt then
		return "ignored"
	end
	if not releaseAt then
		return "miss" -- держал до упора
	end
	local value = (releaseAt - pressAt) / QuickEvents.hold.fillSeconds
	if value > 1 then
		return "miss"
	end
	return QuickEvents.zoneGrade(value, event.zoneCenter, event.zoneWidth)
end

local function gradeOf(event: Active): Grade
	if event.kind == "timing" then
		return gradeTiming(event)
	elseif event.kind == "rhythm" then
		return gradeRhythm(event)
	elseif event.kind == "sequence" then
		return gradeSequence(event)
	end
	return gradeHold(event)
end

local function resolve(player: Player, event: Active)
	if active[player] ~= event then
		return
	end
	active[player] = nil
	local grade = gradeOf(event)
	local delta = QuickEvents.effect[grade]
	if grade == "ignored" then
		ignoredStreak[player] = (ignoredStreak[player] or 0) + 1
	else
		ignoredStreak[player] = 0
	end
	local plan = plans[player] and plans[player][event.projectId]
	local total = 0
	if plan then
		plan.total += delta
		plan.count += 1
		total = clampedTotal(plan)
	end
	QuickRemotes.QuickEventResult:FireClient(
		player,
		{ id = event.id, grade = grade, delta = delta, total = total }
	)
	logAnalytics(player, event.kind, grade)
	noteAchievement(player, grade)
end

-- ===== Старт =====

local function pickKind(player: Player): Kind
	local options = {}
	for _, kind in QuickEvents.kinds do
		if kind ~= lastKind[player] then
			table.insert(options, kind)
		end
	end
	local kind = options[rng:NextInteger(1, #options)]
	lastKind[player] = kind
	return kind
end

local function startEvent(player: Player, projectId: number)
	local profile = DataService.get(player)
	local level = if profile then profile.studioLevel else 1
	nextId += 1
	local kind = pickKind(player)
	local now = serverNow()
	local event: Active = {
		id = nextId,
		projectId = projectId,
		kind = kind,
		startedAt = now,
		leadIn = QuickEvents.leadIn,
		openAt = now + QuickEvents.leadIn,
		expiresAt = now + QuickEvents.leadIn + QuickEvents.timeoutSeconds,
		zoneCenter = 0.5,
		zoneWidth = QuickEvents.zoneWidth(level),
		phase = rng:NextNumber(),
		sequence = {},
		inputs = {},
	}
	if kind == "timing" then
		event.zoneCenter = rng:NextNumber(QuickEvents.timing.zoneMin, QuickEvents.timing.zoneMax)
	elseif kind == "rhythm" then
		local cfg = QuickEvents.rhythm
		-- Первый удар можно поймать чуть раньше; закрываемся сразу после последнего
		event.openAt = now + event.leadIn - cfg.goodWindow
		event.expiresAt = now + event.leadIn + (cfg.beats - 1) * cfg.interval + cfg.goodWindow
	elseif kind == "sequence" then
		-- «Приготовься» — это показ стрелок
		event.leadIn = QuickEvents.sequence.showSeconds
		event.openAt = now + event.leadIn
		event.expiresAt = now + event.leadIn + QuickEvents.timeoutSeconds
		for _ = 1, QuickEvents.sequence.length do
			table.insert(event.sequence, QuickEvents.directions[rng:NextInteger(1, #QuickEvents.directions)])
		end
	else
		event.zoneCenter = rng:NextNumber(QuickEvents.hold.zoneMin, QuickEvents.hold.zoneMax)
	end
	active[player] = event
	QuickRemotes.QuickEvent:FireClient(player, {
		id = event.id,
		kind = kind,
		projectId = projectId,
		startedAt = event.startedAt,
		leadIn = event.leadIn,
		expiresAt = event.expiresAt,
		zoneCenter = event.zoneCenter,
		zoneWidth = event.zoneWidth,
		perfectShare = QuickEvents.perfectShare,
		phase = event.phase,
		period = QuickEvents.timing.period,
		beats = QuickEvents.rhythm.beats,
		interval = QuickEvents.rhythm.interval,
		sequence = event.sequence,
		fillSeconds = QuickEvents.hold.fillSeconds,
	})
end

-- ===== Для DevelopmentService =====

-- Разложить события новой игры по её длительности. skip — авто-релиз (игрок может быть AFK)
function QuickEventService.plan(player: Player, projectId: number, duration: number, skip: boolean)
	local list = plans[player]
	if not list then
		list = {}
		plans[player] = list
	end
	local plan: Plan = { times = {}, done = 0, total = 0, count = 0 }
	list[projectId] = plan
	if skip then
		return
	end
	local count = QuickEvents.countFor(duration)
	local from, to = duration * QuickEvents.windowFrom, duration * QuickEvents.windowTo
	local slot = (to - from) / count
	for index = 1, count do
		table.insert(plan.times, from + slot * (index - 1) + rng:NextNumber(0, slot * 0.6))
	end
end

-- Тик разработки проекта. true — у игрока идёт быстрое событие (событие с выбором ждёт).
-- choiceActive — открыто событие с выбором: быстрое подождёт
function QuickEventService.tick(
	player: Player,
	projectId: number,
	elapsed: number,
	duration: number,
	choiceActive: boolean
): boolean
	if active[player] then
		return true
	end
	local plan = plans[player] and plans[player][projectId]
	if choiceActive or not plan or plan.done >= #plan.times or elapsed < plan.times[plan.done + 1] then
		return false
	end
	plan.done += 1
	-- До релиза не успеть или игрок AFK — пропускаем без штрафа
	if
		elapsed + QuickEvents.roomSeconds > duration
		or (ignoredStreak[player] or 0) >= QuickEvents.afkAfter
	then
		return false
	end
	startEvent(player, projectId)
	return true
end

-- Игра выходит: незаконченное событие этой игры закрываем (без нажатий — без штрафа).
-- Возвращает сумму эффектов (с ограничением) или nil, если событий не было
function QuickEventService.finish(player: Player, projectId: number): number?
	local event = active[player]
	if event and event.projectId == projectId then
		if #event.inputs > 0 then
			resolve(player, event)
		else
			active[player] = nil
			QuickRemotes.QuickEventResult:FireClient(player, { id = event.id, grade = "cancel" })
		end
	end
	local list = plans[player]
	local plan = list and list[projectId]
	if list then
		list[projectId] = nil
	end
	return if plan and plan.count > 0 then clampedTotal(plan) else nil
end

-- Rebirth и выход: всё сбросить
function QuickEventService.cancel(player: Player)
	local event = active[player]
	if event then
		QuickRemotes.QuickEventResult:FireClient(player, { id = event.id, grade = "cancel" })
	end
	plans[player] = nil
	active[player] = nil
end

-- Игрок что-то нажал сам: снова не AFK
function QuickEventService.noteActivity(player: Player)
	ignoredStreak[player] = 0
end

-- ===== Нажатия клиента =====

local function onInput(player: Player, id: any, action: any, clientTime: any)
	local event = active[player]
	if not event or type(id) ~= "number" or event.id ~= id or type(action) ~= "string" then
		return
	end
	-- Ограничение частоты: не чаще minInputGap и не больше maxInputs на событие
	local clock = os.clock()
	local last = lastInput[player]
	if (last and clock - last < QuickEvents.minInputGap) or #event.inputs >= QuickEvents.maxInputs then
		return
	end
	lastInput[player] = clock
	local at = inputTime(player, clientTime)
	-- Рано (ещё «приготовься» / показ стрелок) или уже поздно — не считаем
	if at < event.openAt or at > event.expiresAt then
		return
	end
	local kind = event.kind
	if kind == "timing" or kind == "rhythm" then
		if action ~= "press" then
			return
		end
	elseif kind == "sequence" then
		if not DIRECTIONS[action] then
			return
		end
	else
		local pressed = false
		for _, input in event.inputs do
			pressed = pressed or input.action == "press"
		end
		if (action == "press" and pressed) or (action == "release" and not pressed) then
			return
		end
		if action ~= "press" and action ~= "release" then
			return
		end
	end
	table.insert(event.inputs, { action = action, at = at })
	ignoredStreak[player] = 0

	-- Полоса — одно нажатие, зарядка — до отпускания
	local done = kind == "timing" or (kind == "hold" and action == "release")
	if kind == "rhythm" then
		done = #event.inputs >= QuickEvents.rhythm.beats
	elseif kind == "sequence" then
		done = #event.inputs >= #event.sequence
	elseif kind == "hold" and action == "press" then
		-- Зажал: держать дольше полной шкалы смысла нет — закроем как «Мимо»
		event.expiresAt =
			math.min(event.expiresAt, at + QuickEvents.hold.fillSeconds + QuickEvents.latencyTolerance)
	end
	if done then
		resolve(player, event)
	end
end

function QuickEventService.start()
	QuickRemotes.QuickEventInput.OnServerEvent:Connect(onInput)
	Players.PlayerRemoving:Connect(function(player)
		plans[player] = nil
		active[player] = nil
		lastKind[player] = nil
		ignoredStreak[player] = nil
		lastInput[player] = nil
	end)
	-- Просроченные события: закрываем с тем, что успел нажать (ничего — «пропущено»).
	-- Отдельный цикл: если игрок встал из-за компьютера, тики разработки стоят
	task.spawn(function()
		while true do
			task.wait(EXPIRY_CHECK)
			local now = serverNow()
			for player, event in active do
				if now > event.expiresAt + QuickEvents.latencyTolerance then
					local ok, err = pcall(resolve, player, event)
					if not ok then
						active[player] = nil
						warn("[QuickEventService] Resolve failed:", err)
					end
				end
			end
		end
	end)
end

return QuickEventService
