--!strict
-- Налоговая (Config/Tax, роадмап 7.1). Считаем время в игре и доход релизов; раз в periodSeconds
-- выставляем счёт по ставке этапа студии. Не оплачен за payWindowSeconds — штраф списывается сам
-- (в минус до овердрафта Config/Bailiffs) и идёт налоговая проверка: доход релизов ниже.
-- Данные — (profile :: any).tax = { played, income, bill, due, auditUntil }.
-- Хуки DevelopmentService: onGameReleased(player, revenue), revenueMultiplier(player).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bailiffs = require(ReplicatedStorage.Shared.Config.Bailiffs)
local Tax = require(ReplicatedStorage.Shared.Config.Tax)
local TaxRemotes = require(ReplicatedStorage.Shared.TaxRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local FeatureReleaseService = require(script.Parent.FeatureReleaseService)

local TICK = 1
local REQUEST_COOLDOWN = 1

type TaxData = { played: number, income: number, bill: number, due: number, auditUntil: number }

local TaxService = {}
local lastRequest: { [Player]: number } = {}

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then require(module) :: any else nil
end

local function dataOf(profile: DataService.Profile): TaxData
	local raw = (profile :: any).tax
	if type(raw) ~= "table" then
		raw = {};
		(profile :: any).tax = raw
	end
	raw.played = math.max(tonumber(raw.played) or 0, 0)
	raw.income = math.max(tonumber(raw.income) or 0, 0)
	raw.bill = math.max(math.floor(tonumber(raw.bill) or 0), 0)
	raw.due = tonumber(raw.due) or 0
	raw.auditUntil = tonumber(raw.auditUntil) or 0
	return raw :: TaxData
end

local function noteExpense(player: Player, amount: number)
	local reward = optional("RewardService")
	if reward and type(reward.noteExpense) == "function" then
		pcall(reward.noteExpense, player, amount)
	end
end

local function analytics(player: Player, stage: string, value: number)
	local service = optional("AnalyticsService")
	if service and type(service.logLiveOps) == "function" then
		pcall(service.logLiveOps, player, "tax", value, stage)
	end
end

local function publish(player: Player, data: TaxData, level: number)
	player:SetAttribute("TaxBill", data.bill)
	player:SetAttribute("TaxDue", data.due)
	player:SetAttribute("TaxAuditUntil", data.auditUntil)
	player:SetAttribute("TaxNextIn", math.max(math.ceil(Tax.periodSeconds - data.played), 0))
	player:SetAttribute("TaxRate", Tax.rateFor(level))
end

-- Счёт не оплачен вовремя: штраф (в минус, если надо) и налоговая проверка
local function fine(player: Player, profile: DataService.Profile, data: TaxData, now: number)
	local amount = Tax.fineFor(data.bill)
	local charged = DataService.charge(player, amount, Bailiffs.limitFor(profile.studioLevel))
	if charged > 0 then
		noteExpense(player, charged)
	end
	data.bill = 0
	data.due = 0
	data.auditUntil = now + Tax.auditSeconds
	analytics(player, "fined", charged)
end

local function step(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = dataOf(profile)
	local now = os.time()
	if data.bill > 0 and now >= data.due then
		fine(player, profile, data, now)
	end
	-- Время до налога идёт только со своей студией (в парке налога нет)
	if PlotService.ownsGarage(player) then
		data.played += TICK
		if data.played >= Tax.periodSeconds then
			data.played = 0
			local amount = math.floor(data.income * Tax.rateFor(profile.studioLevel))
			data.income = 0
			-- Старый счёт к этому моменту уже оплачен или оштрафован (окно оплаты короче периода)
			if amount >= Tax.minBill and data.bill <= 0 then
				data.bill = amount
				data.due = now + Tax.payWindowSeconds
				analytics(player, "billed", amount)
			end
		end
	end
	publish(player, data, profile.studioLevel)
end

local function onPay(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = dataOf(profile)
	if data.bill <= 0 or not DataService.trySpend(player, data.bill) then
		return
	end
	noteExpense(player, data.bill)
	analytics(player, "paid", data.bill)
	data.bill = 0
	data.due = 0
	publish(player, data, profile.studioLevel)
end

-- Для RebirthService: налог прошлой студии (счёт, база, проверка) сгорает вместе с ней,
-- как и деньги, с которых он считался. Время до следующего счёта — заново
function TaxService.reset(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = dataOf(profile)
	data.played = 0
	data.income = 0
	data.bill = 0
	data.due = 0
	data.auditUntil = 0
	publish(player, data, profile.studioLevel)
end

-- Хук DevelopmentService: доход релиза идёт в налоговую базу периода
function TaxService.onGameReleased(player: Player, revenue: number)
	local profile = DataService.get(player)
	if
		profile
		and type(revenue) == "number"
		and revenue > 0
		and revenue == revenue
		and revenue < math.huge
	then
		local data = dataOf(profile)
		data.income += revenue
	end
end

-- Хук DevelopmentService: множитель дохода релиза (налоговая проверка)
function TaxService.revenueMultiplier(player: Player): number
	local profile = DataService.get(player)
	if not profile then
		return 1
	end
	return if dataOf(profile).auditUntil > os.time() then Tax.auditRevenueMultiplier else 1
end

local function startNow()
	TaxRemotes.PayTax.OnServerEvent:Connect(onPay)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(step, player)
				if not ok then
					warn("[TaxService] step failed:", err)
				end
			end
		end
	end)
end

-- Обновления по средам (Config/Features): до выхода системы «tax» сервис спит — remotes
-- заглушены, циклы и обработчики не запущены; вышла (в т. ч. пока сервер работает) — startNow()
function TaxService.start()
	FeatureReleaseService.mute("tax", {
		TaxRemotes.PayTax,
	})
	FeatureReleaseService.whenReleased("tax", "TaxService", startNow)
end

return TaxService
