--!strict
-- Геймпассы (покупаются один раз, навсегда). Дизайн и цены — issue #11.
-- gamePassId — ID из Creator Dashboard (0 = ещё не создан, в магазине кнопка «скоро»).
-- robuxPrice — ПРЕДЛОЖЕНИЕ из #11, только для показа; финальную цену решает владелец,
-- реальная задаётся в Dashboard (после этого поправить и здесь, чтобы магазин показывал верную).

export type PassId = "doubleCash" | "autoRelease" | "fastDev" | "extraSlot" | "vipOffice" | "legendaryEmployee"

export type GamePass = {
	id: PassId,
	name: string,
	nameEn: string,
	description: string,
	descriptionEn: string,
	icon: string,
	gamePassId: number,
	robuxPrice: number,
}

local list: { GamePass } = {
	{
		id = "doubleCash",
		name = "×2 деньги",
		nameEn = "×2 Cash",
		description = "Вдвое больше дохода с каждого релиза",
		descriptionEn = "Double revenue from every release",
		icon = "💰",
		gamePassId = 0,
		robuxPrice = 299, -- главный, ставим первым
	},
	{
		id = "autoRelease",
		name = "Авто-релиз",
		nameEn = "Auto Release",
		description = "Новая игра стартует сама после релиза",
		descriptionEn = "The next game starts by itself after a release",
		icon = "🔁",
		gamePassId = 0,
		robuxPrice = 149,
	},
	{
		id = "fastDev",
		name = "Быстрая разработка",
		nameEn = "Fast Development",
		description = "Игры делаются на 25% быстрее",
		descriptionEn = "Games are made 25% faster",
		icon = "⚡",
		gamePassId = 0,
		robuxPrice = 199,
	},
	{
		id = "extraSlot",
		name = "Второй слот проекта",
		nameEn = "Second Project Slot",
		description = "Две игры в разработке одновременно",
		descriptionEn = "Develop two games at once",
		icon = "➕",
		gamePassId = 0,
		robuxPrice = 249,
	},
	{
		id = "vipOffice",
		name = "VIP-офис",
		nameEn = "VIP Office",
		description = "Свой декор и золотая табличка",
		descriptionEn = "Exclusive decor and a golden sign",
		icon = "👑",
		gamePassId = 0,
		robuxPrice = 99, -- дешёвый, «первая покупка»
	},
	{
		id = "legendaryEmployee",
		name = "Мастер Пиксель",
		nameEn = "Master Pixel",
		description = "Легендарный сотрудник в команду",
		descriptionEn = "A legendary employee joins your team",
		icon = "🧙",
		gamePassId = 0,
		robuxPrice = 399,
	},
}

return {
	list = list,
	-- Числа эффектов геймпассов
	effects = {
		doubleCashMultiplier = 2,
		-- −25% времени разработки = скорость ×(1 / 0.75)
		fastDevTimeFactor = 0.75,
	},
}
