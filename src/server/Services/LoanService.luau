--!strict
-- Кредит банка (Config/Loans). Денег меньше threshold, есть гараж и нет долга — предлагаем кредит
-- (атрибут LoanOffer, клиент показывает окно). Долг — (profile :: any).loanDebt и атрибут LoanDebt.
-- Погашение: repayShare дохода каждой выпущенной игры (хук DevelopmentService) и кнопка «Погасить».
-- Rebirth с долгом: RebirthService требует денег на ребёрз + долг и списывает долг.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loans = require(ReplicatedStorage.Shared.Config.Loans)
local LoanRemotes = require(ReplicatedStorage.Shared.LoanRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local CHECK_INTERVAL = 1
local REQUEST_COOLDOWN = 1

local LoanService = {}
local lastRequest: { [Player]: number } = {}
-- Когда (os.clock) у игрока появился гараж в этой сессии; false — гаража ещё нет
local garageSince: { [Player]: number | false } = {}

function LoanService.debt(profile: DataService.Profile): number
	return math.max(math.floor(tonumber((profile :: any).loanDebt) or 0), 0)
end

local function setDebt(player: Player, profile: DataService.Profile, debt: number)
	(profile :: any).loanDebt = if debt > 0 then debt else nil
	player:SetAttribute("LoanDebt", debt)
end

-- Деньги, ушедшие в погашение, — не «минус заработок» для задания «заработай»
local function noteExpense(player: Player, amount: number)
	local reward = script.Parent:FindFirstChild("RewardService")
	if reward then
		pcall((require(reward) :: any).noteExpense, player, amount)
	end
end

local function noteNonEarned(player: Player, amount: number)
	local reward = script.Parent:FindFirstChild("RewardService")
	if reward then
		pcall((require(reward) :: any).noteNonEarned, player, amount)
	end
end

-- Погасить до amount из денег игрока; возвращает, сколько списано
local function repay(player: Player, profile: DataService.Profile, amount: number): number
	local debt = LoanService.debt(profile)
	local pay = math.min(math.floor(amount), debt, math.floor(profile.cash))
	if pay <= 0 or not DataService.trySpend(player, pay) then
		return 0
	end
	setDebt(player, profile, debt - pay)
	noteExpense(player, pay)
	return pay
end

-- Новичок только что купил гараж (осталось $5): сначала название студии и туториал, банк — позже
local function inGrace(player: Player, profile: DataService.Profile): boolean
	local name = (profile :: any).studioName
	if player:GetAttribute("NeedsStudioName") == true or type(name) ~= "string" or name == "" then
		return true
	end
	local since = garageSince[player]
	return type(since) == "number" and os.clock() - since < Loans.graceAfterGarage
end

-- Сколько банк готов дать сейчас (0 — не предлагает)
local function offerFor(player: Player, profile: DataService.Profile): number
	if LoanService.debt(profile) > 0 or not PlotService.ownsGarage(player) or inGrace(player, profile) then
		return 0
	end
	local current = tonumber(player:GetAttribute("LoanOffer")) or 0
	if profile.cash < Loans.threshold then
		return Loans.amountFor(profile.studioLevel)
	end
	-- Уже предложили — держим предложение, пока денег не станет заметно больше (окно не мигает)
	if current > 0 and profile.cash < Loans.threshold * Loans.resetFactor then
		return Loans.amountFor(profile.studioLevel)
	end
	return 0
end

local function refresh(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	-- Гараж уже был при входе — паузы нет; куплен в этой сессии — отсчитываем graceAfterGarage
	local owns = PlotService.ownsGarage(player)
	local since = garageSince[player]
	if since == nil then
		garageSince[player] = if owns then -math.huge else false
	elseif since == false and owns then
		garageSince[player] = os.clock()
	end
	player:SetAttribute("LoanDebt", LoanService.debt(profile))
	player:SetAttribute("LoanOffer", offerFor(player, profile))
end

local function throttled(player: Player): boolean
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return true
	end
	lastRequest[player] = now
	return false
end

local function onTake(player: Player)
	if throttled(player) then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	-- Условия проверяем заново на сервере: клиент мог прислать запрос когда угодно
	local amount = offerFor(player, profile)
	if amount <= 0 then
		return
	end
	setDebt(player, profile, Loans.repayFor(amount))
	DataService.addCash(player, amount)
	noteNonEarned(player, amount)
	player:SetAttribute("LoanOffer", 0)
end

local function onRepay(player: Player)
	if throttled(player) then
		return
	end
	local profile = DataService.get(player)
	if profile then
		repay(player, profile, LoanService.debt(profile))
	end
end

-- Хук DevelopmentService после релиза: часть дохода игры уходит в погашение
function LoanService.onGameReleased(player: Player, revenue: number)
	LoanService.onIncome(player, revenue)
end

-- Любой доход (релиз, офлайн-доход): repayShare уходит в погашение, долг не висит вечно.
-- Доход уже зачислен: сначала он закрыл минус баланса (долг аренды и зарплат, Config/Bailiffs),
-- банку — доля только того, что осталось сверх нуля (вместе не съедают весь доход)
function LoanService.onIncome(player: Player, amount: number)
	local profile = DataService.get(player)
	if profile and type(amount) == "number" and amount > 0 and LoanService.debt(profile) > 0 then
		local free = math.min(amount, math.max(profile.cash, 0))
		repay(player, profile, free * Loans.repayShare)
	end
end

-- Для RebirthService: долг гасится вместе с ребёрзом
function LoanService.clear(player: Player, profile: DataService.Profile)
	setDebt(player, profile, 0)
	player:SetAttribute("LoanOffer", 0)
end

function LoanService.start()
	LoanRemotes.TakeLoan.OnServerEvent:Connect(onTake)
	LoanRemotes.RepayLoan.OnServerEvent:Connect(onRepay)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		garageSince[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(refresh, player)
				if not ok then
					warn("[LoanService] refresh failed:", err)
				end
			end
		end
	end)
end

return LoanService
