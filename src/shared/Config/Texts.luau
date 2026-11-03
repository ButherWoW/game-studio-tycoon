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
} :: { [string]: string }

Texts.en = {
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
