--!strict
-- Звуки и музыка (задача 5.6, ключи — issue #22). id = 0 — звука ещё нет, play() молчит.
-- ЛИЦЕНЗИЯ: только бесплатное аудио из Creator Store от Roblox (user 1) и лицензионных партнёров
-- Roblox — ProSoundEffects (user 7462895450) и APM Music (APMOfficial, user 7462718749). Их можно
-- ставить в любую игру. Аудио случайных авторов не берём (авторские права, приватность ассета).
-- Таблица «ключ → id → название → автор → где играет» и поисковые запросы — docs/SOUNDS.md.
-- Первые 15 ключей подобрал Dev 1 (05.11), остальные — проход «звуки» (05.11, Dev 2), проверить на слух.

export type Sound = {
	id: number,
	volume: number,
	looped: boolean?,
}

local Sounds = {}

Sounds.list = {
	-- ===== Базовые (Dev 1) =====
	click = { id = 15675032796, volume = 0.4 }, -- любая кнопка UI
	card_select = { id = 10066968815, volume = 0.4 }, -- выбор жанра или темы
	unlock = { id = 17208327798, volume = 0.6 }, -- открыли жанр или тему
	buy = { id = 10066947742, volume = 0.6 }, -- купили апгрейд
	cant_afford = { id = 17208353912, volume = 0.5 }, -- не хватает денег
	dev_start = { id = 16480577565, volume = 0.6 }, -- старт разработки
	dev_tick = { id = 16480551554, volume = 0.15 }, -- раз в несколько секунд разработки (тихо)
	critic_reveal = { id = 15675028888, volume = 0.5 }, -- открылась оценка критика
	score_low = { id = 17208214688, volume = 0.6 }, -- итог 1–4
	score_mid = { id = 17208361335, volume = 0.6 }, -- итог 5–7
	score_high = { id = 12222253, volume = 0.7 }, -- итог 8–10
	money = { id = 127645268874265, volume = 0.6 }, -- начислен доход
	record = { id = 15675043410, volume = 0.7 }, -- новый рекорд студии
	move_office = { id = 16480578036, volume = 0.8 }, -- переезд в офис

	-- ===== Музыка (looped, SoundGroup «Music»; меняется по месту игрока — SoundController) =====
	music_garage = { id = 15675069601, volume = 0.25, looped = true }, -- свой участок, этап «гараж»
	music_office = { id = 9047104752, volume = 0.22, looped = true }, -- офис, 1-й этаж (APM «Monday Morning»)
	music_floor2 = { id = 9046863579, volume = 0.22, looped = true }, -- 2-й этаж (APM «City Lights»)
	music_floor3 = { id = 9047105702, volume = 0.22, looped = true }, -- 3-й этаж (APM «Light Dreamer»)
	music_park = { id = 9047104571, volume = 0.22, looped = true }, -- парк и чужие участки (APM «Home Town Easy»)
	music_golden = { id = 9043828640, volume = 0.22, looped = true }, -- идёт Золотой час (APM «Sunshine In Hawaii»)

	-- ===== Интерфейс =====
	tab_switch = { id = 17208408337, volume = 0.35 }, -- вкладка окна (кнопка с атрибутом SoundKey)
	window_open = { id = 17208405682, volume = 0.3 }, -- открылось окно (Ui.windowOpened)
	window_close = { id = 17208186900, volume = 0.3 }, -- закрылось окно (Ui.windowClosed)
	error = { id = 17208353912, volume = 0.45 }, -- ошибка/отказ сервера
	toast = { id = 17208372272, volume = 0.3 }, -- короткое уведомление
	unlock_feature = { id = 15675016548, volume = 0.5 }, -- 🆕 открылась система (FeatureGate)
	achievement = { id = 1848016523, volume = 0.5 }, -- достижение (AchievementWindow)
	level_up = { id = 9117887138, volume = 0.5 }, -- навык сотрудника +1 (StaffFeel)
	training_start = { id = 17208323435, volume = 0.5 }, -- для агента «обучение»: старт
	training_done = { id = 9126073001, volume = 0.5 }, -- для агента «обучение»: готово
	research_start = { id = 17208399163, volume = 0.5 }, -- для агента «исследования»: старт
	research_done = { id = 1839901345, volume = 0.5 }, -- для агента «исследования»: готово

	-- ===== Экономика =====
	coin_pickup = { id = 9113849492, volume = 0.4 }, -- подобрал картридж/жука/монету
	pawn_sell = { id = 9113728756, volume = 0.5 }, -- сдал картриджи в ломбард
	payday = { id = 9113849651, volume = 0.45 }, -- выплата зарплаты команде
	tax_paid = { id = 9114026047, volume = 0.6 }, -- налог оплачен (штамп)
	bailiff_knock = { id = 9114141047, volume = 0.7 }, -- пришли приставы / забрали вещь
	theft_alarm = { id = 9113085764, volume = 0.5 }, -- у тебя крадут хит
	gift_received = { id = 15675055424, volume = 0.6 }, -- тебе подарили
	purchase_robux_thanks = { id = 17208380755, volume = 0.6 }, -- покупка за Robux прошла

	-- ===== События =====
	daily_event_start = { id = 9116395089, volume = 0.5 }, -- началось событие дня
	golden_hour = { id = 1837762485, volume = 0.5 }, -- начался Золотой час (фанфара)
	bug_catch = { id = 12222152, volume = 0.5 }, -- поймал жука
	investor_grant = { id = 9113728042, volume = 0.6 }, -- грант инвестора
	blitz_win = { id = 1837762472, volume = 0.5 }, -- победа в блиц-джеме
	company_event_good = { id = 1847213234, volume = 0.45 }, -- хорошее событие компании
	company_event_bad = { id = 1843027392, volume = 0.45 }, -- плохое событие компании

	-- ===== Мир (3D у предмета или 2D) =====
	construction_hammer = { id = 9114756156, volume = 0.5 }, -- стук молотка у строителя (3D)
	construction_done = { id = 1840076509, volume = 0.5 }, -- стройка закончена
	safe_beep = { id = 9113936355, volume = 0.4 }, -- кнопка клавиатуры сейфа
	safe_wrong = { id = 9119159511, volume = 0.4 }, -- неверный код (3D у сейфа)
	safe_open = { id = 9045298695, volume = 0.6 }, -- сейф открыт (3D у сейфа)
	elevator_ding = { id = 9114302479, volume = 0.6 }, -- лифт поехал (3D у пульта)
	door = { id = 9114150997, volume = 0.5 }, -- вошёл на свой участок / вышел
	rebirth_whoosh = { id = 9125805579, volume = 0.7 }, -- Rebirth
	confetti_pop = { id = 9113263649, volume = 0.5 }, -- хлопушка конфетти (MoveCelebration)
	mascot_squeak = { id = 9120222027, volume = 0.5 }, -- взял маскота
	qte_hit = { id = 15675059323, volume = 0.5 }, -- быстрое событие: хорошо
	qte_miss = { id = 15675062723, volume = 0.5 }, -- быстрое событие: промах
	qte_perfect = { id = 9126073318, volume = 0.55 }, -- быстрое событие: идеально
	stock_buy = { id = 9113728625, volume = 0.5 }, -- купил акции
	stock_sell = { id = 9113849445, volume = 0.5 }, -- продал акции
	ipo_bell = { id = 9125485591, volume = 0.7 }, -- вышел на биржу
	console_stage_done = { id = 1840076509, volume = 0.5 }, -- этап своей консоли готов
	console_launched = { id = 1836473422, volume = 0.5 }, -- консоль вышла (фанфара)
} :: { [string]: Sound }

-- Тайминги звуков, привязанных к событиям
Sounds.devTickInterval = 4 -- пауза между dev_tick во время разработки, секунд
Sounds.criticRevealDelay = 0.6 -- совпадает с REVEAL_DELAY в ReleaseWindow
Sounds.scoreLowMax = 4 -- итог 1..4 — score_low
Sounds.scoreMidMax = 7 -- 5..7 — score_mid, выше — score_high
Sounds.moneyDelay = 0.4 -- пауза между итогом и звуком денег

-- Антиспам: не чаще раза в N секунд для ключа (нет в списке — defaultThrottle)
Sounds.defaultThrottle = 0.08
Sounds.throttle = {
	coin_pickup = 0.125, -- не больше 8 в секунду
	toast = 0.5,
	error = 0.3,
	window_open = 0.15,
	window_close = 0.15,
	bailiff_knock = 2,
	theft_alarm = 3,
	door = 3,
	payday = 1,
} :: { [string]: number }

-- 3D-звуки (playAt): слышно в радиусе rollOffMax, дальше hearDistance от игрока — не играем вовсе
Sounds.rollOffMin = 8
Sounds.rollOffMax = 60
Sounds.hearDistance = 80

-- Эмиттеры в мире: деталь с тегом CollectionService «SoundEmitter» и атрибутом SoundKey
-- (необязательно SoundMin/SoundMax — пауза, сек) стучит этим звуком, пока игрок рядом.
Sounds.emitterTag = "SoundEmitter"
Sounds.emitterMin = 0.6 -- молоток строителя: раз в 0.6–1.5 с
Sounds.emitterMax = 1.5

-- Музыка: как часто проверяем место игрока и сколько длится перекрёстное затухание
Sounds.musicCheckInterval = 1
Sounds.musicFade = 1.5

return Sounds
