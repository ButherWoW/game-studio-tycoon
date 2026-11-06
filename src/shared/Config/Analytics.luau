--!strict
-- Аналитика для запуска (задача 6.4): онбординг-воронка, экономика, редкие кастомные события.
-- Отправляет только сервер (AnalyticsService). Roblox принимает события лишь с опубликованного
-- сервера: в Studio при debugPrint события печатаются в Output и никуда не уходят.
-- Имена шагов и событий меняем осторожно: дашборд склеивает данные по именам.

export type OnboardingStep = {
	id: string, -- ключ детектора в AnalyticsService
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

	-- Порядок = номер шага (1…12) в Funnels → Onboarding. Шаги строго по порядку и один раз за жизнь
	-- игрока: в профиле хранится номер последнего отправленного шага ((profile :: any).analytics.funnel).
	-- Достигнут шаг N — значит, пройдены и все до него (пропущенные дошлём перед ним тем же опросом).
	-- Название студии вводится только после покупки гаража, найм возможен уже в гараже (Мила) —
	-- поэтому они стоят после «Garage Bought» и до офиса. Меняем имена/порядок только до запуска
	onboarding = {
		{ id = "joined", name = "Joined" },
		{ id = "park", name = "Laptop Or Park Job" }, -- сел за ноутбук в парке, заказ с доски или ломбард
		{ id = "firstGameStarted", name = "First Game Started" },
		{ id = "firstRelease", name = "First Game Released" },
		{ id = "garage", name = "Garage Bought" },
		{ id = "studioNamed", name = "Studio Named" },
		{ id = "firstHire", name = "First Hire" },
		{ id = "officeStarted", name = "Office Construction Started" },
		{ id = "office", name = "Office Reached" },
		{ id = "floor2", name = "Floor 2 Reached" },
		{ id = "floor3", name = "Floor 3 Reached" },
		{ id = "rebirth", name = "First Rebirth" },
	} :: { OnboardingStep },

	-- Кастомные события (Analytics → Custom events). Всего до 100 имён на игру — новые не плодить
	events = {
		rebirth = "Rebirth",
		hitStolen = "HitStolen", -- вор донёс чужой картридж
		thiefCaught = "ThiefCaught", -- вора поймали (событие на вора)
		expoWin = "ExpoWin",
		gamePass = "GamePassPurchased",
		-- Developer Product выдан (MonetizationService.processReceipt): поле — ключ товара
		-- (income30, ad_tv, deal_coffee, gift_<id>…), значение — цена в Robux из Config (0 — цена не указана)
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
		furnitureStyle = "FurnitureStylePurchased", -- стиль мебели куплен; поле — "id_cash" / "id_robux"
		interiorFinish = "InteriorFinishPurchased", -- отделка студии куплена за Robux; поле — id
		-- событие компании; поле — "id_этап": shown/insured (сработало), a/b/auto_a (выбор),
		-- win/lose (риск), repaired, insurance_bought
		companyEvent = "CompanyEvent",
		seasonTier = "SeasonTier", -- новый уровень сезона; значение — уровень, поле — источник опыта
		seasonClaim = "SeasonClaim", -- награда сезона; поле — "дорожка_уровень" (free_5, premium_30)
		jamSubmit = "JamSubmit", -- заявка в гейм-джем; значение — оценка, поле — first / improved
		hackathon = "Hackathon", -- начался хакатон (на каждого игрока на сервере)
		-- События дня (DailyEventService): поле — "id_этап" (bugHunt_start, golden_start, investors_grant,
		-- bugHunt_caught — значение: сколько поймал, blitzJam_win — значение: оценка)
		dailyEvent = "DailyEvent",
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
		-- этап консоли (значение — номер этапа, поле — "<этап>_started" / "<этап>_done" /
		-- "<этап>_skip"; покупка оборудования — "equip_<id>", значение — цена; Robux-ускорение —
		-- "speed_<consoleSpeed5|consoleSpeed30|consoleSkip>"),
		-- стример (поле — assigned / unassigned, значение при снятии — заработано донатами)
		platform = "Platform",
		console = "Console",
		streamer = "Streamer",
		arcade = "Arcade", -- мини-аркада после релиза; поле — "вид_этап" (whack_start, lanes_gold, jump_none)
		-- Уведомления, друзья, обмен: поле — этап; у обмена значение — число предметов
		notifyPrompt = "NotifyPrompt", -- shown / unavailable
		referral = "Referral", -- joined_<источник> / new / inviter / inviter_capped / invite_sent
		trade = "Trade", -- started / done / cancelled
		-- Налоговая и биржа (TaxService, StockService): поле — этап, значение — сумма
		tax = "Tax", -- billed / paid / fined
		stock = "Stock", -- ipo / buy / sell / dividend / bankrupt
		-- Сейф в парке (SafeService): поле — ok / wrong / slow / empty; бонус возвращения (ComebackService):
		-- значение — дней не было, поле — shown / claimed
		safe = "SafeAttempt",
		comeback = "Comeback",
		-- Лаборатория (ResearchService, Config/Research.TIMING): поле — "этап_вид_id"
		-- (start/finish/cancel/rebirth; вид node/genre/topic) или "skip_<товар>_вид_id" / "skip_<товар>_credit"
		research = "Research",
		-- Стройка этапа (ConstructionService): поле — "этап_этап" (office_start, floor_finish,
		-- skyscraper_cancel, office_buildSkip — значение: сколько секунд оставалось; buildSpeed5_fallback)
		construction = "Construction",
		-- Фанаты студии (FansService, Config/Fans): значение — на сколько изменилось (по модулю),
		-- поле — "источник_знак": release_gain / release_loss, expo_place1_gain (победа), expo_place2_gain,
		-- expo_place3_gain, expo_high_gain, rebirth_loss
		fans = "Fans",
	},

	-- ===== Экономика (Analytics → Economy) =====
	-- transactionType — только стандартные имена Enum.AnalyticsEconomyTransactionType (по ним дашборд
	-- строит разрезы): IAP, Shop, Gameplay, TimedReward, Onboarding, ContextualPurchase.
	-- sku (itemSKU) — система в camelCase, без id предметов: id идёт в CustomField02 (их сотни).
	-- Исключение — IAP: sku = ключ товара из Config (income30, researchSkip, ad_tv, deal_coffee…), чтобы видеть
	-- выдачу по каждому товару. Возвраты — sku с префиксом refund.
	-- CustomField01 — этап студии (stage1…stage4), CustomField02 — предмет (если есть).

	-- Источники: ключ — сервис, вызвавший DataService.addCash, или "Сервис.функция" (точнее).
	-- Посредник RewardService: ключ ищем по тому, кто вызвал его (тоже "Сервис.функция" или "Сервис").
	-- Всё, что выдано внутри ProcessReceipt (MonetizationService), — IAP с ключом товара, без таблицы
	sources = {
		DevelopmentService = { transactionType = "Gameplay", sku = "gameRelease" },
		HitService = { transactionType = "Gameplay", sku = "hitShelf" }, -- полка хитов
		["HitService.caught"] = { transactionType = "Gameplay", sku = "thiefPenalty" }, -- жертве от вора
		ExpoService = { transactionType = "Gameplay", sku = "expo" },
		QuestService = { transactionType = "Gameplay", sku = "quest" },
		AchievementService = { transactionType = "Gameplay", sku = "achievement" },
		["StartParkService.onJobFinish"] = { transactionType = "Gameplay", sku = "parkJob" },
		["StartParkService.onPawn"] = { transactionType = "Gameplay", sku = "pawnshop" },
		BailiffService = { transactionType = "Gameplay", sku = "bailiffSale" }, -- продажа предмета за долг
		CompanyEventService = { transactionType = "Gameplay", sku = "companyEvent" },
		SeasonService = { transactionType = "Gameplay", sku = "season" },
		GameJamService = { transactionType = "Gameplay", sku = "gameJam" },
		["ContractService.onRespond"] = { transactionType = "Gameplay", sku = "contractAdvance" },
		["ContractService.finish"] = { transactionType = "Gameplay", sku = "contractBonus" },
		ContractService = { transactionType = "Gameplay", sku = "contractBonus" },
		RivalService = { transactionType = "Gameplay", sku = "rivalPassed" },
		CoopService = { transactionType = "Gameplay", sku = "coopShare" }, -- доля гостя совместной игры
		HoldingService = { transactionType = "Gameplay", sku = "holdingGoal" }, -- цели недели холдинга
		["HoldingService.onCreate"] = { transactionType = "Gameplay", sku = "refundHolding" },
		ConsoleService = { transactionType = "Gameplay", sku = "consoleRoyalty" },
		StreamerService = { transactionType = "Gameplay", sku = "streamer" },
		ArcadeService = { transactionType = "Gameplay", sku = "arcade" },
		["StockService.sell"] = { transactionType = "Gameplay", sku = "stockSell" },
		["StockService.dividends"] = { transactionType = "Gameplay", sku = "dividend" },
		["StockService.onIpo"] = { transactionType = "Gameplay", sku = "refundIpo" },
		StockService = { transactionType = "Gameplay", sku = "stockSell" },
		SafeService = { transactionType = "Gameplay", sku = "safe" }, -- приз сейфа в парке
		GotwService = { transactionType = "Gameplay", sku = "gotw" }, -- «Игра недели»
		TourService = { transactionType = "Gameplay", sku = "tours" },
		HolidayService = { transactionType = "Gameplay", sku = "holiday" },
		PerksService = { transactionType = "Gameplay", sku = "publishingRoyalty" }, -- «Издательство»
		LoanService = { transactionType = "Gameplay", sku = "loan" }, -- взятый кредит
		-- События дня (DailyEventService через RewardService)
		["DailyEventService.onCatch"] = { transactionType = "Gameplay", sku = "dailyBugCatch" },
		["DailyEventService.finishBugHunt"] = { transactionType = "Gameplay", sku = "dailyBugHunt" },
		["DailyEventService.onInvestor"] = { transactionType = "Gameplay", sku = "dailyInvestor" },
		["DailyEventService.finishBlitz"] = { transactionType = "Gameplay", sku = "dailyBlitz" },
		DailyEventService = { transactionType = "Gameplay", sku = "dailyEvent" },
		-- Возвраты
		ResearchService = { transactionType = "Gameplay", sku = "refundResearch" }, -- отмена открытия за $
		StaffService = { transactionType = "Gameplay", sku = "refundFire" }, -- увольнение с возвратом
		-- По таймеру и «за вход»
		DailyRewardService = { transactionType = "TimedReward", sku = "dailyReward" },
		OfflineService = { transactionType = "TimedReward", sku = "offline" },
		ComebackService = { transactionType = "TimedReward", sku = "comeback" },
		SocialService = { transactionType = "TimedReward", sku = "groupReward" },
		CodeService = { transactionType = "TimedReward", sku = "promoCode" },
		ReferralService = { transactionType = "TimedReward", sku = "referral" },
		TutorialService = { transactionType = "Onboarding", sku = "tutorial" },
		-- Выдачи за Robux вне ProcessReceipt не бывают; на всякий случай — IAP без ключа товара
		ShopService = { transactionType = "IAP", sku = "incomePack" },
		OfferService = { transactionType = "IAP", sku = "offer" },
		GiftService = { transactionType = "IAP", sku = "giftFallback" },
		ConstructionService = { transactionType = "IAP", sku = "buildSpeedFallback" },
	} :: { [string]: EconomyTag },
	-- Посредники: смотреть на уровень выше по стеку
	passthrough = { RewardService = true } :: { [string]: boolean },
	-- Не экономика (отладочные деньги в Studio)
	ignore = { DebugService = true } :: { [string]: boolean },

	-- Траты: ключ — "Сервис.функция" или "Сервис" (кто вызвал trySpend / charge). Покупки в
	-- PlotService (гараж, апгрейд, стройка, переезд) и найм различаем по изменению профиля — см.
	-- classifySpend в AnalyticsService; CustomField02 — id предмета
	sinks = {
		-- Магазин: постоянные покупки
		garage = { transactionType = "Shop", sku = "garage" },
		upgrade = { transactionType = "Shop", sku = "upgrade" },
		move = { transactionType = "Shop", sku = "move" }, -- переезд без стройки
		construction = { transactionType = "Shop", sku = "construction" }, -- оплата стройки офиса/этажа
		hire = { transactionType = "Shop", sku = "hire" },
		ad = { transactionType = "Shop", sku = "adCampaign" }, -- реклама за $
		DecorService = { transactionType = "Shop", sku = "decor" },
		SkinService = { transactionType = "Shop", sku = "skin" },
		MascotService = { transactionType = "Shop", sku = "mascot" },
		FurnitureStyleService = { transactionType = "Shop", sku = "furnitureStyle" },
		PosterService = { transactionType = "Shop", sku = "poster" },
		["ConsoleService.onEquip"] = { transactionType = "Shop", sku = "consoleEquipment" },
		["CompanyEventService.onBuyInsurance"] = { transactionType = "Shop", sku = "insurance" },
		MonetizationService = { transactionType = "Shop", sku = "adCampaign" },
		-- Покупки «по ходу дела»
		ResearchService = { transactionType = "ContextualPurchase", sku = "research" },
		["StaffService.onUpgradeSkill"] = { transactionType = "ContextualPurchase", sku = "training" },
		["StaffService.onSetPerk"] = { transactionType = "ContextualPurchase", sku = "staffPerk" },
		["ConsoleService.onStage"] = { transactionType = "ContextualPurchase", sku = "consoleStage" },
		["HitService.onRequestUpdate"] = { transactionType = "ContextualPurchase", sku = "hitUpdate" },
		["CompanyEventService.onRepair"] = { transactionType = "ContextualPurchase", sku = "repair" },
		-- Обязательные расходы и игровые потери
		["ExpensesService.paySalary"] = { transactionType = "Gameplay", sku = "salary" },
		ExpensesService = { transactionType = "Gameplay", sku = "rent" },
		["TaxService.onPay"] = { transactionType = "Gameplay", sku = "tax" },
		TaxService = { transactionType = "Gameplay", sku = "taxFine" },
		CompanyEventService = { transactionType = "Gameplay", sku = "companyEventLoss" },
		HitService = { transactionType = "Gameplay", sku = "thiefPenalty" }, -- штраф пойманного вора
		["StockService.buy"] = { transactionType = "Gameplay", sku = "stockBuy" },
		["StockService.onIpo"] = { transactionType = "Gameplay", sku = "ipo" },
		StockService = { transactionType = "Gameplay", sku = "stockBuy" },
		HoldingService = { transactionType = "Gameplay", sku = "holdingCreate" },
		LoanService = { transactionType = "Gameplay", sku = "loanRepay" },
	} :: { [string]: EconomyTag },
	-- Не нашли категорию: Gameplay / other<Сервис> (видно в дашборде — сразу дописать сюда)
	otherTransactionType = "Gameplay",
}

return Analytics
