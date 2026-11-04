--!strict
-- Платформы игры (волна 2): игрок выбирает в окне «Создать игру». ПК — по умолчанию,
-- «Телефоны» — с офиса, «Своя консоль» — после запуска консоли (Config/Console, ConsoleService).
-- revenue — множитель дохода по жанру (нет жанра — default), scoreBonus — прибавка к оценке
-- до округления (у своей консоли — выше шанс хита). Проверяет и применяет сервер.

export type Platform = {
	id: string, -- "pc" | "phone" | "console"
	icon: string,
	-- Условие открытия: studioLevel не ниже (Config/Stages) или запущенная своя консоль
	minStudioLevel: number,
	needsConsole: boolean?,
	default: number, -- множитель дохода для жанров, которых нет в revenue
	revenue: { [string]: number },
	scoreBonus: number,
}

local Platforms = {}

Platforms.order = { "pc", "phone", "console" } :: { string }

Platforms.list = {
	pc = {
		id = "pc",
		icon = "🖥️",
		minStudioLevel = 1,
		default = 1,
		revenue = {},
		scoreBonus = 0,
	},
	-- Телефоны: казуалки и головоломки продаются лучше, стратегии и RPG — хуже
	phone = {
		id = "phone",
		icon = "📱",
		minStudioLevel = 2,
		default = 1,
		revenue = { casual = 1.3, puzzle = 1.3, sports = 1.1, strategy = 0.8, rpg = 0.85, simulation = 0.9 },
		scoreBonus = 0,
	},
	-- Своя консоль: экшен и гонки — лучше всех; +0.3 к оценке (чаще 8+ и хиты).
	-- Ещё × (1 + доля рынка × Console.shareRevenueBonus) — см. ConsoleService.revenueMultiplier
	console = {
		id = "console",
		icon = "🎮",
		minStudioLevel = 4,
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
