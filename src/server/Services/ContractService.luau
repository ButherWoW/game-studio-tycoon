--!strict
-- Контракты издателей (Config/Contracts). С этапа офиса раз в ~intervalSeconds — предложение
-- (только в памяти, ждёт offerSeconds). Принял — аванс сразу, активный контракт хранится в
-- profile.contracts.active, срок тикает, пока игрок в игре. Прогресс — хук DevelopmentService
-- после релиза. Провал — вернуть аванс × failRepayFactor: BailiffService.addDebt, если есть,
-- иначе в долг банка (profile.loanDebt, гасится долей дохода игр), а без банка — из денег,
-- остаток (owed) забирается половиной дохода следующих игр.
-- Данные: profile.contracts = { active = Contract?, done, failed, owed? }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Contracts = require(Shared.Config.Contracts)
local Rivals = require(Shared.Config.Rivals)
local Genres = require(Shared.Config.Genres)
local Topics = require(Shared.Config.Topics)
local Debug = require(Shared.Config.Debug)
local DepthRemotes = require(Shared.DepthRemotes)
local DataService = require(script.Parent.DataService)

export type Contract = {
	id: number,
	publisher: string, -- id студии (Config/Rivals)
	kind: Contracts.Kind,
	genreId: string?,
	topicId: string?,
	count: number,
	minScore: number,
	progress: number,
	seconds: number, -- срок целиком
	remaining: number, -- осталось секунд игры
	advance: number,
	bonus: number,
	expiresAt: number?, -- предложение: до какого os.time() ждёт ответа
}

type Data = { active: Contract?, done: number, failed: number, owed: number }

local TICK = 1
local REQUEST_COOLDOWN = 0.5
local OWED_SHARE = 0.5 -- без банка: доля дохода игры в погашение провала

local ContractService = {}
local offers: { [Player]: Contract } = {}
local nextOfferAt: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
local nextId = 0
local rng = Random.new()

local forced = RunService:IsStudio() and Debug.contractForceOffer == true
local FIRST_DELAY = if forced then 15 else Contracts.firstDelaySeconds
local MIN_STAGE = if forced then 1 else Contracts.minStage

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

local function logEvent(player: Player, stage: string)
	local analytics = optional("AnalyticsService")
	if analytics and type(analytics.logDepth) == "function" then
		pcall(analytics.logDepth, player, "contract", stage)
	end
end

local function num(value: any, default: number): number
	local n = tonumber(value)
	return if n and n == n and n > -math.huge and n < math.huge then n else default
end

local function sanitize(raw: any): Contract?
	if type(raw) ~= "table" or not Rivals.byId(raw.publisher) then
		return nil
	end
	local kind = raw.kind
	if kind ~= "genre" and kind ~= "topic" and kind ~= "score" then
		return nil
	end
	if kind == "genre" and not Genres[raw.genreId] then
		return nil
	end
	if kind == "topic" and not Topics[raw.topicId] then
		return nil
	end
	return {
		id = num(raw.id, 0),
		publisher = raw.publisher,
		kind = kind,
		genreId = if kind == "genre" then raw.genreId else nil,
		topicId = if kind == "topic" then raw.topicId else nil,
		count = math.max(math.floor(num(raw.count, 1)), 1),
		minScore = math.clamp(num(raw.minScore, 7), 1, 10),
		progress = math.max(math.floor(num(raw.progress, 0)), 0),
		seconds = math.max(num(raw.seconds, 60), 1),
		remaining = math.max(num(raw.remaining, 0), 0),
		advance = math.max(math.floor(num(raw.advance, 0)), 0),
		bonus = math.max(math.floor(num(raw.bonus, 0)), 0),
	}
end

local function data(profile: DataService.Profile): Data
	local raw = profile.contracts
	if type(raw) ~= "table" then
		raw = {}
	end
	local fixed: Data = {
		active = sanitize(raw.active),
		done = math.max(math.floor(num(raw.done, 0)), 0),
		failed = math.max(math.floor(num(raw.failed, 0)), 0),
		owed = math.max(math.floor(num(raw.owed, 0)), 0),
	}
	profile.contracts = fixed
	return fixed
end

-- Сохранения уже чинятся при первом обращении, дальше — прямой доступ
local function dataOf(profile: DataService.Profile): Data
	local raw = profile.contracts
	if type(raw) == "table" and raw.done ~= nil and raw.owed ~= nil then
		return raw :: Data
	end
	return data(profile)
end

local function incomePerMinute(player: Player, profile: DataService.Profile): number
	local shop = optional("ShopService")
	local ok, value = pcall(function()
		return shop and shop.incomePerMinute(player, profile)
	end)
	return if ok and type(value) == "number" then value else 0
end

local function noteNonEarned(player: Player, amount: number)
	local rewards = optional("RewardService")
	if rewards and type(rewards.noteNonEarned) == "function" then
		pcall(rewards.noteNonEarned, player, amount)
	end
end

local function noteExpense(player: Player, amount: number)
	local rewards = optional("RewardService")
	if rewards and type(rewards.noteExpense) == "function" then
		pcall(rewards.noteExpense, player, amount)
	end
end

local function publicView(c: Contract?): any
	if not c then
		return nil
	end
	local rival = Rivals.byId(c.publisher)
	local view = table.clone(c) :: any
	view.publisherName = if rival then rival.name else c.publisher
	view.publisherIcon = if rival then rival.icon else "📜"
	return view
end

function ContractService.pushState(player: Player)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	DepthRemotes.ContractState:FireClient(player, {
		offer = publicView(offers[player]),
		active = publicView(dataOf(profile).active),
		serverTime = os.time(),
		repayFactor = Contracts.failRepayFactor,
	})
end

-- Открытые игроку жанры/темы (сезонные темы — нет: большую часть года закрыты)
local function openIds(
	set: { [string]: boolean },
	source: { [string]: any },
	skipSeasonal: boolean
): { string }
	local ids = {}
	for id, open in set do
		if open and source[id] and not (skipSeasonal and source[id].seasonal) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

local function makeOffer(player: Player, profile: DataService.Profile): Contract?
	local template = Contracts.templates[rng:NextInteger(1, #Contracts.templates)]
	local genreId, topicId = nil, nil
	if template.kind == "genre" then
		local ids = openIds(profile.unlockedGenres, Genres, false)
		if #ids == 0 then
			return nil
		end
		genreId = ids[rng:NextInteger(1, #ids)]
	elseif template.kind == "topic" then
		local ids = openIds(profile.unlockedTopics, Topics, true)
		if #ids == 0 then
			return nil
		end
		topicId = ids[rng:NextInteger(1, #ids)]
	end
	local perMinute = incomePerMinute(player, profile)
	nextId += 1
	local seconds = template.minutes * 60
	return {
		id = nextId,
		publisher = Rivals.pick(rng:NextInteger(0, 1_000_000)).id,
		kind = template.kind,
		genreId = genreId,
		topicId = topicId,
		count = template.count,
		minScore = template.minScore,
		progress = 0,
		seconds = seconds,
		remaining = seconds,
		advance = math.max(math.floor(perMinute * Contracts.advanceMinutes), 1),
		bonus = math.max(math.floor(perMinute * Contracts.bonusMinutes), 1),
		expiresAt = os.time() + Contracts.offerSeconds,
	}
end

local function scheduleNext(player: Player)
	local interval = if forced
		then 60
		else Contracts.intervalSeconds + rng:NextNumber(
			-Contracts.intervalJitter,
			Contracts.intervalJitter
		)
	nextOfferAt[player] = os.clock() + interval
end

-- Провал: вернуть аванс × failRepayFactor. Сколько ушло в долг — для тоста
local function applyPenalty(player: Player, profile: DataService.Profile, d: Data, amount: number): number
	if amount <= 0 then
		return 0
	end
	-- Приставы (другая фича): если есть — свой учёт долга
	local bailiff = optional("BailiffService")
	if bailiff and type(bailiff.addDebt) == "function" then
		local ok = pcall(bailiff.addDebt, player, amount, "contract")
		if ok then
			return amount
		end
	end
	-- Долг банка (LoanService): гасится repayShare дохода каждой игры
	if optional("LoanService") then
		local p = profile :: any
		local debt = math.max(math.floor(tonumber(p.loanDebt) or 0), 0) + amount
		p.loanDebt = debt
		player:SetAttribute("LoanDebt", debt)
		return amount
	end
	-- Без банка: из денег, остаток — с дохода следующих игр
	local pay = math.min(amount, math.max(math.floor(profile.cash), 0))
	if pay > 0 and DataService.trySpend(player, pay) then
		noteExpense(player, pay)
	else
		pay = 0
	end
	d.owed += amount - pay
	return amount - pay
end

local function finish(player: Player, profile: DataService.Profile, d: Data, success: boolean)
	local c = d.active
	if not c then
		return
	end
	d.active = nil
	local rival = Rivals.byId(c.publisher)
	local name = if rival then rival.name else c.publisher
	if success then
		d.done += 1
		DataService.addCash(player, c.bonus)
		noteNonEarned(player, c.bonus)
		DepthRemotes.ContractResult:FireClient(
			player,
			{ result = "done", publisher = name, amount = c.bonus }
		)
		logEvent(player, "completed")
	else
		d.failed += 1
		local penalty = math.ceil(c.advance * Contracts.failRepayFactor)
		local debt = applyPenalty(player, profile, d, penalty)
		DepthRemotes.ContractResult:FireClient(
			player,
			{ result = "failed", publisher = name, amount = penalty, debt = debt }
		)
		logEvent(player, "failed")
	end
	scheduleNext(player)
	ContractService.pushState(player)
end

local function matches(c: Contract, info: { genreId: string, topicId: string, score: number }): boolean
	if info.score < c.minScore then
		return false
	end
	if c.kind == "genre" then
		return info.genreId == c.genreId
	elseif c.kind == "topic" then
		return info.topicId == c.topicId
	end
	return true
end

-- Хук DevelopmentService после начисления дохода
function ContractService.onGameReleased(
	player: Player,
	info: {
		genreId: string,
		topicId: string,
		score: number,
		revenue: number,
	}
)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local d = dataOf(profile)
	-- Провал без банка: половина дохода игры в погашение
	if d.owed > 0 and type(info.revenue) == "number" and info.revenue > 0 then
		local pay = math.min(math.floor(info.revenue * OWED_SHARE), d.owed, math.floor(profile.cash))
		if pay > 0 and DataService.trySpend(player, pay) then
			d.owed -= pay
			noteExpense(player, pay)
		end
	end
	local c = d.active
	if not c or not matches(c, info) then
		return
	end
	c.progress += 1
	if c.progress >= c.count then
		finish(player, profile, d, true)
	else
		ContractService.pushState(player)
	end
end

local function onRespond(player: Player, offerId: any, accept: any)
	if type(offerId) ~= "number" or type(accept) ~= "boolean" then
		return
	end
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	local profile = DataService.get(player)
	local offer = offers[player]
	if not profile or not offer or offer.id ~= offerId then
		return
	end
	offers[player] = nil
	local d = dataOf(profile)
	if not accept or d.active or os.time() > (offer.expiresAt or 0) then
		if not accept then
			logEvent(player, "declined")
		end
		scheduleNext(player)
		ContractService.pushState(player)
		return
	end
	offer.expiresAt = nil
	d.active = offer
	DataService.addCash(player, offer.advance)
	noteNonEarned(player, offer.advance)
	local rival = Rivals.byId(offer.publisher)
	DepthRemotes.ContractResult:FireClient(player, {
		result = "accepted",
		publisher = if rival then rival.name else offer.publisher,
		amount = offer.advance,
	})
	logEvent(player, "accepted")
	ContractService.pushState(player)
end

local function onRequest(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	ContractService.pushState(player)
end

local function tickPlayer(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local d = dataOf(profile)
	local c = d.active
	if c then
		c.remaining = math.max(c.remaining - TICK, 0)
		if c.remaining <= 0 then
			finish(player, profile, d, false)
		end
		return
	end
	local offer = offers[player]
	if offer then
		if os.time() > (offer.expiresAt or 0) then
			offers[player] = nil
			logEvent(player, "expired")
			scheduleNext(player)
			ContractService.pushState(player)
		end
		return
	end
	if profile.studioLevel < MIN_STAGE then
		nextOfferAt[player] = nil -- отсчёт начнётся с переезда в офис
		return
	end
	local at = nextOfferAt[player]
	if not at then
		nextOfferAt[player] = os.clock() + FIRST_DELAY
		return
	end
	if os.clock() < at then
		return
	end
	local newOffer = makeOffer(player, profile)
	if newOffer then
		offers[player] = newOffer
		logEvent(player, "offered")
		ContractService.pushState(player)
	else
		scheduleNext(player)
	end
end

function ContractService.start()
	DepthRemotes.ContractRequest.OnServerEvent:Connect(onRequest)
	DepthRemotes.ContractRespond.OnServerEvent:Connect(onRespond)
	DataService.onProfileLoaded(function(player, profile)
		data(profile)
		ContractService.pushState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		offers[player] = nil
		nextOfferAt[player] = nil
		lastRequest[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player)
				if not ok then
					warn("[ContractService] tick failed:", err)
				end
			end
		end
	end)
end

return ContractService
