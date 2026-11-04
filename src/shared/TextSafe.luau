--!strict
-- Чистка названий, которые видят все игроки (студия, игры): убираем невидимые символы
-- нулевой ширины, «Zalgo» из комбинируемых диакритик и экзотические пробелы.
-- Фильтр Roblox (TextService) это не ловит: название выглядело бы пустым или расползалось.

local TextSafe = {}

-- Диапазоны кодовых точек, которые выбрасываем целиком
local DROP: { { number } } = {
	{ 0x0000, 0x001F }, -- управляющие
	{ 0x007F, 0x009F },
	{ 0x0300, 0x036F }, -- комбинируемые диакритики
	{ 0x0483, 0x0489 },
	{ 0x1AB0, 0x1AFF },
	{ 0x1DC0, 0x1DFF },
	{ 0x200B, 0x200F }, -- нулевой ширины и направление текста
	{ 0x202A, 0x202E },
	{ 0x2060, 0x206F },
	{ 0x20D0, 0x20FF },
	{ 0xFE00, 0xFE0F }, -- селекторы вариантов
	{ 0xFE20, 0xFE2F },
	{ 0xFEFF, 0xFEFF },
	{ 0xE0000, 0xE007F }, -- теги
}

-- Экзотические пробелы — в обычный
local SPACES: { { number } } = {
	{ 0x00A0, 0x00A0 },
	{ 0x1680, 0x1680 },
	{ 0x2000, 0x200A },
	{ 0x2028, 0x2029 },
	{ 0x202F, 0x202F },
	{ 0x205F, 0x205F },
	{ 0x3000, 0x3000 },
	{ 0x3164, 0x3164 }, -- хангыль-заполнитель, выглядит пустым
}

local function inRanges(code: number, ranges: { { number } }): boolean
	for _, range in ranges do
		if code >= range[1] and code <= range[2] then
			return true
		end
	end
	return false
end

-- Вернуть очищенную строку (пробелы схлопнуты, края обрезаны) или nil, если UTF-8 битый
function TextSafe.clean(raw: string): string?
	if not utf8.len(raw) then
		return nil
	end
	local out = {}
	for _, code in utf8.codes(raw) do
		if inRanges(code, SPACES) then
			table.insert(out, " ")
		elseif not inRanges(code, DROP) then
			table.insert(out, utf8.char(code))
		end
	end
	local text = table.concat(out):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return text
end

-- Сколько видимых символов (не пробелов)
function TextSafe.visibleLength(text: string): number
	local count = 0
	for _, code in utf8.codes(text) do
		if code ~= 32 then
			count += 1
		end
	end
	return count
end

return TextSafe
