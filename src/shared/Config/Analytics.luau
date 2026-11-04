--!strict
-- Аналитика для запуска (задача 6.4): онбординг-воронка, экономика, редкие кастомные события.
-- Отправляет только сервер (AnalyticsService). Roblox принимает события лишь с опубликованного
-- сервера: в Studio при debugPrint события печатаются в Output и никуда не уходят.
-- Имена шагов и событий меняем осторожно: дашборд склеивает данные по именам.

export type OnboardingStep = {
	id: string, -- ключ в (profile :: any).analytics.onboarding и в детекторе AnalyticsService
	name: string, -- имя шага в Creator Dashboard → Analytics → Funnels → Onboarding
}

-- Как подписать деньги в Economy: transactionType — категория, sku — конкретика
export type EconomyTag = {
	transactionType: string,
	sku: string,
}

local Analytics = {
	enabled = true,
	-- Печатать события в Output. В Studio — вместо отправки; на живом сервере — только если debugPrintLive
	debugPrint = true,
	debugPrintLive = false,

	-- Опрос профилей (шаги онбординга, Rebirth, кражи, язык), секунд
	pollSeconds = 2.5,
	-- Экономика копится по игроку и уходит сводкой раз в столько секунд (и при выходе)
	economyFlushSeconds = 60,
	-- Свой бюджет событий в минуту на сервер. Лимит Roblox ≈ 120 + 20 × игроков, держимся вдвое ниже.
	-- Не влезло: экономика ждёт следующей сводки, шаг онбординга — следующего опроса
	budgetBase = 60,
	budgetPerPlayer = 10,

	currency = "Cash",

	-- Порядок = номер шага (1…9). Шаги логируются один раз за жизнь игрока
	onboarding = {
		{ id = "joined", name = "Joined" },
		{ id = "laptop", name = "Sat At Laptop" },
		{ id = "firstRelease", name = "First Game Released" },
		{ id = "firstParkJob", name = "First Job Or Cartridge" },
		{ id = "garage", name = "Garage Bought" },
		{ id = "studioNamed", name = "Studio Named" },
		{ id = "firstUpgrade", name = "First Upgrade" },
		{ id = "firstEmployee", name = "First Employee" },
		{ id = "office", name = "Office" },
	} :: { OnboardingStep },

	-- Кастомные события (Analytics → Custom events). Всего до 100 имён на игру — новые не плодить
	events = {
		rebirth = "Rebirth",
		hitStolen = "HitStolen", -- вор донёс чужой картридж
		thiefCaught = "ThiefCaught", -- вора поймали (событие на вора)
		expoWin = "ExpoWin",
		gamePass = "GamePassPurchased",
		product = "ProductPurchased",
		languageChanged = "LanguageChanged", -- не чаще раза за сессию
		quickEvent = "QuickEvent", -- быстрое событие разработки; поле — "вид_результат" (timing_perfect)
		achievement = "Achievement", -- получено достижение; поле — id
		gift = "GiftPurchased", -- подарок за Robux; поле — gift_<id>, значение 1 — другу, 0 — достался себе
		groupReward = "GroupReward", -- награда за вступление в группу
		offer = "Offer", -- предложение доната; поле — "вид_этап" (starterPack_shown, floorLock_purchased)
		seizure = "BailiffSeizure", -- приставы забрали предмет за долг; поле — id, значение — выручка
		code = "CodeRedeemed", -- активирован промокод; поле — код
		mascot = "MascotPurchased", -- маскот куплен; поле — "id_cash" / "id_robux"
		-- событие компании; поле — "id_этап": shown/insured (сработало), a/b/auto_a (выбор),
		-- win/lose (риск), repaired, insurance_bought
		companyEvent = "CompanyEvent",
		seasonTier = "SeasonTier", -- новый уровень сезона; значение — уровень, поле — источник опыта
		seasonClaim = "SeasonClaim", -- награда сезона; поле — "дорожка_уровень" (free_5, premium_30)
		jamSubmit = "JamSubmit", -- заявка в гейм-джем; значение — оценка, поле — first / improved
		hackathon = "Hackathon", -- начался хакатон (на каждого игрока на сервере)
		-- Франшизы и контракты: поле — этап (created; offered/accepted/declined/expired/completed/failed)
		-- или id обогнанной студии
		franchise = "Franchise",
		contract = "Contract",
		rivalPassed = "RivalPassed",
		-- Совместная разработка и холдинги: поле — этап (invited/accepted/split/noSplit/ended_*;
		-- created/joined/left/goal_N)
		coop = "Coop",
		holding = "Holding",
		-- Консоль и стример: платформа релиза (значение — оценка, поле — pc/phone/console),
		-- этап консоли (значение — номер, поле — "design_started" / "launch_done"),
		-- стример (поле — assigned / unassigned, значение при снятии — заработано донатами)
		platform = "Platform",
		console = "Console",
		streamer = "Streamer",
		arcade = "Arcade", -- мини-аркада после релиза; поле — "вид_этап" (whack_start, lanes_gold, jump_none)
		-- Уведомления, друзья, обмен: поле — этап; у обмена значение — число предметов
		notifyPrompt = "NotifyPrompt", -- shown / unavailable
		referral = "Referral", -- joined_<источник> / new / inviter / inviter_capped / invite_sent
		trade = "Trade", -- started / done / cancelled
	},

	-- Источники денег: ключ — сервис, вызвавший DataService.addCash, или "Сервис.функция".
	-- RewardService — посредник: категорию берём по тому, кто вызвал его (задания или ежедневка)
	sources = {
		DevelopmentService = { transactionType = "GameRelease", sku = "release" },
		HitService = { transactionType = "HitIncome", sku = "shelf" },
		["HitService.caught"] = { transactionType = "ThiefCatch", sku = "penalty" },
		ExpoService = { transactionType = "Expo", sku = "prize" },
		QuestService = { transactionType = "Quest", sku = "quest" },
		AchievementService = { transactionType = "Achievement", sku = "achievement" },
		DailyRewardService = { transactionType = "TimedReward", sku = "daily" },
		OfflineService = { transactionType = "TimedReward", sku = "offline" },
		["StartParkService.onJobFinish"] = { transactionType = "ParkJob", sku = "job" },
		["StartParkService.onPawn"] = { transactionType = "Pawnshop", sku = "cartridges" },
		ShopService = { transactionType = "IAP", sku = "incomePack" },
		OfferService = { transactionType = "IAP", sku = "offer" },
		TutorialService = { transactionType = "Onboarding", sku = "tutorial" },
		SocialService = { transactionType = "TimedReward", sku = "group" },
		BailiffService = { transactionType = "Seizure", sku = "bailiffs" }, -- продажа предмета за долг
		CodeService = { transactionType = "TimedReward", sku = "code" },
		CompanyEventService = { transactionType = "CompanyEvent", sku = "event" },
		SeasonService = { transactionType = "Season", sku = "season" },
		GameJamService = { transactionType = "GameJam", sku = "jam" },
		ContractService = { transactionType = "Contract", sku = "contract" },
		RivalService = { transactionType = "Reward", sku = "rivalPassed" },
		CoopService = { transactionType = "Coop", sku = "coopShare" }, -- доля гостя совместной игры
		HoldingService = { transactionType = "Reward", sku = "holdingGoal" }, -- цели недели холдинга
		ConsoleService = { transactionType = "Console", sku = "royalty" },
		StreamerService = { transactionType = "Streamer", sku = "donations" },
		ArcadeService = { transactionType = "Reward", sku = "arcade" },
		ReferralService = { transactionType = "TimedReward", sku = "referral" },
	} :: { [string]: EconomyTag },
	-- Посредники: смотреть на уровень выше по стеку
	passthrough = { RewardService = true } :: { [string]: boolean },
	-- Не экономика (отладочные деньги в Studio)
	ignore = { DebugService = true } :: { [string]: boolean },

	-- Траты определяются по тому, что изменилось в профиле сразу после списания
	-- (новый апгрейд, жанр, сотрудник, этап, реклама); категории:
	sinks = {
		upgrade = "Upgrade",
		move = "Move", -- гараж, офис, этаж, небоскрёб
		content = "Content", -- жанры и темы
		staff = "Staff",
		ad = "Ad",
		penalty = "ThiefPenalty", -- штраф пойманного вора
		decor = "Decor", -- декор студии (DecorService), sku — ключ покупки id@этаж
		skin = "Skin", -- скины сотрудников за $ (SkinService), sku — id скина
		mascot = "Mascot", -- маскоты за $ (MascotService), sku — id маскота
		companyEvent = "CompanyEvent", -- потери от событий компании, страховка и починка
		other = "Other",
	},
}

return Analytics
