--!strict
-- Награды «N минут дохода» (задания #9, награды за вход #10).
-- Минута дохода = доход за релиз с лучшей оценкой с последнего Rebirth × релизов в минуту;
-- без гаража — доход ноутбука в парке (RewardFormulas).

export type Reward = {
	incomeMinutes: number?, -- деньги: N минут дохода (см. RewardFormulas.incomeForMinutes)
	researchPoints: number?, -- ОИ, TODO #8: тратить в дереве исследований
	badge: string?, -- значок, TODO #9: выдать через BadgeService, когда появятся id значков
	incomeBonus: number?, -- 0.05 = +5% к доходу навсегда (DevelopmentService.release)
	employee: string?, -- id сотрудника, TODO #7: нанять, когда будет система сотрудников
	coffeeMinutes: number?, -- кофе ×2 к скорости разработки, TODO #10: учесть в DevelopmentService
	adBonus: number?, -- бесплатная реклама: бонус (0.3 = +30%) ...
	adMinutes: number?, -- ... и длительность
	trophy: string?, -- декор в коллекцию, TODO #10: поставить на участок
}

local Rewards = {
	-- Оценка, от которой считается доход, не ниже этой (новичок с оценкой 2 тоже получает ощутимо)
	minScore = 5,
	-- Длительность разработки одной игры, с (как BASE_DURATION в DevelopmentService)
	secondsPerGame = 30,
	-- +50% за каждый Rebirth (как в DevelopmentService)
	rebirthBonus = 0.5,
	-- Без гаража: одна игра на ноутбуке в парке с учётом подхода и окон (StartPark.laptopDuration = 20)
	parkSecondsPerGame = 40,
	-- Без гаража одна денежная награда — не больше этой доли StartPark.garagePrice (30% -> $225)
	parkMaxGarageShare = 0.3,
	-- Отчёт #3: с одним потолком все 7 дней ежедневки давали одинаковые ~$225. Потолок растёт
	-- с минутами награды: до parkCapBaseMinutes — ×1, к parkCapFullMinutes — ×parkCapMaxMultiplier
	-- (5 мин $225, 10 мин $270, 20 мин $360, 30 мин $450 — не больше 2× дня 1)
	parkCapBaseMinutes = 5,
	parkCapFullMinutes = 30,
	parkCapMaxMultiplier = 2,
}

return Rewards
