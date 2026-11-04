--!strict
-- Промокоды (CodeService): для роста через YouTube и Discord.
-- Код вводится без учёта регистра и пробелов по краям; каждый игрок активирует код один раз
-- (profile.codes). expiresAt — unix-время конца действия (nil — бессрочный).
-- Награда (CodeReward): incomeMinutes — N минут дохода (как RewardService.grant),
-- cash — фиксированные $, minCash — не меньше стольких $ (вместе с incomeMinutes),
-- coffeeMinutes — кофе, skin / poster — id из Config/Skins / Config/Posters.
-- Владелец может добавлять новые коды сюда: ключ — код ЗАГЛАВНЫМИ буквами.

export type CodeReward = {
	incomeMinutes: number?,
	cash: number?,
	minCash: number?,
	coffeeMinutes: number?,
	skin: string?,
	poster: string?,
}

export type Code = {
	reward: CodeReward,
	expiresAt: number?,
}

local Codes = {
	-- Защита от перебора: не чаще раза в cooldown секунд и не больше perSession попыток за вход
	cooldown = 2,
	perSession = 10,
	maxLength = 32,

	list = {
		GSTLAUNCH = { reward = { incomeMinutes = 10, coffeeMinutes = 15 } },
		BUILDYOURSTUDIO = { reward = { incomeMinutes = 5, minCash = 5_000 } },
		GAMEJAM = { reward = { coffeeMinutes = 10 } },
		-- Новые коды владельца — сюда же, например:
		-- HALLOWEEN = { reward = { incomeMinutes = 15 }, expiresAt = 1793491200 },
	} :: { [string]: Code },
}

-- Привести ввод к ключу списка: без пробелов по краям, заглавными
function Codes.normalize(raw: any): string?
	if type(raw) ~= "string" or #raw > Codes.maxLength * 4 then
		return nil
	end
	local trimmed = raw:match("^%s*(.-)%s*$") or ""
	if trimmed == "" or #trimmed > Codes.maxLength then
		return nil
	end
	return string.upper(trimmed)
end

return Codes
