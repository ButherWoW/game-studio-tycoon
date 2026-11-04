--!strict
-- Награда за приглашение друга (Config/Friends.referral).
-- Кто пригласил — при первом входе новичка: GetJoinData().ReferredByPlayerId (приглашение или
-- «Присоединиться» к другу), LaunchData "ref:<userId>" (приглашение из кнопки «📨»), иначе —
-- друг Roblox, который уже на сервере. Новичок — первый вход не раньше newWindowSeconds назад,
-- игр не выпускал, Rebirth не делал (смотрим один раз за жизнь профиля: поле checked).
-- Когда новичок наиграл minPlaySeconds (копится по сессиям): новичку newPlayerCash, пригласившему
-- (если он сейчас на сервере) — N минут дохода и кофе, не больше inviterDailyCap раз за сутки UTC.
-- Каждая сторона получает награду один раз; не выдали за expireSeconds — сгорает.
-- Кнопка «📨 Пригласить друга» (FriendsController) шлёт InviteSent — только счётчик в профиле.
-- Данные: (profile :: any).referral (лениво):
--   новичок: { checked, inviterId?, source?, at, played, newRewarded, inviterRewarded };
--   пригласивший: { invitesSent, rewardedCount, day, dayCount }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Friends = require(Shared.Config.Friends)
local FriendRemotes = require(Shared.FriendRemotes)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)

local MAX_INVITES_REPORT = 50 -- за один отчёт клиента больше не бывает

local ReferralService = {}
local lastReport: { [Player]: number } = {}

local function data(profile: DataService.Profile): { [string]: any }
	local p = profile :: any
	if type(p.referral) ~= "table" then
		p.referral = {}
	end
	local r = p.referral
	r.played = tonumber(r.played) or 0
	r.invitesSent = tonumber(r.invitesSent) or 0
	r.rewardedCount = tonumber(r.rewardedCount) or 0
	r.dayCount = tonumber(r.dayCount) or 0
	r.day = tonumber(r.day) or 0
	return r
end

local function notice(player: Player, payload: { [string]: any })
	FriendRemotes.FriendNotice:FireClient(player, payload)
end

local function log(player: Player, field: string)
	local analytics = script.Parent:FindFirstChild("AnalyticsService")
	if analytics and analytics:IsA("ModuleScript") then
		pcall((require(analytics) :: any).logDepth, player, "referral", field)
	end
end

local function isNew(profile: DataService.Profile): boolean
	local offers = (profile :: any).offers
	local firstJoin = if type(offers) == "table" then tonumber(offers.firstJoin) else nil
	return firstJoin ~= nil
		and os.time() - firstJoin <= Friends.referral.newWindowSeconds
		and profile.gamesReleased == 0
		and profile.rebirths == 0
end

-- Кто пригласил: userId и источник (nil — никто)
local function findInviter(player: Player): (number?, string?)
	local ok, join = pcall(function()
		return player:GetJoinData()
	end)
	if ok and type(join) == "table" then
		local referred = tonumber(join.ReferredByPlayerId)
		if referred and referred > 0 and referred ~= player.UserId then
			return referred, "invite"
		end
		local launch = join.LaunchData
		if type(launch) == "string" then
			local id = tonumber(launch:match("^ref:(%d+)$"))
			if id and id > 0 and id ~= player.UserId then
				return id, "launch"
			end
		end
	end
	-- Друг уже на сервере (зашёл раньше всех — первый в списке)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local okFriend, friends = pcall(function()
				return player:IsFriendsWith(other.UserId)
			end)
			if okFriend and friends == true then
				return other.UserId, "friend"
			end
		end
	end
	return nil, nil
end

local function onLoaded(player: Player, profile: DataService.Profile)
	local r = data(profile)
	if r.checked then
		return
	end
	r.checked = true
	if not isNew(profile) then
		return
	end
	local inviterId, source = findInviter(player)
	-- Пока ждали Roblox, игрок мог выйти
	if not inviterId or not player.Parent or DataService.get(player) ~= profile then
		return
	end
	r.inviterId = inviterId
	r.source = source
	r.at = os.time()
	r.newRewarded = false
	r.inviterRewarded = false
	local inviter = Players:GetPlayerByUserId(inviterId)
	notice(player, {
		kind = "referralPending",
		name = if inviter then inviter.DisplayName else "?",
		minutes = math.ceil(Friends.referral.minPlaySeconds / 60),
		money = Friends.referral.newPlayerCash,
	})
	log(player, "joined_" .. tostring(source))
end

local function rewardInviter(player: Player, r: { [string]: any })
	local cfg = Friends.referral
	local inviter = Players:GetPlayerByUserId(r.inviterId)
	local inviterProfile = inviter and DataService.get(inviter)
	if not inviter or not inviterProfile then
		return -- пригласившего нет на сервере: ждём, пока зайдёт (до expireSeconds)
	end
	r.inviterRewarded = true
	local ir = data(inviterProfile)
	local today = os.time() // 86400
	if ir.day ~= today then
		ir.day = today
		ir.dayCount = 0
	end
	if ir.dayCount >= cfg.inviterDailyCap then
		notice(inviter, { kind = "referralCap", name = player.DisplayName })
		log(inviter, "inviter_capped")
		return
	end
	ir.dayCount += 1
	ir.rewardedCount += 1
	local money = RewardService.incomeForMinutes(inviter, inviterProfile, cfg.inviterIncomeMinutes)
	RewardService.grant(
		inviter,
		{ incomeMinutes = cfg.inviterIncomeMinutes, coffeeMinutes = cfg.inviterCoffeeMinutes }
	)
	notice(inviter, { kind = "referralInviter", name = player.DisplayName, money = money })
	log(inviter, "inviter")
	task.spawn(DataService.save, inviter)
end

local function tick(player: Player, dt: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local r = data(profile)
	if type(r.inviterId) ~= "number" or (r.newRewarded and r.inviterRewarded) then
		return
	end
	local cfg = Friends.referral
	if os.time() - (tonumber(r.at) or 0) > cfg.expireSeconds then
		r.newRewarded = true
		r.inviterRewarded = true
		return
	end
	r.played += dt
	if r.played < cfg.minPlaySeconds then
		return
	end
	if not r.newRewarded then
		r.newRewarded = true
		DataService.addCash(player, cfg.newPlayerCash)
		RewardService.noteNonEarned(player, cfg.newPlayerCash)
		local inviter = Players:GetPlayerByUserId(r.inviterId)
		notice(player, {
			kind = "referralNew",
			money = cfg.newPlayerCash,
			name = if inviter then inviter.DisplayName else nil,
		})
		log(player, "new")
		task.spawn(DataService.save, player)
	end
	if not r.inviterRewarded then
		rewardInviter(player, r)
		if r.inviterRewarded then
			task.spawn(DataService.save, player)
		end
	end
end

local function onInviteSent(player: Player, count: any)
	local now = os.clock()
	if (lastReport[player] or 0) + Friends.referral.inviteReportCooldown > now then
		return
	end
	lastReport[player] = now
	local profile = DataService.get(player)
	if not profile or type(count) ~= "number" or count ~= count then
		return
	end
	local n = math.clamp(math.floor(count), 0, MAX_INVITES_REPORT)
	if n <= 0 then
		return
	end
	data(profile).invitesSent += n
	log(player, "invite_sent")
end

function ReferralService.start()
	DataService.onProfileLoaded(onLoaded)
	FriendRemotes.InviteSent.OnServerEvent:Connect(onInviteSent)
	Players.PlayerRemoving:Connect(function(player)
		lastReport[player] = nil
	end)
	task.spawn(function()
		local step = Friends.referral.tickSeconds
		while true do
			task.wait(step)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tick, player, step)
				if not ok then
					warn("[ReferralService] Tick failed:", err)
				end
			end
		end
	end)
end

return ReferralService
