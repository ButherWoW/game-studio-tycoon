--!strict
-- Совместная разработка (Config/Coop, клиент — CoopController).
--   * Хозяин сидит за своим ПК и зовёт игрока с сервера в текущую игру (не ноутбук в парке).
--   * Гость принимает, сидя за своим ПК, и помогает «удалённо»: пока оба за ПК, проект хозяина
--     получает очки мощности студии гостя × Coop.guestPowerShare (DevelopmentService.tickProject
--     зовёт bonusPoints). Оценку считает хозяин со своими бонусами.
--   * Релиз (DevelopmentService.release зовёт settle): гостю Coop.hostShare-остаток дохода
--     (не больше Coop.guestCapMinutes его дохода), хозяину остальное. Гость ушёл с сервера,
--     вышел из проекта или почти не помогал — всё хозяину.
--   * Один совместный проект на игрока (хозяин или гость), кулдаун хозяина после конца.
-- Состояние только в памяти сервера: совместная игра живёт, пока живёт проект хозяина.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Coop = require(Shared.Config.Coop)
local Upgrades = require(Shared.Config.Upgrades)
local CoopRemotes = require(Shared.CoopRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local DevelopmentService = require(script.Parent.DevelopmentService)
local FeatureReleaseService = require(script.Parent.FeatureReleaseService)

local TICK = 1
local REPLY_COOLDOWN = 0.5

type Session = {
	host: Player,
	guest: Player,
	projectId: number,
	game: string,
	devSeconds: number, -- сколько шла разработка хозяина после вступления гостя
	helpSeconds: number, -- из них гость сидел за ПК
}
type Invite = { id: number, host: Player, guest: Player, projectId: number, expiresAt: number }

local CoopService = {}

local byHost: { [Player]: Session } = {}
local byGuest: { [Player]: Session } = {}
local invites: { [number]: Invite } = {}
local nextInviteId = 0
local lastInvite: { [Player]: number } = {}
local lastReply: { [Player]: number } = {}
local cooldownUntil: { [Player]: number } = {}

-- Фичи других веток — по требованию; без модуля ничего не делаем
local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end

local function call(name: string, fnName: string, ...: any)
	local module = optional(name)
	local fn = module and module[fnName]
	if type(fn) == "function" then
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[CoopService] " .. name .. "." .. fnName .. " failed:", err)
		end
	end
end

local function logAnalytics(player: Player, stage: string)
	call("AnalyticsService", "logDepth", player, "coop", stage)
end

local function notice(player: Player, data: { [string]: any })
	if player.Parent then
		CoopRemotes.CoopNotice:FireClient(player, data)
	end
end

local function inSession(player: Player): boolean
	return byHost[player] ~= nil or byGuest[player] ~= nil
end

-- Мощность студии гостя: сумма очков/с купленной техники (как в доходе релиза)
local function guestPower(guest: Player): number
	local profile = DataService.get(guest)
	if not profile then
		return 0
	end
	local power = 0
	for _, upgrade in Upgrades do
		if profile.upgrades[upgrade.id] and upgrade.pointsPerSecond then
			power += upgrade.pointsPerSecond
		end
	end
	return math.max(power, Coop.guestMinPower)
end

local function sendState(session: Session?, player: Player)
	if not player.Parent then
		return
	end
	if not session then
		CoopRemotes.CoopState:FireClient(player, nil)
		return
	end
	local info = DevelopmentService.projectInfo(session.host, session.projectId)
	local progress = if info and info.duration > 0 then math.clamp(info.elapsed / info.duration, 0, 1) else 0
	local isHost = session.host == player
	CoopRemotes.CoopState:FireClient(player, {
		role = if isHost then "host" else "guest",
		partner = if isHost then session.guest.DisplayName else session.host.DisplayName,
		game = session.game,
		projectId = session.projectId,
		progress = progress,
		helping = PlotService.isAtPc(session.guest),
	})
end

-- Закончить без дележа (вышел, отменили, проект пропал): доход останется хозяину целиком
local function endSession(session: Session, reason: string)
	if byHost[session.host] ~= session then
		return
	end
	byHost[session.host] = nil
	byGuest[session.guest] = nil
	cooldownUntil[session.host] = os.clock() + Coop.cooldownSeconds
	sendState(nil, session.host)
	sendState(nil, session.guest)
	notice(session.host, { kind = "ended", reason = reason, name = session.guest.DisplayName })
	notice(session.guest, { kind = "ended", reason = reason, name = session.host.DisplayName })
	logAnalytics(session.host, "ended_" .. reason)
end

-- Можно ли хозяину звать в этот проект; причина отказа — для тоста
local function inviteProblem(host: Player, guest: Player?, projectId: number): string?
	if not guest or guest == host or not guest.Parent then
		return "gone"
	end
	if not PlotService.isAtPc(host) then
		return "hostPc"
	end
	if not PlotService.ownsGarage(host) or not PlotService.ownsGarage(guest) then
		return "garage"
	end
	local info = DevelopmentService.projectInfo(host, projectId)
	if not info or info.pending or info.laptop then
		return "noProject"
	end
	if info.duration - info.elapsed < Coop.minRemainingSeconds then
		return "tooLate"
	end
	if inSession(host) then
		return "busy"
	end
	if inSession(guest) then
		return "guestBusy"
	end
	if (cooldownUntil[host] or 0) > os.clock() then
		return "cooldown"
	end
	return nil
end

local function onInvite(host: Player, userId: any, projectId: any)
	if type(userId) ~= "number" or type(projectId) ~= "number" or projectId ~= projectId then
		return
	end
	local now = os.clock()
	if (lastInvite[host] or 0) + Coop.inviteCooldown > now then
		notice(host, { kind = "fail", reason = "wait" })
		return
	end
	local guest = Players:GetPlayerByUserId(userId)
	local problem = inviteProblem(host, guest, projectId)
	if problem or not guest then
		notice(host, { kind = "fail", reason = problem or "gone" })
		return
	end
	lastInvite[host] = now
	-- У хозяина одно приглашение: старое сгорает
	for id, invite in invites do
		if invite.host == host then
			invites[id] = nil
		end
	end
	nextInviteId += 1
	local info = DevelopmentService.projectInfo(host, projectId)
	invites[nextInviteId] = {
		id = nextInviteId,
		host = host,
		guest = guest,
		projectId = projectId,
		expiresAt = now + Coop.inviteSeconds,
	}
	CoopRemotes.CoopInvited:FireClient(guest, {
		inviteId = nextInviteId,
		name = host.DisplayName,
		game = if info then info.name else "",
		seconds = Coop.inviteSeconds,
	})
	notice(host, { kind = "sent", name = guest.DisplayName })
	logAnalytics(host, "invited")
end

local function onReply(guest: Player, inviteId: any, accept: any)
	if type(inviteId) ~= "number" then
		return
	end
	local now = os.clock()
	if (lastReply[guest] or 0) + REPLY_COOLDOWN > now then
		return
	end
	lastReply[guest] = now
	local invite = invites[inviteId]
	if not invite or invite.guest ~= guest then
		return
	end
	if invite.expiresAt < now then
		invites[inviteId] = nil
		notice(guest, { kind = "fail", reason = "expired" })
		return
	end
	local host = invite.host
	if accept ~= true then
		invites[inviteId] = nil
		notice(host, { kind = "declined", name = guest.DisplayName })
		return
	end
	-- Гость принимает за своим ПК; приглашение не сгорает — можно сесть и нажать снова
	if not PlotService.isAtPc(guest) then
		notice(guest, { kind = "fail", reason = "guestPc" })
		return
	end
	local info = DevelopmentService.projectInfo(host, invite.projectId)
	local problem: string? = nil
	if not host.Parent then
		problem = "gone"
	elseif not info or info.pending or info.laptop then
		problem = "noProject"
	elseif info.duration - info.elapsed < Coop.minRemainingSeconds then
		problem = "tooLate"
	elseif inSession(host) then
		problem = "busy"
	elseif inSession(guest) then
		problem = "guestBusy"
	end
	invites[inviteId] = nil
	if problem or not info then
		notice(guest, { kind = "fail", reason = problem or "gone" })
		return
	end
	local session: Session = {
		host = host,
		guest = guest,
		projectId = invite.projectId,
		game = info.name,
		devSeconds = 0,
		helpSeconds = 0,
	}
	byHost[host] = session
	byGuest[guest] = session
	notice(host, { kind = "joined", name = guest.DisplayName })
	notice(guest, { kind = "joinedGuest", name = host.DisplayName })
	sendState(session, host)
	sendState(session, guest)
	logAnalytics(host, "accepted")
end

local function onLeave(player: Player)
	local session = byHost[player] or byGuest[player]
	if session then
		endSession(session, if session.host == player then "hostLeft" else "guestLeft")
	end
end

-- DevelopmentService.tickProject: очки гостя за шаг step (всего, по фокусу делит вызывающий).
-- Хозяин уже за ПК и разработка идёт; гость должен сидеть за своим ПК
function CoopService.bonusPoints(host: Player, projectId: number, tempo: number, step: number): number
	local session = byHost[host]
	if not session or session.projectId ~= projectId or type(step) ~= "number" or step <= 0 then
		return 0
	end
	session.devSeconds += step
	if not session.guest.Parent or not PlotService.isAtPc(session.guest) then
		return 0
	end
	session.helpSeconds += step
	local speed = if type(tempo) == "number" and tempo > 0 and tempo < math.huge then tempo else 1
	return guestPower(session.guest) * Coop.guestPowerShare * speed * step
end

-- DevelopmentService.release: доля хозяина и гость (если делились). Гостю платим здесь
function CoopService.settle(host: Player, projectId: number, revenue: number): (number, Player?)
	local session = byHost[host]
	if not session or session.projectId ~= projectId then
		return revenue, nil
	end
	byHost[host] = nil
	byGuest[session.guest] = nil
	cooldownUntil[host] = os.clock() + Coop.cooldownSeconds
	local guest = session.guest
	sendState(nil, host)
	sendState(nil, guest)
	local helped = session.helpSeconds >= Coop.minGuestSeconds
		and session.helpSeconds >= Coop.minGuestShare * session.devSeconds
	local guestProfile = DataService.get(guest)
	if not guest.Parent or not guestProfile or not helped or type(revenue) ~= "number" or revenue <= 0 then
		notice(host, { kind = "noSplit", name = guest.DisplayName })
		notice(guest, { kind = "noSplitGuest", name = host.DisplayName })
		logAnalytics(host, "noSplit")
		return revenue, nil
	end
	local share = math.floor(revenue * (1 - math.clamp(Coop.hostShare, 0, 1)))
	local RewardService = optional("RewardService")
	if RewardService then
		local ok, cap = pcall(RewardService.incomeForMinutes, guest, guestProfile, Coop.guestCapMinutes)
		if ok and type(cap) == "number" and cap == cap and cap >= 0 then
			share = math.min(share, math.floor(cap))
		end
	end
	share = math.max(share, 0)
	DataService.addCash(guest, share)
	call("SeasonService", "addXp", guest, Coop.guestSeasonXp, "coop")
	call("AchievementService", "note", host, "coopGames", 1)
	call("AchievementService", "note", guest, "coopGames", 1)
	notice(host, { kind = "split", name = guest.DisplayName, money = share })
	notice(guest, { kind = "paid", name = host.DisplayName, game = session.game, money = share })
	logAnalytics(host, "split")
	return revenue - share, guest
end

-- С кем сейчас идёт совместная игра (для других фич); nil — ни с кем
function CoopService.partnerOf(player: Player): Player?
	local session = byHost[player] or byGuest[player]
	if not session then
		return nil
	end
	return if session.host == player then session.guest else session.host
end

local function startNow()
	CoopRemotes.CoopInvite.OnServerEvent:Connect(onInvite)
	CoopRemotes.CoopReply.OnServerEvent:Connect(onReply)
	CoopRemotes.CoopLeave.OnServerEvent:Connect(onLeave)
	Players.PlayerRemoving:Connect(function(player)
		onLeave(player)
		for id, invite in invites do
			if invite.host == player or invite.guest == player then
				invites[id] = nil
			end
		end
		lastInvite[player] = nil
		lastReply[player] = nil
		cooldownUntil[player] = nil
	end)

	-- Прогресс обоим, конец сессии, если проект пропал (Rebirth, ошибка), сгоревшие приглашения
	task.spawn(function()
		while true do
			task.wait(TICK)
			local now = os.clock()
			for id, invite in invites do
				if invite.expiresAt < now then
					invites[id] = nil
				end
			end
			local list = {}
			for _, session in byHost do
				table.insert(list, session)
			end
			for _, session in list do
				local ok, err = pcall(function()
					if not DevelopmentService.projectInfo(session.host, session.projectId) then
						endSession(session, "cancelled")
					else
						sendState(session, session.host)
						sendState(session, session.guest)
					end
				end)
				if not ok then
					warn("[CoopService] tick failed:", err)
				end
			end
		end
	end)
end

-- Обновления по средам (Config/Features): до выхода системы «coop» сервис спит — remotes
-- заглушены, циклы и обработчики не запущены; вышла (в т. ч. пока сервер работает) — startNow()
function CoopService.start()
	FeatureReleaseService.mute("coop", {
		CoopRemotes.CoopInvite,
		CoopRemotes.CoopReply,
		CoopRemotes.CoopLeave,
	})
	FeatureReleaseService.whenReleased("coop", "CoopService", startNow)
end

return CoopService
