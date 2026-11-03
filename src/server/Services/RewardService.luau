--!strict
-- Выдача наград заданий и наград за вход. Без start(): это библиотека для QuestService
-- и DailyRewardService. Неденежные награды копятся в profile.rewards — их подхватят
-- системы из своих issues (см. TODO в Config/Rewards).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rewards = require(ReplicatedStorage.Shared.Config.Rewards)
local RewardFormulas = require(ReplicatedStorage.Shared.RewardFormulas)
local DataService = require(script.Parent.DataService)

export type RewardStore = {
	researchPoints: number, -- TODO #8
	incomeBonus: number, -- TODO #9: доход × (1 + incomeBonus) в DevelopmentService
	badges: { [string]: boolean }, -- TODO #9: BadgeService
	employees: { [string]: boolean }, -- TODO #7
	trophies: { [string]: number }, -- TODO #10: декор на участке
	coffeeUntil: number, -- os.time(), TODO #10: ×2 скорость разработки до этого времени
}

local RewardService = {}

-- Деньги из наград, которые QuestService не должен считать «заработком» за сессию
local rewardCash: { [Player]: number } = {}

-- Ленивая инициализация: defaultProfile не трогаем
function RewardService.store(profile: DataService.Profile): RewardStore
	local p = profile :: any
	local store = p.rewards
	if type(store) ~= "table" then
		store = {}
		p.rewards = store
	end
	store.researchPoints = tonumber(store.researchPoints) or 0
	store.incomeBonus = tonumber(store.incomeBonus) or 0
	store.coffeeUntil = tonumber(store.coffeeUntil) or 0
	if type(store.badges) ~= "table" then
		store.badges = {}
	end
	if type(store.employees) ~= "table" then
		store.employees = {}
	end
	if type(store.trophies) ~= "table" then
		store.trophies = {}
	end
	return store :: RewardStore
end

function RewardService.incomeForMinutes(profile: DataService.Profile, minutes: number): number
	return RewardFormulas.incomeForMinutes(profile.bestScore, profile.studioLevel, profile.rebirths, minutes)
end

-- Забрать накопленные деньги из наград (QuestService вычитает их из заработка)
function RewardService.takeRewardCash(player: Player): number
	local amount = rewardCash[player] or 0
	rewardCash[player] = nil
	return amount
end

function RewardService.forget(player: Player)
	rewardCash[player] = nil
end

function RewardService.grant(player: Player, reward: Rewards.Reward)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local store = RewardService.store(profile)
	local now = os.time()

	if reward.researchPoints then
		store.researchPoints += reward.researchPoints
	end
	if reward.incomeBonus then
		store.incomeBonus += reward.incomeBonus
	end
	if reward.badge then
		store.badges[reward.badge] = true
	end
	if reward.employee then
		store.employees[reward.employee] = true
	end
	if reward.trophy then
		store.trophies[reward.trophy] = (store.trophies[reward.trophy] or 0) + 1
	end
	if reward.coffeeMinutes then
		store.coffeeUntil = math.max(store.coffeeUntil, now) + reward.coffeeMinutes * 60
	end
	if reward.adBonus and reward.adMinutes then
		-- Как в MonetizationService: бонусы не складываются, берём больший, время продлеваем
		local bonus = reward.adBonus
		local current = profile.activeAd
		if current and current.expiresAt > now then
			bonus = math.max(bonus, current.bonus)
		end
		profile.activeAd = { bonus = math.min(bonus, 1), expiresAt = now + reward.adMinutes * 60 }
	end

	if reward.incomeMinutes then
		local cash = RewardService.incomeForMinutes(profile, reward.incomeMinutes)
		rewardCash[player] = (rewardCash[player] or 0) + cash
		DataService.addCash(player, cash) -- внутри replicate
	else
		DataService.replicate(player)
	end
end

return RewardService
