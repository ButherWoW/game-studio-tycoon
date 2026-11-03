--!strict
-- Разработка и релиз игр. Всё считается на сервере.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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

local DevelopmentService = {}
local projects: { [Player]: Project } = {}
local rng = Random.new()

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
		if v < 0 or v ~= v then
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
	local name = if type(request.name) == "string"
		then request.name:sub(1, MAX_NAME_LENGTH)
		else "Без названия"
	-- TODO (Фаза 2): фильтровать name через TextService:FilterStringAsync перед показом другим игрокам

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

	profile.gamesReleased += 1
	profile.bestScore = math.max(profile.bestScore, score)
	DataService.addCash(player, revenue)

	Remotes.GameReleased:FireClient(player, {
		name = project.name,
		score = score,
		revenue = revenue,
		adBonus = adBonus,
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
