--!strict
-- Офлайн-доход (шаг 4.4). При входе, если lastLogout был больше Config/Offline.minSeconds назад,
-- начисляем min(время, maxSeconds) × доход_в_минуту × rate. Сумма ждёт в профиле
-- (offlinePending — переживёт выход без «Забрать»), клиент видит её в атрибуте OfflinePending.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Offline = require(ReplicatedStorage.Shared.Config.Offline)
local Rebirth = require(ReplicatedStorage.Shared.Config.Rebirth)
local RebirthPerks = require(ReplicatedStorage.Shared.Config.RebirthPerks)
local Social = require(ReplicatedStorage.Shared.Config.Social)
local RetentionRemotes = require(ReplicatedStorage.Shared.RetentionRemotes)
local DataService = require(script.Parent.DataService)

local PROFILE_WAIT = 0.2

local OfflineService = {}

-- Сколько заработала бы студия за seconds офлайна
function OfflineService.earnings(profile: DataService.Profile, seconds: number): number
	local capped = math.min(seconds, Offline.maxSeconds)
	-- Без гаража офлайн-дохода нет: этап парка проходят игрой, а не ожиданием
	-- (старые сохранения без флага — как в PlotService: гараж есть, если куплен стол или вышла игра)
	local owns = (profile :: any).ownsGarage
	if owns == nil then
		owns = profile.upgrades.desk1 == true or profile.gamesReleased > 0
	end
	if capped < Offline.minSeconds or owns ~= true then
		return 0
	end
	-- Лучшая оценка с последнего Rebirth: рекорд прошлой студии не должен кормить новый гараж
	local perGame = Formulas.revenue(
		math.max(profile.runBestScore, 1),
		profile.studioLevel,
		0,
		Rebirth.multiplier(profile.rebirths)
	)
	local perMinute = perGame / Offline.gameMinutes
	-- Команда: «Призрачный кодер» ×2, перк «Ночная смена» (StaffService)
	local staff = script.Parent:FindFirstChild("StaffService")
	local okTeam, teamValue = pcall(function()
		return if staff and staff:IsA("ModuleScript")
			then (require(staff) :: any).offlineMultiplier(profile)
			else 1
	end)
	local team = if okTeam and type(teamValue) == "number" then teamValue else 1
	-- Звёзды студии (Config/RebirthPerks, ветка «Пассив»): +N% к офлайн-доходу
	local stars = 1 + RebirthPerks.forProfile(profile).offline
	local gross = capped / 60 * perMinute * Offline.rate * team * stars
	-- Зарплаты и аренда (ExpensesService) идут и офлайн — в доле rate × expenseShare
	local expenses = script.Parent:FindFirstChild("ExpensesService")
	local okCost, cost = pcall(function()
		return if expenses then (require(expenses) :: any).perMinute(profile) else 0
	end)
	local spent = if okCost and type(cost) == "number"
		then capped / 60 * cost * Offline.rate * Offline.expenseShare
		else 0
	return math.max(math.floor(gross - spent), 0)
end

local function onPlayerAdded(player: Player)
	-- Профиль грузится асинхронно в DataService
	local profile = DataService.get(player)
	while not profile and player.Parent do
		task.wait(PROFILE_WAIT)
		profile = DataService.get(player)
	end
	if not profile then
		return
	end
	local data = profile :: any
	-- Снимок DataService при загрузке: сохранение при входе (награды в onProfileLoaded) уже могло
	-- переписать lastLogout. lastLogout обновляется и при автосейве, так что «уход» точен до 60 с.
	local away = DataService.awaySeconds(player)
	-- Несобранный доход не копится сверх одного максимального ухода (Offline.maxSeconds)
	-- Roblox Premium: +Social.premium.offlineBonus к офлайн-доходу
	local premium = if player.MembershipType == Enum.MembershipType.Premium
		then 1 + Social.premium.offlineBonus
		else 1
	local pending = math.min(
		(tonumber(data.offlinePending) or 0) + math.floor(OfflineService.earnings(profile, away) * premium),
		math.floor(OfflineService.earnings(profile, Offline.maxSeconds) * premium)
	)
	data.offlinePending = pending
	-- Сколько не было (окно «Пока тебя не было» показывает время и лимит Offline.maxSeconds)
	player:SetAttribute("OfflineAway", if away >= Offline.minSeconds then away else 0)
	player:SetAttribute("OfflinePending", pending)
end

local function onClaim(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = profile :: any
	local pending = tonumber(data.offlinePending) or 0
	if pending <= 0 then
		return
	end
	data.offlinePending = 0
	player:SetAttribute("OfflinePending", 0)
	DataService.addCash(player, pending)
	-- Офлайн-доход — не «заработок за сессию» для заданий
	local reward = script.Parent:FindFirstChild("RewardService")
	if reward and reward:IsA("ModuleScript") then
		pcall((require(reward) :: any).noteNonEarned, player, pending)
	end
	-- Кредит банка: доля офлайн-дохода тоже идёт в погашение
	local loan = script.Parent:FindFirstChild("LoanService")
	if loan then
		pcall((require(loan) :: any).onIncome, player, pending)
	end
end

function OfflineService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	RetentionRemotes.ClaimOffline.OnServerEvent:Connect(onClaim)
end

return OfflineService
