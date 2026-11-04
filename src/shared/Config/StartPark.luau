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

	-- Ноутбук на скамейке: длительность и очки/с фиксированы (бонусы студии не действуют)
	laptopDuration = 20,
	laptopPointsPerSecond = 0.6,
	-- Доход игры, начатой на ноутбуке, — эта доля от обычного
	laptopRevenueMultiplier = 0.25,

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
	cartridgeAreaMax = 52,
	cartridgeClearance = 5,
	cartridgeSpacing = 14,
	cartridgeTries = 40,

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
	cartridgeRadius = 42, -- только начальная раскладка точек (WorldService), дальше — случайно
}

return StartPark
