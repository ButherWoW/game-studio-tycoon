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
local DataService = require(script.Parent.DataService)

type Focus = { gameplay: number, graphics: number, sound: number, story: number }

type Project = {
	name: string,
	genreId: string,
	topicId: string,
	focus: Focus,
	points: Formulas.Points,
	elapsed: number,
	duration: number,
}

local BASE_DURATION = 30 -- секунд на одну игру в начале
local MAX_NAME_LENGTH = 30
local DEFAULT_NAME = "Без названия"

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

local function pointsPerSecond(player: Player): number
	local profile = DataService.get(player)
	if not profile then
		return 0
	end
	local total = 0
	for _, upgrade in Upgrades do
		if profile.upgrades[upgrade.id] and upgrade.pointsPerSecond then
			total += upgrade.pointsPerSecond
		end
	end
	return math.max(total, 1) -- даже без стола игрок что-то делает сам
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
	local rawName = if type(request.name) == "string" then request.name:sub(1, MAX_NAME_LENGTH) else ""

	-- Фильтр уступает поток: занимаем слот заранее, чтобы второй запрос не прошёл
	projects[player] = PENDING
	local name = filterName(player, rawName)
	if projects[player] ~= PENDING or not player.Parent then
		return
	end

	projects[player] = {
		name = name,
		genreId = genreId,
		topicId = topicId,
		focus = focus,
		points = { gameplay = 0, graphics = 0, sound = 0, story = 0 },
		elapsed = 0,
		duration = BASE_DURATION,
	}
end

local function release(player: Player, project: Project)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local score = Formulas.review(project.genreId, project.topicId, project.points, rng)

	local adBonus = 0
	if profile.activeAd and profile.activeAd.expiresAt > os.time() then
		adBonus = profile.activeAd.bonus
	end
	local rebirthMultiplier = 1 + 0.5 * profile.rebirths
	local revenue = Formulas.revenue(score, profile.studioLevel, adBonus, rebirthMultiplier)

	local isRecord = profile.gamesReleased > 0 and score > profile.bestScore
	profile.gamesReleased += 1
	profile.bestScore = math.max(profile.bestScore, score)
	DataService.addCash(player, revenue)

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

function DevelopmentService.start()
	Remotes.StartDevelopment.OnServerEvent:Connect(onStartDevelopment)
	Players.PlayerRemoving:Connect(function(player)
		projects[player] = nil
	end)

	-- Один общий цикл вместо таймера на каждого игрока
	task.spawn(function()
		local TICK = 0.5
		while true do
			task.wait(TICK)
			for player, project in projects do
				if project == PENDING then
					continue
				end
				local pps = pointsPerSecond(player) * TICK
				project.points.gameplay += pps * project.focus.gameplay
				project.points.graphics += pps * project.focus.graphics
				project.points.sound += pps * project.focus.sound
				project.points.story += pps * project.focus.story
				project.elapsed += TICK

				Remotes.DevelopmentProgress:FireClient(player, {
					progress = math.min(project.elapsed / project.duration, 1),
					points = project.points,
				})

				if project.elapsed >= project.duration then
					projects[player] = nil
					release(player, project)
				end
			end
		end
	end)
end

return DevelopmentService
