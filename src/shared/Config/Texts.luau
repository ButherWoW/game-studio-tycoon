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
