--!strict
-- Рыночный шум цены акций (Config/Stocks.noiseLayers). Только на сервере: клиент видит прошлые
-- свечи, но не может посчитать будущие. Шум — сумма плавных волн («value noise»): на сетке
-- с шагом period у каждой компании свои случайные точки (зерно = id компании + SALT), между
-- ними — плавная интерполяция. Одинаково на всех серверах, без записи в DataStore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Stocks = require(ReplicatedStorage.Shared.Config.Stocks)

local SALT = 0x5DEECE -- меняет рисунок всех графиков разом

local StockNoise = {}

-- Случайное число [-1, 1] для точки сетки (компания, слой, номер точки)
local function lattice(companyId: number, layer: number, index: number): number
	local seed = (companyId * 7919 + layer * 104729 + index * 15485863 + SALT) % 2147483647
	return Random.new(seed):NextNumber() * 2 - 1
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- Шум в момент time (os.time), обычно в пределах ±(сумма amplitude)
function StockNoise.at(companyId: number, time: number): number
	local total = 0
	for layer, wave in Stocks.noiseLayers do
		local x = time / wave.period
		local i = math.floor(x)
		local a = lattice(companyId, layer, i)
		local b = lattice(companyId, layer, i + 1)
		total += (a + (b - a) * smooth(x - i)) * wave.amplitude
	end
	return total
end

-- Цена акции в момент time: основа (Stocks.priceFor) × e^шум
function StockNoise.price(companyId: number, basePrice: number, time: number): number
	local price = basePrice * math.exp(StockNoise.at(companyId, time))
	return math.max(math.floor(price + 0.5), Stocks.minPrice)
end

export type Candle = { t: number, o: number, h: number, l: number, c: number }

-- Свечи по Stocks.candleSeconds до момента now (последняя — текущая, незакрытая).
-- Основа цены берётся текущая: прошлые изменения дохода график не помнит, только шум
function StockNoise.candles(companyId: number, basePrice: number, now: number, listedAt: number): { Candle }
	local size = Stocks.candleSeconds
	local step = Stocks.candleSampleSeconds
	local lastStart = now - now % size
	local firstStart = math.max(lastStart - (Stocks.candleCount - 1) * size, listedAt - listedAt % size)
	local list: { Candle } = {}
	local start = firstStart
	while start <= lastStart do
		local stop = math.min(start + size, now)
		local open = StockNoise.price(companyId, basePrice, start)
		local high, low, close = open, open, open
		local t = start + step
		while t <= stop do
			close = StockNoise.price(companyId, basePrice, t)
			high = math.max(high, close)
			low = math.min(low, close)
			t += step
		end
		-- Закрытие — точно на конце свечи (у текущей — цена прямо сейчас, как у сделок)
		close = StockNoise.price(companyId, basePrice, stop)
		high = math.max(high, close)
		low = math.min(low, close)
		table.insert(list, { t = start, o = open, h = high, l = low, c = close })
		start += size
	end
	return list
end

return StockNoise
