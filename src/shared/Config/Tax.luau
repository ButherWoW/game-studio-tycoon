--!strict
-- Налоговая (роадмап 7.1, TaxService). Раз в periodSeconds игры (только время в игре)
-- приходит налог с дохода от релизов за этот период: ставка по этапу студии.
-- На оплату — payWindowSeconds. Не заплатил — штраф (налог × (1 + fineShare)) списывается
-- сам, даже в минус (овердрафт Config/Bailiffs), и начинается «налоговая проверка»:
-- доход релизов × auditRevenueMultiplier на auditSeconds.

local Tax = {}

-- Период налога: 30 минут игры
Tax.periodSeconds = 30 * 60
-- Ставка по этапу студии (profile.studioLevel): гараж, офис (1-й этаж), 2-й этаж, 3-й этаж
Tax.rates = { 0, 0.05, 0.08, 0.12 }
-- Сколько секунд на оплату счёта
Tax.payWindowSeconds = 5 * 60
-- Штраф за неуплату: +50% к налогу
Tax.fineShare = 0.5
-- Налоговая проверка после неуплаты
Tax.auditSeconds = 10 * 60
Tax.auditRevenueMultiplier = 0.8
-- Счёт меньше этого не выставляем (мелочь только раздражает)
Tax.minBill = 100

function Tax.rateFor(studioLevel: number): number
	return Tax.rates[math.clamp(math.floor(studioLevel), 1, #Tax.rates)] or 0
end

function Tax.fineFor(bill: number): number
	return math.ceil(bill * (1 + Tax.fineShare))
end

return Tax
