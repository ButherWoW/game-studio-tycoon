--!strict
-- Защита от перепродажи при региональных ценах (Managed Pricing):
-- MarketplaceService:GetUsersPriceLevelsAsync возвращает уровень цены игрока (1..1000, 1000 — полная
-- цена, меньше — дешевле). Подарить за Robux можно только игроку с таким же или более низким
-- уровнем цены, чем у дарящего; обмениваться предметами и деньгами — только игрокам одного уровня,
-- иначе купленное по низкой цене уходило бы в регион с высокой. Результат не кэшируем (требование
-- Roblox): спрашиваем при каждой проверке. Сбой API на живом сервере = запрет (безопасная сторона),
-- в Studio разрешаем, чтобы не мешать тестам.

local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local PriceLevels = {}

local FULL_PRICE = 1000

-- уровни двух игроков или nil, если не удалось узнать
local function levelsOf(a: Player, b: Player): (number?, number?)
	local ok, result = pcall(function()
		return MarketplaceService:GetUsersPriceLevelsAsync({ a.UserId, b.UserId })
	end)
	if not ok or type(result) ~= "table" then
		return nil, nil
	end
	local lookup: { [number]: number } = {}
	for _, info in result :: { any } do
		-- Поля по документации: UserId, PriceLevel; на случай другого регистра принимаем и его
		local userId = if type(info) == "table" then (info.UserId or info.userId) else nil
		local level = if type(info) == "table" then (info.PriceLevel or info.priceLevel) else nil
		if type(userId) == "number" and type(level) == "number" then
			lookup[userId] = level
		end
	end
	return lookup[a.UserId], lookup[b.UserId]
end

local function check(a: Player, b: Player, rule: (number, number) -> boolean): boolean
	local la, lb = levelsOf(a, b)
	if la == nil or lb == nil then
		if RunService:IsStudio() then
			la, lb = FULL_PRICE, FULL_PRICE
		else
			warn(
				"[PriceLevels] не удалось получить уровни цен — действие запрещено"
			)
			return false
		end
	end
	return rule(la :: number, lb :: number)
end

-- Подарок от sender к recipient: уровень дарящего не ниже уровня получателя
function PriceLevels.canGift(sender: Player, recipient: Player): boolean
	return check(sender, recipient, function(s, r)
		return s >= r
	end)
end

-- Обмен: уровни одинаковы
function PriceLevels.canTrade(a: Player, b: Player): boolean
	return check(a, b, function(x, y)
		return x == y
	end)
end

return PriceLevels
