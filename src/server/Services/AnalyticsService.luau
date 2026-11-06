--!strict
-- Аналитика для запуска (задача 6.4): D1/D7 и «где отваливаются».
--   • Онбординг-воронка (LogOnboardingFunnelStepEvent): шаги из Config/Analytics.onboarding,
--     определяются опросом профиля/атрибутов, отправляются строго по порядку и один раз за жизнь
--     игрока (номер последнего шага — (profile :: any).analytics.funnel).
--   • Экономика (LogEconomyEvent): DataService.addCash/trySpend/charge обёрнуты здесь же; источник
--     и трату узнаём по вызвавшему сервису и функции (debug.info, Config/Analytics.sources/sinks),
--     покупки в PlotService и найм — по тому, что изменилось в профиле. Всё, что выдано внутри
--     ProcessReceipt, — IAP с ключом товара (beginReceipt/endReceipt из MonetizationService).
--     Копим по игроку и шлём сводкой раз в economyFlushSeconds. Описание — docs/ANALYTICS.md.
--   • Редкие кастомные события (LogCustomEvent): Rebirth, кражи, выставка, покупки, язык.
-- Чужие сервисы не правим. Любая ошибка аналитики глотается (pcall) и не роняет игру.

local AnalyticsService = game:GetService("AnalyticsService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.Analytics)
local GamePasses = require(Shared.Config.GamePasses)
local Upgrades = require(Shared.Config.Upgrades)
local Stages = require(Shared.Config.Stages)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

type Profile = DataService.Profile

type AnalyticsData = {
	funnel: number, -- номер последнего отправленного шага воронки (0 — ни одного)
	-- Профиль был до аналитики (уже играл): онбординг не шлём, иначе воронку зальют старички
	legacy: boolean,
}

type Bucket = {
	flow: Enum.AnalyticsEconomyFlowType,
	transactionType: string,
	sku: string,
	item: string?, -- CustomField02: id предмета
	amount: number,
}

-- Товар за Robux: ключ из Config и цена (для ProductPurchased)
type ProductInfo = { key: string, robux: number }

type PlayerState = {
	rebirths: number,
	steals: number,
	caught: number,
	lang: any, -- язык на начало сессии
	langLogged: boolean,
	parkTouched: boolean, -- получил деньги с доски заказов/ломбарда (шаг онбординга)
	satLaptop: boolean, -- садился за общий ноутбук в парке
	balance: number, -- последний известный баланс: при выходе профиля может уже не быть
	stage: number,
	economy: { [string]: Bucket },
	economyOrder: { string },
}

-- Снимок профиля сразу после списания: что из этого изменится — то и купили
type SpendSnapshot = {
	upgrades: { [string]: boolean },
	genres: { [string]: boolean },
	topics: { [string]: boolean },
	staff: { [string]: boolean },
	decor: { [string]: boolean },
	skins: { [string]: boolean },
	mascots: { [string]: boolean },
	furniture: { [string]: boolean },
	posters: { [string]: boolean },
	equipment: { [string]: boolean },
	consoleStage: number,
	construction: boolean,
	studioLevel: number,
	ownsGarage: boolean,
	ad: any,
	adExpires: number,
}

local PROFILE_WAIT = 0.5
local PROFILE_WAIT_LIMIT = 60
local MINUTE = 60

local Analytics = {}
local states: { [Player]: PlayerState } = {}
local watched: { [Player]: boolean } = {} -- onPlayerAdded отработал (опрос и слежение за посадкой)
-- Идёт выдача по квитанции: поток ProcessReceipt → товар. Все addCash в этом потоке — IAP
local receiptByThread: { [thread]: ProductInfo } = {}
local productById: { [number]: ProductInfo }? = nil

local isStudio = RunService:IsStudio()
local budgetWindow = os.clock()
local budgetUsed = 0
-- Последняя сводка игрока при выходе / закрытии сервера уходит мимо нашего бюджета: иначе при
-- массовом выходе остаток экономики терялся молча (аудит Fable, P2-2). Лимит Roblox вдвое выше нашего
local finalFlush = false
local warned: { [string]: boolean } = {}

local stepById: { [string]: number } = {}
for index, step in Config.onboarding do
	stepById[step.id] = index
end

local upgradeById: { [string]: Upgrades.Upgrade } = {}
for _, upgrade in Upgrades do
	upgradeById[upgrade.id] = upgrade
end

local function warnOnce(key: string, ...: any)
	if not warned[key] then
		warned[key] = true
		warn("[AnalyticsService]", key, ...)
	end
end

-- ===== Отправка с бюджетом =====

local function takeBudget(): boolean
	local now = os.clock()
	if now - budgetWindow >= MINUTE then
		budgetWindow = now
		budgetUsed = 0
	end
	local limit = Config.budgetBase + Config.budgetPerPlayer * #Players:GetPlayers()
	if budgetUsed >= limit then
		return false
	end
	budgetUsed += 1
	return true
end

-- true — событие «ушло» (или напечатано в Studio); false — нет бюджета, повторить позже
local function emit(describe: string, send: () -> ()): boolean
	if not Config.enabled then
		return true
	end
	if not finalFlush and not takeBudget() then
		return false
	end
	if Config.debugPrint and (isStudio or Config.debugPrintLive) then
		print("[Analytics]", describe)
	end
	if isStudio then
		return true -- Roblox не принимает события из Studio
	end
	local ok, err = pcall(send)
	if not ok then
		local kind = describe:match("^%S+") or "event"
		warnOnce("send failed: " .. kind, err)
	end
	return true
end

local function fields(value: string?): { [string]: string }?
	-- Ключ = Enum.AnalyticsCustomFieldKeys.CustomField01.Name; значения — только строки
	return if value then { CustomField01 = value } else nil
end

local function logCustom(player: Player, eventName: string, value: number, f1: string?): boolean
	return emit(
		string.format("custom %s value=%s field=%s player=%d", eventName, value, f1 or "-", player.UserId),
		function()
			AnalyticsService:LogCustomEvent(player, eventName, value, fields(f1) :: any)
		end
	)
end

-- ===== Данные профиля =====

local function num(value: any): number
	local n = tonumber(value)
	return if n and n == n and n > -math.huge and n < math.huge then n else 0
end

local function isLegacy(profile: Profile): boolean
	local p = profile :: any
	return profile.gamesReleased > 0
		or profile.rebirths > 0
		or profile.upgrades.desk1 == true
		or p.ownsGarage == true
end

local function dataOf(profile: Profile): AnalyticsData
	local p = profile :: any
	local raw = p.analytics
	if type(raw) ~= "table" then
		raw = { funnel = 0, legacy = isLegacy(profile) }
		p.analytics = raw
	end
	-- Старый формат (до 06.11: отметки по id шагов в raw.onboarding) — только тестовые профили,
	-- шаги с тех пор поменялись: начинаем воронку заново
	raw.onboarding = nil
	raw.funnel = math.clamp(math.floor(num(raw.funnel)), 0, #Config.onboarding)
	raw.legacy = raw.legacy == true
	return raw :: AnalyticsData
end

local function thiefStats(profile: Profile): (number, number)
	local raw = (profile :: any).thief
	if type(raw) ~= "table" then
		return 0, 0
	end
	return num(raw.steals), num(raw.caught)
end

local function keySet(map: any): { [string]: boolean }
	local set = {}
	if type(map) == "table" then
		for key, value in map do
			if value then
				set[tostring(key)] = true
			end
		end
	end
	return set
end

local function newKey(before: { [string]: boolean }, after: any): string?
	if type(after) ~= "table" then
		return nil
	end
	for key, value in after do
		if value and not before[tostring(key)] then
			return tostring(key)
		end
	end
	return nil
end

-- ===== Онбординг =====

local function hasAny(map: any, except: string?): boolean
	if type(map) ~= "table" then
		return false
	end
	for key, value in map do
		if value and key ~= except then
			return true
		end
	end
	return false
end

local function optionalService(name: string): any
	local module = script.Parent:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end

-- Детектор: достигнут ли шаг сейчас. Шаги ниже последнего достигнутого считаются пройденными
-- (checkOnboarding), поэтому детектору не нужно помнить прошлое
local detectors: { [string]: (Player, Profile, PlayerState) -> boolean } = {
	joined = function()
		return true
	end,
	-- Ноутбук в парке (общий PcSeat с атрибутом Public, не кресло в своей студии — отчёт #4, P2-6),
	-- заказ с доски или картридж/ломбард
	park = function(player, profile, state)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		if seat ~= nil and seat:GetAttribute("Public") == true and PlotService.isAtPc(player) then
			state.satLaptop = true
		end
		local p = profile :: any
		return state.satLaptop or state.parkTouched or num(p.cartridges) > 0 or hasAny(p.jobReadyAt)
	end,
	firstGameStarted = function(player, profile)
		if profile.gamesReleased >= 1 then
			return true
		end
		local development = optionalService("DevelopmentService")
		return development ~= nil
			and type(development.hasAnyProject) == "function"
			and development.hasAnyProject(player) == true
	end,
	firstRelease = function(_, profile)
		return profile.gamesReleased >= 1
	end,
	garage = function(_, profile)
		return (profile :: any).ownsGarage == true
	end,
	studioNamed = function(_, profile)
		local name = (profile :: any).studioName
		return type(name) == "string" and #name > 0
	end,
	firstHire = function(_, profile)
		return hasAny((profile :: any).staff)
	end,
	officeStarted = function(_, profile)
		local construction = profile.construction
		return profile.studioLevel >= 2 or (type(construction) == "table" and num(construction.stage) >= 2)
	end,
	office = function(_, profile)
		return profile.studioLevel >= 2
	end,
	floor2 = function(_, profile)
		return profile.studioLevel >= 3
	end,
	floor3 = function(_, profile)
		return profile.studioLevel >= 4
	end,
	rebirth = function(_, profile)
		return profile.rebirths >= 1
	end,
}

local function checkOnboarding(player: Player, profile: Profile, state: PlayerState)
	local data = dataOf(profile)
	if data.legacy or data.funnel >= #Config.onboarding then
		return
	end
	-- Самый дальний достигнутый шаг. Шаги могут случиться не по порядку (найм раньше названия,
	-- Rebirth сбросил этап): всё, что до него, считаем пройденным и шлём по порядку 1, 2, 3…
	local reached = data.funnel
	for index = #Config.onboarding, data.funnel + 1, -1 do
		local detector = detectors[Config.onboarding[index].id]
		if detector and detector(player, profile, state) then
			reached = index
			break
		end
	end
	for index = data.funnel + 1, reached do
		local step = Config.onboarding[index]
		local sent = emit(
			string.format("onboarding %d %s player=%d", index, step.name, player.UserId),
			function()
				AnalyticsService:LogOnboardingFunnelStepEvent(player, index, step.name)
			end
		)
		if not sent then
			return -- бюджет кончился: дошлём на следующем опросе
		end
		data.funnel = index
	end
end

-- ===== Кастомные события из профиля =====

local function checkCustom(player: Player, profile: Profile, state: PlayerState)
	if profile.rebirths > state.rebirths then
		state.rebirths = profile.rebirths
		logCustom(player, Config.events.rebirth, profile.rebirths, "rebirth" .. profile.rebirths)
	end
	local steals, caught = thiefStats(profile)
	if steals > state.steals then
		logCustom(player, Config.events.hitStolen, steals - state.steals)
		state.steals = steals
	end
	if caught > state.caught then
		logCustom(player, Config.events.thiefCaught, caught - state.caught)
		state.caught = caught
	end
	local lang = (profile :: any).lang
	if not state.langLogged and lang ~= state.lang and type(lang) == "string" then
		state.langLogged = true
		logCustom(player, Config.events.languageChanged, 1, lang)
	end
	state.balance = profile.cash
	state.stage = profile.studioLevel
end

local function poll(player: Player)
	local state = states[player]
	local profile = DataService.get(player)
	if not state or not profile or not Config.enabled then
		return
	end
	local ok, err = pcall(function()
		checkOnboarding(player, profile, state)
		checkCustom(player, profile, state)
	end)
	if not ok then
		warnOnce("poll failed", err)
	end
end

-- Состояние игрока из профиля. nil — профиля ещё нет или игрок вышел. Создаётся при входе
-- (onPlayerAdded) или лениво — первой же квитанцией, пришедшей раньше инициализации
local function ensureState(player: Player): PlayerState?
	local existing = states[player]
	if existing then
		return existing
	end
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return nil
	end
	local ok, err = pcall(function()
		dataOf(profile) -- legacy определяем сразу при входе, до любых действий
		local steals, caught = thiefStats(profile)
		states[player] = {
			rebirths = profile.rebirths,
			steals = steals,
			caught = caught,
			lang = (profile :: any).lang,
			langLogged = false,
			parkTouched = false,
			satLaptop = false,
			balance = profile.cash,
			stage = profile.studioLevel,
			economy = {},
			economyOrder = {},
		}
	end)
	if not ok then
		warnOnce("player init failed", err)
		return nil
	end
	return states[player]
end

-- ===== Экономика =====

local function addToBucket(
	player: Player,
	flow: Enum.AnalyticsEconomyFlowType,
	tag: Config.EconomyTag,
	item: string?,
	amount: number
)
	if amount <= 0 or amount ~= amount or amount == math.huge then
		return
	end
	-- Отложенная квитанция может прийти раньше onPlayerAdded: состояние создаём здесь
	local state = ensureState(player)
	if not state then
		return
	end
	local key = flow.Name .. "|" .. tag.transactionType .. "|" .. tag.sku .. "|" .. (item or "")
	local bucket = state.economy[key]
	if bucket then
		bucket.amount += amount
	else
		state.economy[key] = {
			flow = flow,
			transactionType = tag.transactionType,
			sku = tag.sku,
			item = item,
			amount = amount,
		}
		table.insert(state.economyOrder, key)
	end
end

local function flushEconomy(player: Player)
	local state = states[player]
	if not state or #state.economyOrder == 0 then
		return
	end
	local profile = DataService.get(player)
	local balance = if profile then profile.cash else state.balance
	local stage = if profile then profile.studioLevel else state.stage
	while #state.economyOrder > 0 do
		local key = state.economyOrder[1]
		local bucket = state.economy[key]
		if bucket then
			local amount = math.floor(bucket.amount)
			local custom: { [string]: string } = { CustomField01 = "stage" .. stage }
			if bucket.item then
				custom.CustomField02 = bucket.item
			end
			local sent = amount <= 0
				or emit(
					string.format(
						"economy %s %s/%s %s %d balance=%d player=%d",
						bucket.flow.Name,
						bucket.transactionType,
						bucket.sku,
						bucket.item or "-",
						amount,
						math.floor(balance),
						player.UserId
					),
					function()
						AnalyticsService:LogEconomyEvent(
							player,
							bucket.flow,
							Config.currency,
							amount,
							math.max(math.floor(balance), 0),
							bucket.transactionType,
							bucket.sku,
							custom :: any
						)
					end
				)
			if not sent then
				return -- бюджет кончился: остаток уйдёт следующей сводкой
			end
		end
		state.economy[key] = nil
		table.remove(state.economyOrder, 1)
	end
end

-- Имя модуля и функции на уровне level стека того, кто вызвал frame (1 — он сам, 2 — его вызвавший).
-- Кадр C-функции (pcall, task) даёт nil, nil
local function frame(level: number): (string?, string?)
	local source, name = debug.info(level + 1, "sn")
	if type(source) ~= "string" then
		return nil, nil
	end
	local module = source:match("([%w_]+)$")
	return module, if type(name) == "string" and name ~= "" then name else nil
end

-- Категория по "Сервис.функция" → "Сервис.внешняя функция" → "Сервис"
-- Имена функций модуля module выше по стеку (уровни from..from+7 считая вызывающую обёртку за 1).
-- Нужны, когда деньги тратятся внутри безымянного колбэка (withLock(player, function() … end)):
-- сам колбэк имени не даёт, а ключ источника — «StockService.onIpo» (аудит Fable, P2-1).
-- Зовётся напрямую из обёртки: уровни считаются как у frame
local function sameModuleCallers(module: string?, from: number): { string }
	local names: { string } = {}
	if not module then
		return names
	end
	for level = from, from + 7 do
		local source, name = debug.info(level + 1, "sn")
		if type(source) ~= "string" then
			break
		end
		if source:match("([%w_]+)$") == module and type(name) == "string" and name ~= "" then
			table.insert(names, name)
		end
	end
	return names
end

local function lookup(
	map: { [string]: Config.EconomyTag },
	module: string,
	fn: string?,
	outerFn: string?,
	callers: { string }?
)
	local tag = (fn and map[module .. "." .. fn]) or (outerFn and map[module .. "." .. outerFn])
	if tag then
		return tag
	end
	for _, name in callers or {} do
		local byCaller = map[module .. "." .. name]
		if byCaller then
			return byCaller
		end
	end
	return map[module]
end

local function otherTag(module: string?): Config.EconomyTag
	return { transactionType = Config.otherTransactionType, sku = "other" .. (module or "Unknown") }
end

-- Вызывается из обёртки addCash: module/fn — кто позвал DataService.addCash, outer/outerFn — ближайший
-- Luau-кадр выше (для посредника RewardService); receipt — идёт выдача по квитанции в этом потоке
local function onSource(
	player: Player,
	amount: number,
	module: string?,
	fn: string?,
	outer: string?,
	outerFn: string?,
	receipt: ProductInfo?,
	callers: { string }?
)
	if receipt then
		-- Деньги за Robux: пакет дохода, «двойной релиз», запасная выдача ускорений и подарков
		local tag = { transactionType = "IAP", sku = receipt.key }
		addToBucket(player, Enum.AnalyticsEconomyFlowType.Source, tag, nil, amount)
		return
	end
	if not module or Config.ignore[module] then
		return
	end
	if Config.passthrough[module] and outer then
		module, fn = outer, outerFn
		callers = nil -- имена были от посредника, не от модуля, куда перешли
	end
	local state = states[player]
	if module == "StartParkService" and state then
		state.parkTouched = true
	end
	if module == "ExpoService" then
		logCustom(player, Config.events.expoWin, 1)
	end
	local tag = lookup(Config.sources, module :: string, fn, nil, callers) or otherTag(module)
	addToBucket(player, Enum.AnalyticsEconomyFlowType.Source, tag, nil, amount)
end

local function snapshot(profile: Profile): SpendSnapshot
	local p = profile :: any
	local ad = profile.activeAd
	local console = if type(p.console) == "table" then p.console else {}
	return {
		upgrades = keySet(profile.upgrades),
		genres = keySet(profile.unlockedGenres),
		topics = keySet(profile.unlockedTopics),
		staff = keySet(p.staff),
		decor = keySet(if type(p.decor) == "table" then p.decor.owned else nil),
		skins = keySet(if type(p.skins) == "table" then p.skins.owned else nil),
		mascots = keySet(if type(p.mascots) == "table" then p.mascots.owned else nil),
		furniture = keySet(if type(p.furniture) == "table" then p.furniture.owned else nil),
		posters = keySet(if type(p.posters) == "table" then p.posters.owned else nil),
		equipment = keySet(console.equipment),
		consoleStage = num(console.stage),
		construction = profile.construction ~= nil,
		studioLevel = profile.studioLevel,
		ownsGarage = p.ownsGarage == true,
		ad = ad,
		adExpires = if ad then ad.expiresAt else 0,
	}
end

local function stageId(level: number): string
	local stage = Stages[level]
	return if stage then stage.id else "stage" .. level
end

local function ownedOf(p: any, field: string): any
	local store = p[field]
	return if type(store) == "table" then store.owned else nil
end

-- Покупки без своей строки в Config/Analytics.sinks (PlotService, найм, реклама) — по изменению профиля
local function spendByDiff(profile: Profile, before: SpendSnapshot): (Config.EconomyTag?, string?)
	local p = profile :: any
	local sinks = Config.sinks
	local construction = profile.construction
	if p.ownsGarage == true and not before.ownsGarage then
		return sinks.garage, nil
	elseif construction and not before.construction then
		return sinks.construction, stageId(construction.stage)
	elseif profile.studioLevel > before.studioLevel then
		return sinks.move, stageId(profile.studioLevel)
	end
	local upgradeId = newKey(before.upgrades, profile.upgrades)
	if upgradeId then
		local upgrade = upgradeById[upgradeId]
		return if upgrade and upgrade.move then sinks.move else sinks.upgrade, upgradeId
	end
	local employeeId = newKey(before.staff, p.staff)
	if employeeId then
		return sinks.hire, employeeId
	end
	local genreId = newKey(before.genres, profile.unlockedGenres)
	local topicId = newKey(before.topics, profile.unlockedTopics)
	if genreId or topicId then
		return sinks.ResearchService, if genreId then "genre_" .. genreId else "topic_" .. (topicId :: string)
	end
	local ad = profile.activeAd
	if ad and (ad ~= before.ad or ad.expiresAt ~= before.adExpires) then
		return sinks.ad, "ad_" .. math.floor(ad.bonus * 100)
	end
	return nil, nil
end

-- id предмета (CustomField02) для трат со строкой в sinks
local function spendItem(profile: Profile, module: string, fn: string?, before: SpendSnapshot): string?
	local p = profile :: any
	if module == "DecorService" then
		-- Ключ покупки — id@этаж: этаж отрезаем, чтобы id было не больше, чем предметов
		local key = newKey(before.decor, ownedOf(p, "decor"))
		return if key then key:match("^[^@]+") else nil
	elseif module == "SkinService" then
		return newKey(before.skins, ownedOf(p, "skins"))
	elseif module == "MascotService" then
		return newKey(before.mascots, ownedOf(p, "mascots"))
	elseif module == "FurnitureStyleService" then
		return newKey(before.furniture, ownedOf(p, "furniture"))
	elseif module == "PosterService" then
		return newKey(before.posters, ownedOf(p, "posters"))
	elseif module == "ResearchService" then
		-- Открытие идёт таймером: в профиле его ещё нет, берём из лаборатории
		local active = if type(p.research) == "table" then p.research.active else nil
		return if type(active) == "table" then tostring(active.kind) .. "_" .. tostring(active.id) else nil
	elseif module == "ConsoleService" then
		local console = if type(p.console) == "table" then p.console else {}
		if fn == "onEquip" then
			return newKey(before.equipment, console.equipment)
		end
		return "stage" .. (before.consoleStage + 1) -- этап начат: d.stage — число завершённых
	elseif module == "MonetizationService" then
		local ad = profile.activeAd
		return if ad then "ad_" .. math.floor(ad.bonus * 100) else nil
	end
	return nil
end

-- Классифицировать трату (вызывается отложенно, после кода покупки)
local function classifySpend(
	player: Player,
	amount: number,
	module: string?,
	fn: string?,
	callers: { string }?,
	before: SpendSnapshot
)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local tag: Config.EconomyTag? = if module then lookup(Config.sinks, module, fn, nil, callers) else nil
	local item: string? = nil
	if tag and module then
		item = spendItem(profile, module, fn, before)
	else
		tag, item = spendByDiff(profile, before)
	end
	addToBucket(player, Enum.AnalyticsEconomyFlowType.Sink, tag or otherTag(module), item, amount)
end

local function wrapDataService()
	local service = DataService :: any
	local originalAdd = service.addCash
	local originalSpend = service.trySpend
	if type(originalAdd) ~= "function" or type(originalSpend) ~= "function" then
		warnOnce("DataService.addCash/trySpend not found, economy disabled")
		return
	end

	service.addCash = function(player: Player, amount: number)
		originalAdd(player, amount)
		if not Config.enabled or type(amount) ~= "number" or amount <= 0 then
			return
		end
		-- Стек: 1 — эта обёртка, 2 — кто позвал addCash, 3+ — кто позвал его (для посредников).
		-- frame зовём напрямую, не из pcall и не из функции: иначе уровни стека сдвинутся.
		-- debug.info на несуществующем уровне не бросает ошибку, а возвращает пусто
		local module, fn = frame(2)
		-- Ближайший Luau-кадр выше: pcall(RewardService.grant, …) даёт между ними кадр «[C]»
		local outer, outerFn = frame(3)
		if not outer then
			outer, outerFn = frame(4)
		end
		if not outer then
			outer, outerFn = frame(5)
		end
		local callers = sameModuleCallers(module, 3)
		local receipt = receiptByThread[coroutine.running()]
		local ok, err = pcall(onSource, player, amount, module, fn, outer, outerFn, receipt, callers)
		if not ok then
			warnOnce("addCash hook failed", err)
		end
	end

	service.trySpend = function(player: Player, amount: number): boolean
		local result = originalSpend(player, amount)
		if result and Config.enabled and type(amount) == "number" and amount > 0 then
			-- Ближайший Luau-модуль выше по стеку: вызов через pcall даёт кадр «[C]» без имени
			-- (так покупка декора писалась как Other/unknown — отчёт #4, P2-3)
			local module, fn = frame(2)
			local found = 2
			for level = 3, 6 do
				if module then
					break
				end
				module, fn = frame(level)
				found = level
			end
			local callers = sameModuleCallers(module, found + 1)
			local ok, err = pcall(function()
				local profile = DataService.get(player)
				if not profile then
					return
				end
				local state = states[player]
				if state then
					state.balance = profile.cash
				end
				local before = snapshot(profile)
				-- Код покупки меняет профиль сразу после trySpend, без yield: смотрим после него
				task.defer(function()
					local okClassify, errClassify =
						pcall(classifySpend, player, amount, module, fn, callers, before)
					if not okClassify then
						warnOnce("spend classify failed", errClassify)
					end
				end)
			end)
			if not ok then
				warnOnce("trySpend hook failed", err)
			end
		end
		return result
	end

	-- Обязательные расходы в минус (DataService.charge, Config/Bailiffs): зарплата и аренда
	-- (ExpensesService), штраф налоговой (TaxService)
	local originalCharge = service.charge
	if type(originalCharge) == "function" then
		service.charge = function(player: Player, amount: number, limit: number): number
			local charged = originalCharge(player, amount, limit)
			if Config.enabled and type(charged) == "number" and charged > 0 then
				local module, fn = frame(2)
				local _, outerFn = frame(3)
				local callers = sameModuleCallers(module, 3)
				local tag = if module then lookup(Config.sinks, module, fn, outerFn, callers) else nil
				pcall(
					addToBucket,
					player,
					Enum.AnalyticsEconomyFlowType.Sink,
					tag or otherTag(module),
					nil,
					charged
				)
			end
			return charged
		end
	end
end

-- ===== Квитанции Developer Products (MonetizationService) =====

-- Ключ товара из Config: обходим конфиги с productId. Префикс — чтобы id из разных конфигов не
-- совпали (скин и постер с одинаковым id). Первый найденный выигрывает: Products раньше остальных
local PRODUCT_CONFIGS: { { name: string, prefix: string } } = {
	{ name = "Products", prefix = "" },
	{ name = "AdCampaigns", prefix = "ad_" },
	{ name = "Social", prefix = "" }, -- подарки: id уже gift_<предмет>
	{ name = "Season", prefix = "" },
	{ name = "Console", prefix = "" },
	{ name = "Construction", prefix = "" },
	{ name = "Training", prefix = "" },
	{ name = "Skins", prefix = "skin_" },
	{ name = "Posters", prefix = "poster_" },
	{ name = "Mascots", prefix = "mascot_" },
	{ name = "FurnitureStyles", prefix = "style_" },
	{ name = "InteriorFinishes", prefix = "finish_" },
}

local function collectProducts(
	map: { [number]: ProductInfo },
	node: any,
	key: string,
	prefix: string,
	depth: number
)
	if type(node) ~= "table" or depth > 5 then
		return
	end
	local productId = node.productId
	if type(productId) == "number" and productId > 0 then
		if not map[productId] then
			local id = if type(node.id) == "string" then node.id else key
			local robux = node.robuxPrice
			map[productId] = { key = prefix .. id, robux = if type(robux) == "number" then robux else 0 }
		end
		return
	end
	for childKey, child in node do
		if type(child) == "table" then
			-- Сделки дня (Products.deals) — те же товары со своими productId: deal_<ключ>
			local childPrefix = if childKey == "deals" then prefix .. "deal_" else prefix
			collectProducts(
				map,
				child,
				if type(childKey) == "string" then childKey else key,
				childPrefix,
				depth + 1
			)
		end
	end
end

local function productInfo(productId: number): ProductInfo
	local map = productById
	if not map then
		local built: { [number]: ProductInfo } = {}
		for _, entry in PRODUCT_CONFIGS do
			local module = Shared.Config:FindFirstChild(entry.name)
			if module and module:IsA("ModuleScript") then
				local ok, config = pcall(require, module)
				if ok then
					collectProducts(built, config, entry.name, entry.prefix, 0)
				end
			end
		end
		productById = built
		map = built
	end
	return (map :: { [number]: ProductInfo })[productId] or { key = "product" .. productId, robux = 0 }
end

-- Начало выдачи по квитанции: все DataService.addCash в этом потоке до endReceipt — IAP с ключом товара
function Analytics.beginReceipt(productId: number)
	if Config.enabled then
		local ok, info = pcall(productInfo, productId)
		if ok then
			receiptByThread[coroutine.running()] = info
		end
	end
end

-- Конец выдачи. granted — товар выдан (новая квитанция, не повтор): ProductPurchased с ключом и ценой
function Analytics.endReceipt(player: Player, productId: number, granted: boolean)
	local thread = coroutine.running()
	local info = receiptByThread[thread]
	receiptByThread[thread] = nil
	if granted and Config.enabled and ensureState(player) then
		info = info or productInfo(productId)
		logCustom(player, Config.events.product, info.robux, info.key)
	end
end

-- ===== Игроки =====

local function watchSeat(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Seated:Connect(function(active: boolean)
			if active then
				-- SeatPart выставляется в том же кадре; проверяем после
				task.defer(poll, player)
			end
		end)
	end
end

local function onPlayerAdded(player: Player)
	if watched[player] then
		return
	end
	local deadline = os.clock() + PROFILE_WAIT_LIMIT
	local profile = DataService.get(player)
	while not profile and player.Parent and os.clock() < deadline do
		task.wait(PROFILE_WAIT)
		profile = DataService.get(player)
	end
	if not profile or not player.Parent or watched[player] or not ensureState(player) then
		return
	end
	watched[player] = true
	poll(player)
	player.CharacterAdded:Connect(function(character)
		watchSeat(player, character)
	end)
	if player.Character then
		task.spawn(watchSeat, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	-- poll здесь не зовём: он пишет funnel в профиль параллельно с closeProfile (гонка), а
	-- пропущенный шаг и так дошлётся при следующем входе
	watched[player] = nil
	finalFlush = true
	pcall(flushEconomy, player)
	finalFlush = false
	states[player] = nil
end

local function onGamePassPurchased(player: Player, gamePassId: number, wasPurchased: boolean)
	if not wasPurchased or not states[player] then
		return
	end
	local label: string? = nil
	for _, pass in GamePasses.list do
		if pass.gamePassId == gamePassId then
			label = pass.id
		end
	end
	-- Только подтверждённые покупки: ждём, пока ShopService перепроверит владение у Roblox
	if not label then
		return
	end
	task.delay(3, function()
		local shop = script.Parent:FindFirstChild("ShopService")
		local okOwns, owns = pcall(function()
			return shop and (require(shop) :: any).ownsPass(player, label)
		end)
		if okOwns and owns == true and states[player] then
			logCustom(player, Config.events.gamePass, 1, label :: string)
		end
	end)
end

-- Быстрое событие разработки (QuickEventService): вид и результат одним полем
function Analytics.logQuickEvent(player: Player, kind: string, grade: string)
	if Config.enabled and states[player] then
		logCustom(player, Config.events.quickEvent, 1, kind .. "_" .. grade)
	end
end

-- Получено достижение (AchievementService): id одним полем
function Analytics.logAchievement(player: Player, id: string)
	if Config.enabled and states[player] then
		logCustom(player, Config.events.achievement, 1, id)
	end
end

-- Подарок за Robux (GiftService): toFriend = false — получатель ушёл, предмет достался покупателю
function Analytics.logGift(player: Player, giftId: string, toFriend: boolean)
	if Config.enabled and states[player] then
		logCustom(player, Config.events.gift, if toFriend then 1 else 0, giftId)
	end
end

-- Награда за вступление в группу (SocialService)
function Analytics.logGroupReward(player: Player)
	if Config.enabled and states[player] then
		logCustom(player, Config.events.groupReward, 1, "group")
	end
end

-- Предложение доната (OfferService): вид и этап (shown / clicked / purchased) одним полем
function Analytics.logOffer(player: Player, kind: string, stage: string)
	if Config.enabled and states[player] then
		logCustom(player, Config.events.offer, 1, kind .. "_" .. stage)
	end
end

-- Приставы забрали предмет (BailiffService): поле — id предмета, значение — выручка
function Analytics.logSeizure(player: Player, itemId: string, value: number)
	if Config.enabled and states[player] then
		logCustom(player, Config.events.seizure, value, itemId)
	end
end

-- Активирован промокод (CodeService)
function Analytics.logCode(player: Player, code: string)
	if Config.enabled and states[player] then
		logCustom(player, Config.events.code, 1, code)
	end
end

-- Куплен маскот (MascotService): how — "cash" или "robux"
function Analytics.logMascot(player: Player, mascotId: string, how: string)
	if Config.enabled and states[player] then
		logCustom(player, Config.events.mascot, 1, mascotId .. "_" .. how)
	end
end

-- Куплен стиль мебели (FurnitureStyleService): how — "cash" или "robux"
function Analytics.logFurnitureStyle(player: Player, styleId: string, how: string)
	if Config.enabled and states[player] then
		logCustom(player, Config.events.furnitureStyle, 1, styleId .. "_" .. how)
	end
end

-- Куплена отделка студии (InteriorFinishService, только за Robux)
function Analytics.logInteriorFinish(player: Player, finishId: string)
	if Config.enabled and states[player] then
		logCustom(player, Config.events.interiorFinish, 1, finishId)
	end
end

-- Событие компании (CompanyEventService): id и этап одним полем
function Analytics.logCompanyEvent(player: Player, id: string, stage: string)
	if Config.enabled and states[player] then
		logCustom(player, Config.events.companyEvent, 1, id .. "_" .. stage)
	end
end

-- Сезон, гейм-джем, хакатон (SeasonService, GameJamService, HackathonService): ключ из Config.events
function Analytics.logLiveOps(player: Player, eventKey: string, value: number, field: string?)
	local name = (Config.events :: any)[eventKey]
	if Config.enabled and states[player] and type(name) == "string" then
		logCustom(player, name, value, field)
	end
end

-- Франшизы, контракты, обгон конкурента (FranchiseService, ContractService, RivalService):
-- eventKey — ключ Config.events, field — этап или id
function Analytics.logDepth(player: Player, eventKey: string, field: string)
	local eventName = (Config.events :: any)[eventKey]
	if Config.enabled and states[player] and type(eventName) == "string" then
		logCustom(player, eventName, 1, field)
	end
end

function Analytics.start()
	if not Config.enabled then
		return
	end
	wrapDataService()

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Участок пересобран (гараж, апгрейд, переезд, Rebirth): проверить шаги сразу, не ждать опроса
	PlotService.plotChanged:Connect(function(player: Player)
		task.defer(poll, player)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		pcall(onGamePassPurchased, player, gamePassId, wasPurchased)
	end)
	task.spawn(function()
		while true do
			task.wait(Config.pollSeconds)
			for player in states do
				task.spawn(poll, player)
			end
		end
	end)

	-- Сервер закрывается: остаток экономики всех игроков, пока их состояние ещё есть
	game:BindToClose(function()
		finalFlush = true
		for player in states do
			pcall(flushEconomy, player)
		end
		finalFlush = false
	end)

	task.spawn(function()
		while true do
			task.wait(Config.economyFlushSeconds)
			for player in states do
				local ok, err = pcall(flushEconomy, player)
				if not ok then
					warnOnce("economy flush failed", err)
				end
			end
		end
	end)
end

return Analytics
