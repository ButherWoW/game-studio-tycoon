--!strict
-- Долг и приставы (BailiffService). Аренда и зарплата (ExpensesService) списываются всегда, даже
-- если денег нет: баланс уходит в минус, но не ниже −limitFor(этап) (овердрафт). Минус — это долг:
-- пока cash < 0, команда бастует, офис «разваливается» (мигает свет, трещины и пыль на полу),
-- настроение −moodPenalty, любой доход сначала гасит минус (кредит банка — только из того, что
-- осталось сверх нуля). Упёрлись в лимит — приходят приставы: раз в seizeSeconds забирают один
-- предмет и продают за sellShare цены покупки, пока баланс не вернётся к ≥ 0.
-- Забирают: декор (окно «Студия»), потом интерьер с конца цепочки requires (то, что не нужно ни
-- одному купленному предмету). Никогда: protected (стол и ПК игрока, стены гаража — без них не
-- сделать игру), переезды/этажи (move), спрятанное старым этапом, Robux-покупки (постеры, скины).
-- Офлайн расходов нет — и приставов тоже. Баланс — docs/BALANCE.md («Долг и приставы»).

local Bailiffs = {}

-- Лимит минуса по этапу студии: гараж, 1-й, 2-й, 3-й этаж офиса. Пока у всех 10 000 (решение
-- владельца); на 3-м этаже аренда $8k/мин — лимит наступает примерно за минуту
Bailiffs.overdraftLimits = { 10_000, 10_000, 10_000, 30_000 }

-- Пристав продаёт предмет за такую долю того, что за него заплатили
Bailiffs.sellShare = 0.25
-- Раз в сколько секунд забирают следующий предмет (NPC идёт к предмету ~3 с)
Bailiffs.seizeSeconds = 8
-- Новичок: первые столько секунд с первого входа (profile.offers.firstJoin) приставов нет
Bailiffs.newPlayerSeconds = 15 * 60
-- После входа в игру — столько секунд на то, чтобы увидеть предупреждение и что-то сделать
Bailiffs.joinGraceSeconds = 30
-- Минус к цели настроения, пока баланс в минусе (строка «Долг: приставы» в разборе настроения)
Bailiffs.moodPenalty = 10

-- Предметы, которые не забирают никогда (без них не сделать игру / оболочка этапа)
Bailiffs.protected = { desk1 = true, pc1 = true, walls = true } :: { [string]: boolean }

-- «Офис разваливается»: трещин и пыли на полу верхнего этажа, как часто мигает свет и насколько
-- тускнеет (доля обычной яркости)
Bailiffs.cracks = 7
Bailiffs.dustClouds = 2
Bailiffs.flickerSeconds = 0.4
Bailiffs.dimFactor = 0.45

function Bailiffs.limitFor(studioLevel: number): number
	local limits = Bailiffs.overdraftLimits
	return limits[math.clamp(math.floor(tonumber(studioLevel) or 1), 1, #limits)] or limits[1]
end

-- Самый большой лимит: до него DataService пропускает минус из сохранения
function Bailiffs.maxLimit(): number
	local best = 0
	for _, limit in Bailiffs.overdraftLimits do
		best = math.max(best, limit)
	end
	return best
end

-- Сколько пристав выручит за предмет, купленный за cost
function Bailiffs.saleFor(cost: number): number
	return math.max(math.floor(cost * Bailiffs.sellShare), 0)
end

return Bailiffs
