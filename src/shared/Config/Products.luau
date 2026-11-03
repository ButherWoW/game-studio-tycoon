--!strict
-- Разовые покупки за Robux (Developer Products), кроме рекламы — она в Config/AdCampaigns.
-- Дизайн и цены — issue #11. Платных лутбоксов нет и не будет.
-- productId — ID из Creator Dashboard (0 = ещё не создан, в магазине кнопка «скоро»).
-- robuxPrice — ПРЕДЛОЖЕНИЕ из #11, только для показа; финальную цену решает владелец.

export type ProductKind = "instantFinish" | "patch" | "coffee" | "incomePack"

export type Product = {
	id: string,
	kind: ProductKind,
	name: string,
	nameEn: string,
	description: string,
	descriptionEn: string,
	icon: string,
	productId: number,
	robuxPrice: number,
	incomeMinutes: number?, -- только для incomePack
}

local list: { Product } = {
	{
		id = "instantFinish",
		kind = "instantFinish",
		name = "Мгновенно закончить",
		nameEn = "Finish Instantly",
		description = "Текущая игра выходит сразу, без потери очков",
		descriptionEn = "The current game is released right away, no points lost",
		icon = "⏩",
		productId = 0,
		robuxPrice = 15,
	},
	{
		id = "patch",
		kind = "patch",
		name = "Патч",
		nameEn = "Patch",
		description = "+1 к оценке следующего релиза",
		descriptionEn = "+1 to the score of the next release",
		icon = "🩹",
		productId = 0,
		robuxPrice = 25,
	},
	{
		id = "coffee",
		kind = "coffee",
		name = "Кофе",
		nameEn = "Coffee",
		description = "×2 скорость разработки на 10 минут",
		descriptionEn = "×2 development speed for 10 minutes",
		icon = "☕",
		productId = 0,
		robuxPrice = 29,
	},
	{
		id = "income10",
		kind = "incomePack",
		name = "10 минут дохода",
		nameEn = "10 minutes of income",
		description = "Деньги, которые студия заработала бы за 10 минут",
		descriptionEn = "Cash your studio would earn in 10 minutes",
		icon = "💵",
		productId = 0,
		robuxPrice = 49,
		incomeMinutes = 10,
	},
	{
		id = "income30",
		kind = "incomePack",
		name = "30 минут дохода",
		nameEn = "30 minutes of income",
		description = "Деньги, которые студия заработала бы за 30 минут",
		descriptionEn = "Cash your studio would earn in 30 minutes",
		icon = "💰",
		productId = 0,
		robuxPrice = 129,
		incomeMinutes = 30,
	},
	{
		id = "income90",
		kind = "incomePack",
		name = "90 минут дохода",
		nameEn = "90 minutes of income",
		description = "Деньги, которые студия заработала бы за 90 минут",
		descriptionEn = "Cash your studio would earn in 90 minutes",
		icon = "🏦",
		productId = 0,
		robuxPrice = 299,
		incomeMinutes = 90,
	},
}

return {
	list = list,
	effects = {
		coffeeSpeed = 2, -- ×2 скорость разработки
		coffeeSeconds = 10 * 60, -- покупка продлевает от текущего конца
		patchScoreBonus = 1,
	},
	-- «Минута дохода» = доход релиза с оценкой max(рекорд, minScore) × релизов в минуту
	-- (с бонусами студии, rebirth и ×2 деньги). Так пакеты не обесцениваются (#11).
	income = {
		releasesPerMinute = 2, -- BASE_DURATION в DevelopmentService = 30 с
		minScore = 5, -- новичку считаем как за среднюю игру
		minPerMinute = 500, -- нижняя граница $ за минуту
	},
}
