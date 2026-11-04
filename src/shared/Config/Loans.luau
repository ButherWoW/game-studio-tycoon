--!strict
-- Кредит банка (LoanService). Денег меньше threshold — всплывает предложение кредита.
-- Вернуть нужно сумму + interest; repayShare дохода каждой выпущенной игры уходит в погашение,
-- остаток можно погасить сам. Один кредит за раз, только со своим гаражом (в парке — копим сами).

local Loans = {}

-- Ниже этого баланса предлагаем кредит
Loans.threshold = 50
-- Предложение снимается, когда денег снова не меньше threshold × resetFactor (без мигания окна)
Loans.resetFactor = 4
-- Сразу после покупки гаража банк молчит столько секунд (новичку и так приходят окна
-- названия студии и туториала); без названия студии кредит не предлагаем вовсе
Loans.graceAfterGarage = 120
-- Сумма кредита по этапу студии: гараж, офис, этаж, небоскрёб
Loans.amounts = { 500, 3_000, 15_000, 60_000 }
-- Переплата: +20% к сумме
Loans.interest = 0.2
-- Доля дохода каждой игры, которая идёт в погашение
Loans.repayShare = 0.3

function Loans.amountFor(studioLevel: number): number
	return Loans.amounts[math.clamp(studioLevel, 1, #Loans.amounts)] or Loans.amounts[1]
end

function Loans.repayFor(amount: number): number
	return math.ceil(amount * (1 + Loans.interest))
end

return Loans
