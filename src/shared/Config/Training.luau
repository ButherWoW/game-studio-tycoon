--!strict
-- Обучение навыку (StaffService, окно «Команда», StaffTraining на клиенте).
-- «+1» к навыку больше не мгновенный: деньги списываются сразу (как раньше, со скидкой ученику
-- наставника), а уровень растёт, когда закончится обучение. Время — по уровню, до которого учим,
-- × множитель этапа сотрудника (на поздних этажах навыки дороже — и учатся дольше).
-- Время — по os.time() в профиле: обучение идёт и офлайн, после входа доучивается сразу.
-- Один сотрудник учит один навык за раз; разные сотрудники учатся параллельно.
-- Пока учится, сотрудник сидит за столом и работает медленнее (workSpeed).
-- Ученик наставника (Config/Mentoring) учится быстрее (menteeSpeed) — вдобавок к скидке на цену;
-- ускорение берётся в момент старта: если пару разорвали посреди обучения, время не меняется.
-- Увольнение посреди обучения отменяет его без возврата (навыки уволенного и так пропадают).
--
-- Почему такие числа: разработка игры ~45 с (Economy.devSeconds), «+1» стоит как несколько игр.
-- 30 с — 3 мин на первом этаже = 1–5 игр: видно полоску и ждать недолго; весь сотрудник 0 → 5
-- (15 уровней по 4 навыкам, обычно ~13) учится ~25 мин, и это параллельно с работой. Максимум —
-- 5-й уровень на 4-м этапе: 3 мин × 2 = 6 мин.

local Universe = require(script.Parent.Universe)
local Skills = require(script.Parent.Skills)

local Training = {}

-- Секунд обучения до уровня (индекс — уровень после обучения, 1..Skills.maxLevel)
Training.seconds = { 30, 60, 90, 120, 180 } :: { number }
-- Множитель времени по этапу сотрудника (как Skills.costBase; легендарные — Skills.legendaryCostStage)
Training.stageFactor = { 1, 1.25, 1.5, 2 } :: { number }
Training.menteeSpeed = 1.5 -- ученик наставника учится в 1.5 раза быстрее
Training.workSpeed = 0.7 -- стол учащегося даёт 70% очков (−30%)
Training.minSeconds = 5

-- «Доучить сейчас» (один сотрудник) и «Доучить всех» за Robux — Developer Products (#11).
-- Если к приходу чека учить нечего (обучение успело закончиться), покупка становится жетоном:
-- skip — 1 жетон, skipAll — skipAllCredits жетонов. Жетон доучивает любого сотрудника кнопкой.
Training.products = {
	skillSkip = { productId = Universe.pick({ test = 0, main = 0 }), robuxPrice = 19 },
	skillSkipAll = { productId = Universe.pick({ test = 0, main = 0 }), robuxPrice = 49 },
}
Training.skipAllCredits = 3
Training.maxCredits = 99

-- Длительность обучения до уровня toLevel (stage — этап для цены, см. Skills.skillCost)
function Training.duration(stage: number, legendary: boolean?, toLevel: number, mentored: boolean): number
	local s = if legendary then Skills.legendaryCostStage else stage
	local factor = Training.stageFactor[math.clamp(math.floor(s), 1, #Training.stageFactor)]
	local base = Training.seconds[math.clamp(math.floor(toLevel), 1, #Training.seconds)]
	local seconds = base * factor / (if mentored then Training.menteeSpeed else 1)
	return math.max(math.floor(seconds + 0.5), Training.minSeconds)
end

return Training
