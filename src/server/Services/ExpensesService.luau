--!strict
-- Расходы студии (Config/Expenses): аренда этапа списывается долями каждые tickSeconds, зарплата
-- команды — раз в paydaySeconds одной суммой (сумма растёт с навыками, Expenses.salary).
-- Не хватает денег на аренду или зарплату — забастовка: profile.staffStrike = true, StaffService
-- выключает бонусы команды (игрок сам продолжает делать игры и выбирается). Долг не копится:
-- невыплаченная зарплата — одна, её пробуем списать каждый тик, пока бастуют зарплата не набегает.
-- Клиенту — атрибуты игрока ExpensesPerMinute, StaffStrike, PaydayAt (серверное время зарплаты),
-- PaydayAmount (сколько спишут), PaydayPaid и PaydayCount (последняя выплата; клиент показывает тост).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Expenses = require(ReplicatedStorage.Shared.Config.Expenses)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StaffService = require(script.Parent.StaffService)

local ExpensesService = {}

-- Набежавшие доли доллара аренды (списываем только целые)
local owedRent: { [Player]: number } = {}
-- Зарплата, набежавшая с прошлой выплаты
local salaryAccrued: { [Player]: number } = {}
-- Невыплаченная зарплата (забастовка до её выплаты)
local salaryDue: { [Player]: number } = {}
-- Когда следующая зарплата (os.clock)
local nextPayday: { [Player]: number } = {}

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

-- Списать с учётом задания «заработай» (расходы — не «минус заработок»)
local function spend(player: Player, amount: number): boolean
	if not DataService.trySpend(player, amount) then
		return false
	end
	local reward = script.Parent:FindFirstChild("RewardService")
	if reward then
		pcall((require(reward) :: any).noteExpense, player, amount)
	end
	return true
end

local function paySalary(player: Player, amount: number): boolean
	if amount <= 0 then
		return true
	end
	if not spend(player, amount) then
		return false
	end
	player:SetAttribute("PaydayPaid", amount)
	-- Счётчик: одинаковая сумма два раза подряд тоже должна показать тост
	player:SetAttribute("PaydayCount", (tonumber(player:GetAttribute("PaydayCount")) or 0) + 1)
	return true
end

local function reset(player: Player)
	owedRent[player] = nil
	salaryAccrued[player] = nil
	salaryDue[player] = nil
	nextPayday[player] = nil
	player:SetAttribute("PaydayAt", nil)
	player:SetAttribute("PaydayAmount", nil)
end

local function charge(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	-- В парке до гаража расходов нет. Без участка (все заняты, игрок в очереди PlotService) студии
	-- на сервере нет: делать игры нельзя (isAtPc), а зарплаты и аренда съедали бы деньги до забастовки
	if not PlotService.ownsGarage(player) or not PlotService.getPlot(player) then
		player:SetAttribute("ExpensesPerMinute", 0)
		reset(player)
		setStrike(player, profile, false)
		return
	end
	local salaryPerMinute = StaffService.salaryPerMinute(profile)
	local rentPerMinute = Expenses.rentFor(profile.studioLevel)
	player:SetAttribute("ExpensesPerMinute", salaryPerMinute + rentPerMinute)
	local now = os.clock()
	if not nextPayday[player] then
		nextPayday[player] = now + Expenses.paydaySeconds
	end

	local ok = true
	-- Аренда — долями
	owedRent[player] = (owedRent[player] or 0) + rentPerMinute * Expenses.tickSeconds / 60
	local rent = math.floor(owedRent[player])
	if rent > 0 then
		if spend(player, rent) then
			owedRent[player] -= rent
		else
			owedRent[player] = 0
			ok = false
		end
	end

	-- Невыплаченная зарплата: пробуем каждый тик, новая пока не набегает
	local due = salaryDue[player]
	if due then
		if paySalary(player, due) then
			salaryDue[player] = nil
			nextPayday[player] = now + Expenses.paydaySeconds
		else
			ok = false
		end
	else
		salaryAccrued[player] = (salaryAccrued[player] or 0) + salaryPerMinute * Expenses.tickSeconds / 60
		if now >= nextPayday[player] then
			local amount = math.floor(salaryAccrued[player] or 0)
			salaryAccrued[player] = 0
			nextPayday[player] = now + Expenses.paydaySeconds
			if not paySalary(player, amount) then
				salaryDue[player] = amount
				ok = false
			end
		end
	end

	-- Клиенту: когда и сколько (оценка — набежавшее + до конца периода по текущей ставке)
	local left = math.max(nextPayday[player] - now, 0)
	local upcoming = salaryDue[player]
		or math.floor((salaryAccrued[player] or 0) + salaryPerMinute * left / 60)
	player:SetAttribute(
		"PaydayAt",
		-- Целые секунды: значение не дрожит от тика к тику (клиент предупреждает один раз)
		if salaryPerMinute > 0 or salaryDue[player]
			then math.round(workspace:GetServerTimeNow() + left)
			else nil
	)
	player:SetAttribute("PaydayAmount", if upcoming > 0 then upcoming else nil)
	setStrike(player, profile, not ok)
end

function ExpensesService.start()
	-- Забастовка из прошлой сессии видна сразу после загрузки профиля, до первого списания
	DataService.onProfileLoaded(function(player, profile)
		player:SetAttribute("StaffStrike", (profile :: any).staffStrike == true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		owedRent[player] = nil
		salaryAccrued[player] = nil
		salaryDue[player] = nil
		nextPayday[player] = nil
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
