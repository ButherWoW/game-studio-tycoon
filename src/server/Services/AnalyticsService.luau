--!strict
-- Аналитика для запуска (задача 6.4): D1/D7 и «где отваливаются».
--   • Онбординг-воронка (LogOnboardingFunnelStepEvent): шаги из Config/Analytics.onboarding,
--     определяются опросом профиля/атрибутов, отправляются один раз за жизнь игрока
--     (отметки в (profile :: any).analytics.onboarding).
--   • Экономика (LogEconomyEvent): DataService.addCash/trySpend обёрнуты здесь же; источник
--     узнаём по вызвавшему сервису (debug.info), трату — по тому, что изменилось в профиле.
--     Копим по игроку и шлём сводкой раз в economyFlushSeconds.
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
local Products = require(Shared.Config.Products)
local AdCampaigns = require(Shared.Config.AdCampaigns)
local Upgrades = require(Shared.Config.Upgrades)
local Stages = require(Shared.Config.Stages)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

type Profile = DataService.Profile

type AnalyticsData = {
	onboarding: { [string]: boolean },
	-- Профиль был до аналитики (уже играл): онбординг не шлём, иначе воронку зальют старички
	legacy: boolean,
}

type Bucket = {
	flow: Enum.AnalyticsEconomyFlowType,
	transactionType: string,
	sku: string,
	amount: number,
}

type PlayerState = {
	rebirths: number,
	steals: number,
	caught: number,
	lastReceipt: string?, -- последняя квитанция в profile.receiptLog
	lang: any, -- язык на начало сессии
	langLogged: boolean,
	parkTouched: boolean, -- получил деньги с доски заказов/ломбарда (шаг онбординга)
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
local lastProductId: { [number]: number } = {} -- UserId → последний купленный productId (для подписи)

local isStudio = RunService:IsStudio()
local budgetWindow = os.clock()
local budgetUsed = 0
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
	if not takeBudget() then
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
		raw = { onboarding = {}, legacy = isLegacy(profile) }
		p.analytics = raw
	end
	if type(raw.onboarding) ~= "table" then
		raw.onboarding = {}
	end
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

local function lastReceipt(profile: Profile): string?
	local log = profile.receiptLog
	return if type(log) == "table" then log[#log] else nil
end

-- Сколько квитанций добавилось после known. receiptLog обрезается до 50 записей,
-- поэтому длину не сравниваем, ищем прошлую последнюю
local function newReceipts(profile: Profile, known: string?): number
	local log = profile.receiptLog
	if type(log) ~= "table" or #log == 0 or log[#log] == known then
		return 0
	end
	for index = #log, 1, -1 do
		if log[index] == known then
			return #log - index
		end
	end
	return 1
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

local detectors: { [string]: (Player, Profile, PlayerState) -> boolean } = {
	joined = function()
		return true
	end,
	laptop = function(player)
		return PlotService.isAtPc(player)
	end,
	firstRelease = function(_, profile)
		return profile.gamesReleased >= 1
	end,
	firstParkJob = function(_, profile, state)
		local p = profile :: any
		return state.parkTouched or num(p.cartridges) > 0 or hasAny(p.jobReadyAt)
	end,
	garage = function(_, profile)
		return (profile :: any).ownsGarage == true
	end,
	studioNamed = function(_, profile)
		local name = (profile :: any).studioName
		return type(name) == "string" and #name > 0
	end,
	firstUpgrade = function(_, profile)
		-- desk1 даётся бесплатно с гаражом — это не апгрейд
		return hasAny(profile.upgrades, "desk1")
	end,
	firstEmployee = function(_, profile)
		return hasAny((profile :: any).staff)
	end,
	office = function(_, profile)
		return profile.studioLevel >= 2
	end,
}

local function checkOnboarding(player: Player, profile: Profile, state: PlayerState)
	local data = dataOf(profile)
	if data.legacy then
		return
	end
	-- Шаги могут случиться не по порядку (заказ раньше первой игры) — шлём, как только достигнут:
	-- дашборд Roblox считает пропущенные ранние шаги пройденными
	for index, step in Config.onboarding do
		if data.onboarding[step.id] then
			continue
		end
		local detector = detectors[step.id]
		if detector and detector(player, profile, state) then
			local sent = emit(
				string.format("onboarding %d %s player=%d", index, step.name, player.UserId),
				function()
					AnalyticsService:LogOnboardingFunnelStepEvent(player, index, step.name)
				end
			)
			if not sent then
				return -- бюджет кончился: дошлём на следующем опросе
			end
			data.onboarding[step.id] = true
		end
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
	-- Новые квитанции Developer Products (их пишет MonetizationService до PurchaseGranted)
	local delta = newReceipts(profile, state.lastReceipt)
	if delta > 0 then
		state.lastReceipt = lastReceipt(profile)
		local productId = lastProductId[player.UserId]
		lastProductId[player.UserId] = nil
		local label = "unknown"
		if productId then
			label = tostring(productId)
			for _, product in Products.list do
				if product.productId == productId then
					label = product.id
				end
			end
			for _, campaign in AdCampaigns do
				if campaign.productId == productId then
					label = "ad_" .. campaign.id
				end
			end
		end
		logCustom(player, Config.events.product, delta, label)
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

-- ===== Экономика =====

local function addToBucket(
	player: Player,
	flow: Enum.AnalyticsEconomyFlowType,
	transactionType: string,
	sku: string,
	amount: number
)
	local state = states[player]
	if not state or amount <= 0 or amount ~= amount or amount == math.huge then
		return
	end
	local key = flow.Name .. "|" .. transactionType .. "|" .. sku
	local bucket = state.economy[key]
	if bucket then
		bucket.amount += amount
	else
		state.economy[key] = { flow = flow, transactionType = transactionType, sku = sku, amount = amount }
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
			local sent = amount <= 0
				or emit(
					string.format(
						"economy %s %s/%s %d balance=%d player=%d",
						bucket.flow.Name,
						bucket.transactionType,
						bucket.sku,
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
							fields("stage" .. stage) :: any
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

-- Имя модуля и функции на уровне level стека того, кто вызвал frame (1 — он сам, 2 — его вызвавший)
local function frame(level: number): (string?, string?)
	local source, name = debug.info(level + 1, "sn")
	if type(source) ~= "string" then
		return nil, nil
	end
	local module = source:match("([%w_]+)$")
	return module, if type(name) == "string" and name ~= "" then name else nil
end

-- Вызывается из обёртки addCash: module/fn — кто позвал DataService.addCash, outer — модуль уровнем выше
local function onSource(player: Player, amount: number, module: string?, fn: string?, outer: string?)
	if not module or Config.ignore[module] then
		return
	end
	if Config.passthrough[module] and outer then
		module = outer
		fn = nil
	end
	local state = states[player]
	if module == "StartParkService" and state then
		state.parkTouched = true
	end
	if module == "ExpoService" then
		logCustom(player, Config.events.expoWin, 1)
	end
	local tag = (fn and Config.sources[module .. "." .. fn]) or Config.sources[module :: string]
	local transactionType = if tag then tag.transactionType else "Other"
	local sku = if tag then tag.sku else module :: string
	addToBucket(player, Enum.AnalyticsEconomyFlowType.Source, transactionType, sku, amount)
end

local function snapshot(profile: Profile): SpendSnapshot
	local p = profile :: any
	local ad = profile.activeAd
	return {
		upgrades = keySet(profile.upgrades),
		genres = keySet(profile.unlockedGenres),
		topics = keySet(profile.unlockedTopics),
		staff = keySet(p.staff),
		studioLevel = profile.studioLevel,
		ownsGarage = p.ownsGarage == true,
		ad = ad,
		adExpires = if ad then ad.expiresAt else 0,
	}
end

-- Классифицировать трату по изменениям профиля (вызывается отложенно, после кода покупки)
local function classifySpend(player: Player, amount: number, module: string?, before: SpendSnapshot)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local p = profile :: any
	local sinks = Config.sinks
	local kind, sku = sinks.other, module or "unknown"
	if module == "HitService" then
		kind, sku = sinks.penalty, "caught"
	elseif module == "ExpensesService" then
		kind, sku = sinks.staff, "expenses"
	elseif p.ownsGarage == true and not before.ownsGarage then
		kind, sku = sinks.move, "garage"
	elseif profile.studioLevel > before.studioLevel then
		local stage = Stages[profile.studioLevel]
		kind, sku = sinks.move, if stage then stage.id else "stage" .. profile.studioLevel
	else
		local upgradeId = newKey(before.upgrades, profile.upgrades)
		local employeeId = newKey(before.staff, p.staff)
		local genreId = newKey(before.genres, profile.unlockedGenres)
		local topicId = newKey(before.topics, profile.unlockedTopics)
		local ad = profile.activeAd
		if upgradeId then
			local upgrade = upgradeById[upgradeId]
			kind, sku = if upgrade and upgrade.move then sinks.move else sinks.upgrade, upgradeId
		elseif employeeId then
			kind, sku = sinks.staff, employeeId
		elseif genreId then
			kind, sku = sinks.content, "genre_" .. genreId
		elseif topicId then
			kind, sku = sinks.content, "topic_" .. topicId
		elseif ad and (ad ~= before.ad or ad.expiresAt ~= before.adExpires) then
			kind, sku = sinks.ad, "ad_" .. math.floor(ad.bonus * 100)
		end
	end
	addToBucket(player, Enum.AnalyticsEconomyFlowType.Sink, kind, sku, amount)
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
		-- Стек: 1 — эта обёртка, 2 — кто позвал addCash, 3 — кто позвал его (для посредников).
		-- frame зовём напрямую, не из pcall: pcall добавил бы уровень в стек.
		-- debug.info на несуществующем уровне не бросает ошибку, а возвращает пусто
		local module, fn = frame(2)
		local outer = frame(3)
		local ok, err = pcall(onSource, player, amount, module, fn, outer)
		if not ok then
			warnOnce("addCash hook failed", err)
		end
	end

	service.trySpend = function(player: Player, amount: number): boolean
		local result = originalSpend(player, amount)
		if result and Config.enabled and type(amount) == "number" and amount > 0 then
			local module = frame(2)
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
					local okClassify, errClassify = pcall(classifySpend, player, amount, module, before)
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
	local deadline = os.clock() + PROFILE_WAIT_LIMIT
	local profile = DataService.get(player)
	while not profile and player.Parent and os.clock() < deadline do
		task.wait(PROFILE_WAIT)
		profile = DataService.get(player)
	end
	if not profile or not player.Parent or states[player] then
		return
	end
	local ok, err = pcall(function()
		dataOf(profile) -- legacy определяем сразу при входе, до любых действий
		local steals, caught = thiefStats(profile)
		states[player] = {
			rebirths = profile.rebirths,
			steals = steals,
			caught = caught,
			lastReceipt = lastReceipt(profile),
			lang = (profile :: any).lang,
			langLogged = false,
			parkTouched = false,
			balance = profile.cash,
			stage = profile.studioLevel,
			economy = {},
			economyOrder = {},
		}
	end)
	if not ok then
		warnOnce("player init failed", err)
		return
	end
	poll(player)
	player.CharacterAdded:Connect(function(character)
		watchSeat(player, character)
	end)
	if player.Character then
		task.spawn(watchSeat, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	pcall(poll, player)
	pcall(flushEconomy, player)
	states[player] = nil
	lastProductId[player.UserId] = nil
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
	-- Только чтобы подписать ProductPurchased: сам факт покупки берём из квитанций в профиле.
	-- Событие устаревшее — если его не станет, подпись будет "unknown", игра не пострадает
	pcall(function()
		MarketplaceService.PromptProductPurchaseFinished:Connect(
			function(userId: number, productId: number, isPurchased: boolean)
				if isPurchased then
					lastProductId[userId] = productId
				end
			end
		)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.pollSeconds)
			for player in states do
				task.spawn(poll, player)
			end
		end
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
