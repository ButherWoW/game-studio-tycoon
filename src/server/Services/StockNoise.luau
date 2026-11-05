--!strict
-- Рыночный шум цены акций (Config/Stocks.noiseLayers). Только на сервере: клиент видит прошлые
-- свечи, но не может посчитать будущие. Шум — сумма плавных волн («value noise»): на сетке
-- с шагом period у каждой компании свои случайные точки, между ними — плавная интерполяция.
-- Зерно точек — секрет компании (record.seed в StockMarket_v1, выдаёт сервер при IPO, клиенту не
-- уходит): код открыт, и по id + константе любой посчитал бы будущие минимумы и максимумы.
-- Одинаково на всех серверах. Без зерна (старые записи до первого ensureSeed) — прежняя формула.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Stocks = require(ReplicatedStorage.Shared.Config.Stocks)

local SALT = 0x5DEECE -- только для старых записей без зерна
-- Зерно < 2^48: с номером точки сетки (до ~1e14) сумма остаётся точным целым double (< 2^53)
local SEED_HALF = 2 ^ 24
local SEED_MAX = SEED_HALF * SEED_HALF
local seedRng = Random.new()

local StockNoise = {}

-- Новое секретное зерно компании (StockService при IPO и для старых записей)
function StockNoise.newSeed(): number
	return seedRng:NextInteger(0, SEED_HALF - 1) * SEED_HALF + seedRng:NextInteger(1, SEED_HALF - 1)
end

-- Зерно из записи DataStore: целое в (0, SEED_MAX), иначе nil
function StockNoise.validSeed(value: any): number?
	if type(value) ~= "number" or value ~= value or value <= 0 or value >= SEED_MAX or value % 1 ~= 0 then
		return nil
	end
	return value
end

-- Случайное число [-1, 1] для точки сетки (компания, слой, номер точки)
local function lattice(companyId: number, seed: number?, layer: number, index: number): number
	if not seed then
		local legacy = (companyId * 7919 + layer * 104729 + index * 15485863 + SALT) % 2147483647
		return Random.new(legacy):NextNumber() * 2 - 1
	end
	return Random.new(seed + layer * 104729 + index * 15485863):NextNumber() * 2 - 1
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- Шум в момент time (os.time), обычно в пределах ±(сумма amplitude)
function StockNoise.at(companyId: number, seed: number?, time: number): number
	local total = 0
	for layer, wave in Stocks.noiseLayers do
		local x = time / wave.period
		local i = math.floor(x)
		local a = lattice(companyId, seed, layer, i)
		local b = lattice(companyId, seed, layer, i + 1)
		total += (a + (b - a) * smooth(x - i)) * wave.amplitude
	end
	return total
end

-- Цена акции в момент time: основа (Stocks.priceFor) × e^шум
function StockNoise.price(companyId: number, seed: number?, basePrice: number, time: number): number
	local price = basePrice * math.exp(StockNoise.at(companyId, seed, time))
	return math.max(math.floor(price + 0.5), Stocks.minPrice)
end

export type Candle = { t: number, o: number, h: number, l: number, c: number }

-- Свечи по Stocks.candleSeconds до момента now (последняя — текущая, незакрытая).
-- Основа цены берётся текущая: прошлые изменения дохода график не помнит, только шум
function StockNoise.candles(
	companyId: number,
	seed: number?,
	basePrice: number,
	now: number,
	listedAt: number
): { Candle }
	local size = Stocks.candleSeconds
	local step = Stocks.candleSampleSeconds
	local lastStart = now - now % size
	-- График полный с первой минуты на бирже: шум есть и «до IPO» (listedAt оставлен для совместимости)
	local _ = listedAt
	local firstStart = lastStart - (Stocks.candleCount - 1) * size
	local list: { Candle } = {}
	local start = firstStart
	while start <= lastStart do
		local stop = math.min(start + size, now)
		local open = StockNoise.price(companyId, seed, basePrice, start)
		local high, low, close = open, open, open
		local t = start + step
		while t <= stop do
			close = StockNoise.price(companyId, seed, basePrice, t)
			high = math.max(high, close)
			low = math.min(low, close)
			t += step
		end
		-- Закрытие — точно на конце свечи (у текущей — цена прямо сейчас, как у сделок)
		close = StockNoise.price(companyId, seed, basePrice, stop)
		high = math.max(high, close)
		low = math.min(low, close)
		table.insert(list, { t = start, o = open, h = high, l = low, c = close })
		start += size
	end
	return list
end

return StockNoise
