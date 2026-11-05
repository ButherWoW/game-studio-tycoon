--!strict
-- Биржа (роадмап 7.2–7.4, StockService).
-- IPO: самая последняя часть 3-го этажа. Условия — весь интерьер 3-го этажа куплен,
-- доход ≥ ipo.minIncomePerMinute, средняя оценка последних ipo.recentGames игр ≥ ipo.minAvgScore;
-- выход на биржу стоит ipo.cost. После IPO студия — компания на бирже, навсегда.
-- Акции: у компании totalShares акций. Цена акции = стоимость компании / totalShares;
-- стоимость = доход в минуту × valuationMinutes × множитель оценки ((средняя / pivotScore)^scorePower).
-- Другие игроки покупают и продают по текущей цене с комиссией tradeFee. Свои акции купить нельзя.
-- Дивиденды: держатели получают dividendShare дохода компании в минуту по своей доле, даже когда
-- владелец не в игре (тогда — по его офлайн-доходу). Компания с доходом ниже
-- dividendMinIncome дивиденды не платит.

local Stocks = {}

Stocks.ipo = {
	cost = 25_000_000,
	requiresLevel = 4, -- 3-й этаж открыт (Config/Stages)
	minIncomePerMinute = 120_000,
	minAvgScore = 7.5,
	recentGames = 20, -- средняя оценка считается по стольким последним играм
	-- Владельцу после IPO: +10% к доходу каждого релиза
	incomeBonus = 0.1,
}

Stocks.totalShares = 1_000_000
-- Стоимость компании = доход в минуту × столько минут (10 часов дохода)
Stocks.valuationMinutes = 600
-- Множитель цены от средней оценки: (средняя / pivotScore) ^ scorePower, в пределах [min, max]
Stocks.pivotScore = 7.5
Stocks.scorePower = 2
Stocks.scoreFactorMin = 0.3
Stocks.scoreFactorMax = 2
-- Цена акции не ниже этого
Stocks.minPrice = 1

-- Комиссия биржи с каждой сделки (покупка дороже, продажа дешевле)
Stocks.tradeFee = 0.02
-- Не больше стольких акций одной компании у одного игрока (10%)
Stocks.maxSharesPerCompany = 100_000
-- Не больше стольких компаний в портфеле
Stocks.maxCompaniesInPortfolio = 10

-- Дивиденды: доля дохода компании в минуту, которую делят все акции
Stocks.dividendShare = 0.02
Stocks.dividendMinIncome = 30_000
Stocks.dividendIntervalSeconds = 60

-- Владелец не обновлял запись столько секунд — он не в игре, считаем по офлайн-доходу
Stocks.ownerOfflineAfter = 180
-- Банкротство (решение владельца): у компании закончились деньги — баланс владельца в минусе
-- (долг, Config/Bailiffs) дольше bankruptAfterSeconds подряд. Компанию снимают с биржи (делистинг),
-- акции у держателей сгорают — они теряют вложенное. Владелец может снова выйти на IPO
Stocks.bankruptAfterSeconds = 10 * 60
-- Как часто сервер владельца обновляет запись компании
Stocks.updateSeconds = 120
-- Свечной график: одна свеча = candleSeconds, показываем последних candleCount;
-- внутри свечи цена берётся каждые candleSampleSeconds (из них — открытие/максимум/минимум/закрытие)
Stocks.candleSeconds = 30 * 60
Stocks.candleCount = 48
Stocks.candleSampleSeconds = 60
-- Рыночный шум (решение владельца: «график хаотично двигается»): цена = основа × e^шум.
-- Шум — сумма плавных волн разной длины (секунды) и силы; у каждой компании свой рисунок,
-- одинаковый на всех серверах (StockNoise на сервере). Итог примерно ±30% от основы
Stocks.noiseLayers = {
	{ period = 5 * 60, amplitude = 0.02 },
	{ period = 40 * 60, amplitude = 0.05 },
	{ period = 4 * 60 * 60, amplitude = 0.08 },
	{ period = 24 * 60 * 60, amplitude = 0.12 },
}
-- Список компаний на бирже (топ по стоимости) перечитывается не чаще, чем раз в столько секунд
Stocks.listRefreshSeconds = 120
Stocks.listSize = 30

function Stocks.scoreFactor(avgScore: number): number
	local f = (math.max(avgScore, 0) / Stocks.pivotScore) ^ Stocks.scorePower
	return math.clamp(f, Stocks.scoreFactorMin, Stocks.scoreFactorMax)
end

-- Цена одной акции по доходу компании в минуту и средней оценке
function Stocks.priceFor(incomePerMinute: number, avgScore: number): number
	local value = math.max(incomePerMinute, 0) * Stocks.valuationMinutes * Stocks.scoreFactor(avgScore)
	return math.max(math.floor(value / Stocks.totalShares + 0.5), Stocks.minPrice)
end

function Stocks.buyCost(price: number, shares: number): number
	return math.ceil(price * shares * (1 + Stocks.tradeFee))
end

function Stocks.sellPayout(price: number, shares: number): number
	return math.floor(price * shares * (1 - Stocks.tradeFee))
end

-- Дивиденды в минуту на shares акций компании с доходом incomePerMinute
function Stocks.dividendPerMinute(incomePerMinute: number, shares: number): number
	if incomePerMinute < Stocks.dividendMinIncome then
		return 0
	end
	return incomePerMinute * Stocks.dividendShare * shares / Stocks.totalShares
end

return Stocks
