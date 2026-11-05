--!strict
-- Своя консоль и стример (волна 2, ConsoleService и StreamerService).
--
-- Консоль — поздний проект 3-го этажа (studioLevel 4): цепочка производства из 6 этапов
-- «процессор → корпус → звуковой чип → прототип → тестирование → запуск» (ConsoleService).
-- Этап можно начать, когда:
--   1) куплено оборудование этапа (equipment: «Лаборатория чипов», «Станция дизайна»,
--      «Стенд тестирования» — покупается в окне консоли за $, стоит на 3-м этаже);
--   2) в команде есть сотрудник с навыком skill не ниже level (Config/Skills, StaffService) —
--      он и «ведёт» этап (имя видно в окне);
--   3) хватает денег на cost (оплата сразу).
-- Дальше идёт таймер minutes (os.time: тикает и офлайн, переживает перезаход). Ускорить —
-- Robux (speedups, как у исследований и стройки); лишнее ускорение переходит на следующий этап.
-- После запуска у консоли доля рынка: +shareHit за игру 8+ на своей консоли, медленно тает
-- (shareDecayPerMinute, не ниже shareBase). Роялти в минуту = доход студии в минуту
-- (ShopService.incomePerMinute) × доля × royaltyPerShare; часть из него — лицензии конкурентов (вкус).
-- Консоль переживает Rebirth (как достижения): поздняя награда не пропадает, оборудование тоже.
-- Порядок цифр: 3-й этаж ~10–15k за игру, ~2 игры в минуту => ~25–35k в минуту.
-- Этапы $16M + оборудование $4M = $20M (было $19M за 3 этапа) и 160 мин таймеров (≈ 2.7 ч,
-- но таймер идёт и офлайн; раньше — ~240 игр ≈ 1.5–2 ч активной игры). Навыки 3–4 у
-- сотрудников 3-го этажа: +1 уровень $0.9–1.8M — заодно растят оценку игр, не «налог».
-- Rebirth консоль не требует (RebirthService), поэтому темп 1-го Rebirth она не меняет.

-- Стример — роль одного нанятого сотрудника (с офиса). Его стол не даёт очков и перков,
-- зато идут донаты: доход в минуту × donationShare × слава × (hypeFloor + (1 − hypeFloor) × хайп).
-- Слава = средняя оценка последних fameGames игр / fameScore (fameMin..fameMax).
-- Хайп 0..100: +hypePerMinute пока идёт стрим, +hypePerHit за игру 7+; релиз тратит
-- hypeSpend и даёт доход × (1 + hypeMaxBonus × хайп/100), т. е. до +30%.
-- Баланс: сотрудник за столом даёт ~4–6% дохода (≈ 1/N очков и +0.1–0.2 к оценке, доход ∝ оценка²);
-- стример при славе ~7 и хайпе ~50 даёт ~3–3.5% + хайп к релизам ≈ 60–80% от этого — выбор, а не must.

local Universe = require(script.Parent.Universe)

export type ConsoleStage = {
	id: string,
	icon: string,
	cost: number,
	minutes: number, -- длительность таймера этапа
	equipment: { string }, -- id из Console.equipment: всё должно быть куплено
	skill: string?, -- ключ Config/Skills; nil — сотрудник не нужен
	level: number, -- минимальный уровень навыка skill у одного сотрудника
	model: string, -- модель на 3-м этаже, пока этап идёт или уже пройден (V23)
}

export type ConsoleEquipment = {
	id: string,
	icon: string,
	cost: number,
	model: string, -- ServerStorage.Upgrades.<model> (V30, Астра); нет — простая заглушка из деталей
	position: Vector3, -- от центра участка, y — над полом 3-го этажа
	rotation: number,
	size: Vector3, -- габарит заглушки (и бриф для модели)
	color: Color3, -- цвет заглушки
}

export type ConsoleSpeedup = {
	id: string, -- ключ продукта и текстов cons_speed_<id>
	seconds: number?, -- сколько минус к таймеру; nil — завершить этап целиком
	productId: number,
	robuxPrice: number, -- только для показа, финальная цена — в Dashboard
}

local Console = {
	minStudioLevel = 4, -- 3-й этаж
	-- Тексты: cons_stage_<id> (название) и cons_stage_<id>_desc (что делаем)
	stages = {
		{
			id = "cpu",
			icon = "🧠",
			cost = 1_500_000,
			minutes = 15,
			equipment = { "chipLab" },
			skill = "gameplay",
			level = 3,
			model = "Console_Design",
		},
		{
			id = "case",
			icon = "📐",
			cost = 1_500_000,
			minutes = 15,
			equipment = { "designStation" },
			skill = "graphics",
			level = 3,
			model = "Console_Design",
		},
		{
			id = "sound",
			icon = "🔊",
			cost = 2_000_000,
			minutes = 20,
			equipment = { "chipLab" },
			skill = "sound",
			level = 3,
			model = "Console_Design",
		},
		{
			id = "prototype",
			icon = "🔧",
			cost = 3_000_000,
			minutes = 30,
			equipment = { "chipLab", "designStation" },
			skill = "graphics",
			level = 4,
			model = "Console_Prototype",
		},
		{
			id = "testing",
			icon = "🧪",
			cost = 3_500_000,
			minutes = 35,
			equipment = { "testBench" },
			skill = "gameplay",
			level = 4,
			model = "Console_Prototype",
		},
		{
			id = "launch",
			icon = "🚀",
			cost = 4_500_000,
			minutes = 45,
			equipment = {},
			skill = "story",
			level = 4,
			model = "Console_Launch",
		},
	} :: { ConsoleStage },
	-- Старые сохранения (3 этапа «проект → прототип → запуск», profile.console без v):
	-- пройдено старых этапов -> пройдено новых. Оплаченный, но не законченный старый этап
	-- засчитывается пройденным (деньги уже списаны — не теряем). Оборудование для пройденных
	-- этапов выдаётся бесплатно (ConsoleService.migrate)
	legacyStageMap = { [0] = 0, [1] = 2, [2] = 4, [3] = 6 } :: { [number]: number },
	-- Оборудование консоли: покупается в окне консоли, стоит на 3-м этаже. Места свободны от
	-- лифта (X −23..−17, Z 21..27), модели консоли (X −16..−10, Z 23..29), кнопок покупки
	-- (X −6..6, Z 22..29), растений (±26, 22), арт-стены (X 8..22, Z ≈ 16), столов (ряды Z −20,
	-- −8, 4 и места сотрудников +3.5 по Z) и декора 3-го этажа (Config/Decor, slots[4]).
	-- Лицом в зал: у передней стены — 180 (к −Z), у правой — −90 (к −X)
	equipment = {
		{
			id = "chipLab",
			icon = "🔬",
			cost = 1_200_000,
			model = "Equip_ChipLab",
			position = Vector3.new(11, 0.5, 25.5), -- X 8..14, Z 23..28
			rotation = 180,
			size = Vector3.new(6, 4, 4),
			color = Color3.fromRGB(70, 150, 255),
		},
		{
			id = "designStation",
			icon = "🖌️",
			cost = 1_200_000,
			model = "Equip_DesignStation",
			position = Vector3.new(18, 0.5, 25.5), -- X 15..21, Z 23..28
			rotation = 180,
			size = Vector3.new(6, 4, 4),
			color = Color3.fromRGB(240, 110, 190),
		},
		{
			id = "testBench",
			icon = "🧰",
			cost = 1_600_000,
			model = "Equip_TestBench",
			position = Vector3.new(25.5, 0.5, 10), -- X 23..28, Z 7..13
			rotation = -90,
			size = Vector3.new(6, 4, 4),
			color = Color3.fromRGB(110, 200, 80),
		},
	} :: { ConsoleEquipment },
	-- Ускорение этапа за Robux (как исследования и стройка): ID — Dev 1 из Dashboard.
	-- Покупка без идущего этапа или больше, чем осталось, — остаток копится (profile.console.credit /
	-- skips) и тратится на следующий этап: Robux не пропадают. −30 мин скрыт, если осталось ≤ 5 мин
	speedups = {
		{
			id = "consoleSpeed5",
			seconds = 5 * 60,
			productId = Universe.pick({ test = 3728502848, main = 3728503139 }),
			robuxPrice = 15,
		},
		{
			id = "consoleSpeed30",
			seconds = 30 * 60,
			productId = Universe.pick({ test = 3728502968, main = 3728503201 }),
			robuxPrice = 69,
		},
		{
			id = "consoleSkip",
			seconds = nil,
			productId = Universe.pick({ test = 3728503072, main = 3728503265 }),
			robuxPrice = 99,
		},
	} :: { ConsoleSpeedup },
	speed30MinLeft = 5 * 60, -- «−30 мин» прячем, когда осталось столько или меньше
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
	-- Модель консоли на 3-м этаже (V23, Астра): ServerStorage.Upgrades.<stage.model>
	-- (идёт этап — его модель, пройден последний — Launch). Нет модели — ничего не ставим.
	-- Место — справа от лифта (зона лифта X −23..−17, Z 21..27): габарит ≤ 6×6 → X −16..−10,
	-- Z 23..29 (до передней стены), лицом в зал (−Z). Свободно от кнопок покупки (на 3-м этаже
	-- 1–2 кнопки у центра, X −6..6), растений (±26, 22), звукостудии (X −24..−12, Z ≤ 18) и декора
	modelPosition = Vector3.new(-13, 0.5, 26), -- от центра участка, y — над полом 3-го этажа
	modelRotation = 180,

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
