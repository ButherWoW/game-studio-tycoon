--!strict
-- Условия открытия жанров и тем (поле requires в Config/Genres и Config/Topics).
-- Пока условия не выполнены, жанр/тему нельзя купить ни за деньги (UnlockService),
-- ни исследованием (ResearchService). Клиент показывает по ним замок и причину.
-- Работает и с профилем сервера, и со снимком DataService.replicate на клиенте.

local ContentDrops = require(script.Parent.Config.ContentDrops)
local Genres = require(script.Parent.Config.Genres)
local Stages = require(script.Parent.Config.Stages)
local Texts = require(script.Parent.Config.Texts)
local HitCartridges = require(script.Parent.Config.HitCartridges)

-- Виды условий: studioLevel (2 = офис, 3 = 2-й этаж, 4 = 3-й этаж), gamesReleased (всего игр),
-- bestScore (лучшая оценка за всё время), genreGames (игр в жанре), hits (выпущено игр с оценкой
-- >= HitCartridges.minScore), employees (сотрудников в команде). Плюс release — жанр/тема ещё не вышли
-- по графику контента (Config/ContentDrops): need = дней до выхода; эта причина всегда первая
export type Requires = Genres.Requires

export type Missing = {
	kind: string, -- release | studioLevel | gamesReleased | bestScore | genreGames | hits | employees
	need: number,
	have: number,
	genre: string?,
}

type Item = { id: string?, unlockCost: number, requires: Requires? }

local UnlockRules = {}

-- Порядок проверки = порядок показа причин
local ORDER = { "studioLevel", "gamesReleased", "bestScore", "genreGames", "hits", "employees" }

local function num(value: any): number
	return if type(value) == "number" and value == value then value else 0
end

-- Значение статистики игрока; employees — число или таблица staff профиля
local function stat(profile: any, kind: string, genre: string?): number
	if kind == "genreGames" then
		local games = profile.genreGames
		return if type(games) == "table" and genre then num(games[genre]) else 0
	elseif kind == "hits" then
		return num(profile.hitsReleased)
	elseif kind == "employees" then
		if type(profile.employees) == "number" then
			return profile.employees
		end
		local count = 0
		if type(profile.staff) == "table" then
			for _ in profile.staff do
				count += 1
			end
		end
		return count
	end
	return num(profile[kind])
end

-- Выполнены ли условия; второе значение — список невыполненных
function UnlockRules.check(item: Item, profile: any): (boolean, { Missing })
	local missing: { Missing } = {}
	-- График контента: жанр/тема ещё не вышли — не открываются ничем (id жанров и тем не пересекаются)
	local id = item.id
	if id then
		local kind: ContentDrops.Kind = if (Genres :: any)[id] then "genre" else "topic"
		local days = ContentDrops.daysUntil(kind, id)
		if days > 0 then
			table.insert(missing, { kind = "release", need = days, have = 0 })
		end
	end
	local requires = item.requires
	if not requires or type(profile) ~= "table" then
		return requires == nil and #missing == 0, missing
	end
	for _, kind in ORDER do
		local value = (requires :: any)[kind]
		if value == nil then
			continue
		end
		local need: number
		local genre: string? = nil
		if kind == "genreGames" then
			need, genre = value.count, value.genre
		else
			need = value
		end
		local have = stat(profile, kind, genre)
		if have < need then
			table.insert(missing, { kind = kind, need = need, have = have, genre = genre })
		end
	end
	return #missing == 0, missing
end

local function localName(
	lang: Texts.Lang,
	prefix: string,
	item: { id: string, name: string, nameEn: string }
): string
	return Texts.lookup(lang, prefix .. item.id) or (if lang == "ru" then item.name else item.nameEn)
end

-- Текст одной причины: «🔒 Офис: 2-й этаж», «🔒 Выпусти игр: 3/5», «🔒 Оценка 8+»
function UnlockRules.describe(lang: Texts.Lang, missing: Missing): string
	local kind = missing.kind
	local vars: { [string]: any } = { need = missing.need, have = missing.have }
	if kind == "release" then
		return Texts.format(lang, "drop_soon_days", { days = missing.need })
	elseif kind == "studioLevel" then
		local stage = Stages[missing.need]
		vars.stage = if stage then localName(lang, "stage_", stage) else tostring(missing.need)
		return Texts.format(lang, "unlock_req_stage", vars)
	elseif kind == "gamesReleased" then
		return Texts.format(lang, "unlock_req_games", vars)
	elseif kind == "bestScore" then
		return Texts.format(lang, "unlock_req_score", vars)
	elseif kind == "genreGames" then
		local genre = missing.genre and (Genres :: any)[missing.genre]
		vars.genre = if genre then localName(lang, "genre_", genre) else missing.genre
		return Texts.format(lang, "unlock_req_genre_games", vars)
	elseif kind == "hits" then
		vars.score = HitCartridges.minScore
		return Texts.format(lang, "unlock_req_hits", vars)
	end
	return Texts.format(lang, "unlock_req_team", vars)
end

-- Первая невыполненная причина (для маленьких карточек); nil — всё выполнено
function UnlockRules.firstReason(lang: Texts.Lang, item: Item, profile: any): string?
	local ok, missing = UnlockRules.check(item, profile)
	if ok then
		return nil
	end
	return UnlockRules.describe(lang, missing[1])
end

-- Все причины одной строкой
function UnlockRules.reasons(lang: Texts.Lang, item: Item, profile: any): string
	local _, missing = UnlockRules.check(item, profile)
	local parts = {}
	for _, m in missing do
		table.insert(parts, UnlockRules.describe(lang, m))
	end
	return table.concat(parts, "  ")
end

return UnlockRules
