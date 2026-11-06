--!strict
-- Живые цены в R$ (Managed Pricing / региональные цены Roblox).
-- Игрок в другой стране платит не ту цену, что записана в Config (robuxPrice), поэтому везде,
-- где в интерфейсе видна цена, показываем то, что вернул Roblox: MarketplaceService:
-- GetProductInfoAsync (PriceInRobux). robuxPrice из Config — только запасной вариант, пока ответ
-- не пришёл или не удался. Ответы кэшируются на клиенте; Controllers/PricePrefetch загружает
-- цены всех товаров и геймпассов при старте, чтобы к открытию окон кэш был полон.
-- of(id, fallback, isPass) всегда отвечает сразу (из кэша или fallback) и при промахе
-- запускает загрузку; RobuxPrice.changed срабатывает, когда пришла новая цена.

local MarketplaceService = game:GetService("MarketplaceService")

local RETRY_AFTER = 30 -- после неудачи не дёргаем Roblox чаще, чем раз в 30 с

local RobuxPrice = {}

local cache: { [string]: number } = {}
local inflight: { [string]: boolean } = {}
local failedAt: { [string]: number } = {}
local changedEvent = Instance.new("BindableEvent")
RobuxPrice.changed = changedEvent.Event

local function keyOf(id: number, isPass: boolean?): string
	return (if isPass then "p" else "d") .. tostring(id)
end

local function fetch(id: number, isPass: boolean?)
	local key = keyOf(id, isPass)
	if cache[key] or inflight[key] then
		return
	end
	local failed = failedAt[key]
	if failed and os.clock() - failed < RETRY_AFTER then
		return
	end
	inflight[key] = true
	task.spawn(function()
		local infoType = if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(id, infoType)
		end)
		inflight[key] = nil
		local price = if ok and type(info) == "table" then (info :: any).PriceInRobux else nil
		if type(price) == "number" and price > 0 then
			failedAt[key] = nil
			if cache[key] ~= price then
				cache[key] = price
				changedEvent:Fire(id)
			end
		else
			failedAt[key] = os.clock()
		end
	end)
end

-- Цена для показа: живая из кэша или fallback (цена из Config). id 0 — товара нет.
function RobuxPrice.of(id: number, fallback: number?, isPass: boolean?): number
	local base = fallback or 0
	if id == 0 then
		return base
	end
	local cached = cache[keyOf(id, isPass)]
	if cached then
		return cached
	end
	fetch(id, isPass)
	return base
end

-- Загрузить цену заранее (без возврата)
function RobuxPrice.prefetch(id: number, isPass: boolean?)
	if id > 0 then
		fetch(id, isPass)
	end
end

-- Обойти таблицу конфига и запросить цены всех productId / gamePassId внутри
function RobuxPrice.prefetchConfig(config: any)
	local seen: { [any]: boolean } = {}
	local function walk(node: any, depth: number)
		if type(node) ~= "table" or seen[node] or depth > 6 then
			return
		end
		seen[node] = true
		local productId = node.productId
		if type(productId) == "number" and productId > 0 then
			RobuxPrice.prefetch(productId, false)
		end
		local passId = node.gamePassId
		if type(passId) == "number" and passId > 0 then
			RobuxPrice.prefetch(passId, true)
		end
		for _, child in node do
			walk(child, depth + 1)
		end
	end
	walk(config, 0)
end

return RobuxPrice
