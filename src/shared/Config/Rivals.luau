--!strict
-- Студии-конкуренты (RivalService), все названия выдуманные. Стоимость студии растёт с минутами
-- игры игрока: value = base × (1 + growthPerMinute × min(минут, growthCapMinutes)).
-- Стоимость игрока = деньги + купленные апгрейды + переезды. «Топ-10 индустрии» — 9 студий + игрок.
-- Обогнал студию впервые — тост и награда passRewardMinutes дохода.
-- Раз в hitIntervalMin..Max секунд одна студия «выпускает хит» в своём жанре: доход игр этого
-- жанра × hitRevenueMultiplier на hitSeconds (на весь сервер).
-- Rivals.pick(seed) — для других фич (например, переманивание сотрудников в событиях компании).

export type Rival = {
	id: string,
	name: string,
	icon: string,
	base: number,
	growthPerMinute: number,
	genre: string, -- жанр хитов (Config/Genres)
}

local Rivals = {
	growthCapMinutes = 1_200,
	passRewardMinutes = 2,
	hitIntervalMin = 8 * 60,
	hitIntervalMax = 12 * 60,
	hitSeconds = 10 * 60,
	hitRevenueMultiplier = 0.85,
	topSize = 10,

	list = {
		{
			id = "tinfoilOwl",
			name = "Tinfoil Owl",
			icon = "🦉",
			base = 3_000,
			growthPerMinute = 0.004,
			genre = "casual",
		},
		{
			id = "mangoComet",
			name = "Mango Comet",
			icon = "☄️",
			base = 15_000,
			growthPerMinute = 0.003,
			genre = "action",
		},
		{
			id = "quokkaPixel",
			name = "Quokka Pixel Works",
			icon = "🐾",
			base = 60_000,
			growthPerMinute = 0.003,
			genre = "adventure",
		},
		{
			id = "gloomberry",
			name = "Gloomberry",
			icon = "🫐",
			base = 250_000,
			growthPerMinute = 0.0025,
			genre = "horror",
		},
		{
			id = "brassfern",
			name = "Brassfern Interactive",
			icon = "🌿",
			base = 900_000,
			growthPerMinute = 0.002,
			genre = "rpg",
		},
		{
			id = "velvetAnvil",
			name = "Velvet Anvil",
			icon = "⚒️",
			base = 3_000_000,
			growthPerMinute = 0.002,
			genre = "strategy",
		},
		{
			id = "nimbusTurtle",
			name = "Nimbus Turtle",
			icon = "🐢",
			base = 9_000_000,
			growthPerMinute = 0.0015,
			genre = "simulation",
		},
		{
			id = "okraLantern",
			name = "Okra Lantern",
			icon = "🏮",
			base = 25_000_000,
			growthPerMinute = 0.0015,
			genre = "puzzle",
		},
		{
			id = "bluemoth",
			name = "Bluemoth Games",
			icon = "🦋",
			base = 70_000_000,
			growthPerMinute = 0.001,
			genre = "racing",
		},
	} :: { Rival },
}

function Rivals.valueOf(rival: Rival, minutes: number): number
	local m = math.clamp(minutes, 0, Rivals.growthCapMinutes)
	return math.floor(rival.base * (1 + rival.growthPerMinute * m))
end

function Rivals.byId(id: string): Rival?
	for _, rival in Rivals.list do
		if rival.id == id then
			return rival
		end
	end
	return nil
end

-- Детерминированно: одинаковый seed — одна и та же студия
function Rivals.pick(seed: number): Rival
	local n = #Rivals.list
	local index = math.floor(math.abs(seed)) % n + 1
	return Rivals.list[index]
end

return Rivals
