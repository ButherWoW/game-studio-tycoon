--!strict
-- Разработка и релиз игр. Всё считается на сервере.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Formulas = require(Shared.Formulas)
local Genres = require(Shared.Config.Genres)
local Topics = require(Shared.Config.Topics)
local Upgrades = require(Shared.Config.Upgrades)
local Employees = require(Shared.Config.Employees)
local DataService = require(script.Parent.DataService)
local DevEvents = require(Shared.Config.DevEvents)
local Economy = require(Shared.Config.Economy)

-- Фичи из других веток (тренды, магазин, исследования, задания) подключаются, если модуль есть.
-- Так порядок мёрджа PR не важен; без модуля множитель 1 и бонус 0.
local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end

-- Вызвать функцию модуля другой фичи; её ошибка не должна ломать релиз игры
local function hook(name: string, fnName: string, ...: any)
	local module = optional(name)
	local fn = module and module[fnName]
	if type(fn) == "function" then
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[DevelopmentService] Hook " .. name .. "." .. fnName .. " failed:", err)
		end
	end
end

local function shopModifiers(player: Player): any
	local ShopService = optional("ShopService")
	return if ShopService then ShopService.getModifiers(player) else nil
end

local function researchModifiers(player: Player): any
	local ResearchService = optional("ResearchService")
	return if ResearchService then ResearchService.getModifiers(player) else nil
end

-- Время разработки: исследование «Удобный движок» (devTime -0.1) и бусты скорости магазина.
-- Скорость сокращает время, а не добавляет очки, поэтому оценка от ускорения не падает:
-- очки в секунду умножаются на ту же скорость (см. цикл в start).
local function speedFactor(player: Player): number
	local shop = shopModifiers(player)
	return if shop and type(shop.devSpeed) == "number" and shop.devSpeed > 0 then shop.devSpeed else 1
end

-- Сумма бонусов купленных предметов студии (Config/Upgrades: speed, reviewBonus)
local function upgradeBonus(player: Player, field: "speed" | "reviewBonus"): number
	local profile = DataService.get(player)
	local total = 0
	if profile then
		for _, upgrade in Upgrades do
			local value = (upgrade :: any)[field]
			if profile.upgrades[upgrade.id] and type(value) == "number" then
				total += value
			end
		end
	end
	return total
end

local function durationFactor(player: Player): number
	local research = researchModifiers(player)
	-- Research.modifiers отдаёт множители: 1 = без изменений, 0.9 = на 10% быстрее
	local devTime = if research and type(research.devTime) == "number" then research.devTime else 1
	local items = math.min(upgradeBonus(player, "speed"), Economy.maxUpgradeSpeed)
	return math.max(devTime, 0.25) * (1 - items) / speedFactor(player)
end
local StaffService = require(script.Parent.StaffService)
local PlotService = require(script.Parent.PlotService)

type Focus = { gameplay: number, graphics: number, sound: number, story: number }

type Project = {
	name: string,
	genreId: string,
	topicId: string,
	focus: Focus,
	points: Formulas.Points,
	elapsed: number,
	duration: number,
	-- События разработки (Config/DevEvents): когда следующее, сколько было, текущее без ответа
	nextEventAt: number,
	eventsDone: number,
	tempo: number, -- скорость разработки на момент старта (см. pointsRate)
	event: { def: DevEvents.DevEvent, expiresAt: number }?,
}

local BASE_DURATION = 30 -- секунд на одну игру в начале
local MAX_NAME_LENGTH = 30
local DEFAULT_NAME = "Без названия" -- только если сам фильтр Roblox упал
local MIN_NAME_LENGTH = 2

local DevelopmentService = {}
local projects: { [Player]: Project } = {}
local rng = Random.new()

-- Заглушка, пока название проходит фильтр: слот занят, но очки не идут
local PENDING: Project = {
	name = "",
	genreId = "",
	topicId = "",
	focus = { gameplay = 0, graphics = 0, sound = 0, story = 0 },
	points = { gameplay = 0, graphics = 0, sound = 0, story = 0 },
	elapsed = 0,
	duration = math.huge,
	nextEventAt = math.huge,
	eventsDone = 0,
	tempo = 1,
}

-- Название увидят другие игроки (релиз, лидерборд), поэтому фильтр обязателен
local function filterName(player: Player, rawName: string): string
	if rawName:match("^%s*$") then
		return DEFAULT_NAME
	end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(rawName, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		warn("[DevelopmentService] Text filter failed:", result)
		return DEFAULT_NAME
	end
	return result
end

local FOCUS_KEYS = { "gameplay", "graphics", "sound", "story" }

-- Очки в секунду по направлениям с учётом сотрудников. Каждый стол даёт pointsPerSecond,
-- сотрудник за ним умножает это на свой multiplier, а в своё направление — ещё на
-- (1 + specBonus), если в фокусе оно >= specThreshold. Формулы оценки не меняются.
-- tempo — во сколько раз быстрее идёт разработка (фиксируется при старте проекта, чтобы
-- ускорение, купленное посреди игры, не давало лишних очков при прежней длительности)
function DevelopmentService.pointsRate(player: Player, focus: Focus, tempo: number?): Formulas.Points
	local rate = { gameplay = 0, graphics = 0, sound = 0, story = 0 }
	local profile = DataService.get(player)
	if not profile then
		return rate
	end
	local byDesk = StaffService.employeesByDesk(player)
	local any = false
	for _, upgrade in Upgrades do
		local deskPoints = upgrade.pointsPerSecond
		if profile.upgrades[upgrade.id] and deskPoints then
			any = true
			local employee = byDesk[upgrade.id]
			local base = deskPoints * (if employee then employee.multiplier else 1)
			for _, key in FOCUS_KEYS do
				local share = (focus :: any)[key] :: number
				local bonus = 1
				if employee and employee.specialization == key and share >= Employees.specThreshold then
					bonus += Employees.specBonus
				end
				(rate :: any)[key] += base * share * bonus
			end
		end
	end
	if not any then
		-- Даже без стола игрок что-то делает сам: 1 очко/с
		for _, key in FOCUS_KEYS do
			(rate :: any)[key] = (focus :: any)[key]
		end
	end
	-- Ускорение сокращает время, поэтому очки в секунду растут так же: за игру их столько же
	local speedUp = tempo or 1 / durationFactor(player)
	local research = researchModifiers(player)
	-- Множители из исследований: 1 = без изменений, 1.1 = +10%
	local graphics = if research and type(research.graphicsPoints) == "number"
		then research.graphicsPoints
		else 1
	local sound = if research and type(research.soundPoints) == "number" then research.soundPoints else 1
	rate.gameplay *= speedUp
	rate.graphics *= speedUp * graphics
	rate.sound *= speedUp * sound
	rate.story *= speedUp
	return rate
end

-- Клиенту нельзя доверять: проверяем каждое поле
local function sanitizeFocus(raw: any): Focus?
	if type(raw) ~= "table" then
		return nil
	end
	local f = {
		gameplay = tonumber(raw.gameplay) or 0,
		graphics = tonumber(raw.graphics) or 0,
		sound = tonumber(raw.sound) or 0,
		story = tonumber(raw.story) or 0,
	}
	local sum = 0
	for _, v in f do
		-- NaN и бесконечность ломают нормализацию (inf / inf = NaN)
		if v < 0 or v ~= v or v == math.huge then
			return nil
		end
		sum += v
	end
	if sum <= 0 then
		return nil
	end
	return {
		gameplay = f.gameplay / sum,
		graphics = f.graphics / sum,
		sound = f.sound / sum,
		story = f.story / sum,
	}
end

local function onStartDevelopment(player: Player, request: any)
	if projects[player] or type(request) ~= "table" then
		return
	end
	-- Игру делают за компьютером, а не на бегу
	if not PlotService.isAtPc(player) then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local genreId, topicId = request.genreId, request.topicId
	if type(genreId) ~= "string" or not Genres[genreId] or not profile.unlockedGenres[genreId] then
		return
	end
	if type(topicId) ~= "string" or not Topics[topicId] or not profile.unlockedTopics[topicId] then
		return
	end
	local focus = sanitizeFocus(request.focus)
	if not focus then
		return
	end
	-- Без названия игру не создать (клиент тоже не даёт нажать «Начать»)
	-- Длинную строку сразу отбрасываем: в 30 символах UTF-8 не больше 120 байт
	if type(request.name) ~= "string" or #request.name > MAX_NAME_LENGTH * 4 then
		return
	end
	local rawName = (request.name:gsub("^%s+", ""):gsub("%s+$", ""))
	local nameLength = utf8.len(rawName)
	if nameLength == nil or nameLength < MIN_NAME_LENGTH then
		return
	end
	if nameLength > MAX_NAME_LENGTH then
		rawName = rawName:sub(1, (utf8.offset(rawName, MAX_NAME_LENGTH + 1) or (#rawName + 1)) - 1)
	end

	-- Фильтр уступает поток: занимаем слот заранее, чтобы второй запрос не прошёл
	projects[player] = PENDING
	local name = filterName(player, rawName)
	if projects[player] ~= PENDING or not player.Parent then
		return
	end

	local factor = durationFactor(player)
	projects[player] = {
		name = name,
		genreId = genreId,
		topicId = topicId,
		focus = focus,
		points = { gameplay = 0, graphics = 0, sound = 0, story = 0 },
		elapsed = 0,
		duration = BASE_DURATION * factor,
		nextEventAt = DevEvents.firstAt,
		eventsDone = 0,
		tempo = 1 / factor,
	}
end

local function release(player: Player, project: Project)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local score = Formulas.review(
		project.genreId,
		project.topicId,
		project.points,
		rng,
		upgradeBonus(player, "reviewBonus")
	)
	local TrendService = optional("TrendService")
	if TrendService then
		score += TrendService.getBonus(project.genreId, project.topicId)
	end
	-- Продукт «Патч»: +1 к оценке, заряд тратится только если есть куда расти
	local ShopService = optional("ShopService")
	if ShopService and score < 10 and ShopService.consumeCharge(player, "patch") then
		score += 1
	end
	score = math.clamp(score, 1, 10)

	local adBonus = 0
	if profile.activeAd and profile.activeAd.expiresAt > os.time() then
		adBonus = profile.activeAd.bonus
	end
	local rebirthMultiplier = 1 + 0.5 * profile.rebirths
	local revenue = Formulas.revenue(score, profile.studioLevel, adBonus, rebirthMultiplier)
	local shop = shopModifiers(player)
	local research = researchModifiers(player)
	local cashMultiplier = if shop and type(shop.cashMultiplier) == "number" then shop.cashMultiplier else 1
	local researchMultiplier = if research and type(research.revenue) == "number" then research.revenue else 1
	revenue = math.floor(revenue * cashMultiplier * researchMultiplier)

	local isRecord = profile.gamesReleased > 0 and score > profile.bestScore
	profile.gamesReleased += 1
	profile.bestScore = math.max(profile.bestScore, score)
	DataService.addCash(player, revenue)

	hook("ResearchService", "onGameReleased", player, score)
	local p = project.points
	hook("ExpoService", "onGameReleased", player, {
		name = project.name,
		score = score,
		points = p.gameplay + p.graphics + p.sound + p.story,
	})
	hook("QuestService", "onGameReleased", player, {
		genreId = project.genreId,
		topicId = project.topicId,
		score = score,
		focus = project.focus,
	})

	Remotes.GameReleased:FireClient(player, {
		name = project.name,
		genreId = project.genreId,
		topicId = project.topicId,
		score = score,
		revenue = revenue,
		adBonus = adBonus,
		isRecord = isRecord,
	})
end

-- Применить выбор события: очки в направление (или по фокусу), время, риск
local function applyEffect(player: Player, project: Project, effect: DevEvents.Effect): boolean
	local ok = effect.chance == nil or rng:NextNumber() < effect.chance
	local work = if ok then effect.work or 0 else effect.failWork or 0
	if work ~= 0 then
		local rate = DevelopmentService.pointsRate(player, project.focus, project.tempo)
		local perSecond = rate.gameplay + rate.graphics + rate.sound + rate.story
		local amount = perSecond * work
		local points = project.points :: any
		if effect.focus and effect.focus ~= "all" and points[effect.focus] ~= nil then
			points[effect.focus] = math.max(points[effect.focus] + amount, 0)
		else
			for key, share in project.focus :: any do
				points[key] = math.max(points[key] + amount * share, 0)
			end
		end
	end
	if ok and effect.time then
		project.duration = math.max(project.duration + effect.time, project.elapsed + 1)
	end
	return ok
end

local function resolveEvent(player: Player, project: Project, choice: string)
	local active = project.event
	if not active then
		return
	end
	project.event = nil
	local effect = if choice == "a" then active.def.a else active.def.b
	local ok = applyEffect(player, project, effect)
	Remotes.DevEventResult:FireClient(player, { id = active.def.id, choice = choice, ok = ok })
end

local function maybeStartEvent(player: Player, project: Project)
	if project.event then
		-- Не ответил вовремя — спокойный вариант
		if project.elapsed >= project.event.expiresAt then
			resolveEvent(player, project, "b")
		end
		return
	end
	if project.eventsDone >= DevEvents.maxPerGame or project.elapsed < project.nextEventAt then
		return
	end
	-- Не начинаем событие перед самым релизом: на ответ должно хватить времени
	if project.elapsed + DevEvents.answerSeconds > project.duration then
		return
	end
	local def = DevEvents.list[rng:NextInteger(1, #DevEvents.list)]
	project.eventsDone += 1
	project.nextEventAt = project.elapsed + rng:NextNumber(DevEvents.intervalMin, DevEvents.intervalMax)
	project.event = { def = def, expiresAt = project.elapsed + DevEvents.answerSeconds }
	Remotes.DevEvent:FireClient(player, { id = def.id, answerSeconds = DevEvents.answerSeconds })
end

local function onEventChoice(player: Player, eventId: any, choice: any)
	local project = projects[player]
	if not project or project == PENDING or not project.event then
		return
	end
	if eventId ~= project.event.def.id or (choice ~= "a" and choice ~= "b") then
		return
	end
	resolveEvent(player, project, choice)
end

local TICK = 0.5

-- Один тик одного проекта. Отдельной функцией, чтобы ошибка у одного игрока
-- (например, в хуке другой фичи) не останавливала разработку у всех
local function tickProject(player: Player, project: Project)
	if project == PENDING then
		return
	end
	-- Встал из-за компьютера — разработка на паузе
	if not PlotService.isAtPc(player) then
		Remotes.DevelopmentProgress:FireClient(player, {
			progress = math.min(project.elapsed / project.duration, 1),
			points = project.points,
			paused = true,
		})
		return
	end
	local rate = DevelopmentService.pointsRate(player, project.focus, project.tempo)
	project.points.gameplay += rate.gameplay * TICK
	project.points.graphics += rate.graphics * TICK
	project.points.sound += rate.sound * TICK
	project.points.story += rate.story * TICK
	project.elapsed += TICK

	Remotes.DevelopmentProgress:FireClient(player, {
		progress = math.min(project.elapsed / project.duration, 1),
		points = project.points,
	})

	maybeStartEvent(player, project)
	if project.elapsed >= project.duration then
		-- Событие без ответа к релизу — спокойный вариант
		resolveEvent(player, project, "b")
		projects[player] = nil
		release(player, project)
	end
end

-- Отменить текущую разработку (Rebirth сбрасывает студию — недоделанная игра пропадает,
-- иначе она вышла бы уже с новым множителем Rebirth)
function DevelopmentService.cancel(player: Player)
	projects[player] = nil
end

function DevelopmentService.start()
	Remotes.DevEventChoice.OnServerEvent:Connect(onEventChoice)
	Remotes.StartDevelopment.OnServerEvent:Connect(onStartDevelopment)
	Players.PlayerRemoving:Connect(function(player)
		projects[player] = nil
	end)

	-- Один общий цикл вместо таймера на каждого игрока
	task.spawn(function()
		while true do
			task.wait(TICK)
			for player, project in projects do
				local ok, err = pcall(tickProject, player, project)
				if not ok then
					warn("[DevelopmentService] Tick failed for", player.Name, err)
					-- Сломанный проект убираем, чтобы ошибка не повторялась каждые полсекунды
					if projects[player] == project then
						projects[player] = nil
					end
				end
			end
		end
	end)
end

return DevelopmentService
