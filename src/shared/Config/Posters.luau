--!strict
-- Постеры для стен студии: косметика, бонусов не дают. Обычные — за $, премиум — за Robux
-- (Developer Products). Картинки — Config/Images.posters (0 = ещё нет: постер рисуется
-- из цвета фона, большого эмодзи и названия). Арт — docs/VISUAL.md, V8.
-- productId — ID из Creator Dashboard (0 = ещё не создан, в магазине кнопка «Скоро»).
-- robuxPrice — предложение, только для показа; финальную цену решает владелец.
-- Переводы названий — ключи poster_<id> в Texts и Locales.

local Stages = require(script.Parent.Stages)
local Universe = require(script.Parent.Universe)

export type Poster = {
	id: string,
	name: string,
	nameEn: string,
	premium: boolean, -- за Robux: неоновая рамка и подсветка
	cost: number?, -- цена в $ (обычные)
	productId: number, -- Developer Product (премиум), 0 = не создан
	robuxPrice: number?, -- подсказка цены в R$ (премиум)
	emoji: string, -- большой знак на запасном виде без картинки
	title: string, -- 1–3 слова по-английски на запасном виде (как название игры на афише)
	background: Color3,
	accent: Color3, -- текст и рамка (у премиум — неон)
}

-- Место на стене. position — центр постера на участке 60×60 (как в Config/Upgrades, пол y = 0.5),
-- rotation — поворот вокруг Y в градусах: 0 — постер смотрит на +Z (задняя стена),
-- 90 — на +X (левая стена), −90 — на −X (правая стена)
export type Slot = {
	id: string,
	stage: number, -- этап студии (Config/Stages), на котором висит место
	position: Vector3,
	rotation: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local list: { Poster } = {
	-- Обычные: простые плоские афиши
	{
		id = "pixelHero",
		name = "Пиксельный герой",
		nameEn = "Pixel Hero",
		premium = false,
		cost = 500,
		productId = 0,
		emoji = "🕹️",
		title = "PIXEL HERO",
		background = rgb(70, 160, 255),
		accent = rgb(255, 255, 255),
	},
	{
		id = "puzzleBlocks",
		name = "Кубики-головоломки",
		nameEn = "Block Puzzle",
		premium = false,
		cost = 1_500,
		productId = 0,
		emoji = "🧩",
		title = "BLOCK PUZZLE",
		background = rgb(255, 170, 60),
		accent = rgb(60, 30, 10),
	},
	{
		id = "turboRacer",
		name = "Турбо-гонщик",
		nameEn = "Turbo Racer",
		premium = false,
		cost = 3_000,
		productId = 0,
		emoji = "🏎️",
		title = "TURBO RACER",
		background = rgb(230, 60, 60),
		accent = rgb(255, 230, 90),
	},
	{
		id = "starBlaster",
		name = "Звёздный бластер",
		nameEn = "Star Blaster",
		premium = false,
		cost = 6_000,
		productId = 0,
		emoji = "🚀",
		title = "STAR BLASTER",
		background = rgb(30, 30, 80),
		accent = rgb(120, 220, 255),
	},
	{
		id = "ninjaCat",
		name = "Кот-ниндзя",
		nameEn = "Ninja Cat",
		premium = false,
		cost = 10_000,
		productId = 0,
		emoji = "🐱",
		title = "NINJA CAT",
		background = rgb(50, 50, 60),
		accent = rgb(255, 120, 120),
	},
	{
		id = "ghostManor",
		name = "Весёлые привидения",
		nameEn = "Ghost Manor",
		premium = false,
		cost = 16_000,
		productId = 0,
		emoji = "👻",
		title = "GHOST MANOR",
		background = rgb(110, 70, 170),
		accent = rgb(230, 230, 255),
	},
	{
		id = "robotArena",
		name = "Арена роботов",
		nameEn = "Robot Arena",
		premium = false,
		cost = 25_000,
		productId = 0,
		emoji = "🤖",
		title = "ROBOT ARENA",
		background = rgb(90, 100, 110),
		accent = rgb(255, 200, 60),
	},
	{
		id = "dragonValley",
		name = "Долина драконов",
		nameEn = "Dragon Valley",
		premium = false,
		cost = 40_000,
		productId = 0,
		emoji = "🐉",
		title = "DRAGON VALLEY",
		background = rgb(40, 140, 90),
		accent = rgb(255, 220, 120),
	},
	-- Премиум (Robux): детальный глянцевый арт, неоновая рамка
	{
		id = "neonCity",
		name = "Неоновый город",
		nameEn = "Neon City",
		premium = true,
		productId = Universe.pick({ test = 3728447969, main = 0 }),
		robuxPrice = 49,
		emoji = "🌃",
		title = "NEON CITY",
		background = rgb(20, 10, 40),
		accent = rgb(255, 60, 220),
	},
	{
		id = "crystalKingdom",
		name = "Хрустальное королевство",
		nameEn = "Crystal Kingdom",
		premium = true,
		productId = Universe.pick({ test = 3728447971, main = 0 }),
		robuxPrice = 79,
		emoji = "💎",
		title = "CRYSTAL KINGDOM",
		background = rgb(20, 60, 110),
		accent = rgb(120, 255, 255),
	},
	{
		id = "mechTitan",
		name = "Мех-титан",
		nameEn = "Mech Titan",
		premium = true,
		productId = Universe.pick({ test = 3728447973, main = 0 }),
		robuxPrice = 99,
		emoji = "🦾",
		title = "MECH TITAN",
		background = rgb(40, 20, 20),
		accent = rgb(255, 120, 40),
	},
	{
		id = "galaxyLegends",
		name = "Легенды галактики",
		nameEn = "Galaxy Legends",
		premium = true,
		productId = Universe.pick({ test = 3728447981, main = 0 }),
		robuxPrice = 129,
		emoji = "🌌",
		title = "GALAXY LEGENDS",
		background = rgb(15, 15, 50),
		accent = rgb(150, 110, 255),
	},
	{
		id = "goldenController",
		name = "Золотой геймпад",
		nameEn = "Golden Controller",
		premium = true,
		productId = Universe.pick({ test = 3728447985, main = 0 }),
		robuxPrice = 149,
		emoji = "🎮",
		title = "GOLDEN CONTROLLER",
		background = rgb(50, 35, 10),
		accent = rgb(255, 210, 60),
	},
}

-- Места на стенах. Свободно от: кнопок (+Z 22..29), окон и ворот, полки хитов (левая стена,
-- z −20.6..−9.4, высота до 6.1), стеллажа гаража (левая, z −9..1), верстака (правая, z 2..10),
-- кофемашины (25, −24), постеров с вывеской гаража (задняя стена, x −11..11 — видны на всех этапах),
-- кулера/серверной (правая стена), экрана небоскрёба (левая, z 0.5..11.5) и полки кубков (правая, z 4..16).
-- Гараж: глухие простенки боковых стен x = ±29.5 — z −29..−9, −1..9, 17..29.
-- Офис/этаж: в боковых стенах окна — места на задней стене. Небоскрёб: задняя стена стеклянная.
local slots: { Slot } = {
	-- Гараж (этап 1)
	{ id = "garage1", stage = 1, position = Vector3.new(-28.85, 6.5, -24.5), rotation = 90 },
	{ id = "garage2", stage = 1, position = Vector3.new(-28.85, 6.5, 5), rotation = 90 },
	{ id = "garage3", stage = 1, position = Vector3.new(-28.85, 6.5, 23), rotation = 90 },
	{ id = "garage4", stage = 1, position = Vector3.new(28.85, 6.5, -14), rotation = -90 },
	{ id = "garage5", stage = 1, position = Vector3.new(28.85, 6.5, 23), rotation = -90 },
	-- Офис, 1-й этаж (этап 2)
	{ id = "office1", stage = 2, position = Vector3.new(-20, 7, -28.85), rotation = 0 },
	{ id = "office2", stage = 2, position = Vector3.new(-14.5, 7, -28.85), rotation = 0 },
	{ id = "office3", stage = 2, position = Vector3.new(14.5, 7, -28.85), rotation = 0 },
	{ id = "office4", stage = 2, position = Vector3.new(20, 7, -28.85), rotation = 0 },
	-- Офис, 2-й этаж (этап 3)
	{ id = "floor1", stage = 3, position = Vector3.new(-20, 8, -28.85), rotation = 0 },
	{ id = "floor2", stage = 3, position = Vector3.new(-14.5, 8, -28.85), rotation = 0 },
	{ id = "floor3", stage = 3, position = Vector3.new(14.5, 8, -28.85), rotation = 0 },
	{ id = "floor4", stage = 3, position = Vector3.new(20, 8, -28.85), rotation = 0 },
	-- Офис, 3-й этаж (этап 4, модель Skyscraper)
	{ id = "sky1", stage = 4, position = Vector3.new(-28.7, 9, -24), rotation = 90 },
	{ id = "sky2", stage = 4, position = Vector3.new(-28.7, 9, 20), rotation = 90 },
	{ id = "sky3", stage = 4, position = Vector3.new(28.7, 9, -20), rotation = -90 },
	{ id = "sky4", stage = 4, position = Vector3.new(28.7, 9, -8), rotation = -90 },
	{ id = "sky5", stage = 4, position = Vector3.new(28.7, 9, 22), rotation = -90 },
}

local byId: { [string]: Poster } = {}
for _, poster in list do
	byId[poster.id] = poster
end

local slotById: { [string]: Slot } = {}
for _, slot in slots do
	slotById[slot.id] = slot
end

local Posters = {
	list = list,
	slots = slots,
	size = Vector3.new(3, 4, 0.2), -- постер в studs (картинка 768×1024 — 3:4)
}

function Posters.get(id: any): Poster?
	return if type(id) == "string" then byId[id] else nil
end

function Posters.getSlot(id: any): Slot?
	return if type(id) == "string" then slotById[id] else nil
end

function Posters.findByProduct(productId: number): Poster?
	if productId == 0 then
		return nil
	end
	for _, poster in list do
		if poster.premium and poster.productId == productId then
			return poster
		end
	end
	return nil
end

-- Сдвиг этажа по высоте. Офисные этажи переезжают «друг на друга»: если в Config/Stages появится
-- floorY (смещение этажа по Y), места поднимаются вместе с этажом.
-- TODO: проверить, когда этажи офиса встанут друг на друга (floorY в Stages)
function Posters.stageY(stage: number): number
	local s = Stages[stage] :: any
	local y = s and s.floorY
	return if type(y) == "number" then y else 0
end

-- Висит ли место на участке при этом studioLevel: место своего этапа; нижние этажи офиса —
-- тоже, если этажи стоят друг на друге (у этапа есть floorY), иначе их модели снесены
function Posters.slotVisible(slot: Slot, studioLevel: number): boolean
	if slot.stage == studioLevel then
		return true
	end
	local s = Stages[slot.stage] :: any
	return slot.stage >= 2 and slot.stage < studioLevel and s ~= nil and type(s.floorY) == "number"
end

return Posters
