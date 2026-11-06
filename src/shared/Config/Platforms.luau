--!strict
-- Платформы игры (волна 2): игрок выбирает в окне «Создать игру». ПК — по умолчанию,
-- «Телефоны» — после 3 выпущенных игр (requires, shared/UnlockRules: уже в гараже),
-- «Своя консоль» — после запуска консоли (Config/Console, ConsoleService).
-- revenue — множитель дохода по жанру (нет жанра — default), scoreBonus — прибавка к оценке
-- до округления (у своей консоли — выше шанс хита). Проверяет и применяет сервер.

local Genres = require(script.Parent.Genres)

export type Platform = {
	id: string, -- "pc" | "phone" | "console"
	icon: string,
	-- Условие открытия (UnlockRules, как у жанров) или запущенная своя консоль
	requires: Genres.Requires?,
	needsConsole: boolean?,
	closed: boolean?, -- закрыта совсем (07.11, владелец): в окне не показывается, выбрать нельзя
	default: number, -- множитель дохода для жанров, которых нет в revenue
	revenue: { [string]: number },
	scoreBonus: number,
}

local Platforms = {}

-- «Телефоны» закрыты совсем (владелец 06.11): нет в строке платформ, не открываются по числу игр
Platforms.order = { "pc", "console" } :: { string }

Platforms.list = {
	pc = {
		id = "pc",
		icon = "🖥️",
		default = 1,
		revenue = {},
		scoreBonus = 0,
	},
	-- Телефоны: казуалки и головоломки продаются лучше, стратегии и RPG — хуже
	phone = {
		id = "phone",
		icon = "📱",
		closed = true,
		requires = { gamesReleased = 3 },
		default = 1,
		revenue = { casual = 1.2, puzzle = 1.2, sports = 1.1, strategy = 0.8, rpg = 0.85, simulation = 0.9 },
		scoreBonus = 0,
	},
	-- Своя консоль: экшен и гонки — лучше всех; +0.3 к оценке (чаще 8+ и хиты).
	-- Ещё × (1 + доля рынка × Console.shareRevenueBonus) — см. ConsoleService.revenueMultiplier
	console = {
		id = "console",
		icon = "🎮",
		needsConsole = true,
		default = 1.05,
		revenue = { action = 1.25, racing = 1.25, sports = 1.15, horror = 1.1, puzzle = 0.9 },
		scoreBonus = 0.3,
	},
} :: { [string]: Platform }

function Platforms.get(id: any): Platform?
	return if type(id) == "string" then Platforms.list[id] else nil
end

-- Множитель дохода платформы для жанра (без доли рынка консоли)
function Platforms.genreMultiplier(platform: Platform, genreId: string): number
	return platform.revenue[genreId] or platform.default
end

return Platforms
