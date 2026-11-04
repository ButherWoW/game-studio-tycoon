--!strict
-- Награда за вступление в группу Roblox (Config/Social.groupId; 0 — выключено).
-- Один раз за жизнь игрока: открытый скин groupReward.skin и N минут дохода.
-- Проверка при входе, раз в groupCheckSeconds, пока награда не получена, и по GroupCheck
-- (клиент нажал «Вступить»), не чаще CHECK_COOLDOWN.
-- Атрибут GroupRewarded — клиент прячет подсказку в магазине.
-- Данные: (profile :: any).social = { groupRewarded = true } (лениво, defaultProfile не трогаем).

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Social = require(Shared.Config.Social)
local SocialRemotes = require(Shared.SocialRemotes)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local SkinService = require(script.Parent.SkinService)

local CHECK_COOLDOWN = 10 -- запрос к Roblox не чаще, с
local PROFILE_WAIT = 0.5

local SocialService = {}
local lastCheck: { [Player]: number } = {}
local checking: { [Player]: boolean } = {}

local function rewarded(profile: DataService.Profile): boolean
	local social = (profile :: any).social
	return type(social) == "table" and social.groupRewarded == true
end

-- true/false — в группе или нет; nil — Roblox не ответил
local function inGroup(player: Player, groupId: number): boolean?
	-- GetGroupsAsync не кэшируется на сессию (IsInGroup — кэшируется): видно вступление посреди игры
	local ok, groups = pcall(function()
		return GroupService:GetGroupsAsync(player.UserId)
	end)
	if ok and type(groups) == "table" then
		for _, group in groups do
			if type(group) == "table" and group.Id == groupId then
				return true
			end
		end
		return false
	end
	local okMember, member = pcall(function()
		return player:IsInGroup(groupId)
	end)
	return if okMember then member == true else nil
end

local function grantReward(player: Player, profile: DataService.Profile)
	local p = profile :: any
	if type(p.social) ~= "table" then
		p.social = {}
	end
	p.social.groupRewarded = true
	player:SetAttribute("GroupRewarded", true)
	local reward = Social.groupReward
	SkinService.grantSkin(player, profile, reward.skin)
	local money = RewardService.incomeForMinutes(player, profile, reward.incomeMinutes)
	RewardService.grant(player, { incomeMinutes = reward.incomeMinutes })
	SocialRemotes.SocialNotice:FireClient(
		player,
		{ kind = "groupReward", money = money, itemId = reward.skin }
	)
	task.spawn(DataService.save, player)
	local analytics = script.Parent:FindFirstChild("AnalyticsService")
	if analytics and analytics:IsA("ModuleScript") then
		pcall((require(analytics) :: any).logGroupReward, player)
	end
end

local function check(player: Player)
	local groupId = Social.groupId
	if groupId <= 0 or checking[player] then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if rewarded(profile) then
		player:SetAttribute("GroupRewarded", true)
		return
	end
	local now = os.clock()
	if (lastCheck[player] or 0) + CHECK_COOLDOWN > now then
		return
	end
	lastCheck[player] = now
	checking[player] = true
	local member = inGroup(player, groupId)
	checking[player] = nil
	-- Пока ждали Roblox, игрок мог выйти или получить награду
	if member and player.Parent and DataService.get(player) == profile and not rewarded(profile) then
		grantReward(player, profile)
	end
end

local function onPlayerAdded(player: Player)
	while not DataService.get(player) and player.Parent do
		task.wait(PROFILE_WAIT)
	end
	if player.Parent then
		check(player)
	end
end

function SocialService.start()
	if Social.groupId <= 0 then
		return
	end
	SocialRemotes.GroupCheck.OnServerEvent:Connect(function(player)
		task.spawn(check, player)
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastCheck[player] = nil
		checking[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Social.groupCheckSeconds)
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("GroupRewarded") ~= true then
					task.spawn(check, player)
				end
			end
		end
	end)
end

return SocialService
