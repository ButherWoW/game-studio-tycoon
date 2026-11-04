--!strict
-- Своя консоль и стример (волна 2, ConsoleService и StreamerService).
--
-- Консоль — поздний проект 3-го этажа (studioLevel 4): три этапа «проект → прототип → запуск».
-- Этап начинается оплатой cost, завершается, когда после старта вышло games игр (на 3-м этаже).
-- После запуска у консоли доля рынка: +shareHit за игру 8+ на своей консоли, медленно тает
-- (shareDecayPerMinute, не ниже shareBase). Роялти в минуту = доход студии в минуту
-- (ShopService.incomePerMinute) × доля × royaltyPerShare; часть из него — лицензии конкурентов (вкус).
-- Консоль переживает Rebirth (как достижения): поздняя награда не пропадает.
-- Порядок цифр: 3-й этаж ~10–15k за игру, ~2 игры в минуту => ~25–35k в минуту.
-- Все этапы — ~19M и ~240 игр (≈ 1.5–2 ч активной игры), как вторая половина «Топ-мест».
--
-- Стример — роль одного нанятого сотрудника (с офиса). Его стол не даёт очков и перков,
-- зато идут донаты: доход в минуту × donationShare × слава × (hypeFloor + (1 − hypeFloor) × хайп).
-- Слава = средняя оценка последних fameGames игр / fameScore (fameMin..fameMax).
-- Хайп 0..100: +hypePerMinute пока идёт стрим, +hypePerHit за игру 7+; релиз тратит
-- hypeSpend и даёт доход × (1 + hypeMaxBonus × хайп/100), т. е. до +30%.
-- Баланс: сотрудник за столом даёт ~4–6% дохода (≈ 1/N очков и +0.1–0.2 к оценке, доход ∝ оценка²);
-- стример при славе ~7 и хайпе ~50 даёт ~3–3.5% + хайп к релизам ≈ 60–80% от этого — выбор, а не must.

export type ConsoleStage = {
	id: string,
	icon: string,
	cost: number,
	games: number,
}

local Console = {
	minStudioLevel = 4, -- 3-й этаж
	stages = {
		{ id = "design", icon = "📐", cost = 3_000_000, games = 40 },
		{ id = "prototype", icon = "🔧", cost = 6_000_000, games = 80 },
		{ id = "launch", icon = "🚀", cost = 10_000_000, games = 120 },
	} :: { ConsoleStage },
	-- Доля рынка, %
	shareBase = 1, -- сразу после запуска и нижняя граница
	shareMax = 25,
	shareHit = 0.5, -- за игру с оценкой hitScore+ на своей консоли
	hitScore = 8,
	shareDecayPerMinute = 0.05, -- пока игрок в игре
	-- Роялти: доля дохода студии в минуту за каждый % рынка (25% => +10% дохода в минуту)
	royaltyPerShare = 0.004,
	licenseShare = 0.3, -- такая часть роялти подписана «лицензии конкурентов»
	-- Доход игр на своей консоли × (1 + доля% × shareRevenueBonus): 25% => ×1.25
	shareRevenueBonus = 0.01,
	tickSeconds = 10, -- как часто начислять роялти и таять доле

	streamer = {
		minStudioLevel = 2, -- с офиса
		donationShare = 0.05,
		fameGames = 5,
		fameScore = 8,
		fameMin = 0.3,
		fameMax = 1.25,
		hypeFloor = 0.4,
		hypeMax = 100,
		hypePerMinute = 6,
		hypePerHit = 4, -- за игру с оценкой 7+
		hypeHitScore = 7,
		hypeSpend = 25, -- столько хайпа тратит релиз
		hypeMaxBonus = 0.3, -- +30% к доходу релиза при полном хайпе
		tickSeconds = 10,
		bubbleMin = 12, -- секунд между репликами чата над NPC
		bubbleMax = 22,
		bubbleSeconds = 4,
		-- Реплики чата: без слов, чтобы не переводить (видят и гости студии)
		bubbles = {
			"🔥 GG!",
			"💜 +1 sub",
			"😂😂😂",
			"👏 W",
			"🎮 POG",
			"💸 donate!",
			"⭐⭐⭐",
			"🤯 wow",
		},
	},
}

return Console
