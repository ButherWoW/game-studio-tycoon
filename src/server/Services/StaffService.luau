--!strict
-- Найм сотрудников (issue #7), рассадка за столы и NPC (без подписей — имена в окне «Команда»).
-- Данные профиля:
--   (profile :: any).staff = { [employeeId]: deskUpgradeId } — "" значит «ждёт стол» (стол спрятан
--     после переезда или его занял легендарный);
--   (profile :: any).staffInfo = { [employeeId]: Info } — навыки, перки и внешность (Config/Skills).
-- Стол — купленный апгрейд с desk = true, который стоит на участке на текущем этапе
-- (StudioLayout.isVisible); за одним столом один сотрудник.
--
-- Публичные функции для других сервисов (сами сюда не лезут):
--   employeesByDesk(player)          — стол -> сотрудник (DevelopmentService.pointsRate)
--   deskMultipliers(player, deskId)  — множители очков стола по направлениям (навыки + «Наставник»)
--   reviewBonus(player)              — прибавка к оценке: «Мастер Пиксель» +1 и «Перфекционист»
--   perkTotals(player)               — остальные эффекты перков (время, баг, стример, тренд)
--   offlineMultiplier(profile)       — офлайн-доход: «Призрачный кодер» ×2, «Ночная смена»
--   hired(profile)                   — нанятые: employeeId -> стол (SkinService)
--   refreshNpcs(player)              — пересобрать NPC (SkinService: сменили скин)
--   power(player)                    — мощность команды для окна и HUD (скорость, оценка по направлениям)
-- Перерывы (StaffLife): setBreak(player, id, on) — сотрудник на перерыве не даёт очков и перков
-- (employeesByDesk, deskMultipliers, perkTotals), но прибавка к оценке (reviewBonus) считается по всем
-- за столами — иначе оценка зависела бы от того, кто отошёл за кофе в момент релиза.
-- Ощущение команды: найм/навык/увольнение шлют клиенту StaffFeel «было → стало», уволенный NPC
-- встаёт и уходит с коробкой (StaffLife.leave), настроение получает временную поправку (MoodService).
-- Скины (SkinService, необязательный): decorate наряжает NPC при сборке, forget — при увольнении.
--
-- Увольнение (FireEmployee): сотрудник уходит вместе с навыками и перками, возвращается
-- Employees.refundFor (доля fireRefund от цены найма; легендарные бесплатные — 0,
-- нанять снова можно даром).
-- Подсказка о забастовке: (profile :: any).strikeTipSeen = true, когда игрок её закрыл;
-- клиенту — атрибут игрока StrikeTipSeen (false — ещё не видел; nil — профиль не загружен).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Employees = require(ReplicatedStorage.Shared.Config.Employees)
local Skills = require(ReplicatedStorage.Shared.Config.Skills)
local StaffAppearance = require(script.Parent.StaffAppearance)
local Expenses = require(ReplicatedStorage.Shared.Config.Expenses)
local Mood = require(ReplicatedStorage.Shared.Config.Mood)
local StaffRemotes = require(ReplicatedStorage.Shared.StaffRemotes)
local StudioLayout = require(ReplicatedStorage.Shared.StudioLayout)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local SEAT_DISTANCE = 3.5 -- насколько перед столом стоит NPC
local SEAT_MIN_GAP = 2.5 -- столы стоят тесно (стол, ПК, кресло): раздвигаем NPC вбок
local SEAT_SIDE_SHIFTS = { 0, -3, 3, -6, 6, -9, 9 }
local DESK_TOP = 3.05 -- высота столешницы над полом (предмет на столе)
local DESK_ITEM_OFFSET = Vector3.new(2.2, 0, 0.7) -- правый передний угол стола
local PANTS = Color3.fromRGB(45, 50, 70)
local ACTION_COOLDOWN = 0.2 -- между запросами навыков/перков/внешности
local PASS_RECHECK = 4 -- через сколько секунд после покупки геймпасса пересылать команду
local JOIN_RECHECK = 8 -- геймпассы ShopService грузит асинхронно: перешлём ещё раз после входа

export type Look = { shirt: number, skin: number, hat: number, item: number }
export type Info = {
	skills: { [string]: number },
	perks: { string }, -- по слоту; "" — пустой слот
	perkChangedAt: number,
	look: Look,
}
export type PerkTotals = {
	devTime: number, -- множитель времени разработки: 0.9 = на 10% быстрее
	bugAlwaysWins: boolean,
	streamerMultiplier: number,
	trendBonus: number,
}

local LOOK_LIMITS: { [string]: { min: number, max: number } } = {
	shirt = { min = 0, max = #Skills.shirts },
	skin = { min = 0, max = #Skills.skins }, -- 0 — свой цвет из Config/StaffLooks
	hat = { min = 1, max = #Skills.hats },
	item = { min = 1, max = #Skills.items },
}

local StaffService = {}
local npcFolders: { [Player]: Folder } = {}
-- Кто сейчас на перерыве (StaffLife): employeeId -> true
local breaks: { [Player]: { [string]: boolean } } = {}
-- Наняли, NPC ещё строится: после пересборки клиенту уйдёт «arrive» с моделью (конфетти у стола)
local pendingArrive: { [Player]: { [string]: boolean } } = {}
local refreshGeneration: { [Player]: number } = {}
local lastAction: { [Player]: number } = {}

local function optionalService(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		return require(module) :: any
	end
	return nil
end

-- «Охота за талантами» (DailyEventService): «звезда» найма и её цена со скидкой; nil — события нет
local function talentStar(player: Player): (string?, number?)
	local DailyEventService = optionalService("DailyEventService")
	if not DailyEventService then
		return nil, nil
	end
	local ok, id, cost = pcall(DailyEventService.talentStar, player)
	if ok and type(id) == "string" and type(cost) == "number" and cost >= 0 then
		return id, cost
	end
	return nil, nil
end

local function hireCost(player: Player, employee: Employees.Employee): number
	local starId, cost = talentStar(player)
	return if starId == employee.id and cost then math.min(cost, employee.cost) else employee.cost
end

local function isInteger(value: any, min: number, max: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= min and value <= max
end

-- Нанятые сотрудники игрока; из сохранения берём только то, что сходится с конфигом.
-- Стол, которого больше нет (продан Rebirth'ом, спрятан), превращается в «ждёт стол»;
-- если у игрока не куплено ни одного стола (после Rebirth) — команда распущена.
local function getStaff(profile: DataService.Profile): { [string]: string }
	local raw = (profile :: any).staff
	if type(raw) ~= "table" then
		raw = {};
		(profile :: any).staff = raw
	end
	local anyDesk = false
	for _, upgrade in Upgrades do
		if upgrade.desk and profile.upgrades[upgrade.id] then
			anyDesk = true
			break
		end
	end
	local usedDesks: { [string]: boolean } = {}
	for employeeId, deskId in raw do
		local valid = anyDesk
			and type(employeeId) == "string"
			and type(deskId) == "string"
			and Employees.get(employeeId) ~= nil
		if not valid then
			raw[employeeId] = nil
		elseif deskId ~= "" then
			local desk = StudioLayout.get(deskId)
			if not desk or not desk.desk or profile.upgrades[deskId] ~= true or usedDesks[deskId] then
				raw[employeeId] = ""
			else
				usedDesks[deskId] = true
			end
		end
	end
	return raw
end

local function defaultInfo(employee: Employees.Employee): Info
	local perks = {}
	for i = 1, Skills.slots(employee.legendary) do
		perks[i] = ""
	end
	return {
		skills = Skills.start(employee.specialization, employee.legendary),
		perks = perks,
		perkChangedAt = 0,
		look = { shirt = 0, skin = 0, hat = 1, item = 1 },
	}
end

local function employeeLevel(info: Info): number
	local total = 0
	for _, key in Skills.keys do
		total += info.skills[key] or 0
	end
	return total
end

-- Навыки/перки/внешность нанятых; мусор из сохранения чинится, уволенных (Rebirth) — удаляем
local function getInfo(profile: DataService.Profile): { [string]: Info }
	local staff = getStaff(profile)
	local raw = (profile :: any).staffInfo
	if type(raw) ~= "table" then
		raw = {};
		(profile :: any).staffInfo = raw
	end
	for employeeId in raw do
		if type(employeeId) ~= "string" or staff[employeeId] == nil then
			raw[employeeId] = nil
		end
	end
	for employeeId in staff do
		local employee = Employees.get(employeeId) :: Employees.Employee
		local fresh = defaultInfo(employee)
		local info = raw[employeeId]
		if type(info) ~= "table" then
			raw[employeeId] = fresh
			continue
		end
		if type(info.skills) ~= "table" then
			info.skills = fresh.skills
		end
		for _, key in Skills.keys do
			if not isInteger(info.skills[key], 0, Skills.maxLevel) then
				info.skills[key] = fresh.skills[key]
			end
		end
		for key in info.skills do
			if not Skills.isKey(key) then
				info.skills[key] = nil
			end
		end
		local perks = if type(info.perks) == "table" then info.perks else {}
		local clean = {}
		local level = employeeLevel(info)
		for i = 1, Skills.slots(employee.legendary) do
			local id = perks[i]
			local perk = if type(id) == "string" then Skills.perk(id) else nil
			local duplicate = perk ~= nil and table.find(clean, id) ~= nil
			clean[i] = if perk and not duplicate and level >= perk.minLevel then id else ""
		end
		info.perks = clean
		info.perkChangedAt = tonumber(info.perkChangedAt) or 0
		if type(info.look) ~= "table" then
			info.look = fresh.look
		end
		for field, limits in LOOK_LIMITS do
			if not isInteger(info.look[field], limits.min, limits.max) then
				info.look[field] = (fresh.look :: any)[field]
			end
		end
	end
	return raw
end

-- Открыт ли легендарный: награда квеста (RewardService кладёт в profile.rewards.employees)
-- или геймпасс. robo — пока нет условия (исследование, другая задача): нанять нельзя.
local function legendUnlocked(
	player: Player,
	profile: DataService.Profile,
	employee: Employees.Employee
): boolean
	if employee.unlockReward then
		local rewards = (profile :: any).rewards
		local unlocked = type(rewards) == "table" and type(rewards.employees) == "table"
		return unlocked and rewards.employees[employee.unlockReward] == true
	end
	if employee.unlockPass then
		local ShopService = optionalService("ShopService")
		return ShopService ~= nil and ShopService.ownsPass(player, employee.unlockPass) == true
	end
	-- РОБО-9000 открывает исследование «ИИ-ассистент» (robotHire)
	if employee.id == "robo" then
		local ResearchService = optionalService("ResearchService")
		return ResearchService ~= nil and ResearchService.getModifiers(player).robotHire == true
	end
	return false
end

-- Кого сажать первым: легендарных, потом сильных; при равенстве — по id (стабильно)
local function priority(employee: Employees.Employee): number
	return (if employee.legendary then 1000 else 0) + employee.multiplier * 10 + employee.stage
end

local function byPriority(a: string, b: string): boolean
	local ea = Employees.get(a) :: Employees.Employee
	local eb = Employees.get(b) :: Employees.Employee
	local pa, pb = priority(ea), priority(eb)
	if pa ~= pb then
		return pa > pb
	end
	return a < b
end

-- Пересадить команду под текущие столы: кто сидит за спрятанным столом — встаёт, ждущие
-- садятся за свободные столы (сначала легендарные), легендарный без места сгоняет самого слабого.
-- Возвращает true, если рассадка изменилась.
local function seatAll(profile: DataService.Profile): boolean
	local staff = getStaff(profile)
	local desks = StudioLayout.visibleDesks(profile.upgrades, profile.studioLevel)
	local visible: { [string]: Upgrades.Upgrade } = {}
	for _, desk in desks do
		visible[desk.id] = desk
	end
	local changed = false
	local taken: { [string]: string } = {} -- deskId -> employeeId
	for employeeId, deskId in staff do
		if deskId ~= "" then
			local employee = Employees.get(employeeId) :: Employees.Employee
			local desk = visible[deskId]
			if desk and StudioLayout.canSit(employee.stage, desk) then
				taken[deskId] = employeeId
			else
				staff[employeeId] = ""
				changed = true
			end
		end
	end
	local waiting = {}
	for employeeId, deskId in staff do
		if deskId == "" then
			table.insert(waiting, employeeId)
		end
	end
	table.sort(waiting, byPriority)
	for _, employeeId in waiting do
		local employee = Employees.get(employeeId) :: Employees.Employee
		local seat: Upgrades.Upgrade? = nil
		for _, desk in desks do
			if not taken[desk.id] and StudioLayout.canSit(employee.stage, desk) then
				seat = desk
				break
			end
		end
		if not seat and employee.legendary then
			-- Самый слабый обычный сотрудник за подходящим столом уступает место
			local weakest: string? = nil
			for _, desk in desks do
				local other = taken[desk.id]
				local otherEmployee = other and Employees.get(other)
				if
					other
					and otherEmployee
					and not otherEmployee.legendary
					and StudioLayout.canSit(employee.stage, desk)
					and (weakest == nil or byPriority(weakest, other))
				then
					weakest = other
					seat = desk
				end
			end
			if weakest then
				staff[weakest] = ""
			end
		end
		if seat then
			staff[employeeId] = seat.id
			taken[seat.id] = employeeId
			changed = true
		end
	end
	return changed
end

-- Сотрудники, которые сидят за столами: employeeId -> deskId
local function seated(profile: DataService.Profile): { [string]: string }
	local result = {}
	for employeeId, deskId in getStaff(profile) do
		if deskId ~= "" then
			result[employeeId] = deskId
		end
	end
	return result
end

-- Кто в строю: за столами и не бастует (ExpensesService ставит staffStrike, когда нечем платить)
local function active(profile: DataService.Profile): { [string]: string }
	if (profile :: any).staffStrike == true then
		return {}
	end
	local result = seated(profile)
	-- Стример (StreamerService) сидит за столом, но не разрабатывает: ни очков, ни перков, ни оценки
	local streamer = (profile :: any).streamer
	if type(streamer) == "table" and type(streamer.employeeId) == "string" then
		result[streamer.employeeId] = nil
	end
	return result
end

-- События компании (CompanyEventService, необязательный): забастовка-«уход», сломанные столы, прибавки
local function companyEvents(): any
	local module = script.Parent:FindFirstChild("CompanyEventService")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, service = pcall(require, module)
	return if ok then service else nil
end

-- Кто работает прямо сейчас: в строю, не на перерыве (StaffLife), стол не сломан и команда
-- не ушла (события компании)
local function working(player: Player, profile: DataService.Profile): { [string]: string }
	local result = active(profile)
	local away = breaks[player]
	if away then
		for employeeId in away do
			result[employeeId] = nil
		end
	end
	local events = companyEvents()
	if events then
		if events.walkout(player) then
			return {}
		end
		for employeeId, deskId in result do
			if events.isBroken(player, deskId) then
				result[employeeId] = nil
			end
		end
	end
	return result
end

-- Зарплаты всех нанятых в минуту (Config/Expenses): платим и тем, кто ждёт стол
function StaffService.salaryPerMinute(profile: DataService.Profile): number
	local info = getInfo(profile)
	local events = companyEvents()
	local total = 0
	for employeeId in getStaff(profile) do
		local employee = Employees.get(employeeId)
		if employee then
			local employeeInfo = info[employeeId]
			local pay = Expenses.salary(employee, if employeeInfo then employeeInfo.skills else nil)
			-- Прибавка, чтобы конкурент не переманил (события компании)
			local factor = if events then events.salaryFactor(profile, employeeId) else 1
			total += math.floor(pay * factor)
		end
	end
	return total
end

-- deskUpgradeId -> сотрудник за этим столом (для DevelopmentService)
function StaffService.employeesByDesk(player: Player): { [string]: Employees.Employee }
	local result = {}
	local profile = DataService.get(player)
	if not profile then
		return result
	end
	for employeeId, deskId in working(player, profile) do
		local employee = Employees.get(employeeId)
		if employee then
			result[deskId] = employee
		end
	end
	return result
end

-- Множители очков стола deskId по направлениям: навыки сотрудника за ним
-- (1 + bonusPerLevel × уровень) и «Наставники» за другими столами (+mentorBonus каждый).
-- Для стола без сотрудника — только наставники. Умножать вклад стола в каждое направление.
function StaffService.deskMultipliers(player: Player, deskId: string): { [string]: number }
	local result = { gameplay = 1, graphics = 1, sound = 1, story = 1 }
	local profile = DataService.get(player)
	if not profile then
		return result
	end
	local info = getInfo(profile)
	local mentor = 0
	local atDesk: string? = nil
	for employeeId, seatId in working(player, profile) do
		local employeeInfo = info[employeeId]
		if seatId == deskId then
			atDesk = employeeId
		elseif employeeInfo then
			for _, perkId in employeeInfo.perks do
				local perk = Skills.perk(perkId)
				if perk and perk.mentorBonus then
					mentor += perk.mentorBonus
				end
			end
		end
	end
	local skills = if atDesk and info[atDesk] then info[atDesk].skills else nil
	for _, key in Skills.keys do
		local level = if skills then skills[key] or 0 else 0
		result[key] = (1 + Skills.bonusPerLevel * level) * (1 + math.min(mentor, Skills.caps.mentorBonus))
	end
	return result
end

-- Перки сотрудников за столами, кроме прибавки к оценке (она в reviewBonus) и «Наставника»
-- (он в deskMultipliers) и «Ночной смены» (offlineMultiplier)
function StaffService.perkTotals(player: Player): PerkTotals
	local totals: PerkTotals = { devTime = 1, bugAlwaysWins = false, streamerMultiplier = 1, trendBonus = 0 }
	local profile = DataService.get(player)
	if not profile then
		return totals
	end
	local info = getInfo(profile)
	for employeeId in working(player, profile) do
		local employeeInfo = info[employeeId]
		if employeeInfo then
			for _, perkId in employeeInfo.perks do
				local perk = Skills.perk(perkId)
				if perk then
					totals.devTime += perk.devTime or 0
					totals.bugAlwaysWins = totals.bugAlwaysWins or perk.bugAlwaysWins == true
					totals.streamerMultiplier =
						math.max(totals.streamerMultiplier, perk.streamerMultiplier or 1)
					totals.trendBonus += perk.trendBonus or 0
				end
			end
		end
	end
	totals.devTime = math.max(totals.devTime, 0.5)
	-- Перки складываются по сотрудникам, но не бесконечно
	totals.trendBonus = math.min(totals.trendBonus, Skills.caps.trendBonus)
	return totals
end

-- Оценка по направлениям от навыков команды: уровень × qualityPerLevel; сумма — не выше потолка
local function teamQuality(
	members: { [string]: string },
	info: { [string]: Info }
): ({ [string]: number }, number)
	local quality = { gameplay = 0, graphics = 0, sound = 0, story = 0 }
	local total = 0
	for employeeId in members do
		local employeeInfo = info[employeeId]
		if employeeInfo then
			for _, key in Skills.keys do
				local value = (employeeInfo.skills[key] or 0) * Skills.qualityPerLevel
				quality[key] += value
				total += value
			end
		end
	end
	return quality, math.min(total, Skills.caps.teamQuality)
end

-- Прибавка к оценке от состава members: «Мастер Пиксель» (+1), «Перфекционист» и навыки
local function reviewOf(members: { [string]: string }, info: { [string]: Info }): number
	local total = 0
	local perkBonus = 0
	for employeeId in members do
		local employee = Employees.get(employeeId)
		total += if employee then employee.reviewBonus or 0 else 0
		local employeeInfo = info[employeeId]
		if employeeInfo then
			for _, perkId in employeeInfo.perks do
				local perk = Skills.perk(perkId)
				perkBonus += if perk then perk.reviewBonus or 0 else 0
			end
		end
	end
	local _, quality = teamQuality(members, info)
	return total + math.min(perkBonus, Skills.caps.reviewBonus) + quality
end

-- Прибавка к оценке каждой игры от команды за столами (перерыв не мешает): легендарный
-- «Мастер Пиксель» (+1), перк «Перфекционист» и навыки (qualityPerLevel). Прибавлять к bonus в Formulas.review
function StaffService.reviewBonus(player: Player): number
	local profile = DataService.get(player)
	if not profile then
		return 0
	end
	return reviewOf(active(profile), getInfo(profile))
end

-- ===== Мощность команды (окно «Команда», HUD, «было → стало») =====
export type Power = {
	speed: number, -- 0.45 = очков разработки в секунду на 45% больше, чем у тех же столов без команды
	quality: { [string]: number }, -- прибавка к оценке по направлениям (навыки)
	review: number, -- вся прибавка команды к оценке игры (reviewBonus)
	breaks: number, -- сколько сейчас на перерыве
}

local function moodSpeed(player: Player): number
	local MoodService = optionalService("MoodService")
	local ok, value = pcall(function()
		return if MoodService then MoodService.speedMultiplier(player) else 1
	end)
	return if ok and type(value) == "number" and value > 0 then value else 1
end

-- Мощность состава members (employeeId -> стол) — как DevelopmentService.pointsRate при ровном
-- фокусе (бонус специализации зависит от фокуса игры — не считаем), с настроением и «Кранчером»
local function powerOf(
	profile: DataService.Profile,
	members: { [string]: string },
	info: { [string]: Info },
	mood: number
): Power
	local mentor, devTime = 0, 1
	local byDesk: { [string]: string } = {}
	for employeeId, deskId in members do
		byDesk[deskId] = employeeId
		local employeeInfo = info[employeeId]
		if employeeInfo then
			for _, perkId in employeeInfo.perks do
				local perk = Skills.perk(perkId)
				if perk then
					mentor += perk.mentorBonus or 0
					devTime += perk.devTime or 0
				end
			end
		end
	end
	local mentorMult = 1 + math.min(mentor, Skills.caps.mentorBonus)
	local base, team = 0, 0
	for _, upgrade in Upgrades do
		local points = upgrade.pointsPerSecond
		if points and profile.upgrades[upgrade.id] then
			base += points
			local employeeId = byDesk[upgrade.id]
			local employee = if employeeId then Employees.get(employeeId) else nil
			local skills = if employeeId and info[employeeId] then info[employeeId].skills else nil
			local average = 0
			for _, key in Skills.keys do
				local level = if skills then skills[key] or 0 else 0
				average += (1 + Skills.bonusPerLevel * level) / #Skills.keys
			end
			team += points * (if employee then employee.multiplier else 1) * average * mentorMult
		end
	end
	local quality = teamQuality(members, info)
	local speed = if base > 0 then team / base * mood / math.max(devTime, 0.5) - 1 else 0
	return { speed = speed, quality = quality, review = reviewOf(members, info), breaks = 0 }
end

-- Мощность команды сейчас. Перерывы не вычитаем: это постоянная сила команды, отдыхающие — в breaks
function StaffService.power(player: Player): Power
	local profile = DataService.get(player)
	if not profile then
		return {
			speed = 0,
			quality = { gameplay = 0, graphics = 0, sound = 0, story = 0 },
			review = 0,
			breaks = 0,
		}
	end
	local result = powerOf(profile, active(profile), getInfo(profile), moodSpeed(player))
	local count = 0
	for _ in breaks[player] or {} do
		count += 1
	end
	result.breaks = count
	return result
end

-- Клиенту: мощность и сколько потеряем без каждого из сотрудников за столами (подтверждение увольнения)
local function sendPower(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local power = StaffService.power(player)
	local info = getInfo(profile)
	local members = active(profile)
	local mood = moodSpeed(player)
	local losses = {}
	for employeeId in members do
		local without = table.clone(members)
		without[employeeId] = nil
		local other = powerOf(profile, without, info, mood)
		losses[employeeId] = { speed = other.speed - power.speed, review = other.review - power.review }
	end
	StaffRemotes.StaffPower:FireClient(player, {
		speed = power.speed,
		quality = power.quality,
		review = power.review,
		breaks = power.breaks,
		losses = losses,
	})
end

-- Перерыв (StaffLife): пока on — стол сотрудника не даёт очков
function StaffService.setBreak(player: Player, employeeId: string, on: boolean)
	local away = breaks[player]
	if on then
		if not away then
			away = {}
			breaks[player] = away
		end
		(away :: { [string]: boolean })[employeeId] = true
	elseif away then
		away[employeeId] = nil
	end
	sendPower(player)
end

-- Сотрудники за столами и не на забастовке (StaffLife выбирает, кому отдохнуть)
function StaffService.activeStaff(player: Player): { [string]: string }
	local profile = DataService.get(player)
	return if profile then active(profile) else {}
end

-- Папка NPC игрока на участке (nil — ещё не собрана)
function StaffService.npcFolder(player: Player): Folder?
	return npcFolders[player]
end

-- Множитель офлайн-дохода: легендарный в команде (даже если ждёт стол) и «Ночная смена» за столом
function StaffService.offlineMultiplier(profile: DataService.Profile): number
	local multiplier = 1
	local staff = getStaff(profile)
	for employeeId in staff do
		local employee = Employees.get(employeeId)
		if employee and employee.offlineMultiplier then
			multiplier *= employee.offlineMultiplier
		end
	end
	local info = getInfo(profile)
	local bonus = 0
	for employeeId, deskId in staff do
		local employeeInfo = info[employeeId]
		if deskId ~= "" and employeeInfo then
			for _, perkId in employeeInfo.perks do
				local perk = Skills.perk(perkId)
				bonus += if perk then perk.offlineBonus or 0 else 0
			end
		end
	end
	return multiplier * (1 + math.min(bonus, Skills.caps.offlineBonus))
end

-- Нанятые (employeeId -> стол, "" — ждёт стол); мусор из сохранения чинится как обычно
function StaffService.hired(profile: DataService.Profile): { [string]: string }
	return getStaff(profile)
end

local function sendStaff(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local unlocked = {}
	for _, employee in Employees.list do
		if employee.legendary then
			unlocked[employee.id] = legendUnlocked(player, profile, employee)
		end
	end
	local staff = getStaff(profile)
	-- Прибавки к зарплате (события компании): окно «Команда» показывает зарплату с ними
	local events = companyEvents()
	local raises = {}
	if events then
		for employeeId in staff do
			local factor = events.salaryFactor(profile, employeeId)
			if factor ~= 1 then
				raises[employeeId] = factor
			end
		end
	end
	local starId, starCost = talentStar(player)
	StaffRemotes.StaffChanged:FireClient(player, staff, {
		info = getInfo(profile),
		unlocked = unlocked,
		now = os.time(),
		raises = raises,
		-- «Звезда» события дня: id и цена со скидкой (окно «Команда»)
		star = if starId then { id = starId, cost = starCost } else nil,
	})
end

-- ===== NPC =====

local function attach(model: Model, size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	-- Не на суставах: в позе «сидя» остаётся закреплённой (иначе шапка падала сквозь пол)
	p:SetAttribute("Loose", true)
	p.Parent = model
	return p
end

-- Вертикальный цилиндр (ось цилиндра в Roblox — X)
local function attachCylinder(
	model: Model,
	height: number,
	diameter: number,
	cframe: CFrame,
	color: Color3
): Part
	return attach(
		model,
		Vector3.new(height, diameter, diameter),
		cframe * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.PartType.Cylinder
	)
end

-- Головной убор из деталей поверх головы (−Z головы — лицо)
local function buildHat(model: Model, hat: string)
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local size = head.Size
	local top = head.CFrame * CFrame.new(0, size.Y / 2, 0)
	if hat == "cap" then
		local red = Color3.fromRGB(220, 50, 60)
		attachCylinder(model, 0.45, size.X * 1.05, top * CFrame.new(0, 0.05, 0), red)
		attach(
			model,
			Vector3.new(size.X * 0.9, 0.08, 0.7),
			top * CFrame.new(0, -0.12, -size.Z / 2 - 0.2),
			red
		)
	elseif hat == "headphones" then
		local dark = Color3.fromRGB(30, 30, 35)
		attach(model, Vector3.new(size.X + 0.3, 0.15, 0.3), top * CFrame.new(0, 0.1, 0), dark)
		for _, side in { -1, 1 } do
			attach(
				model,
				Vector3.new(0.25, 0.6, 0.6),
				head.CFrame * CFrame.new(side * (size.X / 2 + 0.12), 0, 0),
				Color3.fromRGB(0, 200, 255)
			)
		end
	elseif hat == "beanie" then
		local color = Color3.fromRGB(60, 130, 90)
		attach(
			model,
			Vector3.new(size.X * 1.1, size.Y * 0.7, size.Z * 1.1),
			top * CFrame.new(0, -0.05, 0),
			color,
			Enum.PartType.Ball
		)
		attach(
			model,
			Vector3.new(0.4, 0.4, 0.4),
			top * CFrame.new(0, size.Y * 0.35, 0),
			Color3.new(1, 1, 1),
			Enum.PartType.Ball
		)
	elseif hat == "tophat" then
		local black = Color3.fromRGB(20, 20, 25)
		attachCylinder(model, 0.1, size.X * 1.5, top * CFrame.new(0, 0.05, 0), black)
		attachCylinder(model, 1.1, size.X * 0.85, top * CFrame.new(0, 0.6, 0), black)
	elseif hat == "crown" then
		local gold = Color3.fromRGB(255, 200, 50)
		attachCylinder(model, 0.35, size.X * 0.95, top * CFrame.new(0, 0.15, 0), gold)
		for i = 0, 3 do
			local angle = math.rad(i * 90 + 45)
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * size.X * 0.4
			attach(
				model,
				Vector3.new(0.18, 0.35, 0.18),
				top * CFrame.new(offset + Vector3.new(0, 0.45, 0)),
				gold
			)
		end
	end
end

-- Предмет сотрудника на столе (в координатах участка уже посчитан cframe — точка на столешнице)
local function buildDeskItem(model: Model, item: string, cframe: CFrame)
	if item == "mug" then
		attachCylinder(model, 0.5, 0.4, cframe * CFrame.new(0, 0.25, 0), Color3.fromRGB(240, 240, 240))
		attach(
			model,
			Vector3.new(0.08, 0.3, 0.2),
			cframe * CFrame.new(0.25, 0.25, 0),
			Color3.fromRGB(240, 240, 240)
		)
	elseif item == "figurine" then
		attach(
			model,
			Vector3.new(0.4, 0.08, 0.4),
			cframe * CFrame.new(0, 0.04, 0),
			Color3.fromRGB(40, 40, 45)
		)
		attach(
			model,
			Vector3.new(0.25, 0.4, 0.18),
			cframe * CFrame.new(0, 0.28, 0),
			Color3.fromRGB(61, 123, 255)
		)
		attach(
			model,
			Vector3.new(0.22, 0.22, 0.22),
			cframe * CFrame.new(0, 0.6, 0),
			Color3.fromRGB(255, 210, 160),
			Enum.PartType.Ball
		)
	elseif item == "cactus" then
		attachCylinder(model, 0.3, 0.4, cframe * CFrame.new(0, 0.15, 0), Color3.fromRGB(200, 120, 80))
		attachCylinder(model, 0.6, 0.22, cframe * CFrame.new(0, 0.6, 0), Color3.fromRGB(70, 160, 70))
		attach(
			model,
			Vector3.new(0.25, 0.08, 0.08),
			cframe * CFrame.new(0.15, 0.6, 0),
			Color3.fromRGB(70, 160, 70)
		)
	elseif item == "duck" then
		local yellow = Color3.fromRGB(255, 220, 50)
		attach(
			model,
			Vector3.new(0.45, 0.35, 0.35),
			cframe * CFrame.new(0, 0.18, 0),
			yellow,
			Enum.PartType.Ball
		)
		attach(
			model,
			Vector3.new(0.25, 0.25, 0.25),
			cframe * CFrame.new(0, 0.42, 0.1),
			yellow,
			Enum.PartType.Ball
		)
		attach(
			model,
			Vector3.new(0.1, 0.06, 0.14),
			cframe * CFrame.new(0, 0.4, 0.26),
			Color3.fromRGB(255, 140, 40)
		)
	end
end

local function buildNpc(employee: Employees.Employee, look: Look): Model?
	local description = Instance.new("HumanoidDescription")
	local shirt = if look.shirt > 0
		then Skills.shirts[look.shirt]
		else Employees.shirtColors[employee.specialization or "all"]
	local skin = Skills.skins[look.skin] or StaffAppearance.bodyColor(employee.id) or Skills.skins[1]
	local pants = StaffAppearance.pantsColor(employee.id) or PANTS
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = shirt
	description.LeftLegColor = pants
	description.RightLegColor = pants
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn("[StaffService] NPC build failed:", result)
		return nil
	end
	local model = result :: Model
	model.Name = "Staff_" .. employee.id
	-- Лицо, причёска и одежда Астры (V13); платный скин потом перекроет одежду
	StaffAppearance.apply(model, employee.id, look.shirt > 0)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	buildHat(model, Skills.hats[look.hat] or "none")
	return model
end

-- Сидушка кресла в модели стола на участке (у столов Астры: BlueSeat_* / SeatCushion; PcSeat игрока
-- не трогаем). Возвращает центр верха сидушки в мировых координатах или nil — кресла нет
local function chairSeatTop(plot: BasePart, desk: Upgrades.Upgrade): Vector3?
	local position = desk.position or Vector3.zero
	local deskWorld =
		plot.CFrame:PointToWorldSpace(Vector3.new(position.X, plot.Size.Y / 2 + position.Y - 0.5, position.Z))
	local model: Model? = nil
	for _, child in plot:GetChildren() do
		if child:IsA("Model") and child.Name == desk.model then
			local pivot = child:GetPivot().Position
			if Vector3.new(pivot.X - deskWorld.X, 0, pivot.Z - deskWorld.Z).Magnitude < 1 then
				model = child
				break
			end
		end
	end
	if not model then
		return nil
	end
	local minX, maxX, minZ, maxZ, top = math.huge, -math.huge, math.huge, -math.huge, -math.huge
	for _, part in model:GetDescendants() do
		if
			part:IsA("BasePart")
			and part.Name ~= "PcSeat"
			and string.find(string.lower(part.Name), "seat")
		then
			local p = part.Position
			minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
			minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
			top = math.max(top, p.Y + part.Size.Y / 2)
		end
	end
	if top == -math.huge then
		return nil
	end
	return Vector3.new((minX + maxX) / 2, top, (minZ + maxZ) / 2)
end

-- Поза «сидя» для R15: корень закреплён, остальные детали держатся на суставах; бёдра вперёд на 90°,
-- колени обратно вниз (отчёт владельца: сотрудники стояли перед мониторами)
local SIT_ROOT_ABOVE_SEAT = 1.6
local function bendLegs(model: Model, sign: number)
	for _, part in model:GetDescendants() do
		if part:IsA("Motor6D") then
			if part.Name == "LeftHip" or part.Name == "RightHip" then
				part.C0 = part.C0 * CFrame.Angles(math.rad(90 * sign), 0, 0)
			elseif part.Name == "LeftKnee" or part.Name == "RightKnee" then
				part.C0 = part.C0 * CFrame.Angles(math.rad(-90 * sign), 0, 0)
			end
		end
	end
end

local function poseSitting(model: Model)
	if model:GetAttribute("Sitting") == true then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = part == root or part:GetAttribute("Loose") == true
			part.CanCollide = false
		end
	end
	bendLegs(model, 1)
	model:SetAttribute("Sitting", true)
end

-- Встать (StaffLife: перерыв, увольнение): ноги обратно, корень — на высоту стоящего
function StaffService.poseStanding(model: Model)
	if model:GetAttribute("Sitting") == true then
		bendLegs(model, -1)
		model:SetAttribute("Sitting", false)
	end
end

-- Сесть обратно на своё место (после перерыва): поза и точка из атрибутов seatNpc
function StaffService.sitBack(model: Model, plot: BasePart)
	local seat = model:GetAttribute("SeatLocal")
	if typeof(seat) ~= "CFrame" then
		return
	end
	if model:GetAttribute("Chair") == true then
		poseSitting(model)
	end
	model:PivotTo(plot.CFrame * seat)
end

-- Посадить NPC в кресло стола (если оно есть в модели) или поставить перед столом лицом к нему.
-- used — уже занятые точки (в координатах участка)
local function seatNpc(model: Model, plot: BasePart, desk: Upgrades.Upgrade, used: { Vector3 })
	local position = desk.position or Vector3.zero
	-- Пол этажа стола: position.Y = 0.5 (верх участка) + высота этажа (Config/Stages.floorY)
	local floorY = plot.Size.Y / 2 + position.Y - 0.5
	local rotation = CFrame.Angles(0, math.rad(desk.rotation or 0), 0)
	local deskPoint = Vector3.new(position.X, floorY, position.Z)
	-- Для перерывов и ухода (StaffLife): стол, пол этажа и высота корня стоящего NPC
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	local height = (if humanoid then humanoid.HipHeight else 2) + (if root then root.Size.Y / 2 else 1)
	model:SetAttribute("DeskId", desk.id)
	model:SetAttribute("FloorY", floorY)
	model:SetAttribute("StandHeight", height)

	local chair = chairSeatTop(plot, desk)
	if chair then
		local seatLocal = plot.CFrame:PointToObjectSpace(chair)
		table.insert(used, Vector3.new(seatLocal.X, floorY, seatLocal.Z))
		poseSitting(model)
		local spot = Vector3.new(seatLocal.X, seatLocal.Y + SIT_ROOT_ABOVE_SEAT, seatLocal.Z)
		local facing = spot - rotation:VectorToWorldSpace(Vector3.new(0, 0, 1))
		local placement = CFrame.lookAt(spot, facing)
		model:SetAttribute("Chair", true)
		model:SetAttribute("SeatLocal", placement)
		model:PivotTo(plot.CFrame * placement)
		return
	end

	local seat = deskPoint + rotation:VectorToWorldSpace(Vector3.new(0, 0, SEAT_DISTANCE))
	for _, shift in SEAT_SIDE_SHIFTS do
		local candidate = deskPoint + rotation:VectorToWorldSpace(Vector3.new(shift, 0, SEAT_DISTANCE))
		local free = true
		for _, other in used do
			if (other - candidate).Magnitude < SEAT_MIN_GAP then
				free = false
				break
			end
		end
		if free then
			seat = candidate
			break
		end
	end
	table.insert(used, seat)

	-- Pivot R15 — HumanoidRootPart: поднимаем на высоту бёдер над полом (height выше).
	-- Смотрит на стол: стол «лицом» к +Z, значит NPC смотрит в -Z стола
	local facing = seat - rotation:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local placement = CFrame.lookAt(seat, facing) + Vector3.new(0, height, 0)
	model:SetAttribute("SeatLocal", placement)
	model:PivotTo(plot.CFrame * placement)
end

-- Пересадить всех NPC игрока (вход, найм, новый стол, переезд, смена внешности)
local rebuildNpcs: (player: Player) -> ()

-- Пересборка NPC дорогая (CreateHumanoidModelFromDescription уступает поток): одна за раз
-- на игрока, а запросы во время сборки склеиваются в одну следующую (против спама SetLook)
local npcBusy: { [Player]: boolean } = {}
local npcAgain: { [Player]: boolean } = {}

local function refreshNpcs(player: Player)
	if npcBusy[player] then
		npcAgain[player] = true
		return
	end
	npcBusy[player] = true
	repeat
		npcAgain[player] = false
		local ok, err = pcall(rebuildNpcs, player)
		if not ok then
			warn("[StaffService] NPC rebuild failed:", err)
		end
	until not npcAgain[player] or not player.Parent
	npcBusy[player] = nil
	npcAgain[player] = nil
end

rebuildNpcs = function(player: Player)
	-- Сборка NPC уступает поток; актуальна только последняя запущенная пересадка
	local generation = (refreshGeneration[player] or 0) + 1
	refreshGeneration[player] = generation
	local plot = PlotService.getPlot(player)
	local profile = DataService.get(player)
	if not plot or not profile then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Staff"

	local info = getInfo(profile)
	local skins = optionalService("SkinService")
	local byDesk: { [string]: string } = {}
	for employeeId, deskId in seated(profile) do
		byDesk[deskId] = employeeId
	end
	local used: { Vector3 } = {}
	for _, upgrade in Upgrades do
		local employeeId = byDesk[upgrade.id]
		local employee = employeeId and Employees.get(employeeId)
		if employeeId and employee then
			local look = if info[employeeId] then info[employeeId].look else defaultInfo(employee).look
			-- В скине головной убор из «Внешности» не надеваем: у скина свои аксессуары
			local skinned = skins ~= nil and skins.skinOf(profile, employeeId) ~= nil
			local npcLook = look
			if skinned then
				npcLook = table.clone(look)
				npcLook.hat = 1 -- "none"
			end
			local npc = buildNpc(employee, npcLook)
			if npc and skinned then
				skins.decorate(npc, employeeId, profile)
			end
			if npc then
				npc:SetAttribute("EmployeeId", employeeId)
				seatNpc(npc, plot, upgrade, used)
				local item = Skills.items[look.item] or "none"
				if item ~= "none" then
					local position = upgrade.position or Vector3.zero
					local top = plot.CFrame
						* CFrame.new(position.X, plot.Size.Y / 2 + position.Y - 0.5 + DESK_TOP, position.Z)
						* CFrame.Angles(0, math.rad(upgrade.rotation or 0), 0)
						* CFrame.new(DESK_ITEM_OFFSET)
					-- Отдельной моделью: на перерыв сотрудник уходит без кружки
					local itemModel = Instance.new("Model")
					itemModel.Name = "Item_" .. employeeId
					buildDeskItem(itemModel, item, top)
					itemModel.Parent = folder
				end
				npc.Parent = folder
			end
		end
	end
	-- Пока строили, игрок мог уйти или запустить новую пересадку
	if refreshGeneration[player] ~= generation or PlotService.getPlot(player) ~= plot then
		folder:Destroy()
		return
	end
	-- Перерывы старых NPC обрываем: новые сидят на местах
	local life = optionalService("StaffLife")
	if life then
		life.reset(player)
	end
	breaks[player] = nil
	local old = npcFolders[player]
	if old then
		old:Destroy()
	end
	folder.Parent = plot
	npcFolders[player] = folder
	sendPower(player)
	-- Новенькие: клиент празднует у стола (конфетти, «Привет, команда!»)
	local arrivals = pendingArrive[player]
	if arrivals then
		pendingArrive[player] = nil
		for employeeId in arrivals do
			local npc = folder:FindFirstChild("Staff_" .. employeeId)
			if npc then
				StaffRemotes.StaffFeel:FireClient(
					player,
					{ kind = "arrive", employeeId = employeeId, npc = npc }
				)
			end
		end
	end
end

-- Пересобрать NPC (SkinService: сменили скин сотрудника)
function StaffService.refreshNpcs(player: Player)
	task.spawn(refreshNpcs, player)
end

-- Рассадка поменялась (переезд, новый стол, найм): переслать, пересобрать NPC и кнопки
local function onTeamChanged(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	seatAll(profile)
	sendStaff(player)
	sendPower(player)
	-- Размер команды в снимке данных: условия открытия жанров (shared/UnlockRules)
	DataService.replicate(player)
	task.spawn(refreshNpcs, player)
	-- Все столы заняты — на участке может появиться кнопка переезда
	PlotService.refreshButtons(player)
end

-- Награда квеста открыла легендарного (RewardService.grant)
function StaffService.onRewardsChanged(player: Player)
	sendStaff(player)
end

local function throttled(player: Player): boolean
	local now = os.clock()
	if (lastAction[player] or 0) + ACTION_COOLDOWN > now then
		return true
	end
	lastAction[player] = now
	return false
end

local function onHire(player: Player, employeeId: any)
	if type(employeeId) ~= "string" or throttled(player) then
		return
	end
	local employee = Employees.get(employeeId)
	local profile = DataService.get(player)
	if not employee or not profile then
		return
	end
	-- Легендарные — только открытые (квест, геймпасс, исследование для robo)
	if employee.legendary and not legendUnlocked(player, profile, employee) then
		return
	end
	if profile.studioLevel < employee.stage then
		return
	end
	local staff = getStaff(profile)
	if staff[employee.id] then
		return
	end
	-- Сначала сажаем ждущих: новый сотрудник не должен оказаться без стола после оплаты
	seatAll(profile)
	local taken: { [string]: boolean } = {}
	for _, deskId in staff do
		taken[deskId] = true
	end
	local hasSeat = false
	local anyDesk = false
	for _, desk in StudioLayout.visibleDesks(profile.upgrades, profile.studioLevel) do
		if StudioLayout.canSit(employee.stage, desk) then
			anyDesk = true
			hasSeat = hasSeat or not taken[desk.id]
		end
	end
	-- Легендарному место освободит самый слабый обычный сотрудник (seatAll)
	if not hasSeat and not (employee.legendary and anyDesk) then
		return
	end
	if not DataService.trySpend(player, hireCost(player, employee)) then
		return
	end
	local before = StaffService.power(player)
	staff[employee.id] = ""
	getInfo(profile)
	local arrivals = pendingArrive[player] or {}
	arrivals[employee.id] = true
	pendingArrive[player] = arrivals
	onTeamChanged(player)
	-- Новичок в команде: временно +настроение (Config/Mood.newcomer)
	local MoodService = optionalService("MoodService")
	if MoodService then
		pcall(
			MoodService.addTemporary,
			player,
			"mood_part_newbie",
			Mood.newcomer.value,
			Mood.newcomer.seconds
		)
	end
	StaffRemotes.StaffFeel:FireClient(player, {
		kind = "hire",
		employeeId = employee.id,
		before = before,
		after = StaffService.power(player),
		mood = if MoodService then Mood.newcomer.value else 0,
	})
	-- Задания «найми сотрудника»
	local QuestService = optionalService("QuestService")
	if QuestService then
		local count = 0
		for _ in staff do
			count += 1
		end
		QuestService.onEmployeesChanged(player, count)
	end
end

-- Уволить: навыки и перки пропадают, освободившийся стол займёт ждущий (seatAll).
-- Во время забастовки тоже можно — это способ уменьшить зарплаты.
-- withRefund = false — сотрудник ушёл сам (переманили, события компании): без возврата
local function fireEmployee(player: Player, employeeId: string, withRefund: boolean): boolean
	local employee = Employees.get(employeeId)
	local profile = DataService.get(player)
	if not employee or not profile then
		return false
	end
	local staff = getStaff(profile)
	if staff[employee.id] == nil then
		return false
	end
	local before = StaffService.power(player)
	-- NPC не исчезает: встаёт, берёт коробку и уходит к выходу (StaffLife), пересборка его не тронет
	local life = optionalService("StaffLife")
	local folder = npcFolders[player]
	local npc = folder and folder:FindFirstChild("Staff_" .. employee.id)
	local plot = PlotService.getPlot(player)
	if life and npc and npc:IsA("Model") and plot then
		pcall(life.leave, player, npc, plot)
	end
	if breaks[player] then
		breaks[player][employee.id] = nil
	end
	if pendingArrive[player] then
		pendingArrive[player][employee.id] = nil
	end
	staff[employee.id] = nil
	-- getInfo чистит staffInfo уволенных: при повторном найме навыки начнутся с нуля
	getInfo(profile)
	local skins = optionalService("SkinService")
	if skins then
		skins.forget(player, profile, employee.id)
	end
	local refund = if withRefund then Employees.refundFor(employee) else 0
	if refund > 0 then
		DataService.addCash(player, refund)
		-- Возврат за увольнение — не «заработок» для заданий
		local reward = script.Parent:FindFirstChild("RewardService")
		if reward and reward:IsA("ModuleScript") then
			pcall((require(reward) :: any).noteNonEarned, player, refund)
		end
	end
	-- Пересадка, StaffChanged, NPC и кнопка переезда — как при найме.
	-- QuestService не зовём: счётчик заданий «найми» хранит максимум и не уменьшается
	onTeamChanged(player)
	-- Коллегу уволили: временно −настроение оставшимся (Config/Mood.fired; без команды — ничего)
	local MoodService = optionalService("MoodService")
	local hasTeam = next(staff) ~= nil
	if MoodService and hasTeam then
		pcall(MoodService.addTemporary, player, "mood_part_fired", Mood.fired.value, Mood.fired.seconds)
	end
	StaffRemotes.StaffFeel:FireClient(player, {
		kind = "fire",
		employeeId = employee.id,
		before = before,
		after = StaffService.power(player),
		refund = refund,
		mood = if MoodService and hasTeam then Mood.fired.value else 0,
	})
	return true
end

local function onFire(player: Player, employeeId: any)
	if type(employeeId) ~= "string" or throttled(player) then
		return
	end
	fireEmployee(player, employeeId, true)
end

-- Сотрудник уходит сам (события компании: переманил конкурент) — без возврата денег
function StaffService.dismiss(player: Player, employeeId: string): boolean
	return fireEmployee(player, employeeId, false)
end

-- Бесплатный уровень навыка случайному сотруднику (события компании: конференция).
-- Сначала его специализация, иначе любой не максимальный навык. nil — учить некого
function StaffService.grantFreeSkill(player: Player): { employeeId: string, key: string }?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local info = getInfo(profile)
	local options: { { employeeId: string, key: string } } = {}
	for employeeId in getStaff(profile) do
		local employee = Employees.get(employeeId)
		local employeeInfo = info[employeeId]
		if employee and employeeInfo then
			local spec = employee.specialization
			if spec and (employeeInfo.skills[spec] or 0) < Skills.maxLevel then
				table.insert(options, { employeeId = employeeId, key = spec })
			else
				for _, key in Skills.keys do
					if (employeeInfo.skills[key] or 0) < Skills.maxLevel then
						table.insert(options, { employeeId = employeeId, key = key })
						break
					end
				end
			end
		end
	end
	if #options == 0 then
		return nil
	end
	local choice = options[math.random(1, #options)]
	local before = StaffService.power(player)
	local level = info[choice.employeeId].skills[choice.key] or 0
	info[choice.employeeId].skills[choice.key] = level + 1
	sendStaff(player)
	sendPower(player)
	local folder = npcFolders[player]
	StaffRemotes.StaffFeel:FireClient(player, {
		kind = "skill",
		employeeId = choice.employeeId,
		key = choice.key,
		from = level,
		to = level + 1,
		before = before,
		after = StaffService.power(player),
		npc = folder and folder:FindFirstChild("Staff_" .. choice.employeeId),
	})
	return choice
end

-- Переслать клиенту команду и мощность (события компании: прибавка, сломанный стол, уход команды)
function StaffService.refreshStaff(player: Player)
	sendStaff(player)
	sendPower(player)
end

function StaffService.refreshPower(player: Player)
	sendPower(player)
end

-- Игрок закрыл подсказку о забастовке: больше не показывать
local function onStrikeTipSeen(player: Player)
	-- Свой простой фильтр: общий throttled() отбрасывал «Понятно» сразу после найма/увольнения
	if player:GetAttribute("StrikeTipSeen") == true then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	profile.strikeTipSeen = true
	player:SetAttribute("StrikeTipSeen", true)
end

-- «+1» к навыку за деньги
local function onUpgradeSkill(player: Player, employeeId: any, key: any)
	if type(employeeId) ~= "string" or not Skills.isKey(key) or throttled(player) then
		return
	end
	local profile = DataService.get(player)
	local employee = Employees.get(employeeId)
	if not profile or not employee or getStaff(profile)[employeeId] == nil then
		return
	end
	local info = getInfo(profile)[employeeId]
	local level = info.skills[key]
	if level >= Skills.maxLevel then
		return
	end
	if DataService.trySpend(player, Skills.skillCost(employee.stage, employee.legendary, level)) then
		local before = StaffService.power(player)
		info.skills[key] = level + 1
		sendStaff(player)
		sendPower(player)
		-- «Было → стало» и эффект над NPC (клиент: «+1 🎨», вспышка)
		local folder = npcFolders[player]
		StaffRemotes.StaffFeel:FireClient(player, {
			kind = "skill",
			employeeId = employeeId,
			key = key,
			from = level,
			to = level + 1,
			before = before,
			after = StaffService.power(player),
			npc = folder and folder:FindFirstChild("Staff_" .. employeeId),
		})
	end
end

-- Поставить перк в слот: в пустой — бесплатно, сменить — за деньги и не чаще perkCooldown
local function onSetPerk(player: Player, employeeId: any, slot: any, perkId: any)
	if type(employeeId) ~= "string" or type(perkId) ~= "string" or throttled(player) then
		return
	end
	local profile = DataService.get(player)
	local employee = Employees.get(employeeId)
	local perk = Skills.perk(perkId)
	if not profile or not employee or not perk or getStaff(profile)[employeeId] == nil then
		return
	end
	if not isInteger(slot, 1, Skills.slots(employee.legendary)) then
		return
	end
	local info = getInfo(profile)[employeeId]
	if employeeLevel(info) < perk.minLevel or table.find(info.perks, perkId) then
		return
	end
	local current = info.perks[slot]
	if current ~= "" then
		local now = os.time()
		if now - info.perkChangedAt < Skills.perkCooldown then
			return
		end
		if not DataService.trySpend(player, Skills.perkChangeCost(employee.stage, employee.legendary)) then
			return
		end
		info.perkChangedAt = now
	end
	info.perks[slot] = perkId
	sendStaff(player)
	sendPower(player)
end

-- Внешность: бесплатно, только индексы из Config/Skills
local LOOK_COOLDOWN = 1 -- смена внешности перестраивает NPC: не чаще раза в секунду
local lastLook: { [Player]: number } = {}

local function onSetLook(player: Player, employeeId: any, field: any, index: any)
	if type(employeeId) ~= "string" or type(field) ~= "string" or throttled(player) then
		return
	end
	local now = os.clock()
	if (lastLook[player] or 0) + LOOK_COOLDOWN > now then
		return
	end
	lastLook[player] = now
	local limits = LOOK_LIMITS[field]
	local profile = DataService.get(player)
	if not limits or not profile or not isInteger(index, limits.min, limits.max) then
		return
	end
	if getStaff(profile)[employeeId] == nil then
		return
	end
	local info = getInfo(profile)[employeeId];
	(info.look :: any)[field] = index
	sendStaff(player)
	task.spawn(refreshNpcs, player)
end

function StaffService.start()
	StaffRemotes.HireEmployee.OnServerEvent:Connect(onHire)
	StaffRemotes.FireEmployee.OnServerEvent:Connect(onFire)
	StaffRemotes.StrikeTipSeen.OnServerEvent:Connect(onStrikeTipSeen)
	StaffRemotes.UpgradeSkill.OnServerEvent:Connect(onUpgradeSkill)
	StaffRemotes.SetPerk.OnServerEvent:Connect(onSetPerk)
	StaffRemotes.SetLook.OnServerEvent:Connect(onSetLook)
	PlotService.plotChanged:Connect(onTeamChanged)
	-- Купили «Мастера Пикселя»: ShopService перепроверяет покупку асинхронно — перешлём чуть позже
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, _: number, bought: boolean)
			if bought then
				task.delay(PASS_RECHECK, function()
					if player.Parent then
						sendStaff(player)
					end
				end)
			end
		end
	)
	Players.PlayerAdded:Connect(function(player)
		task.delay(JOIN_RECHECK, function()
			if player.Parent then
				sendStaff(player)
				sendPower(player)
			end
		end)
	end)
	-- Видел ли подсказку о забастовке: клиент ждёт этот атрибут, прежде чем её показать
	DataService.onProfileLoaded(function(player, profile)
		player:SetAttribute("StrikeTipSeen", profile.strikeTipSeen == true)
	end)
	-- Настроение меняет скорость (и забастовка тоже идёт через него): переслать мощность
	local MoodService = optionalService("MoodService")
	if MoodService and MoodService.changed then
		MoodService.changed:Connect(function(player: Player)
			if player.Parent then
				sendPower(player)
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		local folder = npcFolders[player]
		if folder then
			folder:Destroy()
		end
		npcFolders[player] = nil
		breaks[player] = nil
		pendingArrive[player] = nil
		refreshGeneration[player] = nil
		lastAction[player] = nil
		lastLook[player] = nil
	end)
end

return StaffService
