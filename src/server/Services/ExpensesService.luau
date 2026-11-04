--!strict
-- Расходы студии (Config/Expenses): каждые tickSeconds списывает зарплаты нанятых и аренду этапа.
-- Не хватает денег — забастовка: profile.staffStrike = true, StaffService выключает бонусы команды
-- (игрок сам продолжает делать игры и выбирается), долг не копится.
-- Клиенту — атрибуты игрока ExpensesPerMinute и StaffStrike.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Expenses = require(ReplicatedStorage.Shared.Config.Expenses)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StaffService = require(script.Parent.StaffService)

local ExpensesService = {}

-- Набежавшие доли доллара (списываем только целые)
local owed: { [Player]: number } = {}

-- Расходы студии в минуту: зарплаты всех нанятых + аренда
function ExpensesService.perMinute(profile: DataService.Profile): number
	return StaffService.salaryPerMinute(profile) + Expenses.rentFor(profile.studioLevel)
end

local function setStrike(player: Player, profile: DataService.Profile, strike: boolean)
	local data = profile :: any
	if (data.staffStrike == true) == strike then
		return
	end
	data.staffStrike = if strike then true else nil
	player:SetAttribute("StaffStrike", strike)
end

local function charge(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	-- В парке до гаража расходов нет
	if not PlotService.ownsGarage(player) then
		player:SetAttribute("ExpensesPerMinute", 0)
		setStrike(player, profile, false)
		return
	end
	local perMinute = ExpensesService.perMinute(profile)
	player:SetAttribute("ExpensesPerMinute", perMinute)
	owed[player] = (owed[player] or 0) + perMinute * Expenses.tickSeconds / 60
	local whole = math.floor(owed[player])
	if whole <= 0 then
		setStrike(player, profile, false)
		return
	end
	if DataService.trySpend(player, whole) then
		owed[player] -= whole
		-- Расходы — не «минус заработок» для задания «заработай»
		local reward = script.Parent:FindFirstChild("RewardService")
		if reward then
			pcall((require(reward) :: any).noteExpense, player, whole)
		end
		setStrike(player, profile, false)
	else
		owed[player] = 0
		setStrike(player, profile, true)
	end
end

function ExpensesService.start()
	Players.PlayerAdded:Connect(function(player)
		-- Забастовка из прошлой сессии видна сразу, до первого списания
		task.delay(Expenses.tickSeconds / 2, function()
			local profile = DataService.get(player)
			if profile and player.Parent then
				player:SetAttribute("StaffStrike", (profile :: any).staffStrike == true)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		owed[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Expenses.tickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(charge, player)
				if not ok then
					warn("[ExpensesService] charge failed:", err)
				end
			end
		end
	end)
end

return ExpensesService
