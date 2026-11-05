--!strict
-- Наставничество сотрудников (роадмап 7.21; StaffService, окно «Команда»).
-- Опытный сотрудник (уровень = сумма навыков ≥ minMentorLevel) берёт одного ученика с уровнем
-- ниже своего. Ученик качает навыки в menteeSkillGain раз быстрее: опыта как отдельной шкалы
-- в игре нет, навык покупается за деньги — поэтому «×2 опыта» = «+1» к навыку ученика стоит
-- в menteeSkillGain раз дешевле. Наставник, пока учит, работает медленнее: очки его стола × mentorSpeed.
-- Пара заканчивается сама, когда ученик догнал наставника по уровню или кто-то из них уволен.
-- Данные: profile.mentoring = { [mentorId]: menteeId } (проверяет StaffService).

local Mentoring = {
	minMentorLevel = 5, -- уровень сотрудника (сумма навыков), с которого он может наставлять
	menteeSkillGain = 2, -- ×2 опыта ученику: «+1» к навыку за 1/2 цены
	mentorSpeed = 0.8, -- стол наставника даёт 80% очков (−20%)
}

function Mentoring.canMentor(level: number): boolean
	return level >= Mentoring.minMentorLevel
end

-- Может ли сотрудник уровня menteeLevel учиться у наставника уровня mentorLevel
function Mentoring.isJunior(menteeLevel: number, mentorLevel: number): boolean
	return menteeLevel < mentorLevel
end

-- Цена «+1» к навыку с учётом наставника (baseCost — Skills.skillCost)
function Mentoring.skillCost(baseCost: number, mentored: boolean): number
	if not mentored then
		return baseCost
	end
	return math.max(math.floor(baseCost / Mentoring.menteeSkillGain), 1)
end

return Mentoring
