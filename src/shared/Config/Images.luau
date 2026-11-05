--!strict
-- Картинки интерфейса (docs/VISUAL.md, V3). id = 0 — картинки ещё нет, кнопка показывает эмодзи.
-- Dev 1: загрузить PNG из docs/visual/astra-2026-11-04/V3 в Creator Hub → Development Items →
-- Decals/Images и вставить сюда Image ID (не Decal ID!) напротив имени файла.

local Images = {}

Images.menu = {
	menu_research = 111519993777789, -- menu_research.png, 🔬
	menu_team = 77230608397075, -- menu_team.png, 👥
	menu_quests = 136993744510245, -- menu_quests.png, 📋
	menu_shop = 137630997422818, -- menu_shop.png, 🛒
	menu_rebirth = 93873527228508, -- menu_rebirth.png, ♻️
	menu_language = 126564198254913, -- menu_language.png, 🌐
	menu_hits = 113373317118331, -- menu_hits.png, 🔒
	menu_thieves = 92220236077266, -- menu_thieves.png, 😈
	menu_holiday = 108939585178579, -- menu_holiday.png, 🎉
	menu_camera = 113053777664719, -- menu_camera.png, 🎥
	menu_bank = 82427982778270, -- menu_bank.png, 🏦
	menu_achievements = 97631283620169, -- menu_achievements.png, 🏆 (V10)
	menu_studio = 127200595653936, -- menu_studio.png, 🛋️ (окно «Студия»: декор и настроение)
	home = 112336651662592, -- home.png, 🏠
} :: { [string]: number }

-- Постеры магазина (docs/VISUAL.md, V8; Config/Posters). 0 — картинки ещё нет: постер рисуется
-- цветом, эмодзи и названием. Dev 1: загрузить poster_<id>.png (768×1024) так же, как иконки
-- меню, и вставить Image ID напротив id постера
Images.posters = {
	pixelHero = 125799592519740, -- poster_pixelHero.png
	puzzleBlocks = 124079163255858, -- poster_puzzleBlocks.png
	turboRacer = 137373149436998, -- poster_turboRacer.png
	starBlaster = 139118042720776, -- poster_starBlaster.png
	ninjaCat = 78345176584706, -- poster_ninjaCat.png
	ghostManor = 125688331125992, -- poster_ghostManor.png
	robotArena = 83554589844882, -- poster_robotArena.png
	dragonValley = 139344957694595, -- poster_dragonValley.png
	neonCity = 96784967978775, -- poster_neonCity.png, премиум
	crystalKingdom = 85457514580817, -- poster_crystalKingdom.png, премиум
	mechTitan = 140307562859835, -- poster_mechTitan.png, премиум
	galaxyLegends = 87137781625902, -- poster_galaxyLegends.png, премиум
	goldenController = 139514087995847, -- poster_goldenController.png, премиум
} :: { [string]: number }

-- Медали достижений (V10, Астра #88): окно 🏆 вместо 🥉🥈🥇
Images.medals = {
	bronze = 71752753521866, -- medal_bronze.png
	silver = 95715963709982, -- medal_silver.png
	gold = 70516815676378, -- medal_gold.png
} :: { [string]: number }

-- Скины сотрудников (docs/VISUAL.md, V12; Config/Skins). 0 — картинки ещё нет: NPC красится
-- запасными цветами скина, в магазине — цветная карточка с эмодзи.
-- Dev 1: из docs/visual/astra-2026-11-05-skins/batch-1..3/V12 загрузить skin_<id>_shirt.png и
-- skin_<id>_pants.png (шаблоны 585×559) и skin_<id>_preview.png (512×512) как Images и вставить
-- Image ID (не Decal ID!) в shirt / pants / preview напротив id скина
Images.skins = {
	hoodie_coder = { shirt = 116925253396107, pants = 77040404351690, preview = 71584634617700 },
	pixel_artist = { shirt = 134341234705476, pants = 110913800554979, preview = 101781629414715 },
	sound_nerd = { shirt = 140584770538068, pants = 114882087803012, preview = 126279785622105 },
	writer = { shirt = 94386345570626, pants = 91319320361436, preview = 72542131784416 },
	intern = { shirt = 113270813059869, pants = 120755267901010, preview = 111233561221579 },
	bug_hunter = { shirt = 131441530857371, pants = 81481283222694, preview = 79545807894976 },
	speedrunner = { shirt = 103872155513441, pants = 109156030900915, preview = 96464281028661 },
	retro_gamer = { shirt = 119464023103825, pants = 138364891743589, preview = 82631326828501 },
	neon_streamer = { shirt = 73791546129249, pants = 74152800336888, preview = 120378517314886 }, -- премиум
	cyber_dev = { shirt = 82642398146223, pants = 130561786132954, preview = 137475696575517 }, -- премиум
	space_dev = { shirt = 88596041155611, pants = 121217414786209, preview = 87409951657588 }, -- премиум
	wizard_dev = { shirt = 133948528089059, pants = 84656926980640, preview = 128736905194190 }, -- премиум
} :: { [string]: { shirt: number, pants: number, preview: number } }

-- VIP (docs/VISUAL.md, V14): vip_crown.png из docs/visual/astra-2026-11-05-vip/V14 — текстура
-- искр над золотой вывеской и корона 👑 в интерфейсе (табличка VIP, выбор получателя подарка,
-- геймпасс «VIP-офис» в магазине). 0 — стандартная искра Roblox и эмодзи 👑
Images.vip = 0

-- Маскоты (docs/VISUAL.md, V16; Config/Mascots). 0 — иконки ещё нет: на карточке эмодзи.
-- Dev 1: загрузить mascot_<id>_icon.png (256×256) как Image и вставить Image ID напротив id
Images.mascots = {
	pixel_cat = 0,
	bug_beetle = 0,
	coffee_cup = 0,
	floppy_dog = 0,
	cloud_ghost = 0,
	controller_bunny = 0,
	robo_owl = 0,
	slime_star = 0,
	neon_fox = 0,
	dragon_byte = 0,
	golden_trophy = 0,
	cosmic_whale = 0,
} :: { [string]: number }

-- Награда за вход (docs/visual/astra-2026-11-05-daily/V17; окно DailyRewardWindow), 0 — плитки цветом и эмодзи
Images.daily = {
	boardBg = 0, -- daily_board_bg.png (1200×700), фон окна
	cardNormal = 0, -- daily_card_normal.png (256×320), завтрашний день
	cardToday = 0, -- daily_card_today.png, сегодняшний день
	cardClaimed = 0, -- daily_card_claimed.png, уже забранные дни
	cardLocked = 0, -- daily_card_locked.png, дни после завтрашнего
	rewardCash = 0, -- reward_cash.png (256×256), деньги и реклама
	rewardCoffee = 0, -- reward_coffee.png, кофе
	rewardResearch = 0, -- reward_research.png, очки исследований
	rewardSkin = 0, -- reward_skin.png, скин
	rewardBig = 0, -- reward_big.png, большая награда (несколько сразу, кубок, постер, маскот)
	streakFlame = 0, -- daily_streak_flame.png (128×128), у заголовка окна
} :: { [string]: number }

-- Сезон, гейм-джем, хакатон, студии, коды (docs/visual/astra-2026-11-05-social/V18), 0 — как раньше: эмодзи и цвет
Images.social = {
	seasonBanner = 0, -- season_banner.png (1600×400), шапка вкладки «Сезон»
	gamejamBanner = 0, -- gamejam_banner.png (1600×400), шапка вкладки «Гейм-джем»
	hackathonBanner = 0, -- hackathon_banner.png (1600×300), над плашкой хакатона
	seasonTierFree = 0, -- season_tier_free.png, рамка иконки бесплатной награды уровня
	seasonTierPremium = 0, -- season_tier_premium.png, рамка иконки премиум-награды уровня
	seasonPremiumBadge = 0, -- season_premium_badge.png, вместо ⭐ у «Премиум»
	gamejamMedalTop10 = 0, -- gamejam_medal_top10.png, отметка «Топ-10 джема»
	gamejamMedalTop100 = 0, -- gamejam_medal_top100.png, отметка «Топ-100 джема»
	iconLike = 0, -- icon_like.png, вместо 👍 в окне «Студии»
	iconVisit = 0, -- icon_visit.png, на кнопке «Посетить»
	iconLeaderboard = 0, -- icon_leaderboard.png, вместо 🏆 у вкладки «Рейтинги»
	iconCodes = 0, -- icon_codes.png, вместо 🎟 у кнопки и окна «Коды»
	menuGamejam = 0, -- menu_gamejam.png, вместо 🎮 у вкладки «Гейм-джем»
} :: { [string]: number }

-- Кнопки меню V18: ключи, которые уже передают Ui.menuButton окна «Студии» и «Сезон»
Images.menu.menu_tours = 0 -- menu_studios.png, 🏘 (слот 15)
Images.menu.menu_season = 0 -- menu_season.png, 🎫 (слот 16), и вкладка «Сезон»

-- События компании (docs/VISUAL.md, V19; Config/CompanyEvents). 0 — иконки ещё нет: на карточке
-- события эмодзи. Dev 1: из docs/visual/astra-2026-11-05-events/events-1/V19 и events-2/V19
-- загрузить cev_<id>.png как Image и вставить Image ID напротив id события
Images.events = {
	angel = 0, -- cev_angel.png (events-1)
	streamer = 0, -- cev_streamer.png (events-1)
	award = 0, -- cev_award.png (events-1)
	conference = 0, -- cev_conference.png (events-1)
	grant = 0, -- cev_grant.png (events-1)
	donations = 0, -- cev_donations.png (events-1)
	luckybug = 0, -- cev_luckybug.png (events-1)
	hype = 0, -- cev_hype.png (events-1)
	crash = 0, -- cev_crash.png (events-1)
	leak = 0, -- cev_leak.png (events-1)
	flood = 0, -- cev_flood.png (events-1)
	audit = 0, -- cev_audit.png (events-2)
	outage = 0, -- cev_outage.png (events-2)
	reviewbomb = 0, -- cev_reviewbomb.png (events-2)
	burnout = 0, -- cev_burnout.png (events-2)
	lawsuit = 0, -- cev_lawsuit.png (events-2)
	poach = 0, -- cev_poach.png (events-2)
	rush = 0, -- cev_rush.png (events-2)
	sponsor = 0, -- cev_sponsor.png (events-2)
	gamble = 0, -- cev_gamble.png (events-2)
	takeover = 0, -- cev_takeover.png (events-2)
	bankrupt = 0, -- cev_bankrupt.png (events-2)
} :: { [string]: number }

-- Логотипы студий-конкурентов (V19; Config/Rivals). 0 — логотипа нет: эмодзи студии.
-- Dev 1: из docs/visual/astra-2026-11-05-events/rivals загрузить rival_<id>.png как Image
Images.rivals = {
	tinfoilOwl = 0, -- rival_tinfoilOwl.png
	mangoComet = 0, -- rival_mangoComet.png
	quokkaPixel = 0, -- rival_quokkaPixel.png
	gloomberry = 0, -- rival_gloomberry.png
	brassfern = 0, -- rival_brassfern.png
	velvetAnvil = 0, -- rival_velvetAnvil.png
	nimbusTurtle = 0, -- rival_nimbusTurtle.png
	okraLantern = 0, -- rival_okraLantern.png
	bluemoth = 0, -- rival_bluemoth.png
} :: { [string]: number }

-- Монетизация (V14; docs/visual/astra-2026-11-05-vip/V14). 0 — картинки нет: как раньше, эмодзи.
-- Корона vip_crown.png — это Images.vip выше
Images.monetization = {
	gift = 0, -- gift_icon.png (256×256): кнопка «🎁 Подарить» и окно выбора получателя
	deal = 0, -- deal_badge.png (256×256, на картинке «-30%»): «Сделка дня» в магазине
	starterBanner = 0, -- starter_pack_banner.png (1024×512): окно стартового набора
	groupBanner = 0, -- group_banner.png (1024×512): подсказка «Вступи в группу» во вкладке скинов
} :: { [string]: number }

-- Контракты, приставы, франшизы (V19 часть 3; docs/visual/astra-2026-11-05-events/contracts-bailiff/V19).
-- 0 — картинки нет: как раньше, эмодзи (📜 ⚖️ 📚) и костюм пристава из деталей.
-- Dev 1: bailiff_shirt/bailiff_pants (шаблоны одежды 585×559) загрузить как Shirt/Pants
-- (Classic Clothing), остальные — как Image, и вставить ID
Images.contracts = {
	bailiffShirt = 0, -- bailiff_shirt.png: ShirtTemplate NPC-пристава (BailiffService)
	bailiffPants = 0, -- bailiff_pants.png: PantsTemplate NPC-пристава (BailiffService)
	bailiffIcon = 0, -- bailiff_icon.png: вместо ⚖️ на плашке долга и над головой пристава
	contract = 0, -- icon_contract.png: вместо 📜 на плашке контракта и в окне предложения
	publisher = 0, -- icon_publisher.png: издатель в заголовке окна предложения контракта
	franchise = 0, -- icon_franchise.png: вместо 📚 у блока «Франшизы» и в тостах франшиз
} :: { [string]: number }

-- Отделка студии (Config/InteriorFinishes; assets/models/astra-interior-*/ShopCard_512.png).
-- 0 — картинки нет: карточка в цветах набора со значком. Dev 1: загрузить ShopCard_512.png
-- каждого набора как Image и вставить ID
Images.interiorFinishes = {
	obsidianGold = 0, -- astra-interior-obsidian-gold/ShopCard_512.png
	sakura = 0, -- astra-interior-sakura/ShopCard_512.png
	aurora = 0, -- astra-interior-aurora/ShopCard_512.png
} :: { [string]: number }

-- Сейф в парке (7.16, SafeService / SafeWindow). 0 — картинки нет: эмодзи 🔐 и простой фон окна
Images.safe = {
	icon = 0, -- safe_icon.png (256×256): заголовок окна клавиатуры
	keypadBg = 0, -- safe_keypad_bg.png (512×640): фон окна клавиатуры
} :: { [string]: number }

-- События дня (V27; Config/DailyEvents). 0 — картинки нет: как раньше, эмодзи события.
-- Иконки devent_<id>.png 256×256, баннер devent_banner.png 1600×300 без текста (над плашкой)
Images.dailyEvents = {
	coffeeRush = 0, -- devent_coffeeRush.png
	investors = 0, -- devent_investors.png
	bugHunt = 0, -- devent_bugHunt.png
	cartridgeRush = 0, -- devent_cartridgeRush.png
	blitzJam = 0, -- devent_blitzJam.png
	critics = 0, -- devent_critics.png
	pizza = 0, -- devent_pizza.png
	talentHunt = 0, -- devent_talentHunt.png
	flashSale = 0, -- devent_flashSale.png
	mascotParade = 0, -- devent_mascotParade.png
	golden = 0, -- devent_golden.png, «Золотой час»
	nightShift = 0, -- devent_nightShift.png, «Ночная смена» (хакатон)
	banner = 0, -- devent_banner.png 1600×300: общий баннер «Событие дня»
} :: { [string]: number }

-- Обложки игр по жанру (V20): рекламные щиты у спавна (BillboardService). 0 — картинки нет:
-- на щите эмодзи жанра
Images.covers = {
	action = 0, -- cover_action.png
	adventure = 0, -- cover_adventure.png
	casual = 0, -- cover_casual.png
	rpg = 0, -- cover_rpg.png
	simulation = 0, -- cover_simulation.png
	puzzle = 0, -- cover_puzzle.png
	racing = 0, -- cover_racing.png
	strategy = 0, -- cover_strategy.png
	sports = 0, -- cover_sports.png
	horror = 0, -- cover_horror.png
} :: { [string]: number }

-- Иконки жанров и тем (V21; docs/visual/astra-2026-11-05-genre-topic-icons/V21; Config/Genres, Config/Topics).
-- 0 — картинки нет: как раньше, эмодзи жанра/темы. Показываются в окне создания игры (выбор жанра
-- и темы), в исследованиях, открывающих жанр/тему, и в баннере тренда.
-- Dev 1: загрузить genre_<id>.png / topic_<id>.png как Image и вставить Image ID напротив id
Images.genres = {
	action = 0, -- genre_action.png
	adventure = 0, -- genre_adventure.png
	casual = 0, -- genre_casual.png
	rpg = 0, -- genre_rpg.png
	simulation = 0, -- genre_simulation.png
	puzzle = 0, -- genre_puzzle.png
	racing = 0, -- genre_racing.png
	strategy = 0, -- genre_strategy.png
	sports = 0, -- genre_sports.png
	horror = 0, -- genre_horror.png
} :: { [string]: number }

Images.topics = {
	space = 0, -- topic_space.png
	fantasy = 0, -- topic_fantasy.png
	zombies = 0, -- topic_zombies.png
	pets = 0, -- topic_pets.png
	cars = 0, -- topic_cars.png
	cooking = 0, -- topic_cooking.png
	pirates = 0, -- topic_pirates.png
	business = 0, -- topic_business.png
	school = 0, -- topic_school.png
	ninja = 0, -- topic_ninja.png
	robots = 0, -- topic_robots.png
	football = 0, -- topic_football.png
	superheroes = 0, -- topic_superheroes.png
	detective = 0, -- topic_detective.png
	ghosts = 0, -- topic_ghosts.png
	pumpkins = 0, -- topic_pumpkins.png
	newyear = 0, -- topic_newyear.png
} :: { [string]: number }

-- Платформы игр (V23; Config/Platforms). 0 — картинки нет: эмодзи 🖥️ 📱 🎮.
-- PNG 128×128 из папки V23
Images.platforms = {
	pc = 0, -- platform_pc.png (монитор)
	phone = 0, -- platform_phone.png (портативка/телефон)
	console = 0, -- platform_console.png (своя консоль из Console_Launch)
} :: { [string]: number }

-- Текстуры частиц (V24). 0 — текстуры нет: эффекты как раньше (стандартные Sparkles/детали).
-- PNG 128×128 на прозрачном фоне; Dev 1: загрузить как Image (Decal) и вставить ID
Images.fx = {
	coin = 0, -- fx_coin.png: релиз и хит (монеты)
	star = 0, -- fx_star.png: релиз и хит (звёзды)
	sparkle = 0, -- fx_sparkle.png: повышение сотрудника
	confetti1 = 0, -- fx_confetti_1.png: оценка 10, Rebirth, переезд
	confetti2 = 0, -- fx_confetti_2.png: оценка 10, Rebirth, переезд
	heart = 0, -- fx_heart.png: настроение команды
	note = 0, -- fx_note.png: нотка (звукостудия)
	smoke = 0, -- fx_smoke.png: поломка
} :: { [string]: number }

-- Логотипы критиков (V25; id из Config/Critics). 0 — логотипа нет: только название издания.
-- PNG 256×256, прозрачный фон, без текста
Images.critics = {
	herald = 0, -- critic_herald.png (Pixel Herald)
	gamertime = 0, -- critic_gamertime.png (GamerTime)
	cube = 0, -- critic_cube.png (Cube Review)
	hardcore = 0, -- critic_hardcore.png (Hardcore Digest)
} :: { [string]: number }

-- Одежда NPC-инвестора «Часа инвесторов» (V27, DailyEventService). Шаблоны 585×559 —
-- Dev 1: загрузить как Shirt/Pants (Classic Clothing) и вставить ID. 0 — инвестор как раньше
Images.investor = {
	shirt = 0, -- investor_shirt.png: ShirtTemplate (костюм)
	pants = 0, -- investor_pants.png: PantsTemplate
} :: { [string]: number }

-- Иконки новых систем (V28). 0 — картинки нет: как раньше, эмодзи или простая плашка
Images.misc = {
	gotwIcon = 0, -- gotw_icon.png (256×256): «Игра недели» (окно GotwPanel)
	rebirthStar = 0, -- rebirth_star.png (256×256): звёзды Rebirth (вкладка перков)
	mentorIcon = 0, -- mentor_icon.png (128×128): блок наставничества в окне сотрудника
	titleFrame = 0, -- title_frame.png (512×96, 9-slice): плашка титула над головой
} :: { [string]: number }

-- Иконки веток перков Rebirth (V28; ветки Config/RebirthPerks). 0 — эмодзи ветки.
-- PNG 128×128. Ветка → ключ: speed → speed, thrift → costs, capital → start, passive → offline;
-- у lab своей иконки в брифе нет (остаётся 🔬), hits — запас (полка хитов — эффект passive)
Images.rebirthPerks = {
	speed = 0, -- rperk_speed.png (часы-молния)
	costs = 0, -- rperk_costs.png (копилка)
	start = 0, -- rperk_start.png (мешок монет)
	hits = 0, -- rperk_hits.png (полка с картриджем)
	offline = 0, -- rperk_offline.png (луна с монеткой)
} :: { [string]: number }

return Images
