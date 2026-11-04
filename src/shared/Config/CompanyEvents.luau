--!strict
-- События компании (CompanyEventService): случайные новости для всей студии, отдельно от событий
-- разработки (Config/DevEvents). Раз в 7–14 мин онлайн-игры с гаражом приходит карточка: хорошая,
-- плохая, катастрофа (2-й этаж+) или выбор из двух вариантов. Деньги — в «минутах дохода»
-- (RewardFormulas), поэтому событие ощутимо на любом этапе. Всё время — секунды ОНЛАЙН-игры:
-- эффекты сохраняются в профиле и тикают только в игре (выход не обнуляет и не «пересиживает» их).
-- Тексты: cev_<id>_title / cev_<id>_text, варианты выбора — cev_<id>_a / cev_<id>_b
-- (в них можно {money} и {name}), строки эффектов — cev_fx_* (Texts + Locales).
--
-- Поля исхода (Outcome), всё необязательно:
--   cashMinutes   — +/− минут дохода (минус — потеря; не больше maxCashShare наличных)
--   cashShare     — потеря доли наличных (катастрофы)
--   revenue, revenueSeconds — множитель дохода релизов на время (0.8 = −20%)
--   nextRevenue   — множитель дохода следующего релиза; nextScore — прибавка к оценке следующей игры
--   rentFreeSeconds — аренда не списывается; pauseSeconds — разработка стоит
--   breakSeconds  — сломан случайный предмет интерьера (стол/техника не работают), починка за
--                   repairMinutes минут дохода; moodValue, moodSeconds — временная поправка настроения
--   rollback      — текущие игры теряют долю прогресса; rush — пропустить долю оставшегося времени
--   skill         — бесплатный уровень навыка случайному сотруднику
--   raise         — зарплата переманиваемого сотрудника × raise навсегда; poach — сотрудник уходит
--   walkoutSeconds — команда не работает (без бонусов сотрудников)
--   chance, fail  — исход срабатывает с шансом chance, иначе применяется fail
-- Страховка (insurance) вдвое уменьшает урон плохих событий и катастроф (деньги, время, силу).
-- Защита от «разорения»: наличные не опускаются ниже cashFloor (и двух минут аренды), постройки
-- не отнимаются, уходит не больше одного сотрудника за событие.

export type Kind = "good" | "bad" | "choice" | "catastrophic"
export type Need = "staff" | "project" | "item" | "rent"

export type Outcome = {
	cashMinutes: number?,
	maxCashShare: number?,
	cashShare: number?,
	revenue: number?,
	revenueSeconds: number?,
	nextRevenue: number?,
	nextScore: number?,
	rentFreeSeconds: number?,
	pauseSeconds: number?,
	breakSeconds: number?,
	moodValue: number?,
	moodSeconds: number?,
	rollback: number?,
	rush: number?,
	skill: number?,
	raise: number?,
	poach: boolean?,
	walkoutSeconds: number?,
	chance: number?,
	fail: Outcome?,
}

export type Event = {
	id: string,
	kind: Kind,
	emoji: string,
	weight: number,
	minStage: number, -- profile.studioLevel (1 гараж, 2 офис, 3 2-й этаж, 4 3-й этаж)
	cooldown: number, -- секунд онлайн-игры до повтора этого же события
	needs: { Need }?, -- без этого событие не выпадает (нет команды, игры в разработке…)
	effect: Outcome?, -- сразу при срабатывании (хорошие/плохие)
	a: Outcome?, -- варианты выбора
	b: Outcome?,
	default: ("a" | "b")?, -- без ответа (таймаут, вышел из игры) — этот вариант
}

local MIN = 60

local CompanyEvents = {
	enabled = true,
	-- Интервал между событиями, секунд онлайн-игры с гаражом
	intervalMin = 7 * MIN,
	intervalMax = 14 * MIN,
	-- Новичок: первые столько секунд онлайн-игры с гаражом событий нет
	newPlayerSeconds = 10 * MIN,
	-- Опытные игроки (столько игр уже выпущено) — без «новичковой» паузы
	veteranGames = 40,
	-- После входа в игру — тишина (как у предложений доната, Config/Offers.popup)
	sessionWarmupSeconds = 2 * MIN,
	-- Не подошло время (туториал, нет участка) — проверить снова через столько секунд
	retrySeconds = 20,
	-- На выбор: столько секунд после показа карточки; карточку не показали (окна) — maxWaitSeconds
	answerSeconds = 45,
	maxWaitSeconds = 4 * MIN,

	-- Шанс хорошего события (среди хороших/плохих) по этапу; дальше — честнее
	goodChance = { 0.65, 0.58, 0.52, 0.48 },
	-- Доля событий с выбором
	choiceShare = 0.22,
	-- После стольких плохих подряд следующее — хорошее
	pityAfter = 2,

	-- Катастрофы: с этого этапа (2-й этаж), шанс заменить плохое событие, не чаще cooldown
	catastrophic = {
		minStage = 3,
		chance = 0.2,
		cooldown = 3 * 60 * MIN,
	},

	-- Наличные не опускаются ниже max(cashFloor, аренда × rentFloorMinutes)
	cashFloor = 1_000,
	rentFloorMinutes = 2,

	-- Страховка: цена в минутах дохода, действует столько секунд онлайн-игры, урон × damageFactor
	insurance = {
		priceMinutes = 10,
		seconds = 30 * MIN,
		damageFactor = 0.5,
	},

	-- Починка сломанного предмета (flood): минут дохода
	repairMinutes = 2,
	-- Предметы, которые никогда не ломаются: свой стол и компьютер игрока (без них не сделать игру)
	unbreakable = { desk1 = true, pc1 = true } :: { [string]: boolean },
	-- Сумма поправок «следующей игры» не выходит за эти пределы
	nextScoreLimit = 2,
	nextRevenueMax = 3,
	-- Множитель дохода от всех активных эффектов — в этих пределах
	revenueMin = 0.3,
	revenueMax = 3,

	list = {
		-- ===== Хорошие =====
		{
			id = "angel",
			kind = "good",
			emoji = "👼",
			weight = 10,
			minStage = 1,
			cooldown = 40 * MIN,
			effect = { cashMinutes = 6 },
		},
		{
			id = "streamer",
			kind = "good",
			emoji = "📺",
			weight = 8,
			minStage = 1,
			cooldown = 30 * MIN,
			effect = { nextRevenue = 2.5 },
		},
		{
			id = "award",
			kind = "good",
			emoji = "🏆",
			weight = 8,
			minStage = 1,
			cooldown = 30 * MIN,
			effect = { nextScore = 0.5 },
		},
		{
			id = "conference",
			kind = "good",
			emoji = "🎤",
			weight = 7,
			minStage = 1,
			cooldown = 40 * MIN,
			needs = { "staff" },
			effect = { skill = 1 },
		},
		{
			id = "grant",
			kind = "good",
			emoji = "🏛",
			weight = 6,
			minStage = 2,
			cooldown = 40 * MIN,
			needs = { "rent" },
			effect = { rentFreeSeconds = 10 * MIN },
		},
		{
			id = "donations",
			kind = "good",
			emoji = "💝",
			weight = 10,
			minStage = 1,
			cooldown = 25 * MIN,
			effect = { cashMinutes = 3 },
		},
		{
			id = "luckybug",
			kind = "good",
			emoji = "🐞",
			weight = 6,
			minStage = 1,
			cooldown = 30 * MIN,
			effect = { nextScore = 1 },
		},
		{
			id = "hype",
			kind = "good",
			emoji = "📰",
			weight = 6,
			minStage = 1,
			cooldown = 30 * MIN,
			effect = { revenue = 1.25, revenueSeconds = 10 * MIN },
		},

		-- ===== Плохие =====
		{
			id = "crash",
			kind = "bad",
			emoji = "💥",
			weight = 7,
			minStage = 1,
			cooldown = 30 * MIN,
			needs = { "project" },
			effect = { rollback = 0.3 },
		},
		{
			id = "leak",
			kind = "bad",
			emoji = "🕵",
			weight = 6,
			minStage = 1,
			cooldown = 40 * MIN,
			effect = { revenue = 0.8, revenueSeconds = 15 * MIN },
		},
		{
			id = "flood",
			kind = "bad",
			emoji = "🌊",
			weight = 5,
			minStage = 1,
			cooldown = 40 * MIN,
			needs = { "item" },
			effect = { breakSeconds = 10 * MIN },
		},
		{
			id = "audit",
			kind = "bad",
			emoji = "🧾",
			weight = 6,
			minStage = 1,
			cooldown = 40 * MIN,
			effect = { cashMinutes = -4, maxCashShare = 0.25 },
		},
		{
			id = "outage",
			kind = "bad",
			emoji = "🔌",
			weight = 7,
			minStage = 1,
			cooldown = 25 * MIN,
			needs = { "project" },
			effect = { pauseSeconds = 30 },
		},
		{
			id = "reviewbomb",
			kind = "bad",
			emoji = "💣",
			weight = 6,
			minStage = 1,
			cooldown = 30 * MIN,
			effect = { nextScore = -0.5 },
		},
		{
			id = "burnout",
			kind = "bad",
			emoji = "🥵",
			weight = 5,
			minStage = 1,
			cooldown = 40 * MIN,
			needs = { "staff" },
			effect = { moodValue = -15, moodSeconds = 5 * MIN },
		},
		-- Плохие с выбором: можно смягчить
		{
			id = "lawsuit",
			kind = "bad",
			emoji = "⚖",
			weight = 5,
			minStage = 2,
			cooldown = 60 * MIN,
			a = { cashMinutes = -5, maxCashShare = 0.3 },
			-- Суд: 50% — выиграли, иначе −30% дохода на 20 мин
			b = { chance = 0.5, fail = { revenue = 0.7, revenueSeconds = 20 * MIN } },
			default = "a",
		},
		{
			id = "poach",
			kind = "bad",
			emoji = "🦈",
			weight = 4,
			minStage = 2,
			cooldown = 60 * MIN,
			needs = { "staff" },
			a = { raise = 1.3 },
			b = { poach = true },
			default = "a",
		},

		-- ===== Выбор с риском =====
		{
			id = "rush",
			kind = "choice",
			emoji = "⏩",
			weight = 6,
			minStage = 1,
			cooldown = 25 * MIN,
			needs = { "project" },
			a = { rush = 0.4, nextScore = -1 },
			b = {},
			default = "b",
		},
		{
			id = "sponsor",
			kind = "choice",
			emoji = "🤝",
			weight = 6,
			minStage = 1,
			cooldown = 30 * MIN,
			a = { cashMinutes = 5, nextScore = -0.5 },
			b = {},
			default = "b",
		},
		{
			id = "gamble",
			kind = "choice",
			emoji = "🎲",
			weight = 5,
			minStage = 2,
			cooldown = 40 * MIN,
			-- Вложить 5 мин дохода: 55% — вернуть 13 мин (чистыми +8), иначе потеря
			a = {
				chance = 0.55,
				cashMinutes = 8,
				fail = { cashMinutes = -5, maxCashShare = 0.3 },
			},
			b = {},
			default = "b",
		},

		-- ===== Катастрофы (2-й этаж+, редко; переживаемые) =====
		{
			id = "takeover",
			kind = "catastrophic",
			emoji = "🦅",
			weight = 5,
			minStage = 3,
			cooldown = 4 * 60 * MIN,
			-- Выкупить акции: −45% наличных. Бороться: −50% дохода 10 мин и забастовка команды 2 мин
			a = { cashShare = 0.45 },
			b = { revenue = 0.5, revenueSeconds = 10 * MIN, walkoutSeconds = 2 * MIN },
			default = "a",
		},
		{
			id = "bankrupt",
			kind = "catastrophic",
			emoji = "🏚",
			weight = 5,
			minStage = 3,
			cooldown = 4 * 60 * MIN,
			-- Банк лопнул: −35% наличных и −30% дохода на 10 мин
			effect = { cashShare = 0.35, revenue = 0.7, revenueSeconds = 10 * MIN },
		},
	} :: { Event },
}

local byId: { [string]: Event } = {}
for _, event in CompanyEvents.list do
	byId[event.id] = event
end

function CompanyEvents.get(id: string): Event?
	return byId[id]
end

-- «12:30» / «0:25» — без слов, одинаково на всех языках
function CompanyEvents.clock(seconds: number): string
	local s = math.max(math.floor(seconds + 0.5), 0)
	return string.format("%d:%02d", s // 60, s % 60)
end

return CompanyEvents
