--!strict
-- Начало игры «Инди в парке»: новый игрок без гаража делает игры на общем ноутбуке у спавна,
-- берёт подработки на доске заказов и сдаёт ретро-картриджи в ломбард, пока не купит гараж.
-- Баланс подобран симуляцией (PR feature/start-park): до гаража ≈ 5 минут обычной игры.

export type Job = {
	id: string,
	minPay: number, -- за нулевой результат (пришёл и честно отыграл 15 с)
	maxPay: number, -- за результат >= target
	target: number, -- сколько очков мини-игры нужно на максимальную оплату
	maxScore: number, -- больше этого за 15 с не набрать: всё сверху — враньё клиента, режем
}

local StartPark = {
	-- Цена гаража (табличка «Гараж продаётся» на своём участке)
	garagePrice = 750,

	-- Ноутбук на скамейке: длительность и очки фиксированы (бонусы студии не действуют).
	-- 05.11 «игры делаются слишком быстро»: 20 → 35 с (первые Economy.firstGames игр — 25 с).
	-- Очки за игру — как за laptopPointsSeconds с при laptopPointsPerSecond (оценка не выросла)
	laptopDuration = 35,
	laptopPointsSeconds = 20,
	laptopPointsPerSecond = 0.6,
	-- Доход игры, начатой на ноутбуке, — эта доля от обычного. Было 0.25 при цикле ~40 с;
	-- цикл стал ~55 с, а Economy.revenueBase ×1.25 — 0.275 держит прежний доход в минуту
	laptopRevenueMultiplier = 0.275,

	-- Доска заказов: мини-игры по jobDuration секунд
	jobDuration = 15,
	-- Сколько после jobDuration ещё ждём результат (сеть, лаги); позже — без оплаты
	jobGrace = 10,
	-- Перезарядка каждого заказа отдельно, с момента сдачи
	jobCooldown = 90,
	-- Отойти от доски дальше этого во время заказа нельзя (сдача не засчитается)
	jobMaxDistance = 14,
	jobs = {
		{ id = "bugs", minPay = 50, maxPay = 130, target = 18, maxScore = 40 },
		{ id = "pixel", minPay = 50, maxPay = 130, target = 4, maxScore = 12 },
		{ id = "rhythm", minPay = 50, maxPay = 130, target = 16, maxScore = 20 },
	} :: { Job },
	-- Ритм: удар каждые beatInterval секунд, попадание — в пределах beatWindow от удара
	beatInterval = 0.75,
	beatWindow = 0.18,

	-- Ретро-картриджи: точки в парке, картридж снова появляется через cartridgeRespawn секунд
	cartridgeSpots = 6,
	cartridgeRespawn = 120,
	cartridgePrice = 25, -- ломбард платит за каждый
	maxCartridges = 20, -- больше в инвентаре не помещается
	-- Где появляются картриджи: случайная точка по всему парку (StartParkService.randomSpotPosition),
	-- в кольце cartridgeAreaMin..cartridgeAreaMax от спавна (за ним уже участки).
	-- Не ближе cartridgeClearance к скамейкам, доске, ломбарду, фонтану и спавну,
	-- и не ближе cartridgeSpacing друг к другу. Не нашлось места за cartridgeTries — старая точка
	cartridgeAreaMin = 10,
	-- До участков: по всему парку и траве вокруг (просьба владельца — шире, не «по кругу»).
	-- Участки, место у их кнопок и тропинки StartParkService обходит сам
	cartridgeAreaMax = 118,
	cartridgePlotMargin = 6, -- от края участка; спереди (кнопки) — ещё +8
	cartridgePathClear = 5, -- от оси тропинки к участку
	cartridgeClearance = 5,
	cartridgeSpacing = 14,
	cartridgeTries = 80,

	-- Название студии (вводится один раз после покупки гаража), символов после trim
	studioNameMin = 3,
	studioNameMax = 24,

	-- Раскладка парка вокруг точки спавна (studs)
	benchCount = 6,
	benchRadius = 28,
	boardRadius = 12,
	-- Раскладка Астры для её парка (assets/models/astra-park-objects/README.md): старые точки доски и
	-- ломбарда (радиус 12) легли бы на её дорожки. От центра спавна, yaw — поворот лица (+Z) в градусах
	landscapeBoard = { position = Vector3.new(0, 0, 17), yaw = 180 },
	landscapePawnshop = { position = Vector3.new(-9.148114, 0, -43.038494), yaw = 12 },
	landscapeFountain = { position = Vector3.new(43.466662, 0, 11.646857), yaw = 0 },
	-- Площадка появления игрока (модель Астры assets/models/astra-v33 в ServerStorage.Upgrades): центр —
	-- X/Z SpawnLocation, низ на уровне земли. Невидимый SpawnLocation вписывается в её габарит и верх,
	-- коллизию он не даёт (опора — сама модель). Нет модели или это заглушка Generated — старый SpawnLocation
	spawnPadName = "SpawnPad",
	cartridgeRadius = 42, -- только начальная раскладка точек (WorldService), дальше — случайно

	-- Рекламные щиты (BillboardService, Config/Billboards): угол/радиус от спавна, лицом к спавну.
	-- Проверено по astra-park (дорожки, деревья, пруд, фонари, скамейки, доска, ломбард, фонтан,
	-- доска лайков, ёлка праздника): опора на газоне с запасом ≥ 1.5 studs, панель выше крон.
	-- В плейсе без парка Астры щит, опора которого легла на PlotPaths, не ставится
	billboards = {
		{ angle = 37, radius = 58 },
		{ angle = 129, radius = 56 },
		{ angle = 218, radius = 61 },
		{ angle = 320, radius = 55 },
	} :: { { angle: number, radius: number } },
	-- Зал славы (HallOfFameService): три пьедестала на помосте 13×5 studs, лицом к спавну.
	-- Поляна между выходами к участкам 60° и 90°, перед помостом 3 studs свободно
	hallOfFame = { angle = 77, radius = 46, width = 13, depth = 5 },
}

return StartPark
