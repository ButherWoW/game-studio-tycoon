--!strict
-- Биржа (Config/Stocks, роадмап 7.2–7.4): IPO студии, покупка/продажа акций, дивиденды, банкротство.
-- Компании — общий DataStore StockMarket_v1 (ключ c_<userId>), список — OrderedDataStore по стоимости.
-- Запись компании пишет только сервер владельца (доход, средняя оценка, основа цены); число
-- проданных акций (sold) меняют сделки на любом сервере через UpdateAsync.
-- Цена акции = основа × рыночный шум (StockNoise) — одинаково на всех серверах.
-- Данные игрока — (profile :: any).stocks = { listed, listedAt, recent = { оценки }, holdings }.
-- holdings[tostring(companyId)] = { shares, cost, listedAt } — listedAt компании на момент покупки:
-- после банкротства и нового IPO старые акции не оживают.
-- Хуки DevelopmentService: onGameReleased(player, score), revenueMultiplier(player).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stocks = require(Shared.Config.Stocks)
local StockRemotes = require(Shared.StockRemotes)
local StudioLayout = require(Shared.StudioLayout)
local Upgrades = require(Shared.Config.Upgrades)
local DataService = require(script.Parent.DataService)
local StockNoise = require(script.Parent.StockNoise)

local STORE_NAME = "StockMarket_v1"
local BOARD_NAME = "StockMarketCap_v1"
local TICK = 5
local REQUEST_COOLDOWN = 0.5
local RECORD_CACHE_SECONDS = 60
-- Бюджет GetAsync общий для всего сервера (60 + 10 × игроков в минуту): дивиденды и список биржи
-- читают десятки компаний. Осталось меньше резерва — обычное чтение берёт кэш (даже старый),
-- чтобы загрузка профилей, холдинги и лайки не упёрлись в лимит. Сделки (fresh) читают всегда
local GET_BUDGET_RESERVE = 60
-- Список компаний обновляем, только если биржу открывали недавно
local LIST_IDLE_SECONDS = 300

type Record = {
	id: number,
	name: string,
	owner: string,
	income: number,
	offline: number,
	avg: number,
	base: number,
	sold: number,
	listedAt: number,
	updatedAt: number,
	delisted: boolean?,
}
type Holding = { shares: number, cost: number, listedAt: number }
type StockData = {
	listed: boolean,
	listedAt: number,
	recent: { number },
	holdings: { [string]: Holding },
}

local StockService = {}

local store: DataStore? = nil
local board: OrderedDataStore? = nil
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(STORE_NAME)
		board = DataStoreService:GetOrderedDataStore(BOARD_NAME)
	end)
	if not ok then
		warn("[StockService] DataStore недоступен:", err)
		store = nil
		board = nil
	end
end

local cache: { [number]: { record: Record?, at: number } } = {}
local listIds: { number } = {}
local listAt = -math.huge
local lastOpened = -math.huge
local lastRequest: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
local lastOwnerWrite: { [Player]: number } = {}
local negativeSince: { [Player]: number } = {}
local dividendRest: { [Player]: number } = {}
local lastDividend = os.clock()

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end

local function analytics(player: Player, stage: string, value: number)
	local service = optional("AnalyticsService")
	if service and type(service.logLiveOps) == "function" then
		pcall(service.logLiveOps, player, "stock", value, stage)
	end
end

local function noteNonEarned(player: Player, amount: number)
	local reward = optional("RewardService")
	if reward and type(reward.noteNonEarned) == "function" then
		pcall(reward.noteNonEarned, player, amount)
	end
end

local function noteExpense(player: Player, amount: number)
	local reward = optional("RewardService")
	if reward and type(reward.noteExpense) == "function" then
		pcall(reward.noteExpense, player, amount)
	end
end

local function key(id: number): string
	return "c_" .. id
end

local function dataOf(profile: DataService.Profile): StockData
	local raw = (profile :: any).stocks
	if type(raw) ~= "table" then
		raw = {};
		(profile :: any).stocks = raw
	end
	raw.listed = raw.listed == true
	raw.listedAt = tonumber(raw.listedAt) or 0
	if type(raw.recent) ~= "table" then
		raw.recent = {}
	end
	if type(raw.holdings) ~= "table" then
		raw.holdings = {}
	end
	return raw :: StockData
end

local function sanitize(raw: any, id: number): Record?
	if type(raw) ~= "table" then
		return nil
	end
	return {
		id = id,
		name = if type(raw.name) == "string" then raw.name else "?",
		owner = if type(raw.owner) == "string" then raw.owner else "?",
		income = math.max(tonumber(raw.income) or 0, 0),
		offline = math.max(tonumber(raw.offline) or 0, 0),
		avg = math.max(tonumber(raw.avg) or 0, 0),
		base = math.max(tonumber(raw.base) or Stocks.minPrice, Stocks.minPrice),
		sold = math.clamp(math.floor(tonumber(raw.sold) or 0), 0, Stocks.totalShares),
		listedAt = tonumber(raw.listedAt) or 0,
		updatedAt = tonumber(raw.updatedAt) or 0,
		delisted = raw.delisted == true,
	}
end

-- Запись компании (fresh — мимо кэша, для сделок)
local function getRecord(id: number, fresh: boolean?): Record?
	local cached = cache[id]
	if not fresh and cached and os.clock() - cached.at < RECORD_CACHE_SECONDS then
		return cached.record
	end
	if not store then
		return nil
	end
	if not fresh then
		local okBudget, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
		end)
		if okBudget and budget < GET_BUDGET_RESERVE then
			return if cached then cached.record else nil
		end
	end
	local ok, raw = pcall(function()
		return (store :: DataStore):GetAsync(key(id))
	end)
	if not ok then
		return if cached then cached.record else nil
	end
	local record = sanitize(raw, id)
	cache[id] = { record = record, at = os.clock() }
	return record
end

-- Изменить запись атомарно; mutate возвращает false — отмена. Возвращает новую запись или nil
local function updateRecord(id: number, mutate: (Record?) -> (Record?, boolean)): Record?
	if not store then
		return nil
	end
	local result: Record? = nil
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(id), function(raw: any): any
			local record, accept = mutate(sanitize(raw, id))
			if not accept or not record then
				result = nil
				return nil
			end
			result = record
			return record
		end)
	end)
	if not ok then
		warn("[StockService] UpdateAsync failed:", err)
		return nil
	end
	if result then
		cache[id] = { record = result, at = os.clock() }
	end
	return result
end

local function writeBoard(record: Record)
	if not board then
		return
	end
	pcall(function()
		if record.delisted then
			(board :: OrderedDataStore):RemoveAsync(tostring(record.id))
		else
			-- Стоимость компании в тысячах $ (OrderedDataStore — целые до 2^63)
			local value = math.floor(record.base * Stocks.totalShares / 1000);
			(board :: OrderedDataStore):SetAsync(tostring(record.id), value)
		end
	end)
end

local function priceNow(record: Record): number
	return StockNoise.price(record.id, record.base, os.time())
end

-- Доход компании, по которому платятся дивиденды: владелец давно не обновлял запись — он не в игре
local function liveIncome(record: Record): number
	if os.time() - record.updatedAt > Stocks.ownerOfflineAfter then
		return record.offline
	end
	return record.income
end

local function average(list: { number }): number
	if #list == 0 then
		return 0
	end
	local sum = 0
	for _, v in list do
		sum += v
	end
	return sum / #list
end

local function incomePerMinute(player: Player, profile: DataService.Profile): number
	local shop = optional("ShopService")
	if shop and type(shop.incomePerMinute) == "function" then
		local ok, value = pcall(shop.incomePerMinute, player, profile)
		if ok and type(value) == "number" and value == value then
			return value
		end
	end
	return 0
end

local function offlinePerMinute(profile: DataService.Profile): number
	local offline = optional("OfflineService")
	if offline and type(offline.earnings) == "function" then
		local ok, value = pcall(offline.earnings, profile, 3600)
		if ok and type(value) == "number" and value == value then
			return math.max(value / 60, 0)
		end
	end
	return 0
end

-- Весь интерьер текущего этапа куплен (как PlotService: всё, кроме переездов)
local function interiorComplete(profile: DataService.Profile): boolean
	for _, upgrade in Upgrades do
		if
			not upgrade.move
			and StudioLayout.isVisible(upgrade, profile.studioLevel)
			and not profile.upgrades[upgrade.id]
		then
			return false
		end
	end
	return true
end

-- Условия IPO для окна и проверки на сервере
local function ipoStatus(player: Player, profile: DataService.Profile)
	local data = dataOf(profile)
	local ipo = Stocks.ipo
	local income = incomePerMinute(player, profile)
	local avg = average(data.recent)
	local checks = {
		level = profile.studioLevel >= ipo.requiresLevel,
		interior = profile.studioLevel >= ipo.requiresLevel and interiorComplete(profile),
		income = income >= ipo.minIncomePerMinute,
		avg = #data.recent >= ipo.recentGames and avg >= ipo.minAvgScore,
		cash = profile.cash >= ipo.cost,
	}
	local ready = not data.listed
		and checks.level
		and checks.interior
		and checks.income
		and checks.avg
		and checks.cash
	return {
		listed = data.listed,
		ready = ready,
		cost = ipo.cost,
		income = math.floor(income),
		needIncome = ipo.minIncomePerMinute,
		avg = math.floor(avg * 10 + 0.5) / 10,
		games = #data.recent,
		needAvg = ipo.minAvgScore,
		needGames = ipo.recentGames,
		checks = checks,
	}
end

local function studioName(player: Player, profile: DataService.Profile): string
	local name = (profile :: any).studioName
	return if type(name) == "string" and name ~= "" then name else player.DisplayName
end

-- Свежие данные компании владельца в запись (sold не трогаем — его меняют сделки)
local function ownerSnapshot(player: Player, profile: DataService.Profile): (number, number, number, number)
	local data = dataOf(profile)
	local income = incomePerMinute(player, profile)
	local avg = average(data.recent)
	return income, offlinePerMinute(profile), avg, Stocks.priceFor(income, avg)
end

local function writeOwner(player: Player, profile: DataService.Profile)
	local data = dataOf(profile)
	if not data.listed then
		return
	end
	lastOwnerWrite[player] = os.clock()
	local income, offline, avg, base = ownerSnapshot(player, profile)
	local name = studioName(player, profile)
	local record = updateRecord(player.UserId, function(old)
		if not old or old.delisted or old.listedAt ~= data.listedAt then
			return nil, false
		end
		old.name = name
		old.owner = player.DisplayName
		old.income = income
		old.offline = offline
		old.avg = avg
		old.base = base
		old.updatedAt = os.time()
		return old, true
	end)
	if record then
		writeBoard(record)
	end
end

local function notice(player: Player, message: string, params: any?)
	StockRemotes.StockState:FireClient(player, { message = message, params = params })
end

-- Компания владельца обанкротилась: снять с биржи, акции держателей сгорают
local function delist(player: Player, profile: DataService.Profile)
	local data = dataOf(profile)
	local listedAt = data.listedAt
	data.listed = false
	player:SetAttribute("StockListed", false)
	local record = updateRecord(player.UserId, function(old)
		if not old or old.listedAt ~= listedAt then
			return nil, false
		end
		old.delisted = true
		old.updatedAt = os.time()
		return old, true
	end)
	if record then
		writeBoard(record)
	end
	analytics(player, "bankrupt", 1)
	notice(player, "stock_bankrupt_owner")
end

-- Акция потеряна (компания снята с биржи или вышла заново): убрать из портфеля
local function burn(player: Player, data: StockData, idText: string, name: string)
	local holding = data.holdings[idText]
	data.holdings[idText] = nil
	dividendRest[player] = dividendRest[player] or 0
	if holding then
		notice(player, "stock_bankrupt_holder", { name = name, money = holding.cost })
	end
end

local function holdingValid(holding: Holding, record: Record?): boolean
	return record ~= nil and not record.delisted and record.listedAt == holding.listedAt
end

-- Сверить портфель с биржей: сгоревшие акции убрать
local function checkPortfolio(player: Player, data: StockData)
	for idText, holding in data.holdings do
		local id = tonumber(idText)
		if id then
			local record = getRecord(id)
			if record and not holdingValid(holding, record) then
				burn(player, data, idText, record.name)
			end
		end
	end
end

local function refreshList()
	if not board or os.clock() - listAt < Stocks.listRefreshSeconds then
		return
	end
	listAt = os.clock()
	local ok, pages = pcall(function()
		return (board :: OrderedDataStore):GetSortedAsync(false, Stocks.listSize)
	end)
	if not ok then
		return
	end
	local ids = {}
	for _, entry in (pages :: DataStorePages):GetCurrentPage() do
		local id = tonumber(entry.key)
		if id then
			table.insert(ids, id)
		end
	end
	listIds = ids
end

local function companyView(record: Record, now: number)
	local price = StockNoise.price(record.id, record.base, now)
	local dayAgo = StockNoise.price(record.id, record.base, now - 24 * 60 * 60)
	local income = liveIncome(record)
	return {
		id = record.id,
		name = record.name,
		owner = record.owner,
		price = price,
		change = if dayAgo > 0 then math.floor((price / dayAgo - 1) * 1000 + 0.5) / 10 else 0,
		income = math.floor(income),
		avg = math.floor(record.avg * 10 + 0.5) / 10,
		available = Stocks.totalShares - record.sold,
		dividend = Stocks.dividendPerMinute(income, 1),
		online = os.time() - record.updatedAt <= Stocks.ownerOfflineAfter,
	}
end

local function sendState(player: Player, selected: number?)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = dataOf(profile)
	lastOpened = os.clock()
	refreshList()
	checkPortfolio(player, data)
	local now = os.time()
	local seen: { [number]: boolean } = {}
	local companies = {}
	local function add(id: number)
		if seen[id] then
			return
		end
		seen[id] = true
		local record = getRecord(id)
		if record and not record.delisted then
			table.insert(companies, companyView(record, now))
		end
	end
	for _, id in listIds do
		add(id)
	end
	for idText in data.holdings do
		local id = tonumber(idText)
		if id then
			add(id)
		end
	end
	if data.listed then
		add(player.UserId)
	end
	local portfolio = {}
	for idText, holding in data.holdings do
		local id = tonumber(idText)
		local record = if id then getRecord(id) else nil
		if record and holdingValid(holding, record) then
			local price = priceNow(record)
			table.insert(portfolio, {
				id = record.id,
				name = record.name,
				shares = holding.shares,
				cost = holding.cost,
				value = price * holding.shares,
				dividend = Stocks.dividendPerMinute(liveIncome(record), holding.shares),
			})
		end
	end
	local candles = nil
	if type(selected) == "number" then
		local record = getRecord(selected)
		if record and not record.delisted then
			candles = StockNoise.candles(record.id, record.base, now, record.listedAt)
		end
	end
	StockRemotes.StockState:FireClient(player, {
		available = store ~= nil,
		companies = companies,
		portfolio = portfolio,
		ipo = ipoStatus(player, profile),
		selected = selected,
		candles = candles,
		you = player.UserId,
	})
end

local function throttled(player: Player): boolean
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return true
	end
	lastRequest[player] = now
	return false
end

local function validShares(value: any): number?
	if type(value) ~= "number" or value ~= value or value < 1 or value > Stocks.maxSharesPerCompany then
		return nil
	end
	return math.floor(value)
end

local function withLock(player: Player, fn: () -> ())
	if busy[player] then
		return
	end
	busy[player] = true
	local ok, err = pcall(fn)
	busy[player] = nil
	if not ok then
		warn("[StockService] action failed:", err)
	end
end

local function buy(player: Player, id: any, amount: any)
	local shares = validShares(amount)
	if type(id) ~= "number" or id ~= id or not shares or throttled(player) then
		return
	end
	id = math.floor(id)
	withLock(player, function()
		local profile = DataService.get(player)
		if not profile or id == player.UserId then
			return
		end
		local data = dataOf(profile)
		local idText = tostring(id)
		local holding = data.holdings[idText]
		local count = 0
		for _ in data.holdings do
			count += 1
		end
		if not holding and count >= Stocks.maxCompaniesInPortfolio then
			notice(player, "stock_err_portfolio", { count = Stocks.maxCompaniesInPortfolio })
			return
		end
		local record = getRecord(id, true)
		if not record or record.delisted then
			notice(player, "stock_err_gone")
			return
		end
		if holding and not holdingValid(holding, record) then
			burn(player, data, idText, record.name)
			holding = nil
		end
		local owned = if holding then holding.shares else 0
		if owned + shares > Stocks.maxSharesPerCompany then
			notice(player, "stock_err_max", { shares = Stocks.maxSharesPerCompany })
			return
		end
		local price = priceNow(record)
		local cost = Stocks.buyCost(price, shares)
		if profile.cash < cost then
			notice(player, "stock_err_cash")
			return
		end
		local listedAt = record.listedAt
		local updated = updateRecord(id, function(old)
			if
				not old
				or old.delisted
				or old.listedAt ~= listedAt
				or old.sold + shares > Stocks.totalShares
			then
				return nil, false
			end
			old.sold += shares
			return old, true
		end)
		if not updated then
			notice(player, "stock_err_gone")
			return
		end
		if not DataService.trySpend(player, cost) then
			updateRecord(id, function(old)
				if not old then
					return nil, false
				end
				old.sold = math.max(old.sold - shares, 0)
				return old, true
			end)
			notice(player, "stock_err_cash")
			return
		end
		noteExpense(player, cost)
		data.holdings[idText] = {
			shares = owned + shares,
			cost = (if holding then holding.cost else 0) + cost,
			listedAt = listedAt,
		}
		analytics(player, "buy", cost)
		notice(player, "stock_bought", { shares = shares, name = record.name, money = cost })
	end)
	sendState(player, id)
end

-- Деньги за проданные акции (имя функции — источник в Config/Analytics.sources)
local function sell(player: Player, amount: number)
	DataService.addCash(player, amount)
	noteNonEarned(player, amount)
end

local function onSell(player: Player, id: any, amount: any)
	local shares = validShares(amount)
	if type(id) ~= "number" or id ~= id or not shares or throttled(player) then
		return
	end
	id = math.floor(id)
	withLock(player, function()
		local profile = DataService.get(player)
		if not profile then
			return
		end
		local data = dataOf(profile)
		local idText = tostring(id)
		local holding = data.holdings[idText]
		if not holding then
			return
		end
		local record = getRecord(id, true)
		if not record or not holdingValid(holding, record) then
			burn(player, data, idText, if record then record.name else "?")
			return
		end
		shares = math.min(shares, holding.shares)
		local price = priceNow(record)
		local payout = Stocks.sellPayout(price, shares)
		local listedAt = holding.listedAt
		local updated = updateRecord(id, function(old)
			if not old or old.delisted or old.listedAt ~= listedAt then
				return nil, false
			end
			old.sold = math.max(old.sold - shares, 0)
			return old, true
		end)
		if not updated then
			return
		end
		local left = holding.shares - shares
		if left <= 0 then
			data.holdings[idText] = nil
		else
			-- Цена покупки уменьшается пропорционально — прибыль/убыток остатка честный
			holding.cost = math.floor(holding.cost * left / holding.shares)
			holding.shares = left
		end
		sell(player, payout)
		analytics(player, "sell", payout)
		notice(player, "stock_sold", { shares = shares, name = record.name, money = payout })
	end)
	sendState(player, id)
end

local function onIpo(player: Player)
	if throttled(player) then
		return
	end
	withLock(player, function()
		local profile = DataService.get(player)
		if not profile or not store then
			return
		end
		local status = ipoStatus(player, profile)
		if not status.ready or not DataService.trySpend(player, Stocks.ipo.cost) then
			return
		end
		noteExpense(player, Stocks.ipo.cost)
		local data = dataOf(profile)
		local now = os.time()
		local income, offline, avg, base = ownerSnapshot(player, profile)
		local name = studioName(player, profile)
		local record = updateRecord(player.UserId, function(old)
			-- Уже на бирже (другой сервер) — второй раз не выходим
			if old and not old.delisted then
				return nil, false
			end
			return {
				id = player.UserId,
				name = name,
				owner = player.DisplayName,
				income = income,
				offline = offline,
				avg = avg,
				base = base,
				sold = 0,
				listedAt = now,
				updatedAt = now,
				delisted = false,
			},
				true
		end)
		if not record then
			DataService.addCash(player, Stocks.ipo.cost)
			return
		end
		data.listed = true
		data.listedAt = now
		player:SetAttribute("StockListed", true)
		writeBoard(record)
		listAt = -math.huge
		analytics(player, "ipo", Stocks.ipo.cost)
		notice(player, "stock_ipo_done", { name = name })
		DataService.save(player)
	end)
	sendState(player, player.UserId)
end

-- Дивиденды (имя функции — источник в Config/Analytics.sources)
local function dividends(player: Player, amount: number)
	DataService.addCash(player, amount)
	noteNonEarned(player, amount)
end

local function payDividends(player: Player, minutes: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = dataOf(profile)
	local total = dividendRest[player] or 0
	for idText, holding in data.holdings do
		local id = tonumber(idText)
		local record = if id then getRecord(id) else nil
		if record then
			if holdingValid(holding, record) then
				total += Stocks.dividendPerMinute(liveIncome(record), holding.shares) * minutes
			else
				burn(player, data, idText, record.name)
			end
		end
	end
	local whole = math.floor(total)
	dividendRest[player] = total - whole
	if whole > 0 then
		dividends(player, whole)
		player:SetAttribute("StockDividend", whole)
	end
end

local function step(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = dataOf(profile)
	player:SetAttribute("StockListed", data.listed)
	if data.listed then
		-- Банкротство: баланс в минусе слишком долго
		if profile.cash < 0 then
			negativeSince[player] = negativeSince[player] or os.clock()
			local left = Stocks.bankruptAfterSeconds - (os.clock() - (negativeSince[player] :: number))
			player:SetAttribute("StockBankruptIn", math.max(math.ceil(left), 0))
			if left <= 0 then
				negativeSince[player] = nil
				player:SetAttribute("StockBankruptIn", nil)
				delist(player, profile)
				return
			end
		else
			negativeSince[player] = nil
			player:SetAttribute("StockBankruptIn", nil)
		end
		if os.clock() - (lastOwnerWrite[player] or -math.huge) >= Stocks.updateSeconds then
			writeOwner(player, profile)
		end
	end
	local ready = ipoStatus(player, profile).ready
	player:SetAttribute("StockIpoReady", ready)
end

-- Хук DevelopmentService: оценка игры — в список последних (средняя для IPO и цены)
function StockService.onGameReleased(player: Player, score: number)
	local profile = DataService.get(player)
	if not profile or type(score) ~= "number" or score ~= score then
		return
	end
	local data = dataOf(profile)
	table.insert(data.recent, math.clamp(score, 0, 10))
	while #data.recent > Stocks.ipo.recentGames do
		table.remove(data.recent, 1)
	end
end

-- Хук DevelopmentService: компания на бирже получает бонус к доходу
function StockService.revenueMultiplier(player: Player): number
	local profile = DataService.get(player)
	if profile and dataOf(profile).listed then
		return 1 + Stocks.ipo.incomeBonus
	end
	return 1
end

-- Только Studio (DebugService → StudioDebug "call"): тестовая компания и сделки без второго игрока
if game:GetService("RunService"):IsStudio() then
	function StockService.debugCreate(id: number, income: number, avg: number): string
		local now = os.time()
		local record = updateRecord(id, function()
			return {
				id = id,
				name = "Test Corp " .. id,
				owner = "Studio",
				income = income,
				offline = income * 0.3,
				avg = avg,
				base = Stocks.priceFor(income, avg),
				sold = 0,
				listedAt = now,
				updatedAt = now,
				delisted = false,
			},
				true
		end)
		if record then
			writeBoard(record)
			listAt = -math.huge
		end
		return if record then "created " .. record.base else "failed"
	end
	function StockService.debugDelist(id: number): string
		local record = updateRecord(id, function(old)
			if not old then
				return nil, false
			end
			old.delisted = true
			return old, true
		end)
		if record then
			writeBoard(record)
		end
		return if record then "delisted" else "failed"
	end
	function StockService.debugBuy(player: Player, id: number, shares: number)
		lastRequest[player] = nil
		buy(player, id, shares)
	end
	function StockService.debugSell(player: Player, id: number, shares: number)
		lastRequest[player] = nil
		onSell(player, id, shares)
	end
	function StockService.debugDividends(player: Player, minutes: number)
		payDividends(player, minutes)
	end
	function StockService.debugRecord(id: number): any
		return getRecord(id, true)
	end
end

function StockService.start()
	StockRemotes.StockRequest.OnServerEvent:Connect(function(player, selected)
		if throttled(player) then
			return
		end
		local id = if type(selected) == "number" and selected == selected then math.floor(selected) else nil
		sendState(player, id)
	end)
	StockRemotes.StockBuy.OnServerEvent:Connect(buy)
	StockRemotes.StockSell.OnServerEvent:Connect(onSell)
	StockRemotes.StockIpo.OnServerEvent:Connect(onIpo)
	Players.PlayerRemoving:Connect(function(player)
		local profile = DataService.get(player)
		if profile and dataOf(profile).listed then
			pcall(writeOwner, player, profile)
		end
		lastRequest[player] = nil
		busy[player] = nil
		lastOwnerWrite[player] = nil
		negativeSince[player] = nil
		dividendRest[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(step, player)
				if not ok then
					warn("[StockService] step failed:", err)
				end
			end
			local elapsed = os.clock() - lastDividend
			if elapsed >= Stocks.dividendIntervalSeconds then
				lastDividend = os.clock()
				for _, player in Players:GetPlayers() do
					local ok, err = pcall(payDividends, player, elapsed / 60)
					if not ok then
						warn("[StockService] dividends failed:", err)
					end
				end
			end
			if os.clock() - lastOpened < LIST_IDLE_SECONDS then
				pcall(refreshList)
			end
		end
	end)
end

return StockService
