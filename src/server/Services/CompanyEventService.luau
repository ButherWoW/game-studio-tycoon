--!strict
-- События компании (Config/CompanyEvents): раз в 7–14 мин онлайн-игры с гаражом — хорошая новость,
-- неприятность, катастрофа (2-й этаж+) или выбор. Всё решает и применяет сервер.
--
-- Время событий — секунды ОНЛАЙН-игры с гаражом (data.play): эффекты, страховка и кулдауны
-- сохраняются в профиле остатком секунд и тикают только в игре. Решение: выход из игры не
-- «пересиживает» плохой эффект и не сжигает хороший. Разовые потери (деньги, прогресс) списываются
-- сразу при срабатывании. Выбор без ответа: таймаут или выход — вариант default; если игрок вышел,
-- выбор сохраняется в профиле (data.pending) и применяется при следующем входе.
--
-- Данные: (profile :: any).companyEvents = { play, nextIn, badStreak, lastAt, lastCatastrophic,
--   effects = { { id, kind, value, left, item? } }, nextScore, nextRevenue, insurance, raises, pending? }
-- Для других сервисов (дополнительные хуки, без модуля всё работает как раньше):
--   revenueMultiplier(player)  — множитель дохода релиза (DevelopmentService.release)
--   scoreBonus(player)         — прибавка к оценке следующей игры (DevelopmentService.scoreBonus)
--   onGameReleased(player)     — «следующая игра» вышла: поправки сбрасываются
--   isPaused(player)           — разработка стоит (отключили свет)
--   isBroken(player, upgradeId) — предмет сломан: стол без очков и сотрудника, без бонусов предмета
--   walkout(player)            — команда не работает (StaffService.working)
--   rentMultiplier(player)     — 0 во время гранта (ExpensesService)
--   salaryFactor(profile, id)  — прибавка к зарплате после «переманивания» (StaffService)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local CompanyEvents = require(Shared.Config.CompanyEvents)
local Expenses = require(Shared.Config.Expenses)
local Employees = require(Shared.Config.Employees)
local Debug = require(Shared.Config.Debug)
local Images = require(Shared.Config.Images)
local StudioLayout = require(Shared.StudioLayout)
local Upgrades = require(Shared.Config.Upgrades)
local CompanyEventRemotes = require(Shared.CompanyEventRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local RewardService = require(script.Parent.RewardService)

type Outcome = CompanyEvents.Outcome
type Event = CompanyEvents.Event
type Line = { key: string, vars: { [string]: any }? }
type EffectKind = "revenue" | "rentFree" | "pause" | "broken" | "mood" | "walkout"
type Effect = { id: string, kind: EffectKind, value: number, left: number, item: string? }
type SavedPending = { id: string, target: string?, insured: boolean? }
type Data = {
	play: number,
	nextIn: number,
	badStreak: number,
	lastAt: { [string]: number },
	lastCatastrophic: number,
	effects: { Effect },
	nextScore: number,
	nextRevenue: number,
	insurance: number,
	raises: { [string]: number },
	pending: SavedPending?,
}
-- Карточка выбора на этом сервере: сколько ждём и показал ли её клиент
type Live = { token: number, id: string, target: string?, insured: boolean, waited: number, seen: boolean }

local TICK = 1
local REQUEST_COOLDOWN = 0.5
local MOOD_KEY = "mood_part_cev_burnout"
local EFFECT_KINDS: { [string]: boolean } =
	{ revenue = true, rentFree = true, pause = true, broken = true, mood = true, walkout = true }

local CompanyEventService = {}
local live: { [Player]: Live } = {}
local joinedAt: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
local nextToken = 0
local rng = Random.new()

-- Studio: принудительное событие и короткий интервал (Config/Debug)
local function debugForced(): string?
	local id = (Debug :: any).forceCompanyEvent
	return if RunService:IsStudio() and type(id) == "string" and CompanyEvents.get(id) then id else nil
end

local function debugInterval(): number?
	local seconds = tonumber((Debug :: any).companyEventInterval)
	return if RunService:IsStudio() and seconds and seconds > 0 then seconds else nil
end

-- Необязательные сервисы: берём при вызове (они сами требуют этот модуль, require кэшируется)
local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

local function call(name: string, fnName: string, ...: any): any
	local service = optional(name)
	local fn = service and service[fnName]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn("[CompanyEventService] " .. name .. "." .. fnName .. " failed:", result)
		return nil
	end
	return result
end

local function num(value: any, default: number): number
	local n = tonumber(value)
	return if n and n == n and n > -math.huge and n < math.huge then n else default
end

local function randomInterval(): number
	return debugInterval() or rng:NextNumber(CompanyEvents.intervalMin, CompanyEvents.intervalMax)
end

-- Уже проверенные таблицы данных (новый профиль — новая таблица, проверим снова)
local checked: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
-- «Катастрофы ещё не было»: конечное число — DataStore не сохраняет бесконечность
local NEVER = -1e9

-- Поле профиля в порядке: старые сохранения без него и мусор
local function dataOf(profile: DataService.Profile): Data
	local p = profile :: any
	local raw = p.companyEvents
	if type(raw) == "table" and checked[raw] then
		return raw :: Data
	end
	if type(raw) ~= "table" then
		raw = {}
		p.companyEvents = raw
		-- Опытным игрокам «новичковая» пауза не нужна
		raw.play = if profile.gamesReleased >= CompanyEvents.veteranGames
			then CompanyEvents.newPlayerSeconds
			else 0
	end
	raw.play = math.max(num(raw.play, 0), 0)
	raw.nextIn = num(raw.nextIn, randomInterval())
	raw.badStreak = math.max(math.floor(num(raw.badStreak, 0)), 0)
	raw.lastCatastrophic = num(raw.lastCatastrophic, NEVER)
	raw.nextScore =
		math.clamp(num(raw.nextScore, 0), -CompanyEvents.nextScoreLimit, CompanyEvents.nextScoreLimit)
	raw.nextRevenue = math.clamp(num(raw.nextRevenue, 1), 0.1, CompanyEvents.nextRevenueMax)
	raw.insurance = math.clamp(num(raw.insurance, 0), 0, CompanyEvents.insurance.seconds * 2)
	if type(raw.lastAt) ~= "table" then
		raw.lastAt = {}
	end
	for id, at in raw.lastAt do
		if type(id) ~= "string" or num(at, NEVER) ~= at then
			raw.lastAt[id] = nil
		end
	end
	if type(raw.raises) ~= "table" then
		raw.raises = {}
	end
	local effects = {}
	if type(raw.effects) == "table" then
		for _, e in raw.effects do
			if type(e) == "table" and EFFECT_KINDS[e.kind] and num(e.left, 0) > 0 then
				table.insert(effects, {
					id = if type(e.id) == "string" then e.id else "?",
					kind = e.kind,
					value = num(e.value, 1),
					left = num(e.left, 0),
					item = if type(e.item) == "string" then e.item else nil,
				})
			end
		end
	end
	raw.effects = effects
	local pending = raw.pending
	if type(pending) ~= "table" or type(pending.id) ~= "string" or not CompanyEvents.get(pending.id) then
		raw.pending = nil
	end
	checked[raw] = true
	return raw :: Data
end

local function dataFor(player: Player): (DataService.Profile?, Data?)
	local profile = DataService.get(player)
	if not profile then
		return nil, nil
	end
	return profile, dataOf(profile)
end

-- ===== Деньги =====

local function income(player: Player, profile: DataService.Profile, minutes: number): number
	return RewardService.incomeForMinutes(player, profile, minutes)
end

-- Ниже этого наличные событие не опускает: можно и дальше делать игры
local function cashFloor(profile: DataService.Profile): number
	return math.max(
		CompanyEvents.cashFloor,
		Expenses.rentFor(profile.studioLevel) * CompanyEvents.rentFloorMinutes
	)
end

-- Сколько реально спишется (с учётом пола)
local function lossFor(profile: DataService.Profile, amount: number): number
	return math.clamp(math.floor(amount), 0, math.max(math.floor(profile.cash - cashFloor(profile)), 0))
end

local function takeCash(player: Player, profile: DataService.Profile, amount: number): number
	local loss = lossFor(profile, amount)
	if loss > 0 and DataService.trySpend(player, loss) then
		-- Потеря от события — не «минус заработок» для заданий (как расходы студии)
		RewardService.noteExpense(player, loss)
		return loss
	end
	return 0
end

local function giveCash(player: Player, amount: number): number
	if amount <= 0 then
		return 0
	end
	DataService.addCash(player, amount)
	-- Подарок события — не заработок за игры
	RewardService.noteNonEarned(player, amount)
	return amount
end

-- Потеря по исходу (минуты дохода с потолком доли или доля наличных) — для карточки и списания
local function plannedLoss(
	player: Player,
	profile: DataService.Profile,
	outcome: Outcome,
	damage: number
): number
	local amount = 0
	local minutes = outcome.cashMinutes
	if minutes and minutes < 0 then
		local value = income(player, profile, -minutes) * damage
		if outcome.maxCashShare then
			value = math.min(value, profile.cash * outcome.maxCashShare)
		end
		amount += value
	end
	if outcome.cashShare then
		amount += profile.cash * outcome.cashShare * damage
	end
	return lossFor(profile, amount)
end

-- ===== Эффекты =====

local function hasEffect(data: Data, kind: EffectKind): Effect?
	for _, effect in data.effects do
		if effect.kind == kind and effect.left > 0 then
			return effect
		end
	end
	return nil
end

local function addEffect(
	data: Data,
	id: string,
	kind: EffectKind,
	value: number,
	seconds: number,
	item: string?
)
	if seconds > 0 then
		table.insert(data.effects, { id = id, kind = kind, value = value, left = seconds, item = item })
	end
end

local function percent(value: number): number
	return math.floor(math.abs(value) * 100 + 0.5)
end

local function scoreText(value: number): string
	local text = string.format("%.1f", math.abs(value)):gsub("%.0$", "")
	return (if value < 0 then "−" else "+") .. text
end

-- Предметы, которые может «сломать» потоп: куплены, стоят на этом этапе, что-то дают
local function breakableItems(profile: DataService.Profile): { string }
	local result = {}
	for _, upgrade in Upgrades do
		local useful = upgrade.pointsPerSecond or upgrade.speed or upgrade.reviewBonus or upgrade.desk
		if
			profile.upgrades[upgrade.id]
			and useful
			and not upgrade.move
			and not CompanyEvents.unbreakable[upgrade.id]
			and StudioLayout.isVisible(upgrade, profile.studioLevel)
		then
			table.insert(result, upgrade.id)
		end
	end
	return result
end

-- Кого переманивают: самый сильный обычный сотрудник (легендарных не трогаем)
local function poachTarget(profile: DataService.Profile): string?
	local StaffService = optional("StaffService")
	if not StaffService then
		return nil
	end
	local best: string?, bestMultiplier = nil, -1
	for employeeId in StaffService.hired(profile) do
		local employee = Employees.get(employeeId)
		if employee and not employee.legendary and employee.multiplier > bestMultiplier then
			best, bestMultiplier = employeeId, employee.multiplier
		end
	end
	return best
end

local function hasStaff(profile: DataService.Profile): boolean
	local StaffService = optional("StaffService")
	return StaffService ~= nil and next(StaffService.hired(profile)) ~= nil
end

-- Дымок над сломанным предметом (V24: текстура Images.fx.smoke). 0 — дыма нет, как раньше
local SMOKE_NAME = "BrokenSmoke"

local function syncSmoke(player: Player)
	local plot = PlotService.getPlot(player)
	local profile = DataService.get(player)
	if not plot or not profile then
		return
	end
	local old = plot:FindFirstChild(SMOKE_NAME)
	local broken = hasEffect(dataOf(profile), "broken")
	local item = broken and broken.item
	local position: Vector3? = nil
	if item and Images.fx.smoke > 0 then
		for _, upgrade in Upgrades do
			if upgrade.id == item then
				position = upgrade.position
				break
			end
		end
	end
	if old and position and old:GetAttribute("Item") == item then
		return
	end
	if old then
		old:Destroy()
	end
	if not position then
		return
	end
	-- Модель: PlotService.rebuild сносит её вместе с остальными (plotChanged ставит заново)
	local model = Instance.new("Model")
	model.Name = SMOKE_NAME
	model:SetAttribute("Item", item)
	local anchor = Instance.new("Part")
	anchor.Name = "SmokeAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(2, 0.2, 2)
	anchor.CFrame = plot.CFrame * CFrame.new(position + Vector3.new(0, 3, 0))
	anchor.Parent = model
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxassetid://" .. Images.fx.smoke
	smoke.Rate = 4
	smoke.Lifetime = NumberRange.new(1.5, 2.5)
	smoke.Speed = NumberRange.new(1.5, 3)
	smoke.SpreadAngle = Vector2.new(20, 20)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-30, 30)
	smoke.Size = NumberSequence.new(1, 2.5)
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Parent = anchor
	model.Parent = plot
end

local function refreshStaff(player: Player)
	call("StaffService", "refreshPower", player)
	syncSmoke(player)
end

-- Применить исход. damage — 1 или множитель страховки (только для урона, не для выгоды)
local function apply(
	player: Player,
	profile: DataService.Profile,
	data: Data,
	event: Event,
	outcome: Outcome,
	damage: number,
	target: string?
): { Line }
	local lines: { Line } = {}
	local function line(key: string, vars: { [string]: any }?)
		table.insert(lines, { key = key, vars = vars })
	end

	if outcome.chance then
		local lucky = rng:NextNumber() < outcome.chance
		call("AnalyticsService", "logCompanyEvent", player, event.id, if lucky then "win" else "lose")
		line(if lucky then "cev_fx_lucky" else "cev_fx_unlucky")
		if not lucky then
			if outcome.fail then
				for _, l in apply(player, profile, data, event, outcome.fail, damage, target) do
					table.insert(lines, l)
				end
			end
			return lines
		end
	end

	-- Деньги
	local minutes = outcome.cashMinutes
	if minutes and minutes > 0 then
		line("cev_fx_cash_gain", { money = giveCash(player, income(player, profile, minutes)) })
	end
	local loss = plannedLoss(player, profile, outcome, damage)
	if loss > 0 then
		line("cev_fx_cash_loss", { money = takeCash(player, profile, loss) })
	elseif (minutes and minutes < 0) or outcome.cashShare then
		-- Наличных не больше пола: событие ничего не забрало
		line("cev_fx_cash_floor")
	end

	-- Доход релизов на время
	local revenue = outcome.revenue
	if revenue and outcome.revenueSeconds then
		local value = if revenue < 1 then 1 - (1 - revenue) * damage else revenue
		addEffect(data, event.id, "revenue", value, outcome.revenueSeconds)
		line(
			if value >= 1 then "cev_fx_revenue_up" else "cev_fx_revenue_down",
			{ pct = percent(value - 1), time = CompanyEvents.clock(outcome.revenueSeconds) }
		)
	end
	if outcome.nextRevenue then
		data.nextRevenue = math.min(data.nextRevenue * outcome.nextRevenue, CompanyEvents.nextRevenueMax)
		line("cev_fx_next_revenue", { mult = string.format("%.1f", outcome.nextRevenue):gsub("%.0$", "") })
	end
	if outcome.nextScore then
		local value = if outcome.nextScore < 0 then outcome.nextScore * damage else outcome.nextScore
		local limit = CompanyEvents.nextScoreLimit
		data.nextScore = math.clamp(data.nextScore + value, -limit, limit)
		line("cev_fx_next_score", { n = scoreText(value) })
	end

	-- Аренда, свет, потоп, настроение
	if outcome.rentFreeSeconds then
		addEffect(data, event.id, "rentFree", 0, outcome.rentFreeSeconds)
		line("cev_fx_rent_free", { time = CompanyEvents.clock(outcome.rentFreeSeconds) })
	end
	if outcome.pauseSeconds then
		local seconds = math.floor(outcome.pauseSeconds * damage)
		addEffect(data, event.id, "pause", 0, seconds)
		line("cev_fx_pause", { sec = seconds })
	end
	if outcome.breakSeconds then
		local items = breakableItems(profile)
		if #items > 0 and not hasEffect(data, "broken") then
			local item = items[rng:NextInteger(1, #items)]
			local seconds = math.floor(outcome.breakSeconds * damage)
			addEffect(data, event.id, "broken", 0, seconds, item)
			line("cev_fx_broken", { item = item, time = CompanyEvents.clock(seconds) })
			refreshStaff(player)
		end
	end
	if outcome.moodValue and outcome.moodSeconds and hasStaff(profile) then
		local value = math.floor(outcome.moodValue * (if outcome.moodValue < 0 then damage else 1))
		addEffect(data, event.id, "mood", value, outcome.moodSeconds)
		call("MoodService", "addTemporary", player, MOOD_KEY, value, outcome.moodSeconds)
		line("cev_fx_mood", { n = scoreText(value), time = CompanyEvents.clock(outcome.moodSeconds) })
	end

	-- Текущие игры
	if outcome.rollback then
		local share = outcome.rollback * damage
		if (call("DevelopmentService", "rollbackProgress", player, share) or 0) > 0 then
			line("cev_fx_rollback", { pct = percent(share) })
		end
	end
	if outcome.rush then
		if (call("DevelopmentService", "rushProjects", player, outcome.rush) or 0) > 0 then
			line("cev_fx_rush", { pct = percent(outcome.rush) })
		end
	end

	-- Команда
	if outcome.skill then
		local granted = call("StaffService", "grantFreeSkill", player)
		if type(granted) == "table" and type(granted.employeeId) == "string" then
			line("cev_fx_skill", { employee = granted.employeeId, skill = granted.key })
		else
			-- Учить некого (все прокачаны) — деньги на курсы
			line("cev_fx_cash_gain", { money = giveCash(player, income(player, profile, 3)) })
		end
	end
	if outcome.raise and target then
		data.raises[target] = math.min((data.raises[target] or 1) * outcome.raise, 3)
		line("cev_fx_raise", { employee = target, pct = percent(outcome.raise - 1) })
		-- Зарплата выросла: пересчитать расходы в окне «Команда»
		call("StaffService", "refreshStaff", player)
	end
	if outcome.poach and target then
		if call("StaffService", "dismiss", player, target) then
			line("cev_fx_poach", { employee = target })
		end
	end
	if outcome.walkoutSeconds and hasStaff(profile) then
		local seconds = math.floor(outcome.walkoutSeconds * damage)
		addEffect(data, event.id, "walkout", 0, seconds)
		line("cev_fx_walkout", { time = CompanyEvents.clock(seconds) })
		refreshStaff(player)
	end

	if #lines == 0 then
		line("cev_fx_nothing")
	end
	return lines
end

-- ===== Состояние клиенту =====

function CompanyEventService.pushState(player: Player)
	local profile, data = dataFor(player)
	if not profile or not data or not player.Parent then
		return
	end
	-- Прибавки к зарплате уволенных/ушедших больше не нужны
	local StaffService = optional("StaffService")
	if StaffService then
		local hired = StaffService.hired(profile)
		for employeeId in data.raises do
			if hired[employeeId] == nil then
				data.raises[employeeId] = nil
			end
		end
	end
	local now = workspace:GetServerTimeNow()
	local effects = {}
	for _, effect in data.effects do
		table.insert(effects, {
			id = effect.id,
			kind = effect.kind,
			value = effect.value,
			endsAt = now + effect.left,
			item = effect.item,
		})
	end
	CompanyEventRemotes.CompanyEventState:FireClient(player, {
		effects = effects,
		insuranceEndsAt = if data.insurance > 0 then now + data.insurance else nil,
		insurancePrice = income(player, profile, CompanyEvents.insurance.priceMinutes),
		insuranceSeconds = CompanyEvents.insurance.seconds,
		repairCost = income(player, profile, CompanyEvents.repairMinutes),
		nextScore = data.nextScore,
		nextRevenue = data.nextRevenue,
	})
end

-- ===== Выбор события =====

local function needsMet(player: Player, profile: DataService.Profile, data: Data, event: Event): boolean
	for _, need in event.needs or {} do
		if need == "staff" and not hasStaff(profile) then
			return false
		elseif need == "project" and call("DevelopmentService", "hasActiveProject", player) ~= true then
			return false
		elseif need == "item" and (#breakableItems(profile) == 0 or hasEffect(data, "broken")) then
			return false
		elseif
			need == "rent" and (Expenses.rentFor(profile.studioLevel) <= 0 or hasEffect(data, "rentFree"))
		then
			return false
		end
	end
	-- «Переманивание»: нужен обычный сотрудник
	local a, b = event.a, event.b
	if (a and (a.raise or a.poach)) or (b and (b.raise or b.poach)) then
		return poachTarget(profile) ~= nil
	end
	return true
end

local function available(player: Player, profile: DataService.Profile, data: Data, event: Event): boolean
	if profile.studioLevel < event.minStage then
		return false
	end
	local last = data.lastAt[event.id]
	if last and data.play - last < event.cooldown then
		return false
	end
	return needsMet(player, profile, data, event)
end

local function weighted(pool: { Event }): Event?
	local total = 0
	for _, event in pool do
		total += event.weight
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, event in pool do
		roll -= event.weight
		if roll <= 0 then
			return event
		end
	end
	return pool[#pool]
end

local function pick(player: Player, profile: DataService.Profile, data: Data): Event?
	local forced = debugForced()
	if forced then
		return CompanyEvents.get(forced)
	end
	local pools: { [string]: { Event } } = { good = {}, bad = {}, choice = {}, catastrophic = {} }
	for _, event in CompanyEvents.list do
		if available(player, profile, data, event) then
			table.insert(pools[event.kind], event)
		end
	end
	local cat = CompanyEvents.catastrophic
	local tone: CompanyEvents.Kind
	if data.badStreak >= CompanyEvents.pityAfter then
		tone = "good" -- полоса неудач: следующее — хорошее
	elseif rng:NextNumber() < CompanyEvents.choiceShare then
		tone = "choice"
	else
		local level = math.clamp(profile.studioLevel, 1, #CompanyEvents.goodChance)
		tone = if rng:NextNumber() < CompanyEvents.goodChance[level] then "good" else "bad"
		if
			tone == "bad"
			and profile.studioLevel >= cat.minStage
			and data.play - data.lastCatastrophic >= cat.cooldown
			and #pools.catastrophic > 0
			and rng:NextNumber() < cat.chance
		then
			tone = "catastrophic"
		end
	end
	return weighted(pools[tone]) or weighted(pools.good)
end

-- ===== Срабатывание и ответ =====

local function isDamaging(event: Event): boolean
	return event.kind == "bad" or event.kind == "catastrophic"
end

local function damageFor(insured: boolean): number
	return if insured then CompanyEvents.insurance.damageFactor else 1
end

-- Подписи вариантов: сколько это стоит в цифрах (уже со страховкой)
local function optionVars(
	player: Player,
	profile: DataService.Profile,
	outcome: Outcome?,
	damage: number,
	target: string?
): { [string]: any }
	local vars: { [string]: any } = {}
	if not outcome then
		return vars
	end
	local minutes = outcome.cashMinutes
	local loss = plannedLoss(player, profile, outcome, damage)
	if loss > 0 then
		vars.money = loss
	elseif minutes and minutes > 0 then
		vars.money = income(player, profile, minutes)
	end
	if outcome.fail then
		local failLoss = plannedLoss(player, profile, outcome.fail, damage)
		if failLoss > 0 then
			vars.loss = failLoss
		end
	end
	if outcome.chance then
		vars.pct = percent(outcome.chance)
	end
	if target then
		vars.employee = target
	end
	return vars
end

local function trigger(player: Player, profile: DataService.Profile, data: Data, event: Event)
	data.lastAt[event.id] = data.play
	if event.kind == "catastrophic" then
		data.lastCatastrophic = data.play
	end
	if isDamaging(event) then
		data.badStreak += 1
	elseif event.kind == "good" then
		data.badStreak = 0
	end
	data.nextIn = randomInterval()
	local insured = isDamaging(event) and data.insurance > 0
	local damage = damageFor(insured)
	nextToken += 1
	local token = nextToken
	call("AnalyticsService", "logCompanyEvent", player, event.id, if insured then "insured" else "shown")

	local info: { [string]: any } = {
		token = token,
		id = event.id,
		kind = event.kind,
		emoji = event.emoji,
		insured = insured,
	}
	if event.effect then
		-- Разовые потери — сразу: выход из игры их не отменяет
		info.lines = apply(player, profile, data, event, event.effect, damage, nil)
		if event.effect.breakSeconds and hasEffect(data, "broken") then
			info.repair = income(player, profile, CompanyEvents.repairMinutes)
		end
	else
		local target = poachTarget(profile)
		data.pending = { id = event.id, target = target, insured = insured }
		live[player] =
			{ token = token, id = event.id, target = target, insured = insured, waited = 0, seen = false }
		info.options = {
			a = optionVars(player, profile, event.a, damage, target),
			b = optionVars(player, profile, event.b, damage, target),
		}
		info.answerSeconds = CompanyEvents.answerSeconds
		info.textVars = { employee = target }
	end
	CompanyEventRemotes.CompanyEvent:FireClient(player, info)
	CompanyEventService.pushState(player)
end

-- Применить выбор (ответ, таймаут или отложенный с прошлой сессии)
local function resolve(player: Player, choice: "a" | "b", auto: boolean)
	local profile, data = dataFor(player)
	if not profile or not data then
		return
	end
	local saved = data.pending
	local current = live[player]
	live[player] = nil
	data.pending = nil
	if not saved then
		return
	end
	local event = CompanyEvents.get(saved.id)
	if not event then
		return
	end
	local outcome = if choice == "a" then event.a else event.b
	local insured = saved.insured == true
	local target = saved.target
	-- Сотрудника уже уволили сами — переманивать некого
	local StaffService = optional("StaffService")
	if target and StaffService and StaffService.hired(profile)[target] == nil then
		target = nil
	end
	local lines = apply(player, profile, data, event, outcome or {}, damageFor(insured), target)
	call("AnalyticsService", "logCompanyEvent", player, event.id, (if auto then "auto_" else "") .. choice)
	CompanyEventRemotes.CompanyEventResult:FireClient(player, {
		token = if current then current.token else 0,
		id = event.id,
		kind = event.kind,
		emoji = event.emoji,
		choice = choice,
		auto = auto,
		insured = insured,
		lines = lines,
		textVars = { employee = saved.target },
	})
	CompanyEventService.pushState(player)
end

local function onChoice(player: Player, token: any, choice: any)
	local current = live[player]
	if not current or token ~= current.token or (choice ~= "a" and choice ~= "b") then
		return
	end
	resolve(player, choice, false)
end

local function onSeen(player: Player, token: any)
	local current = live[player]
	if current and token == current.token and not current.seen then
		current.seen = true
		current.waited = 0
	end
end

local function throttled(player: Player): boolean
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return true
	end
	lastRequest[player] = now
	return false
end

local function onBuyInsurance(player: Player)
	if throttled(player) or not PlotService.ownsGarage(player) then
		return
	end
	local profile, data = dataFor(player)
	if not profile or not data then
		return
	end
	local cfg = CompanyEvents.insurance
	-- Одна страховка за раз: новую — когда кончится старая
	if data.insurance > 0 then
		return
	end
	if DataService.trySpend(player, income(player, profile, cfg.priceMinutes)) then
		data.insurance += cfg.seconds
		call("AnalyticsService", "logCompanyEvent", player, "insurance", "bought")
		CompanyEventService.pushState(player)
	end
end

local function onRepair(player: Player)
	if throttled(player) then
		return
	end
	local profile, data = dataFor(player)
	local broken = data and hasEffect(data, "broken")
	if not profile or not data or not broken then
		return
	end
	if DataService.trySpend(player, income(player, profile, CompanyEvents.repairMinutes)) then
		broken.left = 0
		local index = table.find(data.effects, broken)
		if index then
			table.remove(data.effects, index)
		end
		call("AnalyticsService", "logCompanyEvent", player, broken.id, "repaired")
		refreshStaff(player)
		CompanyEventService.pushState(player)
	end
end

-- ===== Тик =====

local function canTrigger(player: Player, data: Data): boolean
	if not CompanyEvents.enabled or live[player] or data.pending then
		return false
	end
	if player:GetAttribute("TutorialActive") == true then
		return false
	end
	if debugForced() then
		return true
	end
	local sessionAge = os.clock() - (joinedAt[player] or os.clock())
	return sessionAge >= CompanyEvents.sessionWarmupSeconds and data.play >= CompanyEvents.newPlayerSeconds
end

local function tick(player: Player, dt: number)
	local profile, data = dataFor(player)
	if not profile or not data or not joinedAt[player] then
		return
	end
	-- Без гаража (парк) и без участка студии нет: время событий не идёт
	if not PlotService.ownsGarage(player) or not PlotService.getPlot(player) then
		return
	end
	data.play += dt
	local changed = false
	local staffChanged = false
	for i = #data.effects, 1, -1 do
		local effect = data.effects[i]
		effect.left -= dt
		if effect.left <= 0 then
			table.remove(data.effects, i)
			changed = true
			staffChanged = staffChanged or effect.kind == "broken" or effect.kind == "walkout"
		end
	end
	if data.insurance > 0 then
		data.insurance = math.max(data.insurance - dt, 0)
		changed = changed or data.insurance == 0
	end
	if staffChanged then
		refreshStaff(player)
	end

	local current = live[player]
	if current then
		current.waited += dt
		local limit = if current.seen then CompanyEvents.answerSeconds else CompanyEvents.maxWaitSeconds
		if current.waited >= limit then
			local event = CompanyEvents.get(current.id)
			resolve(player, if event and event.default then event.default else "b", true)
			changed = false -- resolve уже прислал состояние
		end
	elseif data.nextIn > 0 then
		data.nextIn -= dt
	elseif canTrigger(player, data) then
		local event = pick(player, profile, data)
		if event then
			trigger(player, profile, data, event)
			changed = false
		else
			data.nextIn = CompanyEvents.retrySeconds
		end
	end
	if changed then
		CompanyEventService.pushState(player)
	end
end

-- ===== API для других сервисов =====

local function effectsOf(player: Player): { Effect }
	local profile = DataService.get(player)
	if not profile then
		return {}
	end
	local raw = (profile :: any).companyEvents
	return if type(raw) == "table" and type(raw.effects) == "table" then raw.effects else {}
end

function CompanyEventService.revenueMultiplier(player: Player): number
	local multiplier = 1
	for _, effect in effectsOf(player) do
		if effect.kind == "revenue" and effect.left > 0 then
			multiplier *= effect.value
		end
	end
	local _, data = dataFor(player)
	if data then
		multiplier *= data.nextRevenue
	end
	return math.clamp(multiplier, CompanyEvents.revenueMin, CompanyEvents.revenueMax)
end

function CompanyEventService.scoreBonus(player: Player): number
	local _, data = dataFor(player)
	return if data then data.nextScore else 0
end

-- Игра вышла: поправки «следующей игры» израсходованы
function CompanyEventService.onGameReleased(player: Player)
	local _, data = dataFor(player)
	if data and (data.nextScore ~= 0 or data.nextRevenue ~= 1) then
		data.nextScore = 0
		data.nextRevenue = 1
	end
	-- Рекорд мог вырасти — пересчитать цену страховки и починки
	CompanyEventService.pushState(player)
end

function CompanyEventService.isPaused(player: Player): boolean
	for _, effect in effectsOf(player) do
		if effect.kind == "pause" and effect.left > 0 then
			return true
		end
	end
	return false
end

function CompanyEventService.isBroken(player: Player, upgradeId: string): boolean
	for _, effect in effectsOf(player) do
		if effect.kind == "broken" and effect.item == upgradeId and effect.left > 0 then
			return true
		end
	end
	return false
end

-- Предмет ушёл из профиля (BailiffService забрал): «поломка» на нём снимается — чинить
-- за деньги больше нечего, и новые события «поломка» снова могут прийти
function CompanyEventService.forgetItem(player: Player, upgradeId: string)
	local _, data = dataFor(player)
	if not data then
		return
	end
	for index = #data.effects, 1, -1 do
		local effect = data.effects[index]
		if effect.kind == "broken" and effect.item == upgradeId then
			table.remove(data.effects, index)
		end
	end
	CompanyEventService.pushState(player)
end

function CompanyEventService.walkout(player: Player): boolean
	for _, effect in effectsOf(player) do
		if effect.kind == "walkout" and effect.left > 0 then
			return true
		end
	end
	return false
end

function CompanyEventService.rentMultiplier(player: Player): number
	for _, effect in effectsOf(player) do
		if effect.kind == "rentFree" and effect.left > 0 then
			return 0
		end
	end
	return 1
end

function CompanyEventService.salaryFactor(profile: DataService.Profile, employeeId: string): number
	local raw = (profile :: any).companyEvents
	local raises = type(raw) == "table" and raw.raises
	local factor = type(raises) == "table" and tonumber(raises[employeeId])
	return if factor and factor == factor and factor > 0 then math.min(factor, 3) else 1
end

function CompanyEventService.start()
	CompanyEventRemotes.CompanyEventChoice.OnServerEvent:Connect(onChoice)
	CompanyEventRemotes.CompanyEventSeen.OnServerEvent:Connect(onSeen)
	CompanyEventRemotes.BuyInsurance.OnServerEvent:Connect(onBuyInsurance)
	CompanyEventRemotes.RepairItem.OnServerEvent:Connect(onRepair)
	-- Участок пересобран (вход, переезд): вернуть дымок над сломанным предметом
	PlotService.plotChanged:Connect(syncSmoke)
	CompanyEventRemotes.CompanyEventStateRequest.OnServerEvent:Connect(function(player: Player)
		if not throttled(player) then
			CompanyEventService.pushState(player)
		end
	end)
	DataService.onProfileLoaded(function(player, profile)
		local data = dataOf(profile)
		joinedAt[player] = os.clock()
		if debugForced() then
			data.nextIn = math.min(data.nextIn, 15)
		end
		-- Настроение не сохраняется (MoodService): вернуть поправку выгорания на остаток
		for _, effect in data.effects do
			if effect.kind == "mood" then
				call("MoodService", "addTemporary", player, MOOD_KEY, effect.value, effect.left, true)
			end
		end
		-- Вышел, не ответив, — вариант по умолчанию сейчас (сначала прогрузится интерфейс)
		local pending = data.pending
		if pending then
			task.delay(8, function()
				local event = CompanyEvents.get(pending.id)
				if player.Parent and data.pending == pending and event then
					resolve(player, event.default or "b", true)
				end
			end)
		end
		CompanyEventService.pushState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		live[player] = nil
		joinedAt[player] = nil
		lastRequest[player] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local now = os.clock()
			local dt = math.min(now - last, TICK * 5)
			last = now
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tick, player, dt)
				if not ok then
					warn("[CompanyEventService] tick failed:", err)
				end
			end
		end
	end)
end

return CompanyEventService
