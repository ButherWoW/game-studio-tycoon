--!strict
-- Сезонный пропуск (Config/Season): опыт, уровни, бесплатная и премиум-дорожка.
-- profile.season = { id, xp, claimedFree, claimedPremium, premium, day, dayXp } — ленивая
-- инициализация; новый id сезона — всё с нуля (звания прошлых сезонов — в profile.seasonTitles).
-- Опыт приходит из хуков: DevelopmentService.release, QuickEventService (идеальное событие),
-- QuestService (ежедневное задание). Премиум и пропуск уровня — Developer Products (grantProduct).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Season = require(ReplicatedStorage.Shared.Config.Season)
local Debug = require(ReplicatedStorage.Shared.Config.Debug)
local HitCartridges = require(ReplicatedStorage.Shared.Config.HitCartridges)
local LiveOpsRemotes = require(ReplicatedStorage.Shared.LiveOpsRemotes)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)

type SeasonData = {
	id: string,
	xp: number,
	claimedFree: { [string]: boolean }, -- ключ "t<уровень>": DataStore не любит дырявые массивы
	claimedPremium: { [string]: boolean },
	premium: boolean,
	day: number, -- сутки (UTC) для потолка опыта за релизы
	dayXp: number,
}

local SeasonService = {}

local CLAIM_COOLDOWN = 0.2
local lastClaim: { [Player]: number } = {}

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end

local function logAnalytics(player: Player, event: string, value: number, field: string?)
	local analytics = optional("AnalyticsService")
	if analytics and type(analytics.logLiveOps) == "function" then
		pcall(analytics.logLiveOps, player, event, value, field)
	end
end

local function map(value: any): { [string]: boolean }
	local result = {}
	if type(value) == "table" then
		for k, v in value do
			if type(k) == "string" and v == true then
				result[k] = true
			end
		end
	end
	return result
end

-- Данные сезона в профиле; новый сезон — с нуля
local function dataOf(profile: DataService.Profile): SeasonData
	local p = profile :: any
	local info = Season.info()
	local s = p.season
	if type(s) ~= "table" or s.id ~= info.id then
		s = {
			id = info.id,
			xp = 0,
			claimedFree = {},
			claimedPremium = {},
			premium = false,
			day = 0,
			dayXp = 0,
		}
		p.season = s
	end
	s.xp = math.clamp(tonumber(s.xp) or 0, 0, Season.maxXp())
	s.claimedFree = map(s.claimedFree)
	s.claimedPremium = map(s.claimedPremium)
	s.premium = s.premium == true
	s.day = tonumber(s.day) or 0
	s.dayXp = tonumber(s.dayXp) or 0
	return s :: SeasonData
end

-- Премиум-дорожка открыта: куплена или (только Studio) Config/Debug.seasonForcePremium — не сохраняется
local function hasPremium(s: SeasonData): boolean
	return s.premium or (Debug.seasonForcePremium and RunService:IsStudio())
end

local function titlesOf(profile: DataService.Profile): { [string]: boolean }
	local p = profile :: any
	if type(p.seasonTitles) ~= "table" then
		p.seasonTitles = {}
	end
	return p.seasonTitles
end

local function tierList(claimed: { [string]: boolean }): { number }
	local list = {}
	for key in claimed do
		local n = tonumber(key:match("^t(%d+)$"))
		if n then
			table.insert(list, n)
		end
	end
	table.sort(list)
	return list
end

function SeasonService.sendState(player: Player)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	local s = dataOf(profile)
	local info = Season.info()
	local titles = titlesOf(profile)
	LiveOpsRemotes.SeasonState:FireClient(player, {
		id = s.id,
		index = info.index,
		startsAt = info.startsAt,
		endsAt = info.endsAt,
		xp = s.xp,
		tier = Season.tierOf(s.xp),
		premium = hasPremium(s),
		claimedFree = tierList(s.claimedFree),
		claimedPremium = tierList(s.claimedPremium),
		title = titles[s.id] == true,
	})
end

-- Прибавить опыт сезона. source — для аналитики (release, quick, daily, skip)
function SeasonService.addXp(player: Player, amount: number, source: string)
	local profile = DataService.get(player)
	if not profile or type(amount) ~= "number" or amount <= 0 then
		return
	end
	local s = dataOf(profile)
	local multiplier = if RunService:IsStudio() then math.max(Debug.seasonXpMultiplier, 1) else 1
	local before = Season.tierOf(s.xp)
	s.xp = math.min(s.xp + math.floor(amount * multiplier), Season.maxXp())
	local after = Season.tierOf(s.xp)
	if after > before then
		-- Аналитика опыта — по уровням, а не по каждой порции (бюджет событий)
		logAnalytics(player, "seasonTier", after, source)
		LiveOpsRemotes.LiveOpsToast:FireClient(player, { key = "season_toast_tier", vars = { tier = after } })
	end
	SeasonService.sendState(player)
end

-- DevelopmentService.release: опыт за игру, хиты — больше. Суточный потолок за релизы
function SeasonService.onGameReleased(player: Player, info: { score: number })
	local profile = DataService.get(player)
	if not profile or type(info) ~= "table" then
		return
	end
	local score = tonumber(info.score) or 0
	local s = dataOf(profile)
	local day = os.time() // 86400
	if s.day ~= day then
		s.day = day
		s.dayXp = 0
	end
	local xp = Season.releaseXp(score, score >= HitCartridges.minScore)
	xp = math.min(xp, math.max(Season.xp.releaseDailyCap - s.dayXp, 0))
	if xp <= 0 then
		return
	end
	s.dayXp += xp
	SeasonService.addXp(player, xp, "release")
end

-- QuickEventService: идеальное быстрое событие
function SeasonService.onQuickPerfect(player: Player)
	SeasonService.addXp(player, Season.xp.quickPerfect, "quick")
end

-- QuestService: забрал ежедневное задание
function SeasonService.onDailyClaimed(player: Player)
	SeasonService.addXp(player, Season.xp.daily, "daily")
end

-- Деньги вместо предмета (уже есть, сервиса нет)
local function fallback(player: Player, reward: Season.Reward)
	local minutes = reward.fallbackMinutes
	if minutes and minutes > 0 then
		RewardService.grant(player, { incomeMinutes = minutes })
	end
end

-- Талисман: MascotService может ещё не быть в main — тогда деньги
local function grantMascot(player: Player, profile: DataService.Profile, mascotId: string): boolean
	local service = optional("MascotService")
	local fn = service and (service.grantMascot or service.grant)
	if type(fn) ~= "function" then
		return false
	end
	local ok, result = pcall(fn, player, profile, mascotId)
	return ok and result ~= false
end

local function grantReward(
	player: Player,
	profile: DataService.Profile,
	reward: Season.Reward,
	seasonId: string
)
	-- Деньги, кофе, исследования — как награды заданий (RewardService; без pcall: аналитика
	-- экономики смотрит, кто вызвал RewardService)
	if reward.incomeMinutes or reward.coffeeMinutes or reward.researchPoints then
		RewardService.grant(player, {
			incomeMinutes = reward.incomeMinutes,
			coffeeMinutes = reward.coffeeMinutes,
			researchPoints = reward.researchPoints,
		})
	end
	if reward.poster then
		local posters = optional("PosterService")
		-- Награды сезона — сразу, даже до выхода волны (ContentDrops): бонус пропуска «раньше всех»
		local granted = posters ~= nil
			and not posters.ownsIn(profile, reward.poster)
			and posters.grantPoster(player, profile, reward.poster) == true
		if not granted then
			fallback(player, reward)
		end
	end
	if reward.skin then
		local skins = optional("SkinService")
		local granted = skins ~= nil
			and not skins.ownsSkin(profile, reward.skin)
			and skins.grantSkin(player, profile, reward.skin) == true
		if not granted then
			fallback(player, reward)
		end
	end
	if reward.mascot and not (grantMascot(player, profile, reward.mascot)) then
		fallback(player, reward)
	end
	if reward.title then
		titlesOf(profile)[seasonId] = true
		player:SetAttribute("SeasonTitle", seasonId)
	end
end

-- Забрать одну награду. true — выдана
local function claimOne(
	player: Player,
	profile: DataService.Profile,
	s: SeasonData,
	track: string,
	tier: number
): boolean
	local entry = Season.tiers[tier]
	if not entry or Season.tierOf(s.xp) < tier then
		return false
	end
	local key = "t" .. tier
	local claimed = if track == "free" then s.claimedFree else s.claimedPremium
	if claimed[key] or (track == "premium" and not hasPremium(s)) then
		return false
	end
	claimed[key] = true
	local reward = if track == "free" then entry.free else entry.premium
	local ok, err = pcall(grantReward, player, profile, reward, s.id)
	if not ok then
		-- Не выдали — уровень остаётся доступным, можно забрать ещё раз
		claimed[key] = nil
		warn("[SeasonService] Награда не выдана:", player.UserId, track, tier, err)
		return false
	end
	logAnalytics(player, "seasonClaim", tier, track .. "_" .. tier)
	return true
end

local function onClaim(player: Player, track: any, tier: any)
	local now = os.clock()
	if now - (lastClaim[player] or 0) < CLAIM_COOLDOWN then
		return
	end
	lastClaim[player] = now
	local profile = DataService.get(player)
	if not profile or type(track) ~= "string" then
		return
	end
	local s = dataOf(profile)
	if track == "all" then
		for n = 1, Season.tierOf(s.xp) do
			claimOne(player, profile, s, "free", n)
			if hasPremium(s) then
				claimOne(player, profile, s, "premium", n)
			end
		end
	elseif
		(track == "free" or track == "premium")
		and type(tier) == "number"
		and tier == math.floor(tier)
	then
		if not claimOne(player, profile, s, track, tier) then
			return
		end
	else
		return
	end
	SeasonService.sendState(player)
	task.spawn(DataService.save, player)
end

-- Developer Products сезона (MonetizationService.ProcessReceipt). false — это не продукт сезона
function SeasonService.grantProduct(player: Player, profile: DataService.Profile, productId: number): boolean
	local products = Season.products
	if productId == 0 then
		return false
	end
	if productId == products.seasonPass.productId then
		local s = dataOf(profile)
		if s.premium then
			-- Уже куплен в этом сезоне (двойное нажатие): Robux не пропадают — деньгами
			RewardService.grant(player, { incomeMinutes = Season.repeatPassMinutes })
		else
			s.premium = true
		end
		task.defer(SeasonService.sendState, player)
		return true
	elseif productId == products.seasonSkip.productId then
		local s = dataOf(profile)
		local nextTier = math.min(Season.tierOf(s.xp) + 1, #Season.tiers)
		local gain = math.max(nextTier * Season.xpPerTier - s.xp, 0)
		if gain > 0 then
			-- Без множителя Studio: ровно один уровень
			s.xp = math.min(s.xp + gain, Season.maxXp())
			logAnalytics(player, "seasonTier", Season.tierOf(s.xp), "skip")
		else
			-- Все уровни уже пройдены
			RewardService.grant(player, { incomeMinutes = 10 })
		end
		task.defer(SeasonService.sendState, player)
		return true
	end
	return false
end

function SeasonService.start()
	-- Запрос состояния не чаще раза в секунду: иначе флуд грузит CPU и трафик сервера
	local lastState: { [Player]: number } = {}
	LiveOpsRemotes.RequestSeason.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if now - (lastState[player] or -1) < 1 then
			return
		end
		lastState[player] = now
		SeasonService.sendState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastState[player] = nil
	end)
	LiveOpsRemotes.ClaimSeason.OnServerEvent:Connect(onClaim)
	DataService.onProfileLoaded(function(player, profile)
		local s = dataOf(profile)
		if titlesOf(profile)[s.id] then
			player:SetAttribute("SeasonTitle", s.id)
		end
		SeasonService.sendState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastClaim[player] = nil
	end)
	-- Сезон сменился, пока игрок в игре: прислать новый (dataOf сбросит при обращении)
	task.spawn(function()
		local current = Season.info().id
		while true do
			task.wait(60)
			local id = Season.info().id
			if id ~= current then
				current = id
				for _, player in Players:GetPlayers() do
					task.spawn(SeasonService.sendState, player)
				end
			end
		end
	end)
end

return SeasonService
