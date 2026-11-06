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
	menu_guides = 0, -- menu_guides.png, 📖 «Справочник» (обучение; ID — Dev 1 после арта Астры)
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
Images.vip = 123181526276822 -- vip_crown.png

-- Маскоты (docs/VISUAL.md, V16; Config/Mascots). 0 — иконки ещё нет: на карточке эмодзи.
-- Dev 1: загрузить mascot_<id>_icon.png (256×256) как Image и вставить Image ID напротив id
Images.mascots = {
	pixel_cat = 71402161805905,
	bug_beetle = 134852982669111,
	coffee_cup = 103950131419839,
	floppy_dog = 120554910932704,
	cloud_ghost = 75059320589809,
	controller_bunny = 130099031780998,
	robo_owl = 125888470887817,
	slime_star = 74757233863602,
	neon_fox = 73049895319166,
	dragon_byte = 119228126015498,
	golden_trophy = 121316119099695,
	cosmic_whale = 129487034798348,
} :: { [string]: number }

-- Награда за вход (docs/visual/astra-2026-11-05-daily/V17; окно DailyRewardWindow), 0 — плитки цветом и эмодзи
Images.daily = {
	boardBg = 73762302263928, -- daily_board_bg.png (1200×700), фон окна
	cardNormal = 78346341679983, -- daily_card_normal.png (256×320), завтрашний день
	cardToday = 89311624065851, -- daily_card_today.png, сегодняшний день
	cardClaimed = 100783940032999, -- daily_card_claimed.png, уже забранные дни
	cardLocked = 77662079383852, -- daily_card_locked.png, дни после завтрашнего
	rewardCash = 89619672161503, -- reward_cash.png (256×256), деньги и реклама
	rewardCoffee = 71068165326557, -- reward_coffee.png, кофе
	rewardResearch = 85370028018752, -- reward_research.png, очки исследований
	rewardSkin = 83696519617290, -- reward_skin.png, скин
	rewardBig = 110975546343656, -- reward_big.png, большая награда (несколько сразу, кубок, постер, маскот)
	streakFlame = 133509484127908, -- daily_streak_flame.png (128×128), у заголовка окна
} :: { [string]: number }

-- Сезон, гейм-джем, хакатон, студии, коды (docs/visual/astra-2026-11-05-social/V18), 0 — как раньше: эмодзи и цвет
Images.social = {
	seasonBanner = 129054288570322, -- season_banner.png (1600×400), шапка вкладки «Сезон» — только первый сезон («SEASON 1»)
	seasonBannerGeneric = 79846210301814, -- season_banner_generic.png (1600×400, V18, без номера): сезоны со второго
	gamejamBanner = 113577119802150, -- gamejam_banner.png (1600×400), шапка вкладки «Гейм-джем»
	hackathonBanner = 79281467397820, -- hackathon_banner.png (1600×300), над плашкой хакатона
	seasonTierFree = 93399096119288, -- season_tier_free.png, рамка иконки бесплатной награды уровня
	seasonTierPremium = 106897064814523, -- season_tier_premium.png, рамка иконки премиум-награды уровня
	seasonPremiumBadge = 92224501888805, -- season_premium_badge.png, вместо ⭐ у «Премиум»
	gamejamMedalTop10 = 70905033741113, -- gamejam_medal_top10.png, отметка «Топ-10 джема»
	gamejamMedalTop100 = 104418279148070, -- gamejam_medal_top100.png, отметка «Топ-100 джема»
	iconLike = 118012671110754, -- icon_like.png, вместо 👍 в окне «Студии»
	iconVisit = 135589658754064, -- icon_visit.png, на кнопке «Посетить»
	iconLeaderboard = 76774397277112, -- icon_leaderboard.png, вместо 🏆 у вкладки «Рейтинги»
	iconCodes = 90962665283927, -- icon_codes.png, вместо 🎟 у кнопки и окна «Коды»
	menuGamejam = 116715408335139, -- menu_gamejam.png, вместо 🎮 у вкладки «Гейм-джем»
} :: { [string]: number }

-- Кнопки меню V18: ключи, которые уже передают Ui.menuButton окна «Студии» и «Сезон»
Images.menu.menu_tours = 88709373253382 -- menu_studios.png, 🏘 (слот 15)
Images.menu.menu_season = 116148775564436 -- menu_season.png, 🎫 (слот 16), и вкладка «Сезон»
-- Кнопки меню V31: окна без своей иконки (как V3: 256×256, прозрачный фон, без текста)
Images.menu.menu_stock = 119571944096135 -- menu_stock.png, 📈 «Биржа»
Images.menu.menu_tax = 116144362072392 -- menu_tax.png, 🧾 «Налоговая»
Images.menu.menu_rivals = 116941946493111 -- menu_rivals.png, 📊 «Конкуренты»

-- События компании (docs/VISUAL.md, V19; Config/CompanyEvents). 0 — иконки ещё нет: на карточке
-- события эмодзи. Dev 1: из docs/visual/astra-2026-11-05-events/events-1/V19 и events-2/V19
-- загрузить cev_<id>.png как Image и вставить Image ID напротив id события
Images.events = {
	angel = 126115030910527, -- cev_angel.png (events-1)
	streamer = 115159229512086, -- cev_streamer.png (events-1)
	award = 106211277250799, -- cev_award.png (events-1)
	conference = 84380235816193, -- cev_conference.png (events-1)
	grant = 117964901637171, -- cev_grant.png (events-1)
	donations = 123501737256227, -- cev_donations.png (events-1)
	luckybug = 90816635277428, -- cev_luckybug.png (events-1)
	hype = 114161603518864, -- cev_hype.png (events-1)
	crash = 79666706088932, -- cev_crash.png (events-1)
	leak = 72521476510399, -- cev_leak.png (events-1)
	flood = 115209998372368, -- cev_flood.png (events-1)
	audit = 119798940366364, -- cev_audit.png (events-2)
	outage = 83369652725201, -- cev_outage.png (events-2)
	reviewbomb = 107416949332943, -- cev_reviewbomb.png (events-2)
	burnout = 111357656165368, -- cev_burnout.png (events-2)
	lawsuit = 126582125316050, -- cev_lawsuit.png (events-2)
	poach = 76640146151427, -- cev_poach.png (events-2)
	rush = 117010825950086, -- cev_rush.png (events-2)
	sponsor = 96177486239631, -- cev_sponsor.png (events-2)
	gamble = 102723895535116, -- cev_gamble.png (events-2)
	takeover = 133071454205817, -- cev_takeover.png (events-2)
	bankrupt = 119607807015573, -- cev_bankrupt.png (events-2)
} :: { [string]: number }

-- Логотипы студий-конкурентов (V19; Config/Rivals). 0 — логотипа нет: эмодзи студии.
-- Dev 1: из docs/visual/astra-2026-11-05-events/rivals загрузить rival_<id>.png как Image
Images.rivals = {
	tinfoilOwl = 138031764808403, -- rival_tinfoilOwl.png
	mangoComet = 85466131957575, -- rival_mangoComet.png
	quokkaPixel = 103446389629834, -- rival_quokkaPixel.png
	gloomberry = 133809133364321, -- rival_gloomberry.png
	brassfern = 95278299138031, -- rival_brassfern.png
	velvetAnvil = 102743410095520, -- rival_velvetAnvil.png
	nimbusTurtle = 114269103997940, -- rival_nimbusTurtle.png
	okraLantern = 108916650744432, -- rival_okraLantern.png
	bluemoth = 99779426829006, -- rival_bluemoth.png
} :: { [string]: number }

-- Монетизация (V14; docs/visual/astra-2026-11-05-vip/V14). 0 — картинки нет: как раньше, эмодзи.
-- Корона vip_crown.png — это Images.vip выше
Images.monetization = {
	gift = 85586503108774, -- gift_icon.png (256×256): кнопка «🎁 Подарить» и окно выбора получателя
	deal = 85619759273073, -- deal_badge.png (256×256, на картинке «-30%»): «Сделка дня» в магазине
	starterBanner = 122248749411596, -- starter_pack_banner.png (1024×512): окно стартового набора
	groupBanner = 94884571361356, -- group_banner.png (1024×512): подсказка «Вступи в группу» во вкладке скинов
} :: { [string]: number }

-- Контракты, приставы, франшизы (V19 часть 3; docs/visual/astra-2026-11-05-events/contracts-bailiff/V19).
-- 0 — картинки нет: как раньше, эмодзи (📜 ⚖️ 📚) и костюм пристава из деталей.
-- Dev 1: bailiff_shirt/bailiff_pants (шаблоны одежды 585×559) загрузить как Shirt/Pants
-- (Classic Clothing), остальные — как Image, и вставить ID
Images.contracts = {
	bailiffShirt = 73501880092096, -- bailiff_shirt.png: ShirtTemplate NPC-пристава (BailiffService)
	bailiffPants = 138546814536898, -- bailiff_pants.png: PantsTemplate NPC-пристава (BailiffService)
	bailiffIcon = 73777796074859, -- bailiff_icon.png: вместо ⚖️ на плашке долга и над головой пристава
	contract = 96443825012555, -- icon_contract.png: вместо 📜 на плашке контракта и в окне предложения
	publisher = 138088086428782, -- icon_publisher.png: издатель в заголовке окна предложения контракта
	franchise = 139694706376820, -- icon_franchise.png: вместо 📚 у блока «Франшизы» и в тостах франшиз
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
	icon = 101236220132388, -- safe_icon.png (256×256): заголовок окна клавиатуры
	keypadBg = 138283852876442, -- safe_keypad_bg.png (512×640): фон окна клавиатуры
} :: { [string]: number }

-- События дня (V27; Config/DailyEvents). 0 — картинки нет: как раньше, эмодзи события.
-- Иконки devent_<id>.png 256×256, баннер devent_banner.png 1600×300 без текста (над плашкой)
Images.dailyEvents = {
	coffeeRush = 140708664840064, -- devent_coffeeRush.png
	investors = 119973277983897, -- devent_investors.png
	bugHunt = 136675377878216, -- devent_bugHunt.png
	cartridgeRush = 92547183096470, -- devent_cartridgeRush.png
	blitzJam = 137591385292606, -- devent_blitzJam.png
	critics = 121666412612751, -- devent_critics.png
	pizza = 108340168149954, -- devent_pizza.png
	talentHunt = 106398702858647, -- devent_talentHunt.png
	flashSale = 80550957576879, -- devent_flashSale.png
	mascotParade = 78535346814509, -- devent_mascotParade.png
	golden = 103336463855619, -- devent_golden.png, «Золотой час»
	nightShift = 97415873402218, -- devent_nightShift.png, «Ночная смена» (хакатон)
	banner = 115965369135869, -- devent_banner.png 1600×300: общий баннер «Событие дня»
} :: { [string]: number }

-- Обложки игр по жанру (V20): рекламные щиты у спавна (BillboardService). 0 — картинки нет:
-- на щите эмодзи жанра
Images.covers = {
	action = 119434423708285, -- cover_action.png
	adventure = 104157762341470, -- cover_adventure.png
	casual = 121340939605556, -- cover_casual.png
	rpg = 111791160634509, -- cover_rpg.png
	simulation = 116134673394548, -- cover_simulation.png
	puzzle = 98069758921557, -- cover_puzzle.png
	racing = 135580703502511, -- cover_racing.png
	strategy = 93697444911421, -- cover_strategy.png
	sports = 124969035886247, -- cover_sports.png
	horror = 107710500766338, -- cover_horror.png
} :: { [string]: number }

-- Иконки жанров и тем (V21; docs/visual/astra-2026-11-05-genre-topic-icons/V21; Config/Genres, Config/Topics).
-- 0 — картинки нет: как раньше, эмодзи жанра/темы. Показываются в окне создания игры (выбор жанра
-- и темы), в исследованиях, открывающих жанр/тему, и в баннере тренда.
-- Dev 1: загрузить genre_<id>.png / topic_<id>.png как Image и вставить Image ID напротив id
Images.genres = {
	action = 89363220082689, -- genre_action.png
	adventure = 105139558534766, -- genre_adventure.png
	casual = 73391229738160, -- genre_casual.png
	rpg = 98597680042200, -- genre_rpg.png
	simulation = 115549538325082, -- genre_simulation.png
	puzzle = 72555618370147, -- genre_puzzle.png
	racing = 77845961912648, -- genre_racing.png
	strategy = 82660805733305, -- genre_strategy.png
	sports = 96011117420957, -- genre_sports.png
	horror = 127714434492669, -- genre_horror.png
} :: { [string]: number }

Images.topics = {
	space = 90894085432626, -- topic_space.png
	fantasy = 102194506615926, -- topic_fantasy.png
	zombies = 114872880713943, -- topic_zombies.png
	pets = 117416936368482, -- topic_pets.png
	cars = 113304329673263, -- topic_cars.png
	cooking = 83441372683820, -- topic_cooking.png
	pirates = 117882755141520, -- topic_pirates.png
	business = 112856225920817, -- topic_business.png
	school = 98977225595639, -- topic_school.png
	ninja = 73648868840202, -- topic_ninja.png
	robots = 136435512572399, -- topic_robots.png
	football = 102650924404339, -- topic_football.png
	superheroes = 81159724233301, -- topic_superheroes.png
	detective = 93966453210921, -- topic_detective.png
	ghosts = 133200802511828, -- topic_ghosts.png
	pumpkins = 123154070608307, -- topic_pumpkins.png
	newyear = 125623041242975, -- topic_newyear.png
} :: { [string]: number }

-- Платформы игр (V23; Config/Platforms). 0 — картинки нет: эмодзи 🖥️ 📱 🎮.
-- PNG 128×128 из папки V23
Images.platforms = {
	pc = 136326540301053, -- platform_pc.png (монитор)
	phone = 76903299256652, -- platform_phone.png (портативка/телефон)
	console = 108212869611553, -- platform_console.png (своя консоль из Console_Launch)
} :: { [string]: number }

-- Текстуры частиц (V24). 0 — текстуры нет: эффекты как раньше (стандартные Sparkles/детали).
-- PNG 128×128 на прозрачном фоне; Dev 1: загрузить как Image (Decal) и вставить ID
Images.fx = {
	coin = 94369218789257, -- fx_coin.png: релиз и хит (монеты)
	star = 120250365832201, -- fx_star.png: релиз и хит (звёзды)
	sparkle = 106591901862289, -- fx_sparkle.png: повышение сотрудника
	confetti1 = 114606871530940, -- fx_confetti_1.png: оценка 10, Rebirth, переезд
	confetti2 = 95626549226023, -- fx_confetti_2.png: оценка 10, Rebirth, переезд
	heart = 134947774669322, -- fx_heart.png: настроение команды
	note = 114492007017372, -- fx_note.png: нотка (звукостудия)
	smoke = 135401861209014, -- fx_smoke.png: поломка
} :: { [string]: number }

-- Логотипы критиков (V25; id из Config/Critics). 0 — логотипа нет: только название издания.
-- PNG 256×256, прозрачный фон, без текста
Images.critics = {
	herald = 75784778052317, -- critic_herald.png (Pixel Herald)
	gamertime = 130859182847532, -- critic_gamertime.png (GamerTime)
	cube = 127230145804127, -- critic_cube.png (Cube Review)
	hardcore = 92479360462097, -- critic_hardcore.png (Hardcore Digest)
} :: { [string]: number }

-- Одежда NPC-инвестора «Часа инвесторов» (V27, DailyEventService). Шаблоны 585×559 —
-- Dev 1: загрузить как Shirt/Pants (Classic Clothing) и вставить ID. 0 — инвестор как раньше
Images.investor = {
	shirt = 99486280169244, -- investor_shirt.png: ShirtTemplate (костюм)
	pants = 86089989725674, -- investor_pants.png: PantsTemplate
} :: { [string]: number }

-- Иконки новых систем (V28). 0 — картинки нет: как раньше, эмодзи или простая плашка
Images.misc = {
	gotwIcon = 97812679579578, -- gotw_icon.png (256×256): «Игра недели» (окно GotwPanel)
	rebirthStar = 127102888714131, -- rebirth_star.png (256×256): звёзды Rebirth (вкладка перков)
	mentorIcon = 91562204861195, -- mentor_icon.png (128×128): блок наставничества в окне сотрудника
	titleFrame = 134212590859011, -- title_frame.png (512×96, 9-slice): плашка титула над головой
} :: { [string]: number }

-- Иконки веток перков Rebirth (V28; ветки Config/RebirthPerks). 0 — эмодзи ветки.
-- PNG 128×128. Ветка → ключ: speed → speed, thrift → costs, capital → start, passive → offline;
-- у lab своей иконки в брифе нет (остаётся 🔬), hits — запас (полка хитов — эффект passive)
Images.rebirthPerks = {
	speed = 77884992713184, -- rperk_speed.png (часы-молния)
	costs = 107137675022834, -- rperk_costs.png (копилка)
	start = 83530676697854, -- rperk_start.png (мешок монет)
	hits = 122010269723585, -- rperk_hits.png (полка с картриджем)
	offline = 127684527776610, -- rperk_offline.png (луна с монеткой)
} :: { [string]: number }

-- Иконки этапов своей консоли (V30; этапы Config/Console.stages). PNG 128×128,
-- 0 — эмодзи этапа в окне консоли
Images.consoleStages = {
	cpu = 73324393733517, -- cstage_cpu.png (кристалл процессора)
	case = 95080248845237, -- cstage_case.png (эскиз корпуса с карандашом)
	sound = 135149153541405, -- cstage_sound.png (звуковой чип с нотой)
	prototype = 113136393064559, -- cstage_prototype.png (открытый корпус, провода)
	testing = 76995691378701, -- cstage_testing.png (геймпад под лупой)
	launch = 118883117815423, -- cstage_launch.png (консоль с ракетой)
} :: { [string]: number }

-- Одежда строителей (V29; assets/models/astra-v29/builder-pack). 0 — нет: цвета/одежда модели BuilderNPC.
-- Dev 1: загрузить builder_shirt.png / builder_pants.png как Shirt/Pants (Classic Clothing) и вставить ID
Images.builder = {
	shirt = 113297982121861, -- builder_shirt.png 585×559
	pants = 94681787561840, -- builder_pants.png 585×559
} :: { [string]: number }

-- Туториал (V31). 0 — стрелка-символ ⬇ как раньше
Images.tutorial = {
	arrow = 137209781827312, -- tut_arrow.png (256×256): жёлтая стрелка вниз над кнопкой (экран и 3D над участком)
} :: { [string]: number }

-- Спрайты мини-аркады (V31; ArcadeWindow). 0 — эмодзи и цветные плашки как раньше
Images.arcade = {
	target = 120111323470005, -- arcade_target.png (256×256): мишень-жук в тире, вместо 🎯
	car = 76501243438051, -- arcade_car.png (256×256): гоночная машинка сверху, носом вверх, вместо 🏎
	barrier = 129390616805177, -- arcade_barrier.png (256×256): дорожный барьер, вместо 🚧
	runner = 98710524657653, -- arcade_runner.png (256×256): бегущий кубик-герой «Забега», вместо плашки с ••
	coin = 97699345337385, -- arcade_coin.png (128×128): монета «Поймай монеты», вместо жёлтого круга с $
} :: { [string]: number }

-- Иконки заголовков окон (V31). 0 — эмодзи в начале заголовка как раньше
Images.windows = {
	stock = 88745925157401, -- win_stock.png (256×256): «📈 Биржа»
	ipo = 106948582182489, -- win_ipo.png (256×256): «🔔 Выйти на биржу (IPO)»
	tax = 121631495915151, -- win_tax.png (256×256): «🧾 Налоговая»
	rivals = 127810529408400, -- win_rivals.png (256×256): «📊 Топ-10 индустрии»
	offline = 112956538812152, -- win_offline.png (256×256): «Пока тебя не было» (луна над студией с монетами)
	comeback = 111001097830060, -- win_comeback.png (256×256): «С возвращением!» (подарок с бантом)
} :: { [string]: number }

return Images
