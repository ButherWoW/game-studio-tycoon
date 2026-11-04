--!strict
-- Достижения (Config/Achievements). Данные — profile.achievements:
--   done   = { [id]: os.time() } — получено (награда выдана один раз, флаг ставится до выдачи);
--   stats  = { [stat]: number } — счётчики, Rebirth их не трогает;
--   combos = { ["жанр/тема"]: true } — разные сочетания выпущенных игр;
--   backfilled — прошлый прогресс уже засчитан.
-- Счётчики профиля (этап, апгрейды, сотрудники, Rebirth, кражи…) — опросом раз в POLL_SECONDS,
-- хранится максимум (после Rebirth этап снова 1, но «Третий этаж» уже получен).
-- События — из других сервисов (ленивый require через FindFirstChild):
--   DevelopmentService.release -> onGameReleased; QuickEventService -> note("qtePerfect");
--   ExpoService -> note("expoWins").
-- Первый вход после появления системы: всё заслуженное засчитывается сразу, награды
-- суммируются и режутся до Achievements.backfillCap — одна выдача и один тост.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementRemotes = require(ReplicatedStorage.Shared.AchievementRemotes)
local Achievements = require(ReplicatedStorage.Shared.Config.Achievements)
local Employees = require(ReplicatedStorage.Shared.Config.Employees)
local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local HitCartridges = require(ReplicatedStorage.Shared.Config.HitCartridges)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local RewardService = require(script.Parent.RewardService)

type Data = {
	done: { [string]: number },
	stats: { [string]: number },
	combos: { [string]: boolean },
	backfilled: boolean?,
}

export type ReleaseInfo = {
	genreId: string,
	topicId: string,
	score: number,
	revenue: number,
	laptop: boolean?,
}

local POLL_SECONDS = 3
local REQUEST_COOLDOWN = 1
local DAY_SECONDS = 86_400

local AchievementService = {}

local lastSignature: { [Player]: string } = {}
local lastRequest: { [Player]: number } = {}
local ready: { [Player]: boolean } = {} -- прошлый прогресс засчитан, можно выдавать по одному

local function num(value: any): number
	local n = tonumber(value)
	return if n and n == n and n >= 0 and n < math.huge then n else 0
end

local function count(map: any): number
	local n = 0
	if type(map) == "table" then
		for _, value in map do
			if value then
				n += 1
			end
		end
	end
	return n
end

-- Ленивая починка profile.achievements (битое сохранение не должно ломать сервис)
local function dataOf(profile: DataService.Profile): Data
	local p = profile :: any
	local raw = p.achievements
	if type(raw) ~= "table" then
		raw = {}
		p.achievements = raw
	end
	for _, key in { "done", "stats", "combos" } do
		if type(raw[key]) ~= "table" then
			raw[key] = {}
		end
	end
	for stat, value in raw.stats do
		raw.stats[stat] = num(value)
	end
	return raw :: Data
end

local function raise(stats: { [string]: number }, stat: string, value: number)
	if value > (stats[stat] or 0) then
		stats[stat] = value
	end
end

-- Счётчики, которые видно по профилю: храним максимум
local function pollStats(player: Player, profile: DataService.Profile, data: Data)
	local stats = data.stats
	local p = profile :: any
	raise(stats, "garage", if PlotService.ownsGarage(player) then 1 else 0)
	raise(stats, "stage", num(profile.studioLevel))
	raise(stats, "upgrades", count(profile.upgrades))
	raise(stats, "posters", count(type(profile.posters) == "table" and profile.posters.owned))
	raise(stats, "research", count(type(p.research) == "table" and p.research.owned))
	raise(stats, "games", num(profile.gamesReleased))
	raise(stats, "bestScore", num(profile.bestScore))
	raise(stats, "rebirths", num(profile.rebirths))
	raise(stats, "combos", count(data.combos))

	local genres = 0
	for id in Genres do
		if profile.unlockedGenres[id] then
			genres += 1
		end
	end
	raise(stats, "genresOwned", genres)

	-- Команда: profile.staff (StaffService), навыки — profile.staffInfo
	local staff = if type(p.staff) == "table" then p.staff else {}
	local info = if type(p.staffInfo) == "table" then p.staffInfo else {}
	local hired, skillMax, legend = 0, 0, 0
	for employeeId in staff do
		hired += 1
		local employee = Employees.get(employeeId)
		if employee and employee.legendary then
			legend = 1
		end
		local entry = info[employeeId]
		if type(entry) == "table" and type(entry.skills) == "table" then
			for _, level in entry.skills do
				skillMax = math.max(skillMax, num(level))
			end
		end
	end
	raise(stats, "employees", hired)
	raise(stats, "skillMax", skillMax)
	raise(stats, "legend", legend)

	-- Воры: profile.thief (HitService / ThiefBoardService), читаем без записи
	local thief = if type(p.thief) == "table" then p.thief else {}
	raise(stats, "steals", num(thief.steals))
	raise(stats, "catches", num(thief.catches))
	raise(stats, "caught", num(thief.caught))

	-- Кредит погашен: был долг, стал 0. Забастовка пережита: была, закончилась
	local inDebt = num(p.loanDebt) > 0
	if inDebt then
		stats.inDebt = 1
	elseif (stats.inDebt or 0) > 0 then
		stats.inDebt = 0
		stats.loansRepaid = (stats.loansRepaid or 0) + 1
	end
	if p.staffStrike == true then
		stats.inStrike = 1
	elseif (stats.inStrike or 0) > 0 then
		stats.inStrike = 0
		stats.strikes = (stats.strikes or 0) + 1
	end

	-- Дни со входом (UTC), как у ежедневных заданий
	local day = os.time() // DAY_SECONDS
	if stats.lastDay ~= day then
		stats.lastDay = day
		stats.days = (stats.days or 0) + 1
	end
end

local function awardBadge(player: Player, badgeId: number)
	if badgeId <= 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			BadgeService:AwardBadge(player.UserId, badgeId)
		end)
		if not ok then
			warn("[AchievementService] AwardBadge failed:", badgeId, err)
		end
	end)
end

local function logAnalytics(player: Player, id: string)
	local module = script.Parent:FindFirstChild("AnalyticsService")
	if not module or not module:IsA("ModuleScript") then
		return
	end
	pcall(function()
		local analytics = require(module) :: any
		if type(analytics.logAchievement) == "function" then
			analytics.logAchievement(player, id)
		end
	end)
end

local function sendState(player: Player, force: boolean?)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = dataOf(profile)
	local stats: { [string]: number } = {}
	local parts = {}
	for _, a in Achievements.list do
		if stats[a.stat] == nil then
			stats[a.stat] = data.stats[a.stat] or 0
			table.insert(parts, a.stat .. "=" .. stats[a.stat])
		end
	end
	for id in data.done do
		table.insert(parts, id)
	end
	table.sort(parts)
	local signature = table.concat(parts, ",")
	if not force and lastSignature[player] == signature then
		return
	end
	lastSignature[player] = signature
	AchievementRemotes.AchievementState:FireClient(player, { done = data.done, stats = stats })
end

-- Отметить выполненные. backfill: награды не выдаём, а возвращаем суммой (выдаст onLoaded)
local function evaluate(
	player: Player,
	profile: DataService.Profile,
	backfill: boolean?
): ({ string }, Achievements.Reward)
	local data = dataOf(profile)
	local unlocked: { string } = {}
	local total: { [string]: number } = {}
	for _, a in Achievements.list do
		if data.done[a.id] or (data.stats[a.stat] or 0) < a.target then
			continue
		end
		data.done[a.id] = os.time()
		table.insert(unlocked, a.id)
		awardBadge(player, a.badgeId)
		logAnalytics(player, a.id)
		if backfill then
			for key, value in a.reward :: any do
				if type(value) == "number" then
					total[key] = (total[key] or 0) + value
				end
			end
		else
			RewardService.grant(player, a.reward)
			AchievementRemotes.AchievementUnlocked:FireClient(player, { id = a.id })
		end
	end
	return unlocked, total :: any
end

local function refresh(player: Player)
	local profile = DataService.get(player)
	if not profile or not ready[player] then
		return
	end
	pollStats(player, profile, dataOf(profile))
	evaluate(player, profile)
	sendState(player)
end

-- Первый вход с системой достижений: прошлый прогресс одной наградой с потолком
local function backfill(player: Player, profile: DataService.Profile, data: Data)
	local p = profile :: any
	-- Сочетания жанр/тема из заданий (QuestService хранит счётчики по ним)
	local quests = p.quests
	if type(quests) == "table" and type(quests.comboGames) == "table" then
		for combo, n in quests.comboGames do
			if type(combo) == "string" and num(n) > 0 then
				data.combos[combo] = true
			end
		end
	end
	-- Хиты на полке — нижняя оценка выпущенных хитов
	if type(p.hits) == "table" then
		local hits, great = 0, 0
		for _, hit in p.hits do
			local score = if type(hit) == "table" then num(hit.score) else 0
			if score >= HitCartridges.minScore then
				hits += 1
			end
			if score >= Achievements.greatScore then
				great += 1
			end
		end
		raise(data.stats, "hitGames", hits)
		raise(data.stats, "score9", great)
	end
	pollStats(player, profile, data)
	local unlocked, total = evaluate(player, profile, true)
	data.backfilled = true
	if #unlocked == 0 then
		return
	end
	local reward = {} :: any
	for key, value in total :: any do
		local cap = Achievements.backfillCap[key]
		reward[key] = if cap then math.min(value, cap) else value
	end
	RewardService.grant(player, reward)
	AchievementRemotes.AchievementUnlocked:FireClient(player, { backfill = #unlocked, reward = reward })
end

local function onLoaded(player: Player, profile: DataService.Profile)
	local data = dataOf(profile)
	if not data.backfilled then
		backfill(player, profile, data)
	end
	-- Значки, заведённые позже, чем получено достижение
	for id in data.done do
		local a = Achievements.find(id)
		if a and a.badgeId > 0 then
			awardBadge(player, a.badgeId)
		end
	end
	ready[player] = true
	refresh(player)
	sendState(player, true)
end

-- Прибавить к счётчику события (выставка, быстрые события) и проверить достижения
function AchievementService.note(player: Player, stat: string, amount: number?)
	local profile = DataService.get(player)
	if not profile or type(stat) ~= "string" then
		return
	end
	local add = num(amount or 1)
	if add <= 0 then
		return
	end
	local stats = dataOf(profile).stats
	stats[stat] = (stats[stat] or 0) + add
	refresh(player)
end

-- DevelopmentService.release после начисления дохода
function AchievementService.onGameReleased(player: Player, info: ReleaseInfo)
	local profile = DataService.get(player)
	if not profile or type(info) ~= "table" then
		return
	end
	local data = dataOf(profile)
	local stats = data.stats
	local score = num(info.score)
	stats.earned = (stats.earned or 0) + num(info.revenue)
	if score >= Achievements.greatScore then
		stats.score9 = (stats.score9 or 0) + 1
	end
	if score >= HitCartridges.minScore then
		stats.hitGames = (stats.hitGames or 0) + 1
	end
	if score > 0 and score <= Achievements.flopScore then
		stats.flops = (stats.flops or 0) + 1
	end
	if info.laptop and score >= Achievements.laptopStarScore then
		stats.laptopStars = (stats.laptopStars or 0) + 1
	end
	if type(info.genreId) == "string" and type(info.topicId) == "string" then
		data.combos[info.genreId .. "/" .. info.topicId] = true
	end
	refresh(player)
end

function AchievementService.start()
	DataService.onProfileLoaded(function(player, profile)
		local ok, err = pcall(onLoaded, player, profile)
		if not ok then
			warn("[AchievementService] load failed:", err)
		end
	end)
	AchievementRemotes.RequestAchievements.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
			return
		end
		lastRequest[player] = now
		sendState(player, true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSignature[player] = nil
		lastRequest[player] = nil
		ready[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(POLL_SECONDS)
			for _, player in Players:GetPlayers() do
				-- Битые данные одного игрока не должны останавливать цикл для всех
				local ok, err = pcall(refresh, player)
				if not ok then
					warn("[AchievementService] poll failed:", err)
				end
			end
		end
	end)
end

return AchievementService
