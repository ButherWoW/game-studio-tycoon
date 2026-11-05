--!strict
-- Мини-аркада «Сыграй в свою игру» (Config/Arcade): серверная часть.
--   • DevelopmentService после релиза зовёт onGameReleased — запоминаем релиз (последние keepReleases).
--   • ArcadeStart(projectId): релиз не старше windowSeconds и ещё не игрался → сессия
--     { token, kind, seed }; релиз сразу помечается сыгранным (переиграть ради золота нельзя).
--   • ArcadeSubmit(token, score): одна отправка на сессию, не раньше countdown + duration − submitEarly
--     и не позже + submitLate; бонус — доля дохода.
--   • Проверка счёта: Arcade.plausible (целое, не выше maxScore и par × plausibleShare). Неправдоподобный
--     счёт — без медали, бонуса и достижения «arcadeGold» (раньше обрезался до максимума = золото).
-- Клиенту можно не верить: худшее, что даст подделка счёта, — +5% дохода одного релиза.
-- Данные в профиль не пишем: всё живёт в памяти сервера несколько минут.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Arcade = require(Shared.Config.Arcade)
local ArcadeRemotes = require(Shared.ArcadeRemotes)
local DataService = require(script.Parent.DataService)

type Release = { projectId: number, revenue: number, genreId: string, at: number, started: boolean }
type Session = {
	token: number,
	projectId: number,
	kind: Arcade.Kind,
	seed: number,
	revenue: number,
	issuedAt: number,
}

local ArcadeService = {}
local releases: { [Player]: { Release } } = {}
local sessions: { [Player]: Session } = {}
local lastStart: { [Player]: number } = {}
local nextToken = 0
local rng = Random.new()

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

-- Вызвать функцию другого сервиса, если он есть; его ошибка не ломает аркаду
local function hook(name: string, fnName: string, ...: any)
	local module = optional(name)
	local fn = module and module[fnName]
	if type(fn) == "function" then
		pcall(fn, ...)
	end
end

-- Релиз (зовёт DevelopmentService): запомнить для плейтеста
function ArcadeService.onGameReleased(
	player: Player,
	info: { projectId: number, revenue: number, genreId: string }
)
	if not Arcade.enabled or type(info) ~= "table" or type(info.projectId) ~= "number" then
		return
	end
	local revenue = tonumber(info.revenue) or 0
	if revenue <= 0 or revenue ~= revenue then
		return
	end
	local list = releases[player] or {}
	table.insert(list, {
		projectId = info.projectId,
		revenue = revenue,
		genreId = tostring(info.genreId),
		at = os.clock(),
		started = false,
	})
	while #list > Arcade.keepReleases do
		table.remove(list, 1)
	end
	releases[player] = list
end

local function findRelease(player: Player, projectId: number): Release?
	for _, release in releases[player] or {} do
		if release.projectId == projectId then
			return release
		end
	end
	return nil
end

local function onStart(player: Player, projectId: any)
	if not Arcade.enabled or type(projectId) ~= "number" or projectId ~= projectId then
		return
	end
	local now = os.clock()
	if (lastStart[player] or 0) + Arcade.startCooldown > now then
		ArcadeRemotes.ArcadeSession:FireClient(player, { projectId = projectId, error = "busy" })
		return
	end
	lastStart[player] = now
	local release = findRelease(player, projectId)
	local problem: string? = nil
	if not release or now - release.at > Arcade.windowSeconds then
		problem = "expired"
	elseif release.started then
		problem = "used"
	end
	if problem or not release then
		ArcadeRemotes.ArcadeSession:FireClient(player, {
			projectId = projectId,
			error = problem or "expired",
			minutes = math.floor(Arcade.windowSeconds / 60),
		})
		return
	end
	release.started = true
	nextToken += 1
	local kind = Arcade.kindFor(release.genreId)
	local session: Session = {
		token = nextToken,
		projectId = projectId,
		kind = kind,
		seed = rng:NextInteger(1, 2 ^ 30),
		revenue = release.revenue,
		issuedAt = now,
	}
	sessions[player] = session
	ArcadeRemotes.ArcadeSession:FireClient(player, {
		projectId = projectId,
		token = session.token,
		kind = kind,
		seed = session.seed,
		duration = Arcade.duration,
		countdown = Arcade.countdown,
	})
	hook("AnalyticsService", "logDepth", player, "arcade", kind .. "_start")
end

local function onSubmit(player: Player, token: any, score: any)
	local session = sessions[player]
	if not session or token ~= session.token then
		return
	end
	-- Одна отправка на сессию
	sessions[player] = nil
	local elapsed = os.clock() - session.issuedAt
	local playTime = Arcade.countdown + Arcade.duration
	local value = if type(score) == "number" and score == score then score else 0
	local onTime = elapsed >= playTime - Arcade.submitEarly and elapsed <= playTime + Arcade.submitLate
	-- Прислано раньше конца игры, слишком поздно или счёт не мог быть набран честно — без медали
	local plausible = onTime and Arcade.plausible(session.kind, session.seed, value)
	if not plausible then
		if onTime and value > 0 then
			hook("AnalyticsService", "logDepth", player, "arcade", session.kind .. "_implausible")
		end
		value = 0
	end
	value = math.clamp(math.floor(value), 0, Arcade.maxScore(session.kind, session.seed))
	local grade = if plausible then Arcade.grade(session.kind, session.seed, value) else nil
	local bonus = if grade then math.floor(session.revenue * Arcade.bonus[grade]) else 0
	if bonus > 0 then
		DataService.addCash(player, bonus)
		-- Как пакеты дохода: не засчитываем в задания «заработай»
		hook("RewardService", "noteNonEarned", player, bonus)
	end
	-- Достижение — только за правдоподобное золото
	if plausible and grade == "gold" then
		hook("AchievementService", "note", player, "arcadeGold")
	end
	hook("AnalyticsService", "logDepth", player, "arcade", session.kind .. "_" .. (grade or "none"))
	ArcadeRemotes.ArcadeResult:FireClient(player, {
		token = session.token,
		score = value,
		grade = grade,
		bonus = bonus,
	})
end

function ArcadeService.start()
	Players.PlayerRemoving:Connect(function(player)
		releases[player] = nil
		sessions[player] = nil
		lastStart[player] = nil
	end)
	ArcadeRemotes.ArcadeStart.OnServerEvent:Connect(onStart)
	ArcadeRemotes.ArcadeSubmit.OnServerEvent:Connect(onSubmit)
end

return ArcadeService
