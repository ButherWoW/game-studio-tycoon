--!strict
-- Разовые покупки за Robux (Developer Products), кроме рекламы — она в Config/AdCampaigns.
-- Дизайн и цены — issue #11. Платных лутбоксов нет и не будет.
-- productId — ID из Creator Dashboard (0 = ещё не создан, в магазине кнопка «скоро»);
-- парой Universe.pick({ test = ..., main = ... }) для двух вселенных — Config/Universe, docs/IDS.md.
-- robuxPrice — ПРЕДЛОЖЕНИЕ из #11, только для показа; финальную цену решает владелец.

local Universe = require(script.Parent.Universe)

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
		productId = Universe.pick({ test = 3728447988, main = 3728498272 }),
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
		productId = Universe.pick({ test = 3728447989, main = 3728498290 }),
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
		productId = Universe.pick({ test = 3728447993, main = 3728498309 }),
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
		productId = Universe.pick({ test = 3728447996, main = 3728498324 }),
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
		productId = Universe.pick({ test = 3728447999, main = 3728498349 }),
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
		productId = Universe.pick({ test = 3728448002, main = 3728498365 }),
		robuxPrice = 299,
		incomeMinutes = 90,
	},
}

-- Продукты предложений (Config/Offers). Не в list: в магазине отдельной строкой не продаются.
-- Dev 1 создаёт их в Dashboard и вписывает productId
export type OfferProduct = { productId: number, robuxPrice: number }

local offers = {
	-- ×2 к доходу только что вышедшей игры (окно релиза). Поздно/повторно — пакет income10
	doubleRelease = { productId = Universe.pick({ test = 3728448015, main = 3728498380 }), robuxPrice = 25 } :: OfferProduct,
	-- Стартовый набор: $ за 30 мин дохода (мин. $5 000), 2 скина, 3 кофе, значок. Раз на аккаунт
	starterPack = { productId = Universe.pick({ test = 3728448017, main = 3728498901 }), robuxPrice = 79 } :: OfferProduct,
}

-- «Сделка дня» (−30%): цену продукта в Dashboard менять нельзя, поэтому у каждого товара пула
-- Offers.dailyDeal своя скидочная копия. Ключ — id из пула; выдаёт то же, что оригинал
local deals: { [string]: OfferProduct } = {
	instantFinish = { productId = Universe.pick({ test = 3728448020, main = 3728498397 }), robuxPrice = 10 },
	patch = { productId = Universe.pick({ test = 3728448022, main = 3728498414 }), robuxPrice = 17 },
	coffee = { productId = Universe.pick({ test = 3728448025, main = 3728498434 }), robuxPrice = 20 },
	income10 = { productId = Universe.pick({ test = 3728448031, main = 3728498444 }), robuxPrice = 34 },
	income30 = { productId = Universe.pick({ test = 3728448038, main = 3728498458 }), robuxPrice = 90 },
	income90 = { productId = Universe.pick({ test = 3728448040, main = 3728498477 }), robuxPrice = 209 },
	poster_neonCity = { productId = Universe.pick({ test = 3728448052, main = 3728498495 }), robuxPrice = 34 },
	poster_crystalKingdom = {
		productId = Universe.pick({ test = 3728448055, main = 3728498515 }),
		robuxPrice = 55,
	},
	poster_mechTitan = {
		productId = Universe.pick({ test = 3728448058, main = 3728498524 }),
		robuxPrice = 69,
	},
	poster_galaxyLegends = {
		productId = Universe.pick({ test = 3728448061, main = 3728498540 }),
		robuxPrice = 90,
	},
	poster_goldenController = {
		productId = Universe.pick({ test = 3728448065, main = 3728498556 }),
		robuxPrice = 104,
	},
	skin_neon_streamer = {
		productId = Universe.pick({ test = 3728448066, main = 3728498572 }),
		robuxPrice = 55,
	},
	skin_cyber_dev = { productId = Universe.pick({ test = 3728448069, main = 3728498585 }), robuxPrice = 69 },
	skin_space_dev = { productId = Universe.pick({ test = 3728448070, main = 3728498600 }), robuxPrice = 90 },
	skin_wizard_dev = {
		productId = Universe.pick({ test = 3728448090, main = 3728498619 }),
		robuxPrice = 104,
	},
}

-- Ускорение исследования (Config/Research.TIMING, ResearchService.grantProduct). Не в list:
-- продаются только из окна «Исследования» (выбор «⚡ Ускорить»). seconds — на сколько раньше
-- закончится активное исследование (не раньше «сейчас»); skip = true — закончить сразу.
-- Нет активного — ускорение копится и применяется к следующему (Robux не пропадают).
-- Цены — предложение (владелец решает); у фиксированного товара цена одна, поэтому «Завершить
-- сейчас» одна на все таймеры, а для коротких остатков окно показывает только −5 мин.
export type ResearchProduct = {
	id: string,
	productId: number,
	robuxPrice: number,
	seconds: number,
	skip: boolean,
}

local research: { ResearchProduct } = {
	{
		id = "researchSpeed5",
		productId = Universe.pick({ test = 0, main = 0 }),
		robuxPrice = 15,
		seconds = 5 * 60,
		skip = false,
	},
	{
		id = "researchSpeed30",
		productId = Universe.pick({ test = 0, main = 0 }),
		robuxPrice = 49,
		seconds = 30 * 60,
		skip = false,
	},
	{
		id = "researchSkip",
		productId = Universe.pick({ test = 0, main = 0 }),
		robuxPrice = 99,
		seconds = 0,
		skip = true,
	},
}

return {
	list = list,
	offers = offers,
	deals = deals,
	research = research,
	effects = {
		coffeeSpeed = 2, -- ×2 скорость разработки
		coffeeSeconds = 10 * 60, -- покупка продлевает от текущего конца
		patchScoreBonus = 1,
	},
	-- «Минута дохода» = доход релиза с оценкой max(рекорд, minScore) × релизов в минуту
	-- (с бонусами студии, rebirth и ×2 деньги). Так пакеты не обесцениваются (#11).
	income = {
		releasesPerMinute = 1.6, -- разработка ~37 с (Economy.devSeconds, balance/dev-pacing): пакеты дохода не дорожают
		minScore = 5, -- новичку считаем как за среднюю игру
		minPerMinute = 500, -- нижняя граница $ за минуту
	},
}
