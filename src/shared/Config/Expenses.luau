--!strict
-- Расходы студии: зарплаты команды (раз в paydaySeconds) и аренда помещения (каждые tickSeconds).
-- Чем сильнее сотрудник (multiplier) и чем выше прокачаны навыки — тем дороже он стоит в минуту.
-- Денег не хватает — команда бастует (без бонусов сотрудников), долг не копится.

local Employees = require(script.Parent.Employees)
local Skills = require(script.Parent.Skills)

local Expenses = {}

-- Как часто списывать (деньги считаются в $/мин, списываются долями)
Expenses.tickSeconds = 10
-- Зарплата команде — раз в paydaySeconds одной суммой (аренда — долями каждые tickSeconds).
-- Чем больше вкачано навыков, тем больше сумма (salaryPerSkill)
Expenses.paydaySeconds = 300
-- За сколько секунд до зарплаты предупредить, если денег не хватает
Expenses.paydayWarnSeconds = 30
-- Зарплата в минуту = salaryBase × multiplier² (Мила ×1.5 — $45, Вера ×3 — $180, РОБО ×4 — $480)
Expenses.salaryBase = 20
-- +15% к зарплате за каждый уровень навыка, вкачанный сверх стартового: прокачал — дороже платишь
Expenses.salaryPerSkill = 0.15
-- Легендарные дороже обычных с тем же множителем
Expenses.legendaryFactor = 1.5
-- Аренда в минуту по этапу студии: гараж свой, 1-й, 2-й, 3-й этаж офиса.
-- Баланс после гаража (docs/BALANCE.md): расходы ~4% дохода в офисе, ~10% на 2-м этаже,
-- ~18% на 3-м — заметны, но активный игрок всегда в плюсе (не хватит — забастовка, кредит)
Expenses.rent = { 0, 500, 3_000, 8_000 }

function Expenses.salary(employee: Employees.Employee, skills: { [string]: number }?): number
	local start = Skills.start(employee.specialization, employee.legendary)
	local extra = 0
	if skills then
		for _, key in Skills.keys do
			extra += math.max((tonumber(skills[key]) or 0) - (start[key] or 0), 0)
		end
	end
	local pay = Expenses.salaryBase * employee.multiplier ^ 2 * (1 + Expenses.salaryPerSkill * extra)
	if employee.legendary then
		pay *= Expenses.legendaryFactor
	end
	return math.floor(pay)
end

function Expenses.rentFor(studioLevel: number): number
	return Expenses.rent[math.clamp(studioLevel, 1, #Expenses.rent)] or 0
end

return Expenses
