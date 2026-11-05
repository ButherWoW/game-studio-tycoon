--!strict
-- Быстрые события (QTE) во время разработки: нажать в нужный момент. Результат
-- «Отлично / Хорошо / Мимо» сдвигает оценку игры (до округления, как бонусы студии).
-- Решает сервер (DevelopmentService): он задаёт параметры и время старта, клиент
-- (QuickEventPopup) присылает только моменты нажатий. Функции ниже общие для сервера и клиента,
-- чтобы метка на экране и проверка на сервере считались одинаково.
-- Тексты: qte_* в Texts и Locales.

export type Kind = "timing" | "rhythm" | "sequence" | "hold"
export type Grade = "perfect" | "good" | "miss" | "ignored"

local QuickEvents = {
	kinds = { "timing", "rhythm", "sequence", "hold" } :: { Kind },

	-- Прибавка к оценке за результат; «ignored» — не нажал вообще (AFK не наказываем сильно).
	-- 05.11 событий стало 2–4 за игру (было 1–3): было 0.4 / 0.15 / −0.3 / −0.1 — средняя
	-- сумма за игру осталась ~+0.3 и реже упирается в предел ±1
	effect = { perfect = 0.3, good = 0.1, miss = -0.25, ignored = -0.08 } :: { [Grade]: number },
	-- Сумма всех быстрых событий одной игры — не больше по модулю
	totalMin = -1,
	totalMax = 1,

	-- Сколько событий за игру: по длительности разработки (секунды). Отзыв владельца 05.11:
	-- «больше быстрых событий с самого начала» — минимум 2, даже на ноутбуке в парке
	countFor = function(duration: number): number
		if duration < 35 then
			return 2
		elseif duration < 60 then
			return 3
		end
		return 4
	end,
	-- Не меньше стольких секунд между стартами событий (быстрых и с выбором). Короткой игре
	-- (кофе, «Быстрая разработка») событий достанется меньше — сколько поместится
	minGap = 6,
	-- Окно, в которое ставятся события: доли длительности разработки
	windowFrom = 0.15,
	windowTo = 0.8,
	-- Не начинать событие, если до релиза меньше (секунд разработки)
	roomSeconds = 7,
	-- После стольких пропущенных подряд событий игрок считается AFK: дальше без событий,
	-- пока снова не нажмёт что-нибудь (событие с выбором, «Создать игру»)
	afkAfter = 2,

	-- Пауза «приготовься» перед стартом: нажатия раньше не считаются
	leadIn = 0.9,
	-- Если игрок ничего не нажал, событие закрывается через столько секунд после leadIn
	timeoutSeconds = 5,

	-- Защита: время нажатия считает сервер — «получено − пинг/2». Время клиента лишь уточняет его
	-- в пределах [оценка − maxBackdate, получено]: подделкой метки нажатие «в прошлое» не сдвинуть
	-- дальше maxBackdate (раньше окно было пинг + latencyTolerance ≈ 0.85 с — шире окна «Отлично»)
	maxBackdate = 0.1,
	-- Запас на задержку сети в концах событий (удержание, просрочка)
	latencyTolerance = 0.25,
	maxPing = 0.6, -- пинг выше этого считаем этим (иначе лаг-свитч растягивает окно)
	minInputGap = 0.04, -- секунд между нажатиями одного игрока; чаще — отбрасываем
	maxInputs = 12, -- нажатий на одно событие; больше — отбрасываем

	-- (a) Полоса: метка ходит туда-обратно за period секунд, жать в зелёной зоне
	timing = {
		period = 1.8,
		zoneMin = 0.25, -- центр зоны — случайно в этих долях полосы
		zoneMax = 0.75,
	},
	-- Ширина зелёной зоны (доля полосы/шкалы) по уровню студии: уже на старших этапах
	zoneWidthBase = 0.2,
	zoneWidthPerLevel = 0.03,
	zoneWidthMin = 0.1,
	-- «Отлично» — во внутренней части зоны (доля ширины)
	perfectShare = 0.45,

	-- (b) Ритм: beats ударов через interval, жать на каждый
	rhythm = {
		beats = 3,
		interval = 0.8,
		perfectWindow = 0.09, -- секунд от удара
		goodWindow = 0.2,
	},

	-- (c) Комбо: последовательность стрелок показывается showSeconds, потом её надо повторить
	sequence = {
		length = 4,
		showSeconds = 1.5,
		perfectSeconds = 3.5, -- уложился во столько после показа — «Отлично», иначе «Хорошо»
	},
	directions = { "up", "down", "left", "right" },

	-- (d) Зарядка: держать, шкала заполняется за fillSeconds; отпустить в зелёной зоне
	hold = {
		fillSeconds = 1.6,
		zoneMin = 0.55,
		zoneMax = 0.85,
	},
}

-- Ширина зелёной зоны на этапе студии studioLevel (1 — гараж … 4 — небоскрёб)
function QuickEvents.zoneWidth(studioLevel: number): number
	local level = math.max(math.floor(studioLevel), 1)
	return math.max(
		QuickEvents.zoneWidthBase - QuickEvents.zoneWidthPerLevel * (level - 1),
		QuickEvents.zoneWidthMin
	)
end

-- Положение метки полосы (0..1) через t секунд после leadIn: «пила» туда-обратно со сдвигом phase
function QuickEvents.sweep(t: number, period: number, phase: number): number
	local x = (math.max(t, 0) / period + phase) % 1
	return if x < 0.5 then x * 2 else 2 - x * 2
end

-- Доля «Отлично» внутри зоны с учётом маскота (scale 1.1 = +10%), не шире самой зоны
function QuickEvents.perfectShareFor(scale: number?): number
	return math.min(QuickEvents.perfectShare * (scale or 1), 1)
end

-- Оценка попадания value в зону [center ± width/2]; perfectScale — маскот «Отлично»
function QuickEvents.zoneGrade(value: number, center: number, width: number, perfectScale: number?): Grade
	local distance = math.abs(value - center)
	if distance <= width * QuickEvents.perfectShareFor(perfectScale) / 2 then
		return "perfect"
	elseif distance <= width / 2 then
		return "good"
	end
	return "miss"
end

return QuickEvents
