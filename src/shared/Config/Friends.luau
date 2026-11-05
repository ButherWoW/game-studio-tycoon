--!strict
-- Уведомления, друзья, обмен (волна 2): опт-ин уведомлений Roblox, награда за приглашение друга,
-- обмен косметикой между игроками на сервере. Код — NotifyService, ReferralService, TradeService
-- (сервер) и NotifyPrompt, FriendsController, TradeWindow (клиент). Настройка в Creator Hub —
-- docs/NOTIFY_REFER_TRADE.md.

local Skins = require(script.Parent.Skins)
local Posters = require(script.Parent.Posters)
local Mascots = require(script.Parent.Mascots)

export type ItemKind = "skin" | "poster" | "mascot"

local Friends = {
	-- Опт-ин уведомлений Roblox (ExperienceNotificationService): один раз после важного момента —
	-- покупки гаража или первого релиза в сессии (если гараж уже был)
	notify = {
		checkSeconds = 15, -- как часто сервер смотрит, пора ли предложить
		minSessionSeconds = 60, -- не раньше, чем через минуту после входа
		maxTries = 3, -- Roblox не дал показать окно (Studio, возраст) — пробуем в следующих сессиях
		windowWaitSeconds = 60, -- клиент ждёт, пока закроется окно игры, потом пропускает
	},

	-- Награда за приглашение: друг пришёл по приглашению / следом за игроком / друг на сервере
	referral = {
		inviterIncomeMinutes = 15, -- пригласившему: N минут дохода ...
		inviterCoffeeMinutes = 10, -- ... и кофе (×2 к скорости разработки)
		newPlayerCash = 2000, -- новичку
		minPlaySeconds = 5 * 60, -- новичок должен поиграть столько, прежде чем награды выдадут
		newWindowSeconds = 10 * 60, -- «новый»: первый вход в игру был не раньше этого
		inviterDailyCap = 10, -- пригласивший получает награду не больше N раз за сутки (UTC)
		expireSeconds = 7 * 24 * 3600, -- не выдали за неделю (пригласивший не заходил) — сгорает
		tickSeconds = 10,
		inviteReportCooldown = 5, -- отчёт клиента «отправил приглашения» не чаще, с
	},

	-- Обмен: косметика за $ (скины, постеры, маскоты) и деньги. Купленное за Robux не меняется
	trade = {
		maxItems = 6, -- предметов с одной стороны
		maxCashShare = 0.5, -- денег не больше этой доли своего баланса (защита от перекачки с альтов)
		lockSeconds = 3, -- после любого изменения подтвердить можно только через N с
		requestSeconds = 30, -- запрос без ответа истекает
		tradeSeconds = 5 * 60, -- обмен целиком не дольше
		requestCooldown = 3, -- запросы не чаще, с
		declineCooldown = 30, -- после отказа тому же игроку не чаще, с
		offerCooldown = 0.25, -- изменения предложения не чаще, с
		afterTradeCooldown = 10, -- после обмена новый — через N с
		-- Денег от обменов за сутки (UTC) получатель берёт не больше N минут своего дохода
		-- (RewardService.incomeForMinutes): альты не перекачивают деньги повторными обменами по 50%
		dailyCashMinutes = 120,
	},
}

-- Можно ли обменивать предмет: только то, что продаётся за $ (премиум и маскоты за Robux,
-- маскоты за достижение/группу — нет)
function Friends.tradeable(kind: any, id: any): boolean
	if type(id) ~= "string" then
		return false
	end
	if kind == "skin" then
		local skin = Skins.get(id)
		return skin ~= nil and not skin.premium
	elseif kind == "poster" then
		local poster = Posters.get(id)
		return poster ~= nil and not poster.premium
	elseif kind == "mascot" then
		local mascot = Mascots.get(id)
		return mascot ~= nil and mascot.how == "cash"
	end
	return false
end

return Friends
