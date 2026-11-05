--!strict
-- Фильтр текста, который видят все игроки сервера (рекламные щиты, Зал славы): названия игр и
-- студий — ввод игроков. TextService:FilterStringAsync → GetNonChatStringForBroadcastAsync в pcall.
-- Без start(): библиотека. Результат кэшируется (одно название показывается много раз).

local TextService = game:GetService("TextService")

local CACHE_LIMIT = 500

local BroadcastText = {}

local cache: { [string]: string } = {}
local cacheSize = 0

-- Отфильтрованный текст или nil (фильтр недоступен — показывать нельзя). Уступает поток
function BroadcastText.filter(text: string, fromUserId: number): string?
	if text == "" then
		return ""
	end
	local key = fromUserId .. "\0" .. text
	local cached = cache[key]
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, fromUserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(result) ~= "string" then
		warn("[BroadcastText] Text filter failed:", result)
		return nil
	end
	if cacheSize >= CACHE_LIMIT then
		cache = {}
		cacheSize = 0
	end
	cache[key] = result
	cacheSize += 1
	return result
end

return BroadcastText
