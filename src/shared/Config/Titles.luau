--!strict
-- Титулы над головой (роадмап 7.21). Открываются достижениями (Config/Achievements), числом
-- Rebirth, гейм-джемом, сезонным пропуском и Roblox Premium; другие фичи выдают свои через
-- TitleService.grant(player, titleId) (условие "grant"). Игрок выбирает один (или ни одного)
-- в окне 🏆 → вкладка «Титулы»; сервер проверяет, что титул открыт (TitleService).
-- Имена — ключи title_<id> в Texts и Locales; условия — title_cond_<kind>.
--
-- Условия (cond):
--   achievement = <id>   — получено достижение (profile.achievements.done);
--   rebirths = N         — profile.rebirths >= N;
--   jamFlag = <flag>     — отметка гейм-джема (profile.gameJam.flags: jamTop10, jamTop100);
--   season = true        — сезонное звание хотя бы одного сезона (profile.seasonTitles);
--   premium = true       — Roblox Premium: доступен, пока подписка активна (в owned не пишется);
--   grant = true         — только через TitleService.grant (события, сейф и т.п.).
-- Временные титулы: TitleService.grant(player, id, untilAt) — титул сразу надевается и снимается
-- в untilAt (os.time), после чего возвращается прежний выбор игрока.
-- condKey — свой ключ подсказки title_cond_<condKey> вместо общего по условию.

export type Condition = {
	achievement: string?,
	rebirths: number?,
	jamFlag: string?,
	season: boolean?,
	premium: boolean?,
	grant: boolean?,
}

export type Title = {
	id: string,
	icon: string,
	color: Color3,
	cond: Condition,
	condKey: string?,
}

local Titles = {}

-- Табличка над головой: под ником (VIP-табличка VipService — выше, StudsOffset 3)
Titles.tag = {
	offsetY = 1.5, -- studs над центром головы: под ником Roblox (подобрать в Studio)
	width = 6, -- studs
	height = 0.6,
	maxDistance = 60,
}

-- Как часто сервер перепроверяет условия (достижения и Rebirth приходят и без опроса)
Titles.checkSeconds = 15

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local BRONZE = rgb(214, 150, 96)
local SILVER = rgb(205, 214, 230)
local GOLD = rgb(255, 205, 70)
local PURPLE = rgb(190, 130, 255)

local list: { Title } = {
	{ id = "rookie", icon = "🕹️", color = SILVER, cond = { achievement = "garage" } },
	{ id = "hitmaker", icon = "🎯", color = BRONZE, cond = { achievement = "hits_10" } },
	{ id = "masterpiece", icon = "🌟", color = GOLD, cond = { achievement = "score_10" } },
	{ id = "director", icon = "🏢", color = SILVER, cond = { achievement = "office_3" } },
	{ id = "teamlead", icon = "👥", color = SILVER, cond = { achievement = "hire_10" } },
	{ id = "tycoon", icon = "💎", color = GOLD, cond = { achievement = "earn_100m" } },
	{ id = "expo_star", icon = "🏅", color = GOLD, cond = { achievement = "expo_25" } },
	{ id = "thief", icon = "🦝", color = PURPLE, cond = { achievement = "steal_10" } },
	{ id = "guard", icon = "🛡️", color = SILVER, cond = { achievement = "catch_10" } },
	{ id = "favorite", icon = "❤️", color = rgb(255, 120, 150), cond = { achievement = "likes_1000" } },
	{ id = "loyal", icon = "📅", color = BRONZE, cond = { achievement = "days_30" } },
	{ id = "flop_king", icon = "🍅", color = rgb(255, 110, 90), cond = { achievement = "flop" } },
	{ id = "reborn", icon = "♻️", color = rgb(110, 220, 160), cond = { rebirths = 1 } },
	{ id = "veteran", icon = "⭐", color = SILVER, cond = { rebirths = 5 } },
	{ id = "legend", icon = "👑", color = GOLD, cond = { rebirths = 10 } },
	{ id = "jam_finalist", icon = "🎮", color = SILVER, cond = { jamFlag = "jamTop100" } },
	{ id = "jam_champion", icon = "🏆", color = GOLD, cond = { jamFlag = "jamTop10" } },
	{ id = "season_star", icon = "🎟️", color = PURPLE, cond = { season = true } },
	{ id = "premium", icon = "💠", color = rgb(120, 200, 255), cond = { premium = true } },
	-- Временные (TitleService.grant с untilAt): победитель блиц-джема (DailyEventService, на сутки)
	-- и «Игра недели» (GotwService, до конца недели; на табличке — место из атрибута GotwRank)
	{ id = "blitz_champion", icon = "⚡", color = GOLD, cond = { grant = true }, condKey = "blitz" },
	{ id = "gotw_winner", icon = "🏆", color = GOLD, cond = { grant = true }, condKey = "gotw" },
}
Titles.list = list

local byId: { [string]: Title } = {}
for _, title in list do
	byId[title.id] = title
end
Titles.byId = byId

-- Ключ текста условия для окна: title_cond_<kind>
function Titles.condKind(title: Title): string
	local c = title.cond
	if title.condKey then
		return title.condKey
	elseif c.achievement then
		return "ach"
	elseif c.rebirths then
		return "rebirths"
	elseif c.jamFlag then
		return if c.jamFlag == "jamTop10" then "jam10" else "jam100"
	elseif c.season then
		return "season"
	elseif c.premium then
		return "premium"
	end
	return "event"
end

return Titles
