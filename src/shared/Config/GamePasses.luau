--!strict
-- Геймпассы (покупаются один раз, навсегда). Дизайн и цены — issue #11.
-- gamePassId — ID из Creator Dashboard (0 = ещё не создан, в магазине кнопка «скоро»).
-- ID парой Universe.pick({ test = v2 (10774624686), main = основная игра }) — Config/Universe, docs/IDS.md.
-- robuxPrice — ПРЕДЛОЖЕНИЕ из #11, только для показа; финальную цену решает владелец,
-- реальная задаётся в Dashboard (после этого поправить и здесь, чтобы магазин показывал верную).

local Universe = require(script.Parent.Universe)

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
		gamePassId = Universe.pick({ test = 2071008855, main = 2070540998 }),
		robuxPrice = 299, -- главный, ставим первым
	},
	{
		id = "autoRelease",
		name = "Авто-релиз",
		nameEn = "Auto Release",
		description = "Новая игра стартует сама после релиза",
		descriptionEn = "The next game starts by itself after a release",
		icon = "🔁",
		gamePassId = Universe.pick({ test = 2072480376, main = 2071816553 }),
		robuxPrice = 149,
	},
	{
		id = "fastDev",
		name = "Быстрая разработка",
		nameEn = "Fast Development",
		description = "Игры делаются на 25% быстрее",
		descriptionEn = "Games are made 25% faster",
		icon = "⚡",
		gamePassId = Universe.pick({ test = 2067092439, main = 2070314173 }),
		robuxPrice = 199,
	},
	{
		id = "extraSlot",
		name = "Второй слот проекта",
		nameEn = "Second Project Slot",
		description = "Две игры в разработке одновременно",
		descriptionEn = "Develop two games at once",
		icon = "➕",
		gamePassId = Universe.pick({ test = 2068496428, main = 2072234478 }),
		robuxPrice = 249,
	},
	{
		id = "vipOffice",
		name = "VIP-офис",
		nameEn = "VIP Office",
		description = "Свой декор и золотая табличка",
		descriptionEn = "Exclusive decor and a golden sign",
		icon = "👑",
		gamePassId = Universe.pick({ test = 2070720897, main = 2071640568 }),
		robuxPrice = 99, -- дешёвый, «первая покупка»
	},
	{
		id = "legendaryEmployee",
		name = "Мастер Пиксель",
		nameEn = "Master Pixel",
		description = "Легендарный сотрудник в команду",
		descriptionEn = "A legendary employee joins your team",
		icon = "🧙",
		gamePassId = Universe.pick({ test = 2070314109, main = 2068652542 }),
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
		-- «Второй слот проекта»: столько игр одновременно (исследование «Второй проект» — то же)
		extraSlotProjects = 2,
		-- VIP-офис: прибавка к оценке каждой игры (как reviewBonus предметов студии)
		vipReviewBonus = 0.3,
		-- Золотая табличка VIP над участком: смещение от центра участка и размер, в studs
		vipSignOffset = Vector3.new(0, 14, 0),
		vipSignSize = Vector3.new(8, 2.5, 0.4),
		vipSignColor = Color3.fromRGB(255, 201, 60),
	},
}
