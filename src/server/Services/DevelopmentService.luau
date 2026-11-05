--!strict
-- Разработка и релиз игр. Всё считается на сервере.
-- У игрока список проектов: обычно 1 слот, 2 — с геймпассом «Второй слот» или исследованием
-- «Второй проект» (одна механика, см. slotCount). Здесь же «Мгновенно закончить», «Авто-релиз»,
-- VIP-бонус к оценке и примерная оценка «Тест-группы» (5.9, 3.8).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local PaidRemotes = require(Shared.PaidRemotes)
local Formulas = require(Shared.Formulas)
local TextSafe = require(Shared.TextSafe)
local WordFilter = require(Shared.WordFilter)
local Genres = require(Shared.Config.Genres)
local Topics = require(Shared.Config.Topics)
local Upgrades = require(Shared.Config.Upgrades)
local Rebirth = require(Shared.Config.Rebirth)
local RebirthPerks = require(Shared.Config.RebirthPerks)
local Employees = require(Shared.Config.Employees)
local GamePasses = require(Shared.Config.GamePasses)
local Research = require(Shared.Config.Research)
local DataService = require(script.Parent.DataService)
local DevEvents = require(Shared.Config.DevEvents)
local Economy = require(Shared.Config.Economy)
local HitCartridges = require(Shared.Config.HitCartridges)

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

-- Число из модуля другой фичи (платформы, стример); без модуля, при ошибке или мусоре — default
local function hookNumber(name: string, fnName: string, default: number, ...: any): number
	local module = optional(name)
	local fn = module and module[fnName]
	if type(fn) ~= "function" then
		return default
	end
	local ok, value = pcall(fn, ...)
	return if ok and type(value) == "number" and value == value and value >= 0 then value else default
end

local function shopModifiers(player: Player): any
	local ShopService = optional("ShopService")
	return if ShopService then ShopService.getModifiers(player) else nil
end

local function researchModifiers(player: Player): any
	local ResearchService = optional("ResearchService")
	return if ResearchService then ResearchService.getModifiers(player) else nil
end

-- Куплен ли геймпасс (через ShopService.ownsPass; без модуля — нет)
local function ownsPass(player: Player, passId: GamePasses.PassId): boolean
	local ShopService = optional("ShopService")
	return ShopService ~= nil and ShopService.ownsPass(player, passId) == true
end

-- Время разработки: исследование «Удобный движок» (devTime -0.1) и бусты скорости магазина.
-- Скорость сокращает время, а не добавляет очки, поэтому оценка от ускорения не падает:
-- очки в секунду умножаются на ту же скорость (см. цикл в start).
local function speedFactor(player: Player): number
	local shop = shopModifiers(player)
	return if shop and type(shop.devSpeed) == "number" and shop.devSpeed > 0 then shop.devSpeed else 1
end

-- События компании (CompanyEventService): вызвать функцию, без модуля или при ошибке — default
local function companyEvent(fnName: string, default: any, ...: any): any
	local service = optional("CompanyEventService")
	local fn = service and service[fnName]
	if type(fn) ~= "function" then
		return default
	end
	local ok, value = pcall(fn, ...)
	return if ok and value ~= nil then value else default
end

-- Предмет сломан событием компании (потоп): не даёт очков и бонусов, пока не починят
local function isBroken(player: Player, upgradeId: string): boolean
	return companyEvent("isBroken", false, player, upgradeId) == true
end

-- Сумма бонусов купленных предметов студии (Config/Upgrades: speed, reviewBonus)
local function upgradeBonus(player: Player, field: "speed" | "reviewBonus"): number
	local profile = DataService.get(player)
	local total = 0
	if profile then
		for _, upgrade in Upgrades do
			local value = (upgrade :: any)[field]
			if
				profile.upgrades[upgrade.id]
				and type(value) == "number"
				and not isBroken(player, upgrade.id)
			then
				total += value
			end
		end
	end
	return total
end

-- Прибавка к оценке до округления: предметы студии + VIP-офис
-- Перки сотрудников (StaffService.perkTotals): devTime, bugAlwaysWins, streamerMultiplier, trendBonus
local function perks(player: Player): any
	-- StaffService подключается ниже по файлу: берём модуль по требованию (require кэшируется)
	local ok, totals = pcall(function()
		return (require(script.Parent.StaffService) :: any).perkTotals(player)
	end)
	return if ok and type(totals) == "table" then totals else {}
end

-- Настроение команды (MoodService): ±0.2 к оценке и множитель скорости; без сотрудников 0 и 1
local function moodReviewBonus(player: Player): number
	local MoodService = optional("MoodService")
	local ok, value = pcall(function()
		return if MoodService then MoodService.reviewBonus(player) else 0
	end)
	return if ok and type(value) == "number" then value else 0
end

local function moodSpeed(player: Player): number
	local MoodService = optional("MoodService")
	local ok, value = pcall(function()
		return if MoodService then MoodService.speedMultiplier(player) else 1
	end)
	return if ok and type(value) == "number" and value > 0 then value else 1
end

-- Бонус надетого маскота (MascotService): devSpeed / revenue / review, без модуля 0
local function mascotBonus(player: Player, kind: string): number
	local MascotService = optional("MascotService")
	local ok, value = pcall(function()
		return if MascotService then MascotService.bonus(player, kind) else 0
	end)
	return if ok and type(value) == "number" and value == value then math.clamp(value, 0, 1) else 0
end

local function reviewBonus(player: Player): number
	local vip = if ownsPass(player, "vipOffice") then GamePasses.effects.vipReviewBonus else 0
	-- «Мастер Пиксель» +1 и перк «Перфекционист» +0.2
	local ok, staff = pcall(function()
		return (require(script.Parent.StaffService) :: any).reviewBonus(player)
	end)
	local staffBonus = if ok and type(staff) == "number" then staff else 0
	return upgradeBonus(player, "reviewBonus")
		+ vip
		+ staffBonus
		+ moodReviewBonus(player)
		+ mascotBonus(player, "review")
end

-- Всё, что сдвигает оценку до округления: бонусы студии минус ожидания критиков этапа
-- и штраф за повтор сочетания среди последних игр (отчёт #2: в офисе всегда 9–10)
-- Штраф за повтор сочетания с учётом сиквела (его же показывает окно релиза)
local function repeatPenaltyFor(
	profile: DataService.Profile,
	genreId: string,
	topicId: string,
	sequel: boolean?
): number
	-- Сиквел геймпасса «Авто-релиз» повторяет сочетание по задумке: штраф за повтор слабее
	local repeatFactor = if sequel then Economy.sequelRepeatFactor else 1
	return Formulas.repeatPenalty(profile.recentCombos, genreId, topicId) * repeatFactor
end

local function scoreBonus(
	player: Player,
	profile: DataService.Profile,
	genreId: string,
	topicId: string,
	sequel: boolean?
): number
	-- + событие компании для следующей игры (награда, ревью-бомбинг, счастливый баг)
	local companyBonus = tonumber(companyEvent("scoreBonus", 0, player)) or 0
	return reviewBonus(player)
		+ companyBonus
		- Formulas.criticExpectation(profile.studioLevel)
		- repeatPenaltyFor(profile, genreId, topicId, sequel)
end

-- Множитель времени без доната: предметы, исследования, перки, настроение (1 = базовое время)
local function durationFactor(player: Player): number
	local research = researchModifiers(player)
	-- Research.modifiers отдаёт множители: 1 = без изменений, 0.9 = на 10% быстрее
	local devTime = if research and type(research.devTime) == "number" then research.devTime else 1
	local items = math.min(upgradeBonus(player, "speed"), Economy.maxUpgradeSpeed)
	-- Перк «Кранчер» и подобные: множитель времени (0.9 = −10%)
	local perkTime = tonumber(perks(player).devTime) or 1
	-- Звёзды студии (Config/RebirthPerks, ветка «Скорость»): под тем же полом 0.25
	local starTime = 1 - RebirthPerks.forProfile(DataService.get(player)).devTime
	return math.max(devTime * perkTime * starTime, 0.25) * (1 - items) / moodSpeed(player)
end
local StaffService = require(script.Parent.StaffService)
local PlotService = require(script.Parent.PlotService)
local QuickEventService = require(script.Parent.QuickEventService)
local StartPark = require(Shared.Config.StartPark)

-- «Инди в парке»: пока нет гаража, игры делаются на общем ноутбуке — фиксированные время
-- и очки в секунду (бонусы студии, магазина и исследований не действуют), доход ниже
local function onLaptop(player: Player): boolean
	return not PlotService.ownsGarage(player)
end

-- Длительность новой игры (с) и темп (во сколько раз быстрее базовой скорости идут очки).
-- Очки за игру не зависят от длительности: темп = секунды очков / длительность (Config/Economy)
local function devTiming(player: Player): (number, number)
	-- Ноутбук: время фиксировано, бонусы студии и магазина не действуют
	local duration: number, pointsSeconds: number = StartPark.laptopDuration, StartPark.laptopPointsSeconds
	if not onLaptop(player) then
		local floor = Economy.devFloorSeconds
		-- Бонусы сокращают только часть сверх пола; донат (быстрая разработка, кофе) — после него
		duration = (floor + (Economy.devSeconds - floor) * durationFactor(player)) / speedFactor(player)
		-- Маскот «скорость»: +N% к скорости (очки в секунду растут вместе с ней)
		duration /= 1 + mascotBonus(player, "devSpeed")
		pointsSeconds = Economy.devPointsSeconds
	end
	-- Первые игры игрока — короче: быстрый онбординг
	local profile = DataService.get(player)
	if profile and profile.gamesReleased < Economy.firstGames then
		duration = math.min(duration, Economy.firstGameSeconds)
	end
	return duration, pointsSeconds / duration
end

type Focus = { gameplay: number, graphics: number, sound: number, story: number }

type Project = {
	id: number,
	-- true, пока название проходит фильтр: слот занят, но очки не идут (защита от гонки)
	pending: boolean,
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
	sequel: boolean?, -- сиквел от «Авто-релиза» (слабее штраф за повтор)
	paid: boolean?, -- доход релиза уже начислен (повторно не выпускать и заряд не возвращать)
	releaseFailures: number?, -- сколько раз релиз упал с ошибкой
	laptop: boolean?, -- начата на ноутбуке в парке: доход × StartPark.laptopRevenueMultiplier
	-- Сумма быстрых событий (QuickEventService.finish) к оценке; nil — событий не было
	quickBonus: number?,
	-- Продолжение франшизы (FranchiseService): id и «та же тема» (штраф за повтор как у сиквела)
	franchiseId: number?,
	franchiseCombo: boolean?,
	platform: string?, -- платформа (ConsoleService.platformFor): "pc" | "phone" | "console"
}

local MAX_RELEASE_FAILURES = 3 -- после стольких ошибок релиза игра снимается, чтобы не падать каждый тик
local LEADERSTATS_REVEAL_SECONDS = 4.5 -- сколько клиент раскрывает оценки в окне релиза
local MAX_NAME_LENGTH = 30
local DEFAULT_NAME = "Без названия" -- только если сам фильтр Roblox упал
local MIN_NAME_LENGTH = 2
local ACTION_COOLDOWN = 0.5 -- «Мгновенно закончить»: секунд между запросами
local PREVIEW_COOLDOWN = 0.5 -- примерная оценка: секунд между запросами
local STATE_COOLDOWN = 1 -- DevStateRequest

local DevelopmentService = {}
local projects: { [Player]: { Project } } = {}
local lastAction: { [Player]: number } = {}
local lastPreview: { [Player]: number } = {}
local lastStateRequest: { [Player]: number } = {}
local nextProjectId = 0
local rng = Random.new()

-- Для примерной оценки: без случайного разброса
local NO_NOISE = {
	NextNumber = function(_self: any, _min: number, _max: number): number
		return 0
	end,
} :: any

local function cooldownPassed(map: { [Player]: number }, player: Player, seconds: number): boolean
	local now = os.clock()
	local last = map[player]
	if last and now - last < seconds then
		return false
	end
	map[player] = now
	return true
end

local function listOf(player: Player): { Project }
	local list = projects[player]
	if not list then
		list = {}
		projects[player] = list
	end
	return list
end

local function removeProject(player: Player, project: Project): boolean
	local list = projects[player]
	local index = list and table.find(list, project)
	if not list or not index then
		return false
	end
	table.remove(list, index)
	return true
end

local function hasProject(player: Player, project: Project): boolean
	local list = projects[player]
	return list ~= nil and table.find(list, project) ~= nil
end

-- Сколько игр игрок может делать одновременно. Ноутбук в парке один — там всегда 1
function DevelopmentService.slotCount(player: Player): number
	if onLaptop(player) then
		return 1
	end
	local research = researchModifiers(player)
	local fromResearch = if research and type(research.projectSlots) == "number"
		then math.floor(research.projectSlots)
		else 1
	local fromPass = if ownsPass(player, "extraSlot") then GamePasses.effects.extraSlotProjects else 1
	return math.max(1, fromResearch, fromPass)
end

-- Снимок для HUD: слоты, проекты, заряды, авто-релиз, роялти
function DevelopmentService.pushState(player: Player)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	local list = projects[player] or {}
	local active = {}
	for _, project in list do
		if not project.pending then
			table.insert(active, { id = project.id, name = project.name, laptop = project.laptop == true })
		end
	end
	local research = researchModifiers(player)
	local Perks = optional("PerksService")
	PaidRemotes.DevState:FireClient(player, {
		slots = DevelopmentService.slotCount(player),
		busy = #list,
		projects = active,
		instantFinish = profile.boosts.instantFinish,
		autoReleaseOwned = ownsPass(player, "autoRelease"),
		autoReleaseOn = Perks ~= nil and Perks.isAutoReleaseOn(player) == true,
		reviewPreview = research ~= nil and research.reviewPreview == true,
		royaltyPerMinute = if Perks then Perks.royaltyPerMinute(player) else 0,
	})
end

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
	if onLaptop(player) then
		-- Темп ноутбука: laptopPointsSeconds / laptopDuration (очки за игру не зависят от длительности)
		local laptopTempo = tempo or StartPark.laptopPointsSeconds / StartPark.laptopDuration
		for _, key in FOCUS_KEYS do
			(rate :: any)[key] = (focus :: any)[key] * StartPark.laptopPointsPerSecond * laptopTempo
		end
		return rate
	end
	local byDesk = StaffService.employeesByDesk(player)
	-- Стол стримера (StreamerService) очков не даёт
	local Streamer = optional("StreamerService")
	local okStream, streamDesk = pcall(function()
		return if Streamer then Streamer.deskOf(player) else nil
	end)
	local skipDesk = if okStream and type(streamDesk) == "string" then streamDesk else nil
	local any = false
	for _, upgrade in Upgrades do
		local deskPoints = upgrade.pointsPerSecond
		if
			profile.upgrades[upgrade.id]
			and deskPoints
			and upgrade.id ~= skipDesk
			and not isBroken(player, upgrade.id)
		then
			any = true
			local employee = byDesk[upgrade.id]
			local base = deskPoints * (if employee then employee.multiplier else 1)
			-- Навыки сотрудника за этим столом и перк «Наставник» соседей
			local okMult, deskMult = pcall(StaffService.deskMultipliers, player, upgrade.id)
			local mult: any = if okMult and type(deskMult) == "table" then deskMult else {}
			for _, key in FOCUS_KEYS do
				local share = (focus :: any)[key] :: number
				local bonus = 1
				if employee and employee.specialization == key and share >= Employees.specThreshold then
					bonus += Employees.specBonus
				end
				(rate :: any)[key] += base * share * bonus * (tonumber(mult[key]) or 1)
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
	local speedUp = tempo
	if not speedUp then
		local _, current = devTiming(player)
		speedUp = current
	end
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

-- Жанр и тема существуют и открыты у игрока
-- Сезонную тему можно брать только во время её праздника
local function seasonalAllowed(topicId: string): boolean
	local seasonal = (Topics[topicId] :: any).seasonal
	if not seasonal then
		return true
	end
	local HolidayService = optional("HolidayService")
	local ok, current = pcall(function()
		return HolidayService and HolidayService.current()
	end)
	return ok and current == seasonal
end

local function comboAllowed(profile: DataService.Profile, genreId: any, topicId: any): boolean
	return type(genreId) == "string"
		and Genres[genreId] ~= nil
		and profile.unlockedGenres[genreId] == true
		and type(topicId) == "string"
		and Topics[topicId] ~= nil
		and profile.unlockedTopics[topicId] == true
		and seasonalAllowed(topicId)
end

-- Франшиза продолжения (FranchiseService.validate): id или nil (обычная игра) и «та же тема»
local function franchiseFor(
	player: Player,
	franchiseId: any,
	genreId: string,
	topicId: string
): (number?, boolean)
	local FranchiseService = optional("FranchiseService")
	if franchiseId == nil or not FranchiseService then
		return nil, false
	end
	local ok, id, sameTopic = pcall(FranchiseService.validate, player, franchiseId, genreId, topicId)
	if not ok or type(id) ~= "number" then
		return nil, false
	end
	return id, sameTopic == true
end

-- Множитель дохода от франшизы (FranchiseService) и хита конкурента (RivalService); 1 — без них
local function depthMultiplier(player: Player, project: Project, score: number): (number, any)
	local multiplier, details = 1, nil
	local FranchiseService = optional("FranchiseService")
	if FranchiseService and project.franchiseId then
		local ok, value, info = pcall(FranchiseService.revenueMultiplier, player, project.franchiseId, score)
		if ok and type(value) == "number" and value > 0 then
			multiplier, details = value, info
		end
	end
	local RivalService = optional("RivalService")
	if RivalService then
		local ok, value = pcall(RivalService.genreMultiplier, project.genreId)
		if ok and type(value) == "number" and value > 0 then
			multiplier *= value
		end
	end
	return multiplier, details
end

-- Начать игру: общие проверки для «Создать игру» и «Авто-релиза».
-- rawName уже очищен (TextSafe) и обрезан; здесь он проходит фильтр Roblox
local function beginProject(
	player: Player,
	genreId: string,
	topicId: string,
	focus: Focus,
	rawName: string,
	sequel: boolean?,
	franchiseId: any?,
	platform: any?
)
	-- Игру делают за компьютером, а не на бегу
	if not PlotService.isAtPc(player) then
		return
	end
	local profile = DataService.get(player)
	if not profile or not comboAllowed(profile, genreId, topicId) then
		return
	end
	local list = listOf(player)
	if #list >= DevelopmentService.slotCount(player) then
		return
	end

	-- Фильтр уступает поток: занимаем слот заранее, чтобы второй запрос не прошёл
	nextProjectId += 1
	local project: Project = {
		id = nextProjectId,
		pending = true,
		name = "",
		genreId = genreId,
		topicId = topicId,
		focus = focus,
		points = { gameplay = 0, graphics = 0, sound = 0, story = 0 },
		elapsed = 0,
		duration = math.huge,
		nextEventAt = math.huge,
		eventsDone = 0,
		tempo = 1,
		sequel = sequel == true,
	}
	project.franchiseId, project.franchiseCombo = franchiseFor(player, franchiseId, genreId, topicId)
	local Console = optional("ConsoleService")
	local okPlatform, platformId = pcall(function()
		return if Console then Console.platformFor(player, platform) else "pc"
	end)
	project.platform = if okPlatform and type(platformId) == "string" then platformId else "pc"
	table.insert(list, project)
	DevelopmentService.pushState(player)

	local name = filterName(player, rawName)
	-- Пока ждали фильтр, слот могли снять (Rebirth, выход)
	if not hasProject(player, project) or not player.Parent then
		return
	end
	local duration, tempo = devTiming(player)
	project.name = name
	project.duration = duration
	project.nextEventAt = DevEvents.firstAt
	project.tempo = tempo
	project.laptop = onLaptop(player)
	project.pending = false
	-- Быстрые события (Config/QuickEvents); у игр «Авто-релиза» их нет — игрок может быть AFK
	QuickEventService.plan(player, project.id, project.duration, sequel == true)
	DevelopmentService.pushState(player)
end

local function onStartDevelopment(player: Player, request: any)
	if type(request) ~= "table" then
		return
	end
	local profile = DataService.get(player)
	if not profile or not comboAllowed(profile, request.genreId, request.topicId) then
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
	-- Невидимые символы и «Zalgo» вырезаем: название игры видят все (выставка, хиты)
	local rawName = TextSafe.clean(request.name)
	local nameLength = rawName and utf8.len(rawName)
	if not rawName or not nameLength or TextSafe.visibleLength(rawName) < MIN_NAME_LENGTH then
		return
	end
	-- Свой фильтр мата поверх фильтра Roblox (тот слабо ловит русский мат и молчит в Studio)
	if not WordFilter.isClean(rawName) then
		return
	end
	if nameLength > MAX_NAME_LENGTH then
		rawName = rawName:sub(1, (utf8.offset(rawName, MAX_NAME_LENGTH + 1) or (#rawName + 1)) - 1)
	end
	QuickEventService.noteActivity(player)
	beginProject(
		player,
		request.genreId,
		request.topicId,
		focus,
		rawName,
		nil,
		request.franchiseId,
		request.platform
	)
end

local function release(player: Player, project: Project)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	-- До rememberCombo: сколько сняли за повтор именно этой игры (критик в окне релиза)
	local sequelLike = project.sequel or project.franchiseCombo
	local repeatPenalty = repeatPenaltyFor(profile, project.genreId, project.topicId, sequelLike)
	local score = Formulas.review(
		project.genreId,
		project.topicId,
		project.points,
		rng,
		-- + быстрые события (QuickEventService): до округления, как бонусы студии
		scoreBonus(player, profile, project.genreId, project.topicId, sequelLike)
			+ (project.quickBonus or 0)
			-- + платформа (своя консоль: чаще хиты)
			+ hookNumber("ConsoleService", "scoreBonus", 0, project.platform)
	)
	local TrendService = optional("TrendService")
	if TrendService then
		local okTrend, trendValue = pcall(TrendService.getBonus, project.genreId, project.topicId)
		local trend = if okTrend and type(trendValue) == "number" then trendValue else 0
		score += trend
		-- Перк «Тренд-хантер»: ещё бонус, если игра в тренде
		if trend > 0 then
			score += tonumber(perks(player).trendBonus) or 0
		end
		score = math.floor(score + 0.5)
	end
	-- Праздник (Хэллоуин: хоррор/призраки/тыквы; Новый год) — бонус к оценке
	local HolidayService = optional("HolidayService")
	if HolidayService then
		local ok, bonus = pcall(HolidayService.reviewBonus, project.genreId, project.topicId)
		if ok and type(bonus) == "number" then
			score += bonus
		end
	end
	-- «Критики в городе» (DailyEventService): жанр дня +1
	local criticsBonus = hookNumber("DailyEventService", "reviewBonus", 0, project.genreId)
	score += criticsBonus
	-- Продукт «Патч»: +1 к оценке, заряд тратится только если есть куда расти
	local ShopService = optional("ShopService")
	if ShopService and score < 10 then
		local okPatch, used = pcall(ShopService.consumeCharge, player, "patch")
		if okPatch and used then
			score += 1
		end
	end
	score = math.clamp(score, 1, 10)

	local adBonus = 0
	if profile.activeAd and profile.activeAd.expiresAt > os.time() then
		adBonus = profile.activeAd.bonus
	end
	local rebirthMultiplier = Rebirth.multiplier(profile.rebirths)
	local revenue = Formulas.revenue(score, profile.studioLevel, adBonus, rebirthMultiplier)
	local shop = shopModifiers(player)
	local research = researchModifiers(player)
	local cashMultiplier = if shop and type(shop.cashMultiplier) == "number" then shop.cashMultiplier else 1
	local researchMultiplier = if research and type(research.revenue) == "number" then research.revenue else 1
	local laptopMultiplier = if project.laptop then StartPark.laptopRevenueMultiplier else 1
	-- Мощность студии (сумма очков/с купленной техники): лучше студия — больше продаж.
	-- Раньше доход зависел только от оценки, и мощный ПК или офис деньги не меняли (отчёт #42)
	local power = 0
	for _, upgrade in Upgrades do
		if profile.upgrades[upgrade.id] and upgrade.pointsPerSecond then
			power += upgrade.pointsPerSecond
		end
	end
	local powerMultiplier = 1 + math.min(power * Economy.revenuePerPower, Economy.maxPowerBonus)
	-- Постоянные бонусы из наград заданий (Config/Quests: incomeBonus), не больше +50%
	local rewards = (profile :: any).rewards
	local rewardBonus = if type(rewards) == "table" then tonumber(rewards.incomeBonus) or 0 else 0
	local rewardMultiplier = 1 + math.clamp(rewardBonus, 0, 0.5)
	local holidayMultiplier = 1
	if HolidayService then
		local ok, value = pcall(HolidayService.revenueMultiplier, project.genreId)
		if ok and type(value) == "number" and value > 0 then
			holidayMultiplier = value
		end
	end
	-- «Золотой час» (DailyEventService): ×2, но вместе с праздником не выше общего лимита
	holidayMultiplier *= hookNumber("DailyEventService", "revenueMultiplier", 1, holidayMultiplier)
	-- События компании: стример, утечка кода, иск, катастрофы (1 — ничего не действует)
	local companyMultiplier = tonumber(companyEvent("revenueMultiplier", 1, player)) or 1
	-- Франшиза (хайп/усталость) и хит конкурента в жанре
	local depth, franchiseDetails = depthMultiplier(player, project, score)
	revenue = math.floor(
		revenue
			* depth
			* cashMultiplier
			* researchMultiplier
			* laptopMultiplier
			* powerMultiplier
			* holidayMultiplier
			* rewardMultiplier
			* companyMultiplier
	)
	-- Маскот «доход»: +N% к доходу релиза
	revenue = math.floor(revenue * (1 + mascotBonus(player, "revenue")))
	-- Платформа (жанр × доля рынка своей консоли) и хайп стримера (тратится этим релизом)
	local platformMultiplier =
		hookNumber("ConsoleService", "revenueMultiplier", 1, player, project.platform, project.genreId)
	local hypeMultiplier = hookNumber("StreamerService", "consumeHype", 1, player)
	-- Налоговая проверка (TaxService, ×0.8) и бонус компании на бирже (StockService, +10%)
	local taxMultiplier = hookNumber("TaxService", "revenueMultiplier", 1, player)
	local stockMultiplier = hookNumber("StockService", "revenueMultiplier", 1, player)
	-- Roblox Premium: +10% (PremiumService, Config/Premium)
	local premiumMultiplier = hookNumber("PremiumService", "revenueMultiplier", 1, player)
	revenue = math.floor(
		revenue * platformMultiplier * hypeMultiplier * taxMultiplier * stockMultiplier * premiumMultiplier
	)
	-- Совместная разработка (CoopService): доля гостя уходит ему, дальше считаем долю хозяина
	local coopPartner: Player? = nil
	local CoopService = optional("CoopService")
	if CoopService then
		local okCoop, hostRevenue, partner = pcall(CoopService.settle, player, project.id, revenue)
		if okCoop and type(hostRevenue) == "number" and hostRevenue >= 0 and hostRevenue <= revenue then
			revenue = math.floor(hostRevenue)
			coopPartner = if typeof(partner) == "Instance" and partner:IsA("Player") then partner else nil
		end
	end

	local isRecord = profile.gamesReleased > 0 and score > profile.bestScore
	profile.gamesReleased += 1
	profile.bestScore = math.max(profile.bestScore, score)
	profile.runBestScore = math.max(profile.runBestScore, score)
	Formulas.rememberCombo(profile.recentCombos, project.genreId, project.topicId)
	-- Счётчики для условий открытия жанров/тем (shared/UnlockRules)
	profile.genreGames[project.genreId] = (profile.genreGames[project.genreId] or 0) + 1
	if score >= HitCartridges.minScore then
		profile.hitsReleased += 1
	end
	-- Сначала прячем доход в таблице лидеров, потом начисляем: addCash сразу обновляет leaderstats
	DataService.holdLeaderstats(player, revenue, LEADERSTATS_REVEAL_SECONDS)
	DataService.addCash(player, revenue)
	project.paid = true

	hook("ResearchService", "onGameReleased", player, score)
	-- Поправки «следующей игры» событий компании израсходованы
	hook("CompanyEventService", "onGameReleased", player)
	hook("PerksService", "onGameReleased", player, revenue)
	-- Налоговая база периода и оценка для биржи (средняя последних игр)
	hook("TaxService", "onGameReleased", player, revenue)
	hook("StockService", "onGameReleased", player, score)
	-- Кредит: часть дохода игры уходит в погашение (Config/Loans.repayShare); сколько — для окна релиза
	local debtBefore = tonumber(player:GetAttribute("LoanDebt")) or 0
	hook("LoanService", "onGameReleased", player, revenue)
	local loanRepaid = math.max(debtBefore - (tonumber(player:GetAttribute("LoanDebt")) or 0), 0)
	local p = project.points
	hook("ExpoService", "onGameReleased", player, {
		name = project.name,
		score = score,
		points = p.gameplay + p.graphics + p.sound + p.story,
	})
	hook("HitService", "onGameReleased", player, {
		name = project.name,
		genreId = project.genreId,
		topicId = project.topicId,
		score = score,
	})
	-- «Игра недели» между серверами и рекламные щиты (последняя игра); name уже отфильтрован
	local releaseInfo = {
		name = project.name,
		genreId = project.genreId,
		score = score,
		revenue = revenue,
	}
	hook("GotwService", "onGameReleased", player, releaseInfo)
	hook("BillboardService", "onGameReleased", player, releaseInfo)
	-- Лучший хит недели для рейтинга (TourService)
	hook("TourService", "onGameReleased", player, {
		score = score,
		points = p.gameplay + p.graphics + p.sound + p.story,
	})
	hook("QuestService", "onGameReleased", player, {
		genreId = project.genreId,
		topicId = project.topicId,
		score = score,
		focus = project.focus,
	})
	hook("AchievementService", "onGameReleased", player, {
		genreId = project.genreId,
		topicId = project.topicId,
		score = score,
		revenue = revenue,
		laptop = project.laptop == true,
	})
	-- Сезонный пропуск (опыт за игру) и гейм-джем (игра по теме недели)
	hook("SeasonService", "onGameReleased", player, { score = score })
	hook("GameJamService", "onGameReleased", player, {
		genreId = project.genreId,
		topicId = project.topicId,
		score = score,
		revenue = revenue,
	})
	-- Франшизы (фанаты, кандидаты) и контракт издателя (прогресс)
	hook("FranchiseService", "onGameReleased", player, {
		projectId = project.id,
		name = project.name,
		genreId = project.genreId,
		topicId = project.topicId,
		score = score,
		franchiseId = project.franchiseId,
		multiplier = depth,
		details = franchiseDetails,
	})
	hook("ContractService", "onGameReleased", player, {
		genreId = project.genreId,
		topicId = project.topicId,
		score = score,
		revenue = revenue,
	})
	-- Очки недели холдинга (HoldingService); совместная игра двух участников — больше
	hook(
		"HoldingService",
		"onGameReleased",
		player,
		{ coopWith = coopPartner, laptop = project.laptop == true }
	)
	-- Своя консоль (этапы, доля рынка) и стример (слава, хайп)
	hook("ConsoleService", "onGameReleased", player, {
		platform = project.platform,
		score = score,
		genreId = project.genreId,
	})
	hook("StreamerService", "onGameReleased", player, { score = score })
	-- События дня: заявка в блиц-джем (жанр и тема часа)
	hook("DailyEventService", "onGameReleased", player, {
		genreId = project.genreId,
		topicId = project.topicId,
		score = score,
		revenue = revenue,
	})
	-- Предложение «×2 к доходу этой игры» (OfferService запоминает релиз на минуту)
	hook("OfferService", "onGameReleased", player, {
		projectId = project.id,
		revenue = revenue,
		score = score,
	})
	-- Мини-аркада «Сыграй в свою игру» (ArcadeService запоминает релиз на windowSeconds)
	hook("ArcadeService", "onGameReleased", player, {
		projectId = project.id,
		revenue = revenue,
		genreId = project.genreId,
	})

	Remotes.GameReleased:FireClient(player, {
		name = project.name,
		genreId = project.genreId,
		topicId = project.topicId,
		score = score,
		revenue = revenue,
		loanRepaid = loanRepaid,
		adBonus = adBonus,
		isRecord = isRecord,
		repeatPenalty = repeatPenalty,
		quickBonus = project.quickBonus,
		-- Настроение команды в оценке (уже внутри score); 0 — строку в окне не показываем
		moodBonus = moodReviewBonus(player),
		-- «Критики в городе»: реплики критиков восторженнее (ReleaseWindow)
		criticsHype = criticsBonus > 0,
		-- Команда в оценке (StaffService.reviewBonus: навыки, перки, легендарные; уже внутри score)
		teamBonus = StaffService.reviewBonus(player),
		projectId = project.id,
		platform = project.platform,
		-- Сколько игр ещё в разработке: клиент не прячет прогресс и событие второй игры
		activeProjects = #(projects[player] or {}),
	})
end

-- Применить выбор события: очки в направление (или по фокусу), время, риск
local function applyEffect(
	player: Player,
	project: Project,
	effect: DevEvents.Effect,
	eventId: string?
): boolean
	local perk = perks(player)
	-- Перк «Багоборец»: событие «баг» всегда заканчивается удачно
	local ok = effect.chance == nil
		or (eventId == "bug" and perk.bugAlwaysWins == true)
		or rng:NextNumber() < effect.chance
	local work = if ok then effect.work or 0 else effect.failWork or 0
	-- Перк «Хайпожор»: стример даёт больше
	if eventId == "streamer" and work > 0 then
		work *= tonumber(perk.streamerMultiplier) or 1
	end
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
	local ok = applyEffect(player, project, effect, active.def.id)
	Remotes.DevEventResult:FireClient(player, { id = active.def.id, choice = choice, ok = ok })
end

-- Активное событие игрока (одно на игрока, даже при двух проектах)
local function projectWithEvent(player: Player): Project?
	for _, project in projects[player] or {} do
		if project.event then
			return project
		end
	end
	return nil
end

local function maybeStartEvent(player: Player, project: Project)
	if project.event then
		-- Не ответил вовремя — спокойный вариант
		if project.elapsed >= project.event.expiresAt then
			resolveEvent(player, project, "b")
		end
		return
	end
	-- Быстрое событие важнее: пока оно идёт (или только что началось), выбор ждёт
	local choiceActive = projectWithEvent(player) ~= nil
	if QuickEventService.tick(player, project.id, project.elapsed, project.duration, choiceActive) then
		-- Выбор — не раньше чем через 2 с после быстрого события (пусть игрок увидит результат)
		project.nextEventAt = math.max(project.nextEventAt, project.elapsed + 2)
		return
	end
	if project.eventsDone >= DevEvents.maxPerGame or project.elapsed < project.nextEventAt then
		return
	end
	-- Не начинаем событие перед самым релизом: на ответ должно хватить времени
	if project.elapsed + DevEvents.answerSeconds > project.duration then
		return
	end
	-- У второй игры событие подождёт, пока игрок ответит на первое
	if projectWithEvent(player) then
		return
	end
	-- Быстрые события в приоритете: не рядом с ними (QuickEvents.minGap)
	if not QuickEventService.choiceAllowed(player) then
		return
	end
	local def = DevEvents.list[rng:NextInteger(1, #DevEvents.list)]
	project.eventsDone += 1
	project.nextEventAt = project.elapsed + rng:NextNumber(DevEvents.intervalMin, DevEvents.intervalMax)
	project.event = { def = def, expiresAt = project.elapsed + DevEvents.answerSeconds }
	QuickEventService.noteChoice(player)
	Remotes.DevEvent:FireClient(
		player,
		{ id = def.id, answerSeconds = DevEvents.answerSeconds, projectId = project.id }
	)
end

local function onEventChoice(player: Player, eventId: any, choice: any)
	local project = projectWithEvent(player)
	if not project or not project.event or project.pending then
		return
	end
	if eventId ~= project.event.def.id or (choice ~= "a" and choice ~= "b") then
		return
	end
	QuickEventService.noteActivity(player)
	resolveEvent(player, project, choice)
end

-- «Сиквел»: «Игра» -> «Игра 2», «Игра 2» -> «Игра 3»; не длиннее MAX_NAME_LENGTH
local function sequelName(name: string): string
	local base, number = name:match("^(.-)%s+(%d+)$")
	local nextNumber = if base and base ~= "" and number then (tonumber(number) or 1) + 1 else 2
	local baseName = if base and base ~= "" and number then base else name
	local suffix = " " .. tostring(math.min(nextNumber, 999))
	local maxBase = MAX_NAME_LENGTH - #suffix
	local length = utf8.len(baseName)
	if not length then
		baseName = DEFAULT_NAME
	elseif length > maxBase then
		baseName = baseName:sub(1, (utf8.offset(baseName, maxBase + 1) or (#baseName + 1)) - 1)
	end
	return baseName .. suffix
end

-- Геймпасс «Авто-релиз»: следующая игра с тем же жанром, темой, фокусом и названием-сиквелом.
-- Все обычные проверки (за ПК, слот, жанр открыт, фильтр названия) — в beginProject
local function maybeAutoRelease(player: Player, project: Project)
	if not ownsPass(player, "autoRelease") then
		return
	end
	local Perks = optional("PerksService")
	if not Perks or not Perks.isAutoReleaseOn(player) or not PlotService.isAtPc(player) then
		return
	end
	-- defer: фильтр названия уступает поток, а мы ещё внутри цикла тиков
	task.defer(
		beginProject,
		player,
		project.genreId,
		project.topicId,
		table.clone(project.focus),
		sequelName(project.name),
		true,
		project.franchiseId,
		project.platform
	)
end

-- Завершить проект: событие без ответа — спокойный вариант, слот освобождается, релиз
local function finishProject(player: Player, project: Project)
	resolveEvent(player, project, "b")
	-- Один раз: при повторе упавшего релиза план событий уже закрыт
	if project.quickBonus == nil then
		project.quickBonus = QuickEventService.finish(player, project.id)
	end
	if not removeProject(player, project) then
		return
	end
	local ok, err = pcall(release, player, project)
	if not ok and not project.paid then
		-- Релиз упал до начисления дохода: игра не должна пропасть — возвращаем её в разработку,
		-- следующий тик попробует снова (но не бесконечно)
		project.releaseFailures = (project.releaseFailures or 0) + 1
		local list = projects[player]
		if list and project.releaseFailures < MAX_RELEASE_FAILURES then
			table.insert(list, project)
		end
		DevelopmentService.pushState(player)
		-- Без error: иначе цикл тиков посчитает проект сломанным и уберёт его из списка
		warn("[DevelopmentService] Release failed, will retry:", player.Name, project.releaseFailures, err)
		return
	elseif not ok then
		warn("[DevelopmentService] Release finished with an error after payout:", err)
	end
	DevelopmentService.pushState(player)
	maybeAutoRelease(player, project)
end

-- «Мгновенно закончить»: заряд из ShopService, очки за оставшееся время, сразу релиз.
-- Без yield между проверкой и выдачей: двойной клик не потратит два заряда
local function onInstantFinish(player: Player, projectId: any)
	if type(projectId) ~= "number" or projectId ~= projectId then
		return
	end
	if not cooldownPassed(lastAction, player, ACTION_COOLDOWN) then
		return
	end
	local project: Project? = nil
	for _, candidate in projects[player] or {} do
		if candidate.id == projectId then
			project = candidate
			break
		end
	end
	-- На ноутбуке в парке не работает
	if not project or project.pending or project.laptop or onLaptop(player) then
		return
	end
	if project.elapsed >= project.duration then
		return -- и так выходит на следующем тике
	end
	-- Как и обычная разработка — только сидя за компьютером
	if not PlotService.isAtPc(player) then
		return
	end
	local ShopService = optional("ShopService")
	if not ShopService or not ShopService.consumeCharge(player, "instantFinish") then
		return
	end
	-- Сначала событие (спокойный вариант может сдвинуть время), потом очки за остаток
	resolveEvent(player, project, "b")
	local remaining = math.max(project.duration - project.elapsed, 0)
	local rate = DevelopmentService.pointsRate(player, project.focus, project.tempo)
	project.points.gameplay += rate.gameplay * remaining
	project.points.graphics += rate.graphics * remaining
	project.points.sound += rate.sound * remaining
	project.points.story += rate.story * remaining
	project.elapsed = project.duration
	local ok, err = pcall(finishProject, player, project)
	if not ok then
		warn("[DevelopmentService] Instant finish failed:", err)
		-- Доход не начислен — игра вернулась в разработку, заряд возвращаем
		local refund = ShopService.refundCharge
		if not project.paid and type(refund) == "function" then
			pcall(refund, player, "instantFinish")
		end
	end
end

-- «Тест-группа»: ожидаемая оценка без случайного разброса ± Research.PREVIEW_SPREAD.
-- Очки — как если бы вся разработка шла с текущими очками/с, без событий
local function onPreviewRequest(player: Player, request: any)
	if type(request) ~= "table" or not cooldownPassed(lastPreview, player, PREVIEW_COOLDOWN) then
		return
	end
	local profile = DataService.get(player)
	local research = researchModifiers(player)
	if not profile or not research or research.reviewPreview ~= true then
		return
	end
	local genreId, topicId = request.genreId, request.topicId
	if not comboAllowed(profile, genreId, topicId) then
		return
	end
	local focus = sanitizeFocus(request.focus)
	if not focus then
		return
	end
	local duration, tempo = devTiming(player)
	local rate = DevelopmentService.pointsRate(player, focus, tempo)
	local points = {
		gameplay = rate.gameplay * duration,
		graphics = rate.graphics * duration,
		sound = rate.sound * duration,
		story = rate.story * duration,
	}
	local score =
		Formulas.review(genreId, topicId, points, NO_NOISE, scoreBonus(player, profile, genreId, topicId))
	-- Тренд, перк «Тренд-хантер» и праздник — как в release, чтобы прогноз совпадал с оценкой
	local TrendService = optional("TrendService")
	if TrendService then
		local okTrend, trendValue = pcall(TrendService.getBonus, genreId, topicId)
		local trend = if okTrend and type(trendValue) == "number" then trendValue else 0
		score += trend
		if trend > 0 then
			score += tonumber(perks(player).trendBonus) or 0
		end
		score = math.floor(score + 0.5)
	end
	local HolidayService = optional("HolidayService")
	if HolidayService then
		local okHoliday, bonus = pcall(HolidayService.reviewBonus, genreId, topicId)
		if okHoliday and type(bonus) == "number" then
			score += bonus
		end
	end
	score += hookNumber("DailyEventService", "reviewBonus", 0, genreId)
	score = math.clamp(score, 1, 10)
	PaidRemotes.ReviewPreview:FireClient(player, {
		genreId = genreId,
		topicId = topicId,
		min = math.max(score - Research.PREVIEW_SPREAD, 1),
		max = math.min(score + Research.PREVIEW_SPREAD, 10),
	})
end

local function onStateRequest(player: Player)
	if cooldownPassed(lastStateRequest, player, STATE_COOLDOWN) then
		DevelopmentService.pushState(player)
	end
end

local TICK = 0.5

local function hackathonSpeed(): number
	local HackathonService = optional("HackathonService")
	local ok, value = pcall(function()
		return if HackathonService then HackathonService.speedMultiplier() else 1
	end)
	return if ok and type(value) == "number" and value > 0 then value else 1
end

-- Один тик одного проекта. Отдельной функцией, чтобы ошибка у одного игрока
-- (например, в хуке другой фичи) не останавливала разработку у всех
local function tickProject(player: Player, project: Project, atPc: boolean)
	if project.pending or not hasProject(player, project) then
		return
	end
	-- Встал из-за компьютера (или событие компании «отключили свет») — разработка на паузе
	if not atPc or companyEvent("isPaused", false, player) == true then
		Remotes.DevelopmentProgress:FireClient(player, {
			id = project.id,
			progress = math.min(project.elapsed / project.duration, 1),
			points = project.points,
			paused = true,
		})
		return
	end
	local rate = DevelopmentService.pointsRate(player, project.focus, project.tempo)
	-- Ночь хакатона (HackathonService): время идёт ×2, очков за игру столько же;
	-- «Кофе-раш» (DailyEventService) — ещё +25%, вместе не выше DailyEvents.maxDevSpeed
	local hackathon = hackathonSpeed()
	local step = TICK * hookNumber("DailyEventService", "devSpeed", hackathon, hackathon)
	project.points.gameplay += rate.gameplay * step
	project.points.graphics += rate.graphics * step
	project.points.sound += rate.sound * step
	project.points.story += rate.story * step
	-- Гость совместной разработки (CoopService): его очки — по фокусу проекта
	local CoopService = optional("CoopService")
	if CoopService then
		local okCoop, extra = pcall(CoopService.bonusPoints, player, project.id, project.tempo, step)
		if okCoop and type(extra) == "number" and extra > 0 and extra < math.huge then
			for key, share in project.focus :: any do
				(project.points :: any)[key] += extra * share
			end
		end
	end
	project.elapsed += step

	Remotes.DevelopmentProgress:FireClient(player, {
		id = project.id,
		progress = math.min(project.elapsed / project.duration, 1),
		points = project.points,
		-- Секунд до релиза (кнопка «⚡ Закончить сейчас», Config/Offers.longDev)
		remaining = math.max(project.duration - project.elapsed, 0),
	})

	maybeStartEvent(player, project)
	if project.elapsed >= project.duration then
		finishProject(player, project)
	end
end

-- Снимок проекта для совместной разработки (CoopService); nil — проекта нет
function DevelopmentService.projectInfo(player: Player, projectId: number): any
	for _, project in projects[player] or {} do
		if project.id == projectId then
			return {
				name = project.name,
				pending = project.pending,
				laptop = project.laptop == true,
				elapsed = project.elapsed,
				duration = project.duration,
			}
		end
	end
	return nil
end

-- Игра в разработке в студии (не ноутбук): событиям компании есть что «уронить» или ускорить
function DevelopmentService.hasActiveProject(player: Player): boolean
	for _, project in projects[player] or {} do
		if not project.pending and not project.laptop and project.elapsed < project.duration then
			return true
		end
	end
	return false
end

-- Событие «упал сервер»: игры теряют share длительности прогресса (очки — пропорционально).
-- Возвращает, сколько игр задело
function DevelopmentService.rollbackProgress(player: Player, share: number): number
	local count = 0
	for _, project in projects[player] or {} do
		if not project.pending and not project.laptop and project.elapsed > 0 then
			local lost = math.min(project.duration * math.clamp(share, 0, 1), project.elapsed)
			local keep = (project.elapsed - lost) / project.elapsed
			project.elapsed -= lost
			for key, value in project.points :: any do
				(project.points :: any)[key] = value * keep
			end
			count += 1
		end
	end
	return count
end

-- Событие «выпустить раньше»: пропустить share оставшегося времени с очками за него
-- (как «Мгновенно закончить», но частично). Возвращает, сколько игр задело
function DevelopmentService.rushProjects(player: Player, share: number): number
	local count = 0
	for _, project in projects[player] or {} do
		if not project.pending and not project.laptop and project.elapsed < project.duration then
			local skip = math.max(project.duration - project.elapsed, 0) * math.clamp(share, 0, 1)
			local rate = DevelopmentService.pointsRate(player, project.focus, project.tempo)
			project.points.gameplay += rate.gameplay * skip
			project.points.graphics += rate.graphics * skip
			project.points.sound += rate.sound * skip
			project.points.story += rate.story * skip
			project.elapsed += skip
			count += 1
		end
	end
	return count
end

-- Отменить всю разработку (Rebirth сбрасывает студию — недоделанные игры пропадают,
-- иначе они вышли бы уже с новым множителем Rebirth). Ждущие фильтра тоже снимаются
function DevelopmentService.cancel(player: Player)
	projects[player] = nil
	QuickEventService.cancel(player)
	DevelopmentService.pushState(player)
end

function DevelopmentService.start()
	Remotes.DevEventChoice.OnServerEvent:Connect(onEventChoice)
	Remotes.StartDevelopment.OnServerEvent:Connect(onStartDevelopment)
	PaidRemotes.InstantFinish.OnServerEvent:Connect(onInstantFinish)
	PaidRemotes.ReviewPreviewRequest.OnServerEvent:Connect(onPreviewRequest)
	PaidRemotes.DevStateRequest.OnServerEvent:Connect(onStateRequest)
	Players.PlayerRemoving:Connect(function(player)
		projects[player] = nil
		lastAction[player] = nil
		lastPreview[player] = nil
		lastStateRequest[player] = nil
	end)

	-- Один общий цикл вместо таймера на каждого игрока. Снимок списков: релиз и авто-релиз
	-- меняют их во время обхода
	task.spawn(function()
		while true do
			task.wait(TICK)
			local snapshot: { [Player]: { Project } } = {}
			for player, list in projects do
				if #list > 0 then
					snapshot[player] = table.clone(list)
				end
			end
			for player, list in snapshot do
				local atPc = PlotService.isAtPc(player)
				for _, project in list do
					local ok, err = pcall(tickProject, player, project, atPc)
					if not ok then
						warn("[DevelopmentService] Tick failed for", player.Name, err)
						-- Сломанный проект убираем, чтобы ошибка не повторялась каждые полсекунды
						if removeProject(player, project) then
							pcall(DevelopmentService.pushState, player)
						end
					end
				end
			end
		end
	end)
end

return DevelopmentService
