--!strict
-- Декор студии: покупается в окне «Студия» (не кнопками на полу) и поднимает настроение команды
-- (Config/Mood). Каждый предмет покупается отдельно на каждый этаж: в гараже — «1-й этаж»,
-- после переезда гаражный декор переезжает на 1-й этаж офиса (своё место stage 2).
-- Ключ покупки в профиле: "<id>@<этаж>" (DecorService). Rebirth декор не сбрасывает (как постеры):
-- после него виден только декор 1-го этажа, верхние вернутся вместе с этажами.
-- model — имя модели в ServerStorage.Upgrades (импорт из Studio), иначе ModelFactory строит из деталей.
-- Модели Астры из набора гаража: Plant, Rug, PendantLamp, WallBench, Sofa, CoffeeTable.
-- Места: x, z на участке 60×60 (как в Config/Upgrades), поворот в градусах (0 — лицом к +Z),
-- y — высота над полом этажа (лампа висит под потолком, вывеска — на стене). Свободно от столов
-- и мест сотрудников (+3.5 по Z от стола), кнопок (Z 22..28), лифта (X −23…−17, Z 21…27),
-- полки хитов (левая стена, Z −20.6…−9.4), кофемашины (25, −24), переговорки, серверной,
-- зоны отдыха, студии звукозаписи, арт-стены и постеров (docs/VISUAL.md, V9).
-- Переводы названий — ключи decor_<id> в Texts и Locales.

export type Slot = { x: number, z: number, rotation: number, y: number? }

export type Item = {
	id: string,
	name: string,
	nameEn: string,
	emoji: string,
	cost: number, -- цена на 1-м этаже (и в гараже); выше — × floorCostMultiplier
	mood: number, -- очки настроения за каждый поставленный экземпляр
	model: string,
	-- Импортированная модель Астры больше нужного (ковёр 21×23): уменьшить при установке
	importScale: number?,
	-- Место по этапу студии: [1] гараж, [2] 1-й этаж офиса, [3] 2-й этаж, [4] 3-й этаж
	slots: { [number]: Slot },
}

-- Цена на этаже N офиса: этажи дороже, как и их мебель
local floorCostMultiplier = { 1, 3, 10 }

local CEILING = 12 -- лампа: pivot модели Астры — крепление к потолку
local WALL_SIGN = 8 -- центр неоновой вывески на стене

local function slot(x: number, z: number, rotation: number, y: number?): Slot
	return { x = x, z = z, rotation = rotation, y = y }
end

local list: { Item } = {
	{
		id = "plant",
		name = "Растение в горшке",
		nameEn = "Potted plant",
		emoji = "🪴",
		cost = 300,
		mood = 2,
		model = "Plant",
		slots = {
			slot(-26, -26, 0),
			slot(-26.5, -2, 0),
			slot(-26, -26, 0),
			slot(-26, -26, 0),
		},
	},
	{
		id = "rug",
		name = "Мягкий ковёр",
		nameEn = "Soft rug",
		emoji = "🟦",
		cost = 1_200,
		mood = 2,
		model = "Rug",
		importScale = 0.5,
		slots = {
			slot(12, 7, 0),
			slot(8, 8, 0),
			slot(-14, -16, 0),
			slot(-18, -18, 0),
		},
	},
	{
		id = "pendantLamp",
		name = "Подвесная лампа",
		nameEn = "Pendant lamp",
		emoji = "💡",
		cost = 2_000,
		mood = 2,
		model = "PendantLamp",
		slots = {
			slot(12, 7, 0, CEILING),
			slot(8, 8, 0, CEILING),
			slot(-14, -16, 0, CEILING),
			slot(-18, -18, 0, CEILING),
		},
	},
	{
		id = "wallBench",
		name = "Скамья у стены",
		nameEn = "Wall bench",
		emoji = "🪑",
		cost = 3_500,
		mood = 3,
		model = "WallBench",
		slots = {
			slot(-27.8, 12, 90),
			slot(27.8, 2, -90),
			slot(-27.8, -2, 90),
			slot(-27.8, -14, 90),
		},
	},
	{
		id = "beanBags",
		name = "Кресла-мешки",
		nameEn = "Bean bags",
		emoji = "🫘",
		cost = 5_000,
		mood = 3,
		model = "BeanBags",
		slots = {
			slot(-14, 6, 0),
			slot(19, 6, -90),
			slot(25, -2, -90),
			slot(-2, 15, 180),
		},
	},
	{
		id = "bookshelf",
		name = "Книжный шкаф",
		nameEn = "Bookshelf",
		emoji = "📚",
		cost = 8_000,
		mood = 3,
		model = "Bookshelf",
		slots = {
			slot(28, -6, -90),
			slot(28, 10, -90),
			slot(-8, -28.2, 0),
			slot(6, -28.2, 0),
		},
	},
	{
		id = "sofa",
		name = "Диван",
		nameEn = "Sofa",
		emoji = "🛋️",
		cost = 12_000,
		mood = 4,
		model = "Sofa",
		slots = {
			slot(12, 14.5, 180),
			slot(8, 15.5, 180),
			slot(-14, -19.5, 0),
			slot(-18, -24, 0),
		},
	},
	{
		id = "coffeeTable",
		name = "Журнальный столик",
		nameEn = "Coffee table",
		emoji = "☕",
		cost = 15_000,
		mood = 3,
		model = "CoffeeTable",
		slots = {
			slot(12, 7, 0),
			slot(8, 8.5, 0),
			slot(-14, -14.5, 0),
			slot(-18, -18, 0),
		},
	},
	{
		id = "miniFridge",
		name = "Мини-холодильник",
		nameEn = "Mini fridge",
		emoji = "🧃",
		cost = 20_000,
		mood = 4,
		model = "MiniFridge",
		slots = {
			slot(27.5, 14, -90),
			slot(20.5, -27.3, 0),
			slot(-26.5, -14, 90),
			slot(27, -26, -90),
		},
	},
	{
		id = "neonSign",
		name = "Неоновая вывеска",
		nameEn = "Neon sign",
		emoji = "✨",
		cost = 28_000,
		mood = 4,
		model = "NeonSign",
		slots = {
			slot(-28.8, 17, 90, WALL_SIGN),
			slot(-28.8, -15, 90, WALL_SIGN),
			slot(-28.8, -20, 90, WALL_SIGN),
			slot(-28.8, -6, 90, WALL_SIGN),
		},
	},
	{
		id = "aquarium",
		name = "Аквариум",
		nameEn = "Aquarium",
		emoji = "🐠",
		cost = 40_000,
		mood = 5,
		model = "Aquarium",
		slots = {
			slot(-22, -4, 90),
			slot(19, -4, -90),
			slot(27, -24, -90),
			slot(26, -2, -90),
		},
	},
	{
		id = "arcade",
		name = "Игровой автомат",
		nameEn = "Arcade machine",
		emoji = "🕹️",
		cost = 60_000,
		mood = 6,
		model = "ArcadeMachine",
		slots = {
			slot(-4, 14, 0),
			slot(-2, 16, 0),
			slot(-23, -1, 90),
			slot(4, 16, 0),
		},
	},
}

local byId: { [string]: Item } = {}
for _, item in list do
	byId[item.id] = item
end

local Decor = {
	list = list,
	floorCostMultiplier = floorCostMultiplier,
	FLOORS = #floorCostMultiplier,
}

function Decor.get(id: any): Item?
	return if type(id) == "string" then byId[id] else nil
end

function Decor.key(id: string, floor: number): string
	return id .. "@" .. floor
end

-- "<id>@<этаж>" -> предмет и этаж (nil — мусор из сохранения)
function Decor.parseKey(key: any): (Item?, number?)
	if type(key) ~= "string" then
		return nil, nil
	end
	local id, floorText = key:match("^([%w_]+)@(%d+)$")
	local floor = tonumber(floorText)
	local item = Decor.get(id)
	if not item or not floor or floor < 1 or floor > Decor.FLOORS then
		return nil, nil
	end
	return item, floor
end

function Decor.cost(item: Item, floor: number): number
	return item.cost * (floorCostMultiplier[floor] or 1)
end

-- Сколько этажей открыто для декора: гараж — 1, офис — открытые этажи (studioLevel 2/3/4 = 1/2/3)
function Decor.floorsOpen(studioLevel: number): number
	return math.clamp(math.floor(studioLevel) - 1, 1, Decor.FLOORS)
end

-- Этап (ключ slots), где стоит декор этажа floor при этом studioLevel
function Decor.stageFor(floor: number, studioLevel: number): number
	return if studioLevel <= 1 then 1 else floor + 1
end

-- Купленный декор, который сейчас стоит на участке: { item, floor, slot, stage }
export type Placed = { item: Item, floor: number, slot: Slot, stage: number }

function Decor.placed(owned: { [string]: boolean }, studioLevel: number): { Placed }
	local result = {}
	local open = Decor.floorsOpen(studioLevel)
	for _, item in list do
		for floor = 1, open do
			if owned[Decor.key(item.id, floor)] then
				local stage = Decor.stageFor(floor, studioLevel)
				local s = item.slots[stage]
				if s then
					table.insert(result, { item = item, floor = floor, slot = s, stage = stage })
				end
			end
		end
	end
	return result
end

return Decor
