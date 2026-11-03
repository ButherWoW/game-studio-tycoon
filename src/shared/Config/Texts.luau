--!strict
-- Тексты интерфейса RU + EN (задача A из docs/DEV2_NEXT.md).
-- Подстановки: {name}, {price}, {percent} и т.п. — см. Texts.format.

export type Lang = "ru" | "en"

local Texts = {}

Texts.ru = {
	-- HUD
	hud_cash = "$ {cash}",
	hud_games = "Игр: {count}",
	hud_ad = "Реклама +{percent}%",
	hud_create = "🎮 Создать игру",
	hud_developing = "Разработка: {percent}%",

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
	tutorial_open = "Нажми «Создать игру»",
	tutorial_pick = "Выбери жанр и тему",
	tutorial_start = "Распредели фокус и начни разработку",
	tutorial_wait = "Пока студия работает, купи компьютер (или подожди)",
	tutorial_release = "Критики оценили игру! Деньги — твои",
	tutorial_done = "Покупай апгрейды и делай игры лучше. Бонус: {money}!",
	tutorial_skip = "Пропустить",
	tutorial_ok = "Готово",
} :: { [string]: string }

Texts.en = {
	hud_cash = "$ {cash}",
	hud_games = "Games: {count}",
	hud_ad = "Ads +{percent}%",
	hud_create = "🎮 Make a game",
	hud_developing = "Developing: {percent}%",

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
	tutorial_open = "Press “Make a game”",
	tutorial_pick = "Pick a genre and a topic",
	tutorial_start = "Split the focus and start development",
	tutorial_wait = "While the studio works, buy a computer (or just wait)",
	tutorial_release = "Critics have rated your game! The money is yours",
	tutorial_done = "Buy upgrades and make better games. Bonus: {money}!",
	tutorial_skip = "Skip",
	tutorial_ok = "Done",
} :: { [string]: string }

-- Подставить {key} из vars; неизвестные ключи остаются как есть
function Texts.format(lang: Lang, key: string, vars: { [string]: any }?): string
	local tbl = if lang == "en" then Texts.en else Texts.ru
	local text = tbl[key] or Texts.ru[key] or key
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
