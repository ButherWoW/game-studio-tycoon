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
local Employees = require(Shared.Config.Employees)
local DataService = require(script.Parent.DataService)

-- Фичи из других веток (тренды, магазин, исследования, задания) подключаются, если модуль есть.
-- Так порядок мёрджа PR не важен; без модуля множитель 1 и бонус 0.
local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end

local function shopModifiers(player: Player): any
	local ShopService = optional("ShopService")
	return if ShopService then ShopService.getModifiers(player) else nil
end

local function researchModifiers(player: Player): any
	local ResearchService = optional("ResearchService")
	return if ResearchService then ResearchService.getModifiers(player) else nil
end

-- Время разработки: исследование «Удобный движок» (devTime -0.1) и бусты скорости магазина.
-- Скорость сокращает время, а не добавляет очки, поэтому оценка от ускорения не падает:
-- очки в секунду умножаются на ту же скорость (см. цикл в start).
local function speedFactor(player: Player): number
	local shop = shopModifiers(player)
	return if shop and type(shop.devSpeed) == "number" and shop.devSpeed > 0 then shop.devSpeed else 1
end

local function durationFactor(player: Player): number
	local research = researchModifiers(player)
	local devTime = if research and type(research.devTime) == "number" then research.devTime else 0
	return math.max(1 + devTime, 0.25) / speedFactor(player)
end
local StaffService = require(script.Parent.StaffService)

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

local FOCUS_KEYS = { "gameplay", "graphics", "sound", "story" }

-- Очки в секунду по направлениям с учётом сотрудников. Каждый стол даёт pointsPerSecond,
-- сотрудник за ним умножает это на свой multiplier, а в своё направление — ещё на
-- (1 + specBonus), если в фокусе оно >= specThreshold. Формулы оценки не меняются.
function DevelopmentService.pointsRate(player: Player, focus: Focus): Formulas.Points
	local rate = { gameplay = 0, graphics = 0, sound = 0, story = 0 }
	local profile = DataService.get(player)
	if not profile then
		return rate
	end
	local byDesk = StaffService.employeesByDesk(player)
	local any = false
	for _, upgrade in Upgrades do
		local deskPoints = upgrade.pointsPerSecond
		if profile.upgrades[upgrade.id] and deskPoints then
			any = true
			local employee = byDesk[upgrade.id]
			local base = deskPoints * (if employee then employee.multiplier else 1)
			for _, key in FOCUS_KEYS do
				local share = (focus :: any)[key] :: number
				local bonus = 1
				if employee and employee.specialization == key and share >= Employees.specThreshold then
					bonus += Employees.specBonus
				end
				(rate :: any)[key] += base * share * bonus
			end
		end
	end
	if not any then
		-- Даже без стола игрок что-то делает сам: 1 очко/с
		for _, key in FOCUS_KEYS do
			(rate :: any)[key] = (focus :: any)[key]
		end
	end
	-- Ускорение сокращает время, поэтому очки в секунду растут так же: за игру их столько же
	local tempo = 1 / durationFactor(player)
	local research = researchModifiers(player)
	local graphics = if research and type(research.graphicsPoints) == "number"
		then research.graphicsPoints
		else 0
	local sound = if research and type(research.soundPoints) == "number" then research.soundPoints else 0
	rate.gameplay *= tempo
	rate.graphics *= tempo * (1 + graphics)
	rate.sound *= tempo * (1 + sound)
	rate.story *= tempo
	return rate
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
		duration = BASE_DURATION * durationFactor(player),
	}
end

local function release(player: Player, project: Project)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local score = Formulas.review(project.genreId, project.topicId, project.points, rng)
	local TrendService = optional("TrendService")
	if TrendService then
		score += TrendService.getBonus(project.genreId, project.topicId)
	end
	-- Продукт «Патч»: +1 к оценке, заряд тратится только если есть куда расти
	local ShopService = optional("ShopService")
	if ShopService and score < 10 and ShopService.consumeCharge(player, "patch") then
		score += 1
	end
	score = math.clamp(score, 1, 10)

	local adBonus = 0
	if profile.activeAd and profile.activeAd.expiresAt > os.time() then
		adBonus = profile.activeAd.bonus
	end
	local rebirthMultiplier = 1 + 0.5 * profile.rebirths
	local revenue = Formulas.revenue(score, profile.studioLevel, adBonus, rebirthMultiplier)
	local shop = shopModifiers(player)
	local research = researchModifiers(player)
	local cashMultiplier = if shop and type(shop.cashMultiplier) == "number" then shop.cashMultiplier else 1
	local researchBonus = if research and type(research.revenue) == "number" then research.revenue else 0
	revenue = math.floor(revenue * cashMultiplier * (1 + researchBonus))

	local isRecord = profile.gamesReleased > 0 and score > profile.bestScore
	profile.gamesReleased += 1
	profile.bestScore = math.max(profile.bestScore, score)
	DataService.addCash(player, revenue)

	local ResearchService = optional("ResearchService")
	if ResearchService then
		ResearchService.onGameReleased(player, score)
	end
	local ExpoService = optional("ExpoService")
	if ExpoService then
		local p = project.points
		ExpoService.onGameReleased(player, {
			name = project.name,
			score = score,
			points = p.gameplay + p.graphics + p.sound + p.story,
		})
	end
	local QuestService = optional("QuestService")
	if QuestService then
		QuestService.onGameReleased(player, {
			genreId = project.genreId,
			topicId = project.topicId,
			score = score,
			focus = project.focus,
		})
	end

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
				local rate = DevelopmentService.pointsRate(player, project.focus)
				project.points.gameplay += rate.gameplay * TICK
				project.points.graphics += rate.graphics * TICK
				project.points.sound += rate.sound * TICK
				project.points.story += rate.story * TICK
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
