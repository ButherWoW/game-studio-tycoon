--!strict
-- Награды «N минут дохода» (задания #9, награды за вход #10).
-- Минута дохода = доход за релиз с лучшей оценкой игрока × релизов в минуту.

export type Reward = {
	incomeMinutes: number?, -- деньги: N минут дохода (см. Rewards.incomeForMinutes)
	researchPoints: number?, -- ОИ, TODO #8: тратить в дереве исследований
	badge: string?, -- значок, TODO #9: выдать через BadgeService, когда появятся id значков
	incomeBonus: number?, -- 0.05 = +5% к доходу навсегда, TODO #9: учесть в DevelopmentService
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
}

return Rewards
