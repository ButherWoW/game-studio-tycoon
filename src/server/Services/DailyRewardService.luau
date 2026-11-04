--!strict
-- Награды за вход 7 дней подряд (issue #10). День — по UTC.
-- Вчера забрал -> сегодня следующий день серии; пропуск -> день 1; после 7 -> снова 1.
-- profile.dailyReward = { lastClaimDay, streak } (ленивая инициализация).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestRemotes = require(ReplicatedStorage.Shared.QuestRemotes)
local DailyRewards = require(ReplicatedStorage.Shared.Config.DailyRewards)
local Social = require(ReplicatedStorage.Shared.Config.Social)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)

local POLL_SECONDS = 2
local REQUEST_COOLDOWN = 1
local DAY_SECONDS = 86_400

type DailyRewardData = { lastClaimDay: number, streak: number }

local DailyRewardService = {}

-- Какой день UTC последним отправили клиенту: при смене суток окно покажется снова
local sentDay: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}

local function today(): number
	return os.time() // DAY_SECONDS
end

local function data(profile: DataService.Profile): DailyRewardData
	local p = profile :: any
	local d = p.dailyReward
	if type(d) ~= "table" then
		d = {}
		p.dailyReward = d
	end
	d.lastClaimDay = tonumber(d.lastClaimDay) or -1
	d.streak = tonumber(d.streak) or 0
	return d :: DailyRewardData
end

-- День серии (1..7), который можно забрать сегодня, и можно ли
local function current(profile: DataService.Profile): (number, boolean)
	local d = data(profile)
	local day = today()
	if d.lastClaimDay == day then
		return math.clamp(d.streak, 1, #DailyRewards), false
	end
	if d.lastClaimDay == day - 1 then
		return d.streak % #DailyRewards + 1, true
	end
	return 1, true
end

local function sendState(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local streakDay, available = current(profile)
	sentDay[player] = today()
	QuestRemotes.DailyRewardState:FireClient(player, { day = streakDay, available = available })
end

local function onClaim(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local streakDay, available = current(profile)
	if not available then
		return
	end
	local d = data(profile)
	d.lastClaimDay = today()
	d.streak = streakDay
	RewardService.grant(player, DailyRewards[streakDay])
	-- Roblox Premium: кофе к награде (Social.premium.dailyCoffeeMinutes, 0 — выключено)
	local coffee = Social.premium.dailyCoffeeMinutes
	if coffee > 0 and player.MembershipType == Enum.MembershipType.Premium then
		RewardService.grant(player, { coffeeMinutes = coffee })
	end
	sendState(player)
end

function DailyRewardService.start()
	QuestRemotes.ClaimDailyReward.OnServerEvent:Connect(onClaim)
	QuestRemotes.RequestQuestData.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
			return
		end
		lastRequest[player] = now
		sendState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		sentDay[player] = nil
		lastRequest[player] = nil
	end)

	-- Профиль грузится асинхронно: отправляем, как только он появился, и при смене суток
	task.spawn(function()
		while true do
			task.wait(POLL_SECONDS)
			local day = today()
			for _, player in Players:GetPlayers() do
				if sentDay[player] ~= day and DataService.get(player) then
					sendState(player)
				end
			end
		end
	end)
end

return DailyRewardService
