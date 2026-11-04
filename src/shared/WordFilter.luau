--!strict
-- Свой фильтр мата для названий игр и студий — поверх фильтра Roblox (TextService),
-- который слабо ловит русский мат и не работает в Studio. Общий для сервера (решает)
-- и клиента (сразу подсказывает в окне ввода).
-- Ловит обходы: регистр, латиница вместо кириллицы (xyй), цифры (3 → з, 0 → о),
-- ё → е, повторы букв и пробелы/точки между буквами («х у й», «х.у.й»).

local WordFilter = {}

-- Корни, которые плохие в любом месте слова (и в слитном тексте без пробелов)
local ANYWHERE = {
	"хуй",
	"хуе",
	"хуё",
	"хуя",
	"хуи",
	"пизд",
	"пезд",
	"ебан",
	"ебат",
	"ебал",
	"ебуч",
	"ебну",
	"уеба",
	"заеб",
	"выеб",
	"доеб",
	"наеб",
	"отъеб",
	"проеб",
	"мудак",
	"мудил",
	"пидор",
	"пидар",
	"педик",
	"гандон",
	"гондон",
	"залуп",
	"шлюх",
	"блядь",
	"бляд",
	"сучар",
	"дрочи",
	"говноед",
	"fuck",
	"fuk",
	"bitch",
	"cunt",
	"nigg",
	"nigga",
	"fagg",
	"faggot",
	"whore",
	"asshole",
	"dickhead",
	"pussy",
}

-- Корни, плохие только в начале слова (внутри слова — обычные слова: «рубля», «сукно» и т.п.)
local WORD_START = {
	"бля",
	"сука",
	"суки",
	"сучк",
	"еба",
	"ебл",
	"ебу",
	"ебн",
	"дроч",
	"шлюш",
	"shit",
	"slut",
	"dick",
	"porn",
	"sex",
}

-- Латиница и цифры, похожие на кириллицу, — в кириллицу (только для проверки)
local LOOKALIKE: { [string]: string } = {
	a = "а",
	b = "в",
	c = "с",
	e = "е",
	k = "к",
	m = "м",
	o = "о",
	p = "р",
	t = "т",
	x = "х",
	y = "у",
	["0"] = "о",
	["3"] = "з",
	["@"] = "а",
	["6"] = "б",
}

local function lowerCode(code: number): number
	if code >= 0x0410 and code <= 0x042F then -- А–Я
		return code + 0x20
	elseif code == 0x0401 or code == 0x0451 then -- Ё ё → е
		return 0x0435
	elseif code >= 65 and code <= 90 then -- A–Z
		return code + 32
	end
	return code
end

local function isLetter(code: number): boolean
	return (code >= 97 and code <= 122) or (code >= 0x0430 and code <= 0x044F) or code == 0x0451
end

-- Слова в нижнем регистре: латиница оставлена как есть (для английских корней) и отдельно
-- «кириллизованная» копия (для русских корней, написанных латиницей)
local function normalize(text: string): ({ string }, { string })
	local latinWords, cyrWords = {}, {}
	local latin, cyr = {}, {}
	local last = ""
	local function flush()
		if #latin > 0 then
			table.insert(latinWords, table.concat(latin))
			table.insert(cyrWords, table.concat(cyr))
		end
		latin, cyr, last = {}, {}, ""
	end
	for _, rawCode in utf8.codes(text) do
		local code = lowerCode(rawCode)
		local char = utf8.char(code)
		local mapped = LOOKALIKE[char]
		if isLetter(code) or mapped then
			local cyrChar = mapped or char
			-- Схлопываем повторы: «хууууй» → «хуй»
			if cyrChar ~= last then
				table.insert(latin, char)
				table.insert(cyr, cyrChar)
				last = cyrChar
			end
		else
			flush()
		end
	end
	flush()
	return latinWords, cyrWords
end

local function containsAny(text: string, roots: { string }, atStart: boolean): boolean
	for _, root in roots do
		local position = string.find(text, root, 1, true)
		if position and (not atStart or position == 1) then
			return true
		end
	end
	return false
end

-- true — в тексте нет мата
function WordFilter.isClean(text: string): boolean
	if not utf8.len(text) then
		return false
	end
	local latinWords, cyrWords = normalize(text)
	for i, word in latinWords do
		local cyrWord = cyrWords[i]
		if
			containsAny(word, ANYWHERE, false)
			or containsAny(cyrWord, ANYWHERE, false)
			or containsAny(word, WORD_START, true)
			or containsAny(cyrWord, WORD_START, true)
		then
			return false
		end
	end
	-- Буквы через пробел или точку: «х у й», «f.u.c.k» — склеиваем только короткие «слова»
	-- (1–2 буквы), чтобы обычные соседние слова случайно не сложились в мат
	local shortLatin, shortCyr = {}, {}
	for i, word in latinWords do
		if (utf8.len(word) or 0) <= 2 then
			table.insert(shortLatin, word)
			table.insert(shortCyr, cyrWords[i])
		end
	end
	local joinedLatin = table.concat(shortLatin)
	local joinedCyr = table.concat(shortCyr)
	return not (containsAny(joinedLatin, ANYWHERE, false) or containsAny(joinedCyr, ANYWHERE, false))
end

return WordFilter
