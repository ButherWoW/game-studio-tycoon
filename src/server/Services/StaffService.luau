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
local Expenses = require(ReplicatedStorage.Shared.Config.Expenses)
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
	skin = { min = 1, max = #Skills.skins },
	hat = { min = 1, max = #Skills.hats },
	item = { min = 1, max = #Skills.items },
}

local StaffService = {}
local npcFolders: { [Player]: Folder } = {}
local refreshGeneration: { [Player]: number } = {}
local lastAction: { [Player]: number } = {}

local function optionalService(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		return require(module) :: any
	end
	return nil
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
		look = { shirt = 0, skin = 1, hat = 1, item = 1 },
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

-- Кто сейчас работает: за столами и не бастует (ExpensesService ставит staffStrike, когда нечем платить)
local function working(profile: DataService.Profile): { [string]: string }
	if (profile :: any).staffStrike == true then
		return {}
	end
	return seated(profile)
end

-- Зарплаты всех нанятых в минуту (Config/Expenses): платим и тем, кто ждёт стол
function StaffService.salaryPerMinute(profile: DataService.Profile): number
	local info = getInfo(profile)
	local total = 0
	for employeeId in getStaff(profile) do
		local employee = Employees.get(employeeId)
		if employee then
			local employeeInfo = info[employeeId]
			total += Expenses.salary(employee, if employeeInfo then employeeInfo.skills else nil)
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
	for employeeId, deskId in working(profile) do
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
	for employeeId, seatId in working(profile) do
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
	for employeeId in working(profile) do
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

-- Прибавка к оценке каждой игры от команды за столами: легендарный «Мастер Пиксель» (+1)
-- и перк «Перфекционист». Прибавлять к bonus в Formulas.review
function StaffService.reviewBonus(player: Player): number
	local profile = DataService.get(player)
	if not profile then
		return 0
	end
	local info = getInfo(profile)
	local total = 0
	local perkBonus = 0
	for employeeId in working(profile) do
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
	return total + math.min(perkBonus, Skills.caps.reviewBonus)
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
	StaffRemotes.StaffChanged:FireClient(player, staff, {
		info = getInfo(profile),
		unlocked = unlocked,
		now = os.time(),
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
	local skin = Skills.skins[look.skin] or Skills.skins[1]
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = shirt
	description.LeftLegColor = PANTS
	description.RightLegColor = PANTS
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn("[StaffService] NPC build failed:", result)
		return nil
	end
	local model = result :: Model
	model.Name = "Staff_" .. employee.id
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

-- Поставить NPC перед столом лицом к нему. used — уже занятые точки (в координатах участка).
local function seatNpc(model: Model, plot: BasePart, desk: Upgrades.Upgrade, used: { Vector3 })
	local position = desk.position or Vector3.zero
	local floorY = plot.Size.Y / 2
	local rotation = CFrame.Angles(0, math.rad(desk.rotation or 0), 0)
	local deskPoint = Vector3.new(position.X, floorY, position.Z)

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

	-- Pivot R15 — HumanoidRootPart: поднимаем на высоту бёдер над полом
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	local height = (if humanoid then humanoid.HipHeight else 2) + (if root then root.Size.Y / 2 else 1)
	-- Смотрит на стол: стол «лицом» к +Z, значит NPC смотрит в -Z стола
	local facing = seat - rotation:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local placement = CFrame.lookAt(seat, facing) + Vector3.new(0, height, 0)
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
			local npc = buildNpc(employee, look)
			if npc then
				seatNpc(npc, plot, upgrade, used)
				local item = Skills.items[look.item] or "none"
				if item ~= "none" then
					local position = upgrade.position or Vector3.zero
					local top = plot.CFrame
						* CFrame.new(position.X, plot.Size.Y / 2 + DESK_TOP, position.Z)
						* CFrame.Angles(0, math.rad(upgrade.rotation or 0), 0)
						* CFrame.new(DESK_ITEM_OFFSET)
					buildDeskItem(npc, item, top)
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
	local old = npcFolders[player]
	if old then
		old:Destroy()
	end
	folder.Parent = plot
	npcFolders[player] = folder
end

-- Рассадка поменялась (переезд, новый стол, найм): переслать, пересобрать NPC и кнопки
local function onTeamChanged(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	seatAll(profile)
	sendStaff(player)
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
	if not DataService.trySpend(player, employee.cost) then
		return
	end
	staff[employee.id] = ""
	getInfo(profile)
	onTeamChanged(player)
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
-- Во время забастовки тоже можно — это способ уменьшить зарплаты
local function onFire(player: Player, employeeId: any)
	if type(employeeId) ~= "string" or throttled(player) then
		return
	end
	local employee = Employees.get(employeeId)
	local profile = DataService.get(player)
	if not employee or not profile then
		return
	end
	local staff = getStaff(profile)
	if staff[employee.id] == nil then
		return
	end
	staff[employee.id] = nil
	-- getInfo чистит staffInfo уволенных: при повторном найме навыки начнутся с нуля
	getInfo(profile)
	local refund = Employees.refundFor(employee)
	if refund > 0 then
		DataService.addCash(player, refund)
	end
	-- Пересадка, StaffChanged, NPC и кнопка переезда — как при найме.
	-- QuestService не зовём: счётчик заданий «найми» хранит максимум и не уменьшается
	onTeamChanged(player)
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
		info.skills[key] = level + 1
		sendStaff(player)
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
			end
		end)
	end)
	-- Видел ли подсказку о забастовке: клиент ждёт этот атрибут, прежде чем её показать
	DataService.onProfileLoaded(function(player, profile)
		player:SetAttribute("StrikeTipSeen", profile.strikeTipSeen == true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local folder = npcFolders[player]
		if folder then
			folder:Destroy()
		end
		npcFolders[player] = nil
		refreshGeneration[player] = nil
		lastAction[player] = nil
	end)
end

return StaffService
