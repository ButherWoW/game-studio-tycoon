--!strict
-- Бонус Roblox Premium (7.17, PremiumService): +incomeBonus к доходу каждого релиза
-- (DevelopmentService.release, рядом с налогом и биржей) и ⭐ у имени над головой и на вывеске студии.
-- Не Premium — подсказка «⭐ Premium +10%» в шапке магазина открывает покупку Premium (Roblox).
-- Прибавка к офлайн-доходу и кофе к ежедневной награде — по-прежнему Config/Social.premium.

local Premium = {
	incomeBonus = 0.1,
	marker = "⭐",
	-- Табличка ⭐ над головой: выше таблички VIP (StudsOffset 3), дальше этого не видно
	tagOffset = 4.2,
	tagMaxDistance = 60,
}

return Premium
