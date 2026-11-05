--!strict
-- Две вселенной — два набора ID товаров, геймпассов и значков (docs/IDS.md).
-- Developer Product / GamePass / Badge принадлежат вселенной: ID из тестовой v2 в основной игре
-- не работают. Поэтому в конфигах ID записаны парой Universe.pick({ test = ..., main = ... }),
-- и при require остаётся число только текущей вселенной (по game.GameId). Один и тот же билд
-- работает в обеих. main = 0 — товар в основной игре ещё не создан: «Скоро»/скрыт, как сейчас
-- с 0; тестовый ID в основной игре не подставляется никогда.

local RunService = game:GetService("RunService")

local Debug = require(script.Parent.Debug)

export type Name = "test" | "main" | "studio-unpublished"
export type Pair = { test: number, main: number }

local Universe = {
	-- Universe ID (game.GameId)
	TEST_GAME_ID = 10774624686, -- «Game Studio Tycoon v2», плейс 75334772365832
	MAIN_GAME_ID = 10774551088, -- «Game Studio Tycoon», плейс 91848575533083
}

local function detect(): Name
	local forced = Debug.forceUniverse
	if forced ~= nil and RunService:IsStudio() then
		if forced == "main" then
			return "main"
		elseif forced == "test" then
			return "test"
		elseif forced == "studio-unpublished" then
			return "studio-unpublished"
		end
		warn("[Universe] Debug.forceUniverse: неизвестное значение", forced)
	end
	local gameId = game.GameId
	if gameId == Universe.MAIN_GAME_ID then
		return "main"
	elseif gameId == Universe.TEST_GAME_ID then
		return "test"
	elseif gameId == 0 then
		return "studio-unpublished" -- неопубликованный плейс в Studio: тестовые ID
	end
	warn("[Universe] неизвестная вселенная", gameId, "— берём тестовые ID")
	return "test"
end

-- Определяем один раз: ID в конфигах выбираются при require
local current: Name = detect()

-- "test" | "main" | "studio-unpublished"
function Universe.current(): Name
	return current
end

function Universe.isMain(): boolean
	return current == "main"
end

-- ID для текущей вселенной: main во вселенной основной игры, иначе test. nil — 0 (не создан)
function Universe.pick(ids: Pair?): number
	if ids == nil then
		return 0
	end
	local id = if current == "main" then ids.main else ids.test
	return if id > 0 then id else 0
end

return Universe
