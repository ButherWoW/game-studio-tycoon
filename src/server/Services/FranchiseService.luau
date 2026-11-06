--!strict
-- Франшизы (Config/Franchises). Хит с оценкой ≥ minScore попадает в кандидаты; игрок делает его
-- франшизой в окне «Создать игру» (название франшизы = название игры, уже прошло фильтр).
-- Продолжение: жанр франшизы (иначе это обычная игра), доход × revenueMultiplier (хайп фанатов,
-- усталость), после релиза фанаты растут или падают (onGameReleased — хук DevelopmentService).
-- Данные: profile.franchises = { list = { Franchise }, candidates = { Candidate }, nextId }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Franchises = require(Shared.Config.Franchises)
local Genres = require(Shared.Config.Genres)
local Topics = require(Shared.Config.Topics)
local DepthRemotes = require(Shared.DepthRemotes)
local DataService = require(script.Parent.DataService)
local FeatureReleaseService = require(script.Parent.FeatureReleaseService)

export type Franchise = {
	id: number,
	name: string,
	genreId: string,
	topicId: string,
	fans: number,
	entries: number,
	lastAt: number, -- os.time() последней части
	lastScore: number,
	lastName: string,
}

type Candidate = { key: string, name: string, genreId: string, topicId: string, score: number }
type Data = { list: { Franchise }, candidates: { Candidate }, nextId: number }

local REQUEST_COOLDOWN = 0.5

local FranchiseService = {}
local lastRequest: { [Player]: number } = {}
local lastCandidateToast: { [Player]: number } = {}

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

local function logEvent(player: Player, field: string)
	local analytics = optional("AnalyticsService")
	if analytics and type(analytics.logDepth) == "function" then
		pcall(analytics.logDepth, player, "franchise", field)
	end
end

local function num(value: any, default: number): number
	local n = tonumber(value)
	return if n and n == n and n > -math.huge and n < math.huge then n else default
end

-- Поле профиля в порядке: старые сохранения без него и мусор
local function data(profile: DataService.Profile): Data
	local raw = profile.franchises
	if type(raw) ~= "table" then
		raw = {}
	end
	local list: { Franchise } = {}
	if type(raw.list) == "table" then
		for _, f in raw.list do
			if
				type(f) == "table"
				and type(f.name) == "string"
				and Genres[f.genreId] ~= nil
				and Topics[f.topicId] ~= nil
			then
				table.insert(list, {
					id = num(f.id, #list + 1),
					name = f.name,
					genreId = f.genreId,
					topicId = f.topicId,
					fans = math.max(math.floor(num(f.fans, 0)), 0),
					entries = math.max(math.floor(num(f.entries, 1)), 1),
					lastAt = num(f.lastAt, 0),
					lastScore = num(f.lastScore, 0),
					lastName = if type(f.lastName) == "string" then f.lastName else f.name,
				})
			end
		end
	end
	local candidates: { Candidate } = {}
	if type(raw.candidates) == "table" then
		for _, c in raw.candidates do
			if
				type(c) == "table"
				and type(c.key) == "string"
				and type(c.name) == "string"
				and Genres[c.genreId] ~= nil
				and Topics[c.topicId] ~= nil
			then
				table.insert(candidates, {
					key = c.key,
					name = c.name,
					genreId = c.genreId,
					topicId = c.topicId,
					score = num(c.score, 0),
				})
			end
		end
	end
	local nextId = math.max(math.floor(num(raw.nextId, 1)), 1)
	for _, f in list do
		nextId = math.max(nextId, f.id + 1)
	end
	local fixed: Data = { list = list, candidates = candidates, nextId = nextId }
	profile.franchises = fixed
	return fixed
end

local function find(d: Data, id: any): Franchise?
	if type(id) ~= "number" or id ~= id then
		return nil
	end
	for _, f in d.list do
		if f.id == id then
			return f
		end
	end
	return nil
end

function FranchiseService.pushState(player: Player)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	local d = data(profile)
	DepthRemotes.FranchiseState:FireClient(player, {
		list = d.list,
		candidates = d.candidates,
		serverTime = os.time(),
		max = Franchises.maxFranchises,
	})
end

-- Для DevelopmentService.beginProject: франшиза существует и жанр совпадает.
-- Возвращает id (или nil — обычная игра) и «та же тема» (слабее штраф за повтор, как у сиквела)
function FranchiseService.validate(
	player: Player,
	franchiseId: any,
	genreId: string,
	topicId: string
): (number?, boolean)
	local profile = DataService.get(player)
	if not profile then
		return nil, false
	end
	local f = find(data(profile), franchiseId)
	if not f or f.genreId ~= genreId then
		return nil, false
	end
	return f.id, f.topicId == topicId
end

-- Множитель дохода части франшизы (до обновления фанатов): хайп × усталость.
-- Второе значение — подробности для тоста
function FranchiseService.revenueMultiplier(player: Player, franchiseId: any, score: number): (number, any)
	local profile = DataService.get(player)
	local f = profile and find(data(profile), franchiseId)
	if not f then
		return 1, nil
	end
	local hype = Franchises.hype(f.fans)
	local multiplier = 1 + hype
	local fatigue = os.time() - f.lastAt < Franchises.fatigueSeconds
	if fatigue then
		multiplier *= Franchises.fatigueMultiplier
	end
	local worse = score < f.lastScore
	if worse then
		multiplier *= Franchises.worseMultiplier
	end
	multiplier = math.max(multiplier, Franchises.minMultiplier)
	return multiplier, { hype = hype, fatigue = fatigue, worse = worse }
end

local function fansAfter(fans: number, score: number): number
	if score >= Franchises.goodScore then
		return fans + Franchises.fansPerPoint * (score - 7)
	elseif score <= Franchises.badScore then
		return math.floor(fans * Franchises.badKeep)
	end
	return fans
end

-- Хук DevelopmentService после начисления дохода
function FranchiseService.onGameReleased(
	player: Player,
	info: {
		projectId: number,
		name: string,
		genreId: string,
		topicId: string,
		score: number,
		franchiseId: number?,
		multiplier: number?,
		details: any,
	}
)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local d = data(profile)
	local f = find(d, info.franchiseId)
	if f then
		local before = f.fans
		f.fans = fansAfter(f.fans, info.score)
		f.entries += 1
		f.lastAt = os.time()
		f.lastScore = info.score
		f.lastName = info.name
		local details = if type(info.details) == "table" then info.details else {}
		DepthRemotes.FranchiseNotice:FireClient(player, {
			name = f.name,
			multiplier = info.multiplier or 1,
			fans = f.fans,
			fansDelta = f.fans - before,
			fatigue = details.fatigue == true,
			worse = details.worse == true,
		})
	elseif info.score >= Franchises.minScore then
		-- Новый хит — кандидат во франшизы (последние candidatesKept)
		table.insert(d.candidates, 1, {
			key = tostring(os.time()) .. "_" .. tostring(info.projectId),
			name = info.name,
			genreId = info.genreId,
			topicId = info.topicId,
			score = info.score,
		})
		while #d.candidates > Franchises.candidatesKept do
			table.remove(d.candidates)
		end
		local now = os.clock()
		if
			#d.list < Franchises.maxFranchises
			and now - (lastCandidateToast[player] or -math.huge) >= Franchises.candidateToastSeconds
		then
			lastCandidateToast[player] = now
			DepthRemotes.FranchiseNotice:FireClient(player, { candidate = info.name })
		end
	end
	FranchiseService.pushState(player)
end

local function onCreate(player: Player, key: any)
	if type(key) ~= "string" or #key > 40 then
		return
	end
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local d = data(profile)
	if #d.list >= Franchises.maxFranchises then
		return
	end
	for index, c in d.candidates do
		if c.key == key then
			table.remove(d.candidates, index)
			table.insert(d.list, {
				id = d.nextId,
				name = c.name,
				genreId = c.genreId,
				topicId = c.topicId,
				-- Основатель франшизы сразу приводит фанатов
				fans = Franchises.fansPerPoint * math.max(c.score - 7, 0),
				entries = 1,
				lastAt = 0,
				lastScore = c.score,
				lastName = c.name,
			})
			d.nextId += 1
			logEvent(player, "created")
			break
		end
	end
	FranchiseService.pushState(player)
end

local function onRequest(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	FranchiseService.pushState(player)
end

local function startNow()
	DepthRemotes.FranchiseRequest.OnServerEvent:Connect(onRequest)
	DepthRemotes.FranchiseCreate.OnServerEvent:Connect(onCreate)
	DataService.onProfileLoaded(function(player)
		FranchiseService.pushState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		lastCandidateToast[player] = nil
	end)
end

-- Обновления по средам (Config/Features): до выхода системы «franchises» сервис спит — remotes
-- заглушены, циклы и обработчики не запущены; вышла (в т. ч. пока сервер работает) — startNow()
function FranchiseService.start()
	FeatureReleaseService.mute("franchises", {
		DepthRemotes.FranchiseRequest,
		DepthRemotes.FranchiseCreate,
	})
	FeatureReleaseService.whenReleased("franchises", "FranchiseService", startNow)
end

return FranchiseService
