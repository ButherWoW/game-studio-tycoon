--!strict
-- Тексты интерфейса (задача A из docs/DEV2_NEXT.md).
-- RU и EN — здесь, новые ключи дописывать в обе таблицы. Остальные языки —
-- Config/Locales/<code>.luau с теми же ключами; чего нет в языке, берётся из EN, потом из RU.
-- Подстановки: {name}, {price}, {percent} и т.п. — см. Texts.format.

export type Lang = string

local Texts = {}

-- Языки для меню выбора: код (как имя файла в Locales) и самоназвание
Texts.languages = {
	{ code = "ru", nativeName = "Русский" },
	{ code = "en", nativeName = "English" },
	{ code = "uk", nativeName = "Українська" },
	{ code = "de", nativeName = "Deutsch" },
	{ code = "fr", nativeName = "Français" },
	{ code = "es", nativeName = "Español" },
	{ code = "it", nativeName = "Italiano" },
	{ code = "pt", nativeName = "Português" },
	{ code = "nl", nativeName = "Nederlands" },
	{ code = "pl", nativeName = "Polski" },
	{ code = "cs", nativeName = "Čeština" },
	{ code = "sk", nativeName = "Slovenčina" },
	{ code = "sl", nativeName = "Slovenščina" },
	{ code = "hr", nativeName = "Hrvatski" },
	{ code = "sr", nativeName = "Српски" },
	{ code = "bg", nativeName = "Български" },
	{ code = "ro", nativeName = "Română" },
	{ code = "hu", nativeName = "Magyar" },
	{ code = "el", nativeName = "Ελληνικά" },
	{ code = "sv", nativeName = "Svenska" },
	{ code = "da", nativeName = "Dansk" },
	{ code = "fi", nativeName = "Suomi" },
	{ code = "no", nativeName = "Norsk" },
	{ code = "et", nativeName = "Eesti" },
	{ code = "lv", nativeName = "Latviešu" },
	{ code = "lt", nativeName = "Lietuvių" },
	{ code = "tr", nativeName = "Türkçe" },
	{ code = "zh-cn", nativeName = "中文" },
	{ code = "id", nativeName = "Bahasa Indonesia" },
	{ code = "hi", nativeName = "हिन्दी" },
} :: { { code: string, nativeName: string } }

function Texts.isLanguage(code: any): boolean
	if type(code) ~= "string" then
		return false
	end
	for _, language in Texts.languages do
		if language.code == code then
			return true
		end
	end
	return false
end

-- Таблица языка: ru/en отсюда, остальные из Locales (грузятся при первом обращении)
local loaded: { [string]: { [string]: string } } = {}

function Texts.locale(lang: Lang): { [string]: string }?
	if lang == "ru" or lang == "en" then
		return (Texts :: any)[lang]
	end
	local cached = loaded[lang]
	if cached then
		return cached
	end
	local folder = (script.Parent :: Instance):FindFirstChild("Locales")
	local module = folder and folder:FindFirstChild(lang)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok or type(result) ~= "table" then
		warn("[Texts] Locale failed to load:", lang, result)
		return nil
	end
	loaded[lang] = result :: any
	return result :: any
end

-- Текст ключа только в этом языке, без запасных (nil — перевода нет)
function Texts.lookup(lang: Lang, key: string): string?
	local tbl = Texts.locale(lang)
	return tbl and tbl[key]
end

Texts.ru = {
	price_free = "Бесплатно",
	-- HUD
	hud_cash = "$ {cash}",
	hud_games = "Игр: {count}",
	hud_ad = "Реклама +{percent}%",
	hud_create = "🎮 Создать игру",
	hud_developing = "Разработка: {percent}%",

	-- Выбор языка
	lang_title = "🌐 Язык",

	-- Окно «Создать игру»
	create_title = "Новая игра",
	create_name_label = "Название",
	create_name_placeholder = "Моя первая игра",
	create_genre_label = "Жанр",
	create_topic_label = "Тема",
	create_focus_label = "На что тратим силы",
	create_focus_hint = "Каждому жанру важно своё. Угадай рецепт!",
	focus_gameplay = "Геймплей",
	focus_graphics = "Графика",
	focus_sound = "Звук",
	focus_story = "Сюжет",
	create_start = "Начать разработку",
	create_close = "✕",
	create_locked = "🔒 {price}",
	create_unlock_ask = "Открыть за {price}?",
	create_combo_great = "Отличное сочетание!",
	create_combo_bad = "Не очень сочетание…",
	create_combo_unknown = "Что скажут критики?",

	-- Ошибки и подсказки
	error_no_money = "Не хватает денег: нужно {price}",
	error_pick_genre = "Выбери жанр",
	error_pick_topic = "Выбери тему",
	error_busy = "Студия уже делает игру",
	error_focus_empty = "Распредели хотя бы одно очко фокуса",

	-- Окно релиза
	release_title = "«{name}» вышла!",
	release_critics = "Оценки критиков",
	release_score = "Итог: {score}/10",
	release_revenue = "+{money}",
	release_ad_bonus = "в том числе реклама +{percent}%",
	release_again = "Ещё игру",
	release_ad = "📢 Реклама +30% за {price}",
	release_close = "Закрыть",
	release_best = "Новый рекорд студии!",

	-- staff
	team_title = "Команда",
	team_desks = "Свободных столов: {free} из {total}",
	team_hire = "Нанять {price}",
	team_hired = "В команде",
	team_locked = "🔒 {stage}",
	team_soon = "⭐ Скоро",
	team_no_desk = "Нет стола",
	team_multiplier = "×{mult} · {spec}",
	team_spec_all = "всё",
	team_stage = "Студия: {stage}",
	team_next = "Следующий этап: {stage}",
	team_req_money = "{price}",
	team_req_games = "игр: {have}/{need}",
	team_req_upgrade = "купить «{name}»",
	team_move = "🚚 Переезд",
	team_max_stage = "Это самый большой этап!",
	-- research
	research_title = "🔬 Исследования",
	research_points = "ОИ: {points}",
	research_hint = "Каждая выпущенная игра даёт столько ОИ, какая у неё оценка",
	research_branch_genres = "Жанры",
	research_branch_tech = "Технологии",
	research_branch_studio = "Студия",
	research_cost = "{cost} ОИ",
	research_buy = "Исследовать · {cost} ОИ",
	research_need = "Нужно {cost} ОИ",
	research_owned = "✓ Изучено",
	research_requires = "🔒 Сначала: {names}",
	research_genre_owned = "(жанр уже открыт)",
	-- tutorial
	tutorial_desk = "Наступи на зелёную кнопку — это твой первый стол",
	tutorial_open = "Сядь за компьютер — откроется «Создать игру»",
	tutorial_pick = "Выбери жанр и тему",
	tutorial_start = "Распредели фокус и начни разработку",
	tutorial_wait = "Пока студия работает, купи компьютер (или подожди)",
	tutorial_release = "Критики оценили игру! Деньги — твои",
	tutorial_done = "Покупай апгрейды и делай игры лучше. Бонус: {money}!",
	tutorial_skip = "Пропустить",
	tutorial_ok = "Готово",
	-- retention
	trend_banner = "🔥 В тренде: {genre} + {topic}, ещё {time}",
	rebirth_title = "♻️ Rebirth",
	rebirth_count = "Ребёрзов: {count} · доход ×{mult}",
	rebirth_next = "После ребёрза доход ×{mult} навсегда",
	rebirth_need_office = "Переезд в офис",
	rebirth_need_cash = "Деньги: {price}",
	rebirth_resets = "Сбросится: деньги (останется $100), апгрейды, открытые жанры и темы",
	rebirth_keeps = "Останется: рекорд и число выпущенных игр",
	rebirth_button = "Начать заново",
	rebirth_confirm = "Точно? Нажми ещё раз",
	rebirth_locked = "Условия не выполнены",
	rebirth_done = "Студия начинает заново! Доход ×{mult}",
	rebirth_close = "Закрыть",
	offline_title = "Пока тебя не было",
	offline_amount = "+{money}",
	offline_hint = "Студия работала без тебя за половину дохода",
	offline_claim = "Забрать",
	-- shop
	shop_title = "🛒 Магазин",
	shop_tab_ads = "Реклама",
	shop_tab_passes = "Геймпассы",
	shop_tab_boosts = "Бусты",
	shop_robux = "R$ {price}",
	shop_soon = "Скоро",
	shop_owned = "✓ Куплено",
	shop_ad_line = "+{percent}% к доходу на {minutes} мин",
	shop_ad_note = "Бонусы не складываются: действует самый большой, максимум +100%",
	shop_charges = "Есть: {count}",
	shop_coffee_left = "Действует ещё {minutes} мин",
	shop_income_amount = "Сейчас ≈ {money}",
	ad_name_social = "Баннеры в соцсетях",
	ad_name_streamers = "Стримеры",
	ad_name_tv = "ТВ-реклама",
	ad_name_worldwide = "Мировая кампания",
	-- quests
	quests_title = "Задания",
	quests_tab_quests = "Задания",
	quests_tab_daily = "Ежедневные",
	quests_tab_leaders = "Лидеры",
	quests_claim = "Забрать",
	quests_claimed = "✓ Получено",
	quests_progress = "{progress} / {target}",
	quests_daily_reset = "Новые задания через {time}",
	quests_loading = "Загрузка…",
	reward_income = "{minutes} мин дохода (~{money})",
	reward_research = "{count} ОИ",
	reward_badge = "значок «{name}»",
	reward_income_bonus = "+{percent}% к доходу навсегда",
	reward_employee = "сотрудник «{name}»",
	reward_coffee = "кофе ×2 скорость на {minutes} мин",
	reward_ad = "реклама +{percent}% на {minutes} мин",
	reward_trophy = "декор «{name}»",
	badge_masterpiece = "Шедевр",
	employee_ghost_coder = "Призрачный кодер",
	trophy_weekly_cup = "Кубок недели",
	leaders_best = "Лучшая оценка",
	leaders_games = "Всего игр",
	leaders_unavailable = "Таблица лидеров недоступна",
	leaders_empty = "Пока пусто",
	daily_reward_title = "Награда за вход",
	daily_reward_day = "День {day}",
	daily_reward_claim = "День {day} — забрать",
	daily_reward_hint = "Заходи каждый день: пропуск начинает серию заново",
	-- expo
	expo_banner = "🏆 Выставка через {time} · приз {prize}",
	expo_banner_leader = "🏆 Выставка через {time} · лидер: «{name}» {score}/10 ({player})",
	expo_winner = "🏆 Выставку выиграла «{name}» ({player}), {score}/10! Приз {prize}",
	expo_you_won = "🏆 Твоя «{name}» выиграла выставку! +{prize}",
	expo_no_games = "🏆 Выставка прошла без игр. Выпусти игру — и приз твой!",
	-- desk + dev events + item bonuses
	hud_sit = "🪑 Сядь за компьютер",
	hud_paused = "⏸ Пауза — сядь за компьютер",
	bonus_pps = "+{value} очк/с",
	bonus_speed = "−{value}% времени",
	bonus_review = "+{value} к оценке",
	devevent_ok = "👍 Получилось!",
	devevent_fail = "😬 Не вышло…",
	devevent_skip = "Ладно, работаем дальше",
	devevent_bug_title = "🐛 Нашёлся баг!",
	devevent_bug_a = "Починить",
	devevent_bug_b = "Оставить как есть",
	devevent_music_title = "🎵 Композитор принёс трек",
	devevent_music_a = "Взять в игру",
	devevent_music_b = "Не сейчас",
	devevent_art_title = "🎨 Художник нарисовал крутой арт",
	devevent_art_a = "В игру!",
	devevent_art_b = "Пропустить",
	devevent_story_title = "📖 Идея для сюжета!",
	devevent_story_a = "Дописать сюжет",
	devevent_story_b = "Без неё",
	devevent_crunch_title = "🔥 Дедлайн горит!",
	devevent_crunch_a = "Кранч: быстрее",
	devevent_crunch_b = "Спокойно",
	devevent_playtest_title = "🧪 Тестерам скучно на уровне",
	devevent_playtest_a = "Переделать",
	devevent_playtest_b = "И так сойдёт",
	devevent_streamer_title = "📺 Стример заметил игру",
	devevent_streamer_a = "Показать демо",
	devevent_streamer_b = "Пока рано",
	-- hits
	hit_prompt = "🕵️ Украсть",
	hit_new = "📀 «{name}» — хит! ★{score}, +{income}/мин на полке",
	hit_shelf_full = "📀 «{name}» не влез на полку: там хиты сильнее",
	hit_income = "💰 Твои хиты принесли {amount}",
	hit_carry_hint = "🏃 Неси «{name}» к своей полке хитов!",
	hit_stolen_by_you = "😈 Ты украл «{name}» у {player}",
	hit_lost = "😢 {player} унёс твой «{name}»",
	hit_alarm = "🚨 Крадут твой хит! «{name}» — {player}. Догони!",
	hit_alarm_arrow = "🚨 ВОР",
	hit_caught_thief = "🛡️ Ты поймал вора! +{amount}",
	hit_you_were_caught = "🚨 Тебя поймал {player}! Штраф {amount}",
	hit_returned = "↩️ «{name}» вернулся на твою полку",
	hit_carry_failed = "↩️ Картридж вернулся владельцу",
	hit_err_newbie = "🔰 Красть можно после {count} выпущенных игр",
	hit_err_victim_newbie = "🔰 Новичков не обворовывают",
	hit_err_cooldown = "⏳ Снова красть можно через {seconds} с",
	hit_err_immune = "🛡️ Эту студию недавно обокрали — подожди {seconds} с",
	hit_err_locked = "🔒 Студия закрыта",
	hit_err_busy = "Этот картридж уже уносят",
	hit_window_title = "🔒 Хиты и защита",
	hit_summary = "Хиты: {count}/{slots}, доход {income}/мин",
	hit_rules = "Игры с оценкой 7+ становятся картриджами на полке и приносят деньги каждую минуту. Чужие можно украсть и донести до своей полки, а вора — поймать, коснувшись его.",
	hit_lock = "🔒 Закрыть студию на {seconds} с",
	hit_locked = "🔒 Закрыто ещё {seconds} с",
	hit_lock_cooldown = "⏳ Снова закрыть через {time}",
	hit_lock_hint = "Пока студия закрыта, твои картриджи нельзя украсть.",
	hit_my_stats = "Ты: 😈 {steals} краж (+{income}/мин) · 🛡️ поймал {catches} · пойман {caught}",
	hit_close = "Закрыть",
	thief_title = "😈 Главные воры",
	thief_tab_server = "На сервере",
	thief_tab_global = "За всё время",
	thief_unavailable = "Недоступно",
	thief_empty = "Пока никто ничего не украл",
	thief_row = "{place}. {name}   😈 {steals}   🛡️ {catches}",
	thief_crown = "👑 Главный вор",
} :: { [string]: string }

Texts.en = {
	price_free = "Free",
	hud_cash = "$ {cash}",
	hud_games = "Games: {count}",
	hud_ad = "Ads +{percent}%",
	hud_create = "🎮 Make a game",
	hud_developing = "Developing: {percent}%",

	lang_title = "🌐 Language",

	create_title = "New game",
	create_name_label = "Title",
	create_name_placeholder = "My first game",
	create_genre_label = "Genre",
	create_topic_label = "Topic",
	create_focus_label = "Where does the effort go",
	create_focus_hint = "Every genre has its own recipe. Find it!",
	focus_gameplay = "Gameplay",
	focus_graphics = "Graphics",
	focus_sound = "Sound",
	focus_story = "Story",
	create_start = "Start development",
	create_close = "✕",
	create_locked = "🔒 {price}",
	create_unlock_ask = "Unlock for {price}?",
	create_combo_great = "Great combo!",
	create_combo_bad = "Not a great combo…",
	create_combo_unknown = "What will critics say?",

	error_no_money = "Not enough money: {price} needed",
	error_pick_genre = "Pick a genre",
	error_pick_topic = "Pick a topic",
	error_busy = "The studio is already making a game",
	error_focus_empty = "Put at least one point into focus",

	release_title = "“{name}” is out!",
	release_critics = "Critic reviews",
	release_score = "Score: {score}/10",
	release_revenue = "+{money}",
	release_ad_bonus = "ads included +{percent}%",
	release_again = "Make another",
	release_ad = "📢 Ads +30% for {price}",
	release_close = "Close",
	release_best = "New studio record!",

	-- staff
	team_title = "Team",
	team_desks = "Free desks: {free} of {total}",
	team_hire = "Hire {price}",
	team_hired = "On the team",
	team_locked = "🔒 {stage}",
	team_soon = "⭐ Soon",
	team_no_desk = "No desk",
	team_multiplier = "×{mult} · {spec}",
	team_spec_all = "everything",
	team_stage = "Studio: {stage}",
	team_next = "Next stage: {stage}",
	team_req_money = "{price}",
	team_req_games = "games: {have}/{need}",
	team_req_upgrade = "buy “{name}”",
	team_move = "🚚 Move",
	team_max_stage = "This is the biggest stage!",
	-- research
	research_title = "🔬 Research",
	research_points = "RP: {points}",
	research_hint = "Every released game gives as many RP as its score",
	research_branch_genres = "Genres",
	research_branch_tech = "Technology",
	research_branch_studio = "Studio",
	research_cost = "{cost} RP",
	research_buy = "Research · {cost} RP",
	research_need = "Need {cost} RP",
	research_owned = "✓ Researched",
	research_requires = "🔒 First: {names}",
	research_genre_owned = "(genre already unlocked)",
	-- tutorial
	tutorial_desk = "Step on the green button: it's your first desk",
	tutorial_open = "Sit at your computer to open “Make a game”",
	tutorial_pick = "Pick a genre and a topic",
	tutorial_start = "Split the focus and start development",
	tutorial_wait = "While the studio works, buy a computer (or just wait)",
	tutorial_release = "Critics have rated your game! The money is yours",
	tutorial_done = "Buy upgrades and make better games. Bonus: {money}!",
	tutorial_skip = "Skip",
	tutorial_ok = "Done",
	-- retention
	trend_banner = "🔥 Trending: {genre} + {topic}, {time} left",
	rebirth_title = "♻️ Rebirth",
	rebirth_count = "Rebirths: {count} · income ×{mult}",
	rebirth_next = "After rebirth: income ×{mult} forever",
	rebirth_need_office = "Move to an office",
	rebirth_need_cash = "Money: {price}",
	rebirth_resets = "Resets: money (you keep $100), upgrades, unlocked genres and topics",
	rebirth_keeps = "Keeps: best score and games released",
	rebirth_button = "Start over",
	rebirth_confirm = "Sure? Click again",
	rebirth_locked = "Requirements not met",
	rebirth_done = "Your studio starts over! Income ×{mult}",
	rebirth_close = "Close",
	offline_title = "While you were away",
	offline_amount = "+{money}",
	offline_hint = "Your studio kept working at half income",
	offline_claim = "Claim",
	-- shop
	shop_title = "🛒 Shop",
	shop_tab_ads = "Ads",
	shop_tab_passes = "Game Passes",
	shop_tab_boosts = "Boosts",
	shop_robux = "R$ {price}",
	shop_soon = "Soon",
	shop_owned = "✓ Owned",
	shop_ad_line = "+{percent}% revenue for {minutes} min",
	shop_ad_note = "Bonuses don't stack: the biggest one applies, up to +100%",
	shop_charges = "You have: {count}",
	shop_coffee_left = "Active for {minutes} more min",
	shop_income_amount = "Now ≈ {money}",
	ad_name_social = "Social media banners",
	ad_name_streamers = "Streamers",
	ad_name_tv = "TV ads",
	ad_name_worldwide = "Worldwide campaign",
	-- quests
	quests_title = "Quests",
	quests_tab_quests = "Quests",
	quests_tab_daily = "Daily",
	quests_tab_leaders = "Leaders",
	quests_claim = "Claim",
	quests_claimed = "✓ Claimed",
	quests_progress = "{progress} / {target}",
	quests_daily_reset = "New quests in {time}",
	quests_loading = "Loading…",
	reward_income = "{minutes} min of income (~{money})",
	reward_research = "{count} RP",
	reward_badge = "“{name}” badge",
	reward_income_bonus = "+{percent}% income forever",
	reward_employee = "employee “{name}”",
	reward_coffee = "coffee ×2 speed for {minutes} min",
	reward_ad = "ads +{percent}% for {minutes} min",
	reward_trophy = "“{name}” decor",
	badge_masterpiece = "Masterpiece",
	employee_ghost_coder = "Ghost Coder",
	trophy_weekly_cup = "Weekly Cup",
	leaders_best = "Best score",
	leaders_games = "Games released",
	leaders_unavailable = "Leaderboard unavailable",
	leaders_empty = "Nobody yet",
	daily_reward_title = "Daily reward",
	daily_reward_day = "Day {day}",
	daily_reward_claim = "Day {day} — claim",
	daily_reward_hint = "Come back every day: missing one restarts the streak",
	-- expo
	expo_banner = "🏆 Game expo in {time} · prize {prize}",
	expo_banner_leader = "🏆 Expo in {time} · leader: “{name}” {score}/10 ({player})",
	expo_winner = "🏆 “{name}” by {player} won the expo with {score}/10! Prize {prize}",
	expo_you_won = "🏆 Your “{name}” won the expo! +{prize}",
	expo_no_games = "🏆 No games at this expo. Release one and the prize is yours!",
	-- desk + dev events + item bonuses
	hud_sit = "🪑 Sit at your computer",
	hud_paused = "⏸ Paused — sit at your computer",
	bonus_pps = "+{value} pts/s",
	bonus_speed = "−{value}% time",
	bonus_review = "+{value} score",
	devevent_ok = "👍 It worked!",
	devevent_fail = "😬 That didn't go well…",
	devevent_skip = "Okay, back to work",
	devevent_bug_title = "🐛 Found a bug!",
	devevent_bug_a = "Fix it",
	devevent_bug_b = "Leave it",
	devevent_music_title = "🎵 The composer brought a track",
	devevent_music_a = "Add it to the game",
	devevent_music_b = "Not now",
	devevent_art_title = "🎨 The artist drew amazing art",
	devevent_art_a = "Put it in!",
	devevent_art_b = "Skip",
	devevent_story_title = "📖 A story idea!",
	devevent_story_a = "Write it in",
	devevent_story_b = "Not needed",
	devevent_crunch_title = "🔥 The deadline is on fire!",
	devevent_crunch_a = "Crunch: go faster",
	devevent_crunch_b = "Stay calm",
	devevent_playtest_title = "🧪 Testers are bored in a level",
	devevent_playtest_a = "Redo it",
	devevent_playtest_b = "Good enough",
	devevent_streamer_title = "📺 A streamer noticed the game",
	devevent_streamer_a = "Show a demo",
	devevent_streamer_b = "Too early",
	-- hits
	hit_prompt = "🕵️ Steal",
	hit_new = "📀 “{name}” is a hit! ★{score}, +{income}/min on your shelf",
	hit_shelf_full = "📀 “{name}” didn't fit: your shelf has stronger hits",
	hit_income = "💰 Your hits earned {amount}",
	hit_carry_hint = "🏃 Carry “{name}” to your own hit shelf!",
	hit_stolen_by_you = "😈 You stole “{name}” from {player}",
	hit_lost = "😢 {player} stole your “{name}”",
	hit_alarm = "🚨 Someone is stealing your hit! “{name}” — {player}. Catch them!",
	hit_alarm_arrow = "🚨 THIEF",
	hit_caught_thief = "🛡️ You caught a thief! +{amount}",
	hit_you_were_caught = "🚨 {player} caught you! Fine: {amount}",
	hit_returned = "↩️ “{name}” is back on your shelf",
	hit_carry_failed = "↩️ The cartridge went back to its owner",
	hit_err_newbie = "🔰 You can steal after releasing {count} games",
	hit_err_victim_newbie = "🔰 Newcomers can't be robbed",
	hit_err_cooldown = "⏳ You can steal again in {seconds}s",
	hit_err_immune = "🛡️ This studio was just robbed — wait {seconds}s",
	hit_err_locked = "🔒 The studio is closed",
	hit_err_busy = "Someone is already carrying this cartridge",
	hit_window_title = "🔒 Hits & protection",
	hit_summary = "Hits: {count}/{slots}, income {income}/min",
	hit_rules = "Games rated 7+ become cartridges on your shelf and earn money every minute. Steal other players' cartridges and carry them to your shelf — or catch a thief by touching them.",
	hit_lock = "🔒 Close the studio for {seconds}s",
	hit_locked = "🔒 Closed for {seconds}s more",
	hit_lock_cooldown = "⏳ Can close again in {time}",
	hit_lock_hint = "While the studio is closed, your cartridges can't be stolen.",
	hit_my_stats = "You: 😈 {steals} steals (+{income}/min) · 🛡️ caught {catches} · got caught {caught}",
	hit_close = "Close",
	thief_title = "😈 Top thieves",
	thief_tab_server = "This server",
	thief_tab_global = "All time",
	thief_unavailable = "Unavailable",
	thief_empty = "Nobody has stolen anything yet",
	thief_row = "{place}. {name}   😈 {steals}   🛡️ {catches}",
	thief_crown = "👑 Top thief",
} :: { [string]: string }

-- Подставить {key} из vars; неизвестные ключи остаются как есть
function Texts.format(lang: Lang, key: string, vars: { [string]: any }?): string
	local text = Texts.lookup(lang, key) or Texts.en[key] or Texts.ru[key] or key
	if vars then
		text = text:gsub("{(%w+)}", function(name: string): string?
			local value = vars[name]
			return if value ~= nil then tostring(value) else nil
		end)
	end
	return text
end

-- $12 500
function Texts.money(amount: number): string
	local digits = tostring(math.floor(amount))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
	return "$" .. grouped
end

return Texts
