--!strict
-- Задания (issue #9): 15 постоянных и 3 ежедневных из пула (смена в 00:00 UTC,
-- выбор детерминирован от даты и UserId). Прогресс считает только сервер:
--   * по профилю (gamesReleased, bestScore, upgrades, cash) — опросом раз в POLL_SECONDS;
--   * по событию релиза — QuestService.onGameReleased (вызывает DevelopmentService);
--   * сотрудники — QuestService.onEmployeesChanged (TODO #7, вызовет система сотрудников).
-- Награда выдаётся один раз: флаг claimed ставится до выдачи.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestRemotes = require(ReplicatedStorage.Shared.QuestRemotes)
local Quests = require(ReplicatedStorage.Shared.Config.Quests)
local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)

local POLL_SECONDS = 2
local REQUEST_COOLDOWN = 1
local DAY_SECONDS = 86_400

-- То, что знает DevelopmentService в момент релиза
export type ReleaseInfo = {
	genreId: string,
	topicId: string,
	score: number,
	focus: { gameplay: number, graphics: number, sound: number, story: number }?,
}

type QuestData = {
	claimed: { [string]: boolean },
	genreGames: { [string]: number },
	comboGames: { [string]: number }, -- "genre/topic" -> игр
	greatCombo: number,
	streak: number, -- текущая серия оценок >= minScore задания scoreStreak
	bestStreak: number,
	employees: number,
}

type DailyData = {
	day: number,
	ids: { string },
	targets: { number },
	progress: { number },
	claimed: { boolean },
	genreId: string?,
	baseGames: number, -- gamesReleased на момент выдачи (для releaseGames)
}

local QuestService = {}

-- Сессия (не сохраняется)
local sessionEarned: { [Player]: number } = {}
local lastCash: { [Player]: number } = {}
local lastSignature: { [Player]: string } = {}
local lastRequest: { [Player]: number } = {}

local function today(): number
	return os.time() // DAY_SECONDS
end

-- Ленивая инициализация profile.quests (defaultProfile не трогаем)
local function questData(profile: DataService.Profile): QuestData
	local p = profile :: any
	local q = p.quests
	if type(q) ~= "table" then
		q = {}
		p.quests = q
	end
	for _, key in { "claimed", "genreGames", "comboGames" } do
		if type(q[key]) ~= "table" then
			q[key] = {}
		end
	end
	for _, key in { "greatCombo", "streak", "bestStreak", "employees" } do
		q[key] = tonumber(q[key]) or 0
	end
	return q :: QuestData
end

local function sortedUnlockedGenres(profile: DataService.Profile): { string }
	local list = {}
	for id in Genres do
		if profile.unlockedGenres[id] then
			table.insert(list, id)
		end
	end
	table.sort(list)
	return list
end

local function rollDaily(player: Player, profile: DataService.Profile, day: number): DailyData
	local rng = Random.new(day * 100_003 + player.UserId)
	local indices = {}
	for i = 1, #Quests.dailyPool do
		indices[i] = i
	end
	for i = #indices, 2, -1 do
		local j = rng:NextInteger(1, i)
		indices[i], indices[j] = indices[j], indices[i]
	end

	local genres = sortedUnlockedGenres(profile)
	local genreId = if #genres > 0 then genres[rng:NextInteger(1, #genres)] else "action"

	local daily: DailyData = {
		day = day,
		ids = {},
		targets = {},
		progress = {},
		claimed = {},
		genreId = genreId,
		baseGames = profile.gamesReleased,
	}
	for n = 1, math.min(Quests.dailyCount, #indices) do
		local quest = Quests.dailyPool[indices[n]]
		local target = quest.target
		if quest.kind == "earnIncome" then
			target = RewardService.incomeTarget(player, profile, quest.target)
		end
		table.insert(daily.ids, quest.id)
		table.insert(daily.targets, target)
		table.insert(daily.progress, 0)
		table.insert(daily.claimed, false)
	end
	return daily
end

-- Текущие ежедневные; в новый день UTC — новые
local function dailyData(player: Player, profile: DataService.Profile): DailyData
	local p = profile :: any
	local day = today()
	local d = p.dailyQuests
	if type(d) ~= "table" or d.day ~= day or type(d.ids) ~= "table" then
		d = rollDaily(player, profile, day)
		p.dailyQuests = d
	end
	return d :: DailyData
end

local function questProgress(
	profile: DataService.Profile,
	q: QuestData,
	quest: Quests.Quest,
	player: Player
): number
	local kind = quest.kind
	if kind == "gamesReleased" then
		return profile.gamesReleased
	elseif kind == "upgrades" then
		local count = 0
		for _, owned in profile.upgrades do
			if owned then
				count += 1
			end
		end
		return count
	elseif kind == "upgradeOwned" then
		return if quest.upgradeId and profile.upgrades[quest.upgradeId] then 1 else 0
	elseif kind == "bestScore" then
		return if profile.bestScore >= quest.target then quest.target else profile.bestScore
	elseif kind == "employees" then
		return q.employees
	elseif kind == "sessionEarnings" then
		return sessionEarned[player] or 0
	elseif kind == "greatCombo" then
		return q.greatCombo
	elseif kind == "genreGames" then
		return q.genreGames[quest.genreId or ""] or 0
	elseif kind == "distinctGenres" then
		local count = 0
		for _, n in q.genreGames do
			if n > 0 then
				count += 1
			end
		end
		return count
	elseif kind == "comboGames" then
		return q.comboGames[(quest.genreId or "") .. "/" .. (quest.topicId or "")] or 0
	elseif kind == "scoreStreak" then
		return q.bestStreak
	end
	return 0
end

local function dailyProgress(profile: DataService.Profile, daily: DailyData, index: number): number
	local quest = Quests.findDaily(daily.ids[index])
	if quest and quest.kind == "releaseGames" then
		return math.max(profile.gamesReleased - daily.baseGames, 0)
	end
	return daily.progress[index] or 0
end

local function sendState(player: Player, force: boolean?)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local q = questData(profile)
	local daily = dailyData(player, profile)

	local parts = {}
	local quests = {}
	for _, quest in Quests.list do
		local progress = math.min(questProgress(profile, q, quest, player), quest.target)
		local claimed = q.claimed[quest.id] == true
		table.insert(quests, { id = quest.id, progress = progress, target = quest.target, claimed = claimed })
		table.insert(parts, progress .. (if claimed then "+" else "-"))
	end
	local dailyList = {}
	for i, id in daily.ids do
		local target = daily.targets[i]
		local progress = math.min(dailyProgress(profile, daily, i), target)
		local claimed = daily.claimed[i] == true
		table.insert(dailyList, { id = id, progress = progress, target = target, claimed = claimed })
		table.insert(parts, progress .. (if claimed then "+" else "-"))
	end
	table.insert(parts, tostring(daily.day))

	local signature = table.concat(parts, ",")
	if not force and lastSignature[player] == signature then
		return
	end
	lastSignature[player] = signature
	QuestRemotes.QuestState:FireClient(player, {
		quests = quests,
		daily = dailyList,
		dailyGenre = daily.genreId,
		resetAt = (daily.day + 1) * DAY_SECONDS,
	})
end

-- Заработок за сессию и за день: рост cash без денег из наград.
-- Траты в том же окне опроса уменьшают учтённый заработок (занижение, не завышение).
local function trackEarnings(player: Player, profile: DataService.Profile)
	local rewardCash = RewardService.takeRewardCash(player)
	local previous = lastCash[player]
	lastCash[player] = profile.cash
	if not previous then
		return
	end
	local earned = profile.cash - previous - rewardCash
	if earned <= 0 then
		return
	end
	sessionEarned[player] = (sessionEarned[player] or 0) + earned
	local daily = dailyData(player, profile)
	for i, id in daily.ids do
		local quest = Quests.findDaily(id)
		if quest and quest.kind == "earnIncome" then
			daily.progress[i] = (daily.progress[i] or 0) + earned
		end
	end
end

local function onClaim(player: Player, kind: any, id: any)
	if type(kind) ~= "string" or type(id) ~= "string" then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end

	if kind == "quest" then
		local quest = Quests.find(id)
		local q = questData(profile)
		if not quest or q.claimed[id] then
			return
		end
		if questProgress(profile, q, quest, player) < quest.target then
			return
		end
		q.claimed[id] = true
		RewardService.grant(player, quest.reward)
	elseif kind == "daily" then
		local daily = dailyData(player, profile)
		local index = table.find(daily.ids, id)
		if not index or daily.claimed[index] then
			return
		end
		if dailyProgress(profile, daily, index) < daily.targets[index] then
			return
		end
		daily.claimed[index] = true
		RewardService.grant(player, Quests.dailyReward)
	else
		return
	end
	sendState(player)
end

-- Интеграция: DevelopmentService.release после начисления дохода вызывает
-- QuestService.onGameReleased(player, { genreId = ..., topicId = ..., score = ..., focus = project.focus })
function QuestService.onGameReleased(player: Player, info: ReleaseInfo)
	local profile = DataService.get(player)
	if not profile or type(info) ~= "table" then
		return
	end
	local genreId, topicId, score = info.genreId, info.topicId, info.score
	if type(genreId) ~= "string" or not Genres[genreId] then
		return
	end
	if type(topicId) ~= "string" or not Topics[topicId] or type(score) ~= "number" then
		return
	end

	local q = questData(profile)
	q.genreGames[genreId] = (q.genreGames[genreId] or 0) + 1
	local combo = genreId .. "/" .. topicId
	q.comboGames[combo] = (q.comboGames[combo] or 0) + 1
	local great = Formulas.topicFit(topicId, genreId) >= Quests.greatComboFit
	if great then
		q.greatCombo += 1
	end

	for _, quest in Quests.list do
		if quest.kind == "scoreStreak" then
			q.streak = if score >= (quest.minScore or 0) then q.streak + 1 else 0
			q.bestStreak = math.max(q.bestStreak, q.streak)
			break
		end
	end

	local daily = dailyData(player, profile)
	local focus = info.focus :: any
	local sound = if type(focus) == "table" then tonumber(focus.sound) or 0 else 0
	for i, id in daily.ids do
		local quest = Quests.findDaily(id)
		if not quest then
			continue
		end
		local hit = false
		if quest.kind == "soundFocus" then
			hit = sound >= (quest.minFocus or 0)
		elseif quest.kind == "scoreInGenre" then
			hit = genreId == daily.genreId and score >= (quest.minScore or 0)
		elseif quest.kind == "scoreAtLeast" then
			hit = score >= (quest.minScore or 0)
		elseif quest.kind == "greatCombo" then
			hit = great
		end
		if hit then
			daily.progress[i] = (daily.progress[i] or 0) + 1
		end
	end
	sendState(player)
end

-- RebirthService после сброса студии: невыполненные «Заработай N минут дохода» пересчитываем
-- под новый (меньший) доход и начинаем с нуля — заработок старой студии сюда не идёт.
-- Денежные награды заданий и так считаются при выдаче по доходу с последнего Rebirth
function QuestService.onRebirth(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local daily = dailyData(player, profile)
	for i, id in daily.ids do
		local quest = Quests.findDaily(id)
		if quest and quest.kind == "earnIncome" and not daily.claimed[i] then
			daily.targets[i] = RewardService.incomeTarget(player, profile, quest.target)
			daily.progress[i] = 0
		end
	end
	-- Деньги до Rebirth не должны попасть в заработок как «рост cash»
	lastCash[player] = profile.cash
	sendState(player, true)
end

-- TODO #7: система сотрудников вызывает при найме/увольнении
function QuestService.onEmployeesChanged(player: Player, count: number)
	local profile = DataService.get(player)
	if not profile or type(count) ~= "number" then
		return
	end
	local q = questData(profile)
	q.employees = math.max(q.employees, count)
	sendState(player)
end

function QuestService.start()
	QuestRemotes.ClaimQuest.OnServerEvent:Connect(onClaim)
	QuestRemotes.RequestQuestData.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
			return
		end
		lastRequest[player] = now
		sendState(player, true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessionEarned[player] = nil
		lastCash[player] = nil
		lastSignature[player] = nil
		lastRequest[player] = nil
		RewardService.forget(player)
	end)

	task.spawn(function()
		while true do
			task.wait(POLL_SECONDS)
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile then
					trackEarnings(player, profile)
					sendState(player)
				end
			end
		end
	end)
end

return QuestService
