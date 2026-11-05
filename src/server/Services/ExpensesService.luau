--!strict
-- Расходы студии (Config/Expenses): аренда этапа списывается долями каждые tickSeconds, зарплата
-- команды — раз в paydaySeconds одной суммой (сумма растёт с навыками, Expenses.salary).
-- Не хватает денег — расходы всё равно списываются, баланс уходит в минус (долг) до лимита
-- овердрафта (Config/Bailiffs, DataService.charge). Пока cash < 0 — забастовка: profile.staffStrike
-- = true, StaffService выключает бонусы команды; упёрлись в лимит — BailiffService (приставы).
-- Клиенту — атрибуты игрока ExpensesPerMinute, StaffStrike, PaydayAt (серверное время зарплаты),
-- PaydayAmount (сколько спишут), PaydayPaid и PaydayCount (последняя выплата; клиент показывает тост).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Expenses = require(ReplicatedStorage.Shared.Config.Expenses)
local Bailiffs = require(ReplicatedStorage.Shared.Config.Bailiffs)
local RebirthPerks = require(ReplicatedStorage.Shared.Config.RebirthPerks)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StaffService = require(script.Parent.StaffService)

local ExpensesService = {}

-- Набежавшие доли доллара аренды (списываем только целые)
local owedRent: { [Player]: number } = {}
-- Зарплата, набежавшая с прошлой выплаты
local salaryAccrued: { [Player]: number } = {}
-- Когда следующая зарплата (os.clock)
local nextPayday: { [Player]: number } = {}

-- Расходы студии в минуту: зарплаты всех нанятых + аренда
-- Скидка звёзд студии (Config/RebirthPerks, ветка «Экономия»): множитель аренды и зарплат
local function perkMultiplier(profile: DataService.Profile): number
	return 1 - RebirthPerks.forProfile(profile).expenses
end

function ExpensesService.perMinute(profile: DataService.Profile): number
	return (StaffService.salaryPerMinute(profile) + Expenses.rentFor(profile.studioLevel))
		* perkMultiplier(profile)
end

local function setStrike(player: Player, profile: DataService.Profile, strike: boolean)
	local data = profile :: any
	if (data.staffStrike == true) == strike then
		return
	end
	data.staffStrike = if strike then true else nil
	player:SetAttribute("StaffStrike", strike)
end

-- Списать с учётом задания «заработай» (расходы — не «минус заработок»). Приставы: списываем
-- и в минус, до лимита овердрафта этапа (Config/Bailiffs)
local function spend(player: Player, profile: DataService.Profile, amount: number)
	local charged = DataService.charge(player, amount, Bailiffs.limitFor(profile.studioLevel))
	local reward = script.Parent:FindFirstChild("RewardService")
	if reward and charged > 0 then
		pcall((require(reward) :: any).noteExpense, player, charged)
	end
end

local function paySalary(player: Player, profile: DataService.Profile, amount: number)
	if amount <= 0 then
		return
	end
	spend(player, profile, amount)
	player:SetAttribute("PaydayPaid", amount)
	-- Счётчик: одинаковая сумма два раза подряд тоже должна показать тост
	player:SetAttribute("PaydayCount", (tonumber(player:GetAttribute("PaydayCount")) or 0) + 1)
end

-- Множитель аренды от событий компании (CompanyEventService, необязательный): 0 — грант
local function rentMultiplier(player: Player): number
	local module = script.Parent:FindFirstChild("CompanyEventService")
	if not module or not module:IsA("ModuleScript") then
		return 1
	end
	local ok, value = pcall(function()
		return (require(module) :: any).rentMultiplier(player)
	end)
	return if ok and type(value) == "number" and value >= 0 then value else 1
end

local function reset(player: Player)
	owedRent[player] = nil
	salaryAccrued[player] = nil
	nextPayday[player] = nil
	player:SetAttribute("PaydayAt", nil)
	player:SetAttribute("PaydayAmount", nil)
end

-- Для RebirthService: набежавшая зарплата и таймер выплаты прошлой команды сгорают со студией
-- (без этого зарплату до Rebirth списали бы с новых денег на ближайшей выплате)
function ExpensesService.reset(player: Player)
	reset(player)
	local profile = DataService.get(player)
	if profile then
		(profile :: any).payday = nil
	end
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
	local discount = perkMultiplier(profile)
	local salaryPerMinute = StaffService.salaryPerMinute(profile) * discount
	-- Грант (события компании): аренда на время не списывается
	local rentPerMinute = Expenses.rentFor(profile.studioLevel) * rentMultiplier(player) * discount
	player:SetAttribute("ExpensesPerMinute", salaryPerMinute + rentPerMinute)
	local now = os.clock()
	if not nextPayday[player] then
		-- Набежавшая зарплата и время до выплаты — из прошлой сессии: перезаход их не обнуляет
		local saved = (profile :: any).payday
		local accrued = if type(saved) == "table" then tonumber(saved.accrued) else nil
		local left = if type(saved) == "table" then tonumber(saved.left) else nil
		if accrued and accrued == accrued and accrued > 0 then
			salaryAccrued[player] = math.min(accrued, 1e12)
		end
		left = if left and left == left then math.clamp(left, 0, Expenses.paydaySeconds) else nil
		nextPayday[player] = now + (left or Expenses.paydaySeconds)
	end

	-- Аренда — долями (и в минус: долг, Config/Bailiffs)
	owedRent[player] = (owedRent[player] or 0) + rentPerMinute * Expenses.tickSeconds / 60
	local rent = math.floor(owedRent[player])
	if rent > 0 then
		spend(player, profile, rent)
		owedRent[player] -= rent
	end

	-- Зарплата раз в paydaySeconds — тоже и в минус
	salaryAccrued[player] = (salaryAccrued[player] or 0) + salaryPerMinute * Expenses.tickSeconds / 60
	if now >= nextPayday[player] then
		local amount = math.floor(salaryAccrued[player] or 0)
		salaryAccrued[player] = 0
		nextPayday[player] = now + Expenses.paydaySeconds
		paySalary(player, profile, amount)
	end

	-- Клиенту: когда и сколько (оценка — набежавшее + до конца периода по текущей ставке)
	local left = math.max(nextPayday[player] - now, 0)
	local stored: any = profile
	stored.payday = { accrued = salaryAccrued[player] or 0, left = left }
	local upcoming = math.floor((salaryAccrued[player] or 0) + salaryPerMinute * left / 60)
	player:SetAttribute(
		"PaydayAt",
		-- Целые секунды: значение не дрожит от тика к тику (клиент предупреждает один раз)
		if salaryPerMinute > 0 then math.round(workspace:GetServerTimeNow() + left) else nil
	)
	player:SetAttribute("PaydayAmount", if upcoming > 0 then upcoming else nil)
	-- Бастуют, пока баланс в минусе (долг)
	setStrike(player, profile, profile.cash < 0)
end

-- Для BailiffService: долг погашен доходом или приставами — снять забастовку сразу, не ждать тика
function ExpensesService.syncStrike(player: Player)
	local profile = DataService.get(player)
	if profile and (profile :: any).staffStrike == true and profile.cash >= 0 then
		setStrike(player, profile, false)
	end
end

function ExpensesService.start()
	-- Забастовка из прошлой сессии видна сразу после загрузки профиля, до первого списания
	DataService.onProfileLoaded(function(player, profile)
		player:SetAttribute("StaffStrike", (profile :: any).staffStrike == true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		owedRent[player] = nil
		salaryAccrued[player] = nil
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
