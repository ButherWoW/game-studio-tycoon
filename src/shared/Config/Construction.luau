--!strict
-- Стройка следующего этапа (V29). Покупка офиса или этажа больше не переносит студию сразу:
-- деньги списываются, на участке ставится стройплощадка (забор, леса, кран, стройматериалы,
-- табличка с прогрессом) и прибегают строители, а переезд случается, когда время вышло.
-- Владелец: «пусть делает офис 10 минут, а не появляется сразу». Этажи — наше предложение.
-- Время — по os.time() в профиле (construction.endsAt): стройка идёт и офлайн; закончилась, пока
-- игрока не было, — переезд при следующем входе (с обычным праздником MoveCelebration).
-- Пока идёт стройка, студия работает на текущем этапе: разработка, сотрудники, доход как обычно.

local Universe = require(script.Parent.Universe)

export type SpeedKind = "minutes" | "skip"

export type Speedup = {
	id: string,
	kind: SpeedKind,
	minutes: number?, -- только для kind = "minutes"
	-- Показывать, только если до конца стройки осталось больше стольких секунд (−30 мин на
	-- 7-минутном остатке — пустая трата)
	minLeftSeconds: number?,
	icon: string,
	productId: number,
	robuxPrice: number, -- ПРЕДЛОЖЕНИЕ, только для показа; финальную цену решает владелец
}

local Construction = {
	-- Длительность стройки по номеру этапа (Config/Stages.level), секунд
	durations = {
		[2] = 600, -- офис: 10 минут (просьба владельца)
		[3] = 900, -- 2-й этаж: 15 минут (предложение)
		[4] = 1200, -- 3-й этаж: 20 минут (предложение)
	} :: { [number]: number },
	-- Подтверждение покупки переезда (золотая кнопка): удержание подсказки, секунд, и дистанция, studs
	confirmHoldSeconds = 1,
	confirmDistance = 10,
	-- Сколько строителей прибегает на площадку
	builders = 4,
	-- Скорость строителей, studs/с: прибегают бегом, на площадке ходят шагом
	runSpeed = 16,
	walkSpeed = 7,
	-- Сколько секунд строитель стучит молотком / ждёт между делами
	hammerSeconds = { 3, 7 },
	-- Ускорения за Robux (Developer Products; 0 = ещё не создан — в окне «Скоро»).
	-- Квитанция пришла, а стройки нет: Robux не теряются — доход по цене товара (fallbackMinutesPerRobux)
	speedups = {
		{
			id = "buildSpeed5",
			kind = "minutes",
			minutes = 5,
			icon = "⏩",
			productId = Universe.pick({ test = 3728500645, main = 3728500862 }),
			robuxPrice = 15,
		},
		{
			id = "buildSpeed30",
			kind = "minutes",
			minutes = 30,
			minLeftSeconds = 5 * 60,
			icon = "⏭️",
			productId = Universe.pick({ test = 3728500661, main = 3728500873 }),
			robuxPrice = 49,
		},
		{
			id = "buildSkip",
			kind = "skip",
			icon = "⚡",
			productId = Universe.pick({ test = 3728500681, main = 3728500885 }),
			robuxPrice = 79,
		},
	} :: { Speedup },
	-- Запасной доход: столько минут за 1 R$ цены — как у пакета «10 минут дохода» (49 R$), иначе
	-- −5 мин без стройки стал бы дешёвым пакетом денег (аудит 05.11)
	fallbackMinutesPerRobux = 10 / 49,
}

function Construction.duration(stageLevel: number): number
	return Construction.durations[stageLevel] or 0
end

function Construction.speedupById(id: string): Speedup?
	for _, speedup in Construction.speedups do
		if speedup.id == id then
			return speedup
		end
	end
	return nil
end

function Construction.speedupByProduct(productId: number): Speedup?
	if productId == 0 then
		return nil
	end
	for _, speedup in Construction.speedups do
		if speedup.productId == productId then
			return speedup
		end
	end
	return nil
end

-- "7:42" / "1:05:00"
function Construction.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h, m = s // 3600, (s // 60) % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s % 60)
	end
	return string.format("%d:%02d", m, s % 60)
end

return Construction
