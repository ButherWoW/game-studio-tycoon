--!strict
-- Контракты издателей (ContractService): с этапа офиса раз в ~intervalSeconds издатель (Config/Rivals)
-- предлагает контракт. Аванс сразу (advanceMinutes дохода), условие и срок в минутах игры (тикает,
-- пока игрок в игре). Выполнил — бонус, провалил — вернуть аванс × failRepayFactor (в долг банка,
-- гасится долей дохода игр, Config/Loans.repayShare). Окно — по правилам Config/Offers.popup.

export type Kind = "genre" | "topic" | "score"
export type Template = { kind: Kind, count: number, minScore: number, minutes: number }

local Contracts = {
	minStage = 2, -- studioLevel: офис
	firstDelaySeconds = 5 * 60, -- после входа / переезда в офис
	intervalSeconds = 10 * 60,
	intervalJitter = 2 * 60, -- ± к интервалу
	offerSeconds = 4 * 60, -- сколько предложение ждёт ответа

	advanceMinutes = 3, -- аванс = доход студии за столько минут (ShopService.incomePerMinute)
	bonusMinutes = 4, -- бонус за выполнение
	failRepayFactor = 1.25,

	templates = {
		{ kind = "genre", count = 2, minScore = 7, minutes = 8 },
		{ kind = "topic", count = 2, minScore = 7, minutes = 8 },
		{ kind = "score", count = 1, minScore = 9, minutes = 10 },
	} :: { Template },
}

return Contracts
