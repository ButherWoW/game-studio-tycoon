--!strict
-- Отделка студии (премиум-наборы Астры, assets/models/astra-interior-*/INTEGRATION.md):
-- пол, стены, окна, плинтусы и светильники оболочек этапов. Только внешний вид, на работу не влияет.
-- Отдельно от стиля мебели (Config/FurnitureStyles, V15): у игрока два независимых выбора —
-- смена отделки не меняет мебель, смена мебели не меняет отделку.
-- Модель отделки — ServerStorage.Upgrades.<Оболочка><suffix> (Office_Sakura рядом с Office);
-- нет такой (или заглушка Generated) — ставится классика. Подмена только у оболочек SHELLS,
-- мебель и декор V9 берут стиль мебели (StyleModels.find).
-- Как получить: только за Robux — productId (Developer Product, 0 = ещё не создан: «Скоро»);
-- robuxPrice — подсказка цены, финальную цену и ID задаёт владелец/Dev 1 в Creator Dashboard.
-- Классика бесплатна. Потолок — нижняя сторона перекрытий OfficeFloors (FloorSlab):
-- ceilingColor/ceilingMaterial из manifest.json набора; nil — как раньше (классика).
-- Названия и строка настроения — ключи ifinish_<id> и ifinish_<id>_desc в Texts и Locales.

local Universe = require(script.Parent.Universe)

export type Finish = {
	id: string,
	suffix: string, -- "" у классики
	emoji: string, -- знак на карточке без картинки
	color: Color3, -- фон карточки без картинки
	accent: Color3, -- рамка и полоса карточки
	ceilingColor: Color3?, -- потолок (низ перекрытия этажа); nil — классический
	ceilingMaterial: Enum.Material?,
	imageKey: string?, -- ключ Images.interiorFinishes (ShopCard_512.png набора)
	productId: number, -- Developer Product, 0 = не создан
	robuxPrice: number?, -- подсказка цены в R$
}

local InteriorFinishes = {}

InteriorFinishes.default = "classic"

-- Оболочки этапов, у которых меняется отделка: имя модели на участке -> имя шаблона отделки.
-- Ранний гараж Garage берёт шаблон стен гаража (GarageWalls_<suffix>): у Астры это одна оболочка,
-- клон на участке всё равно называется Garage (правило SUPERSEDED_BY в PlotService)
InteriorFinishes.SHELLS = {
	Garage = "GarageWalls",
	GarageWalls = "GarageWalls",
	Office = "Office",
	Floor = "Floor",
	Skyscraper = "Skyscraper",
} :: { [string]: string }

InteriorFinishes.list = {
	{
		id = "classic",
		suffix = "",
		emoji = "🏠",
		color = Color3.fromHex("3A3D52"),
		accent = Color3.fromHex("8A8FA8"),
		productId = 0,
	},
	{
		-- Чёрный мрамор, латунные вставки, ар-деко фриз
		id = "obsidianGold",
		suffix = "_ObsidianGold",
		emoji = "🖤",
		color = Color3.fromHex("1B1C24"),
		accent = Color3.fromHex("D4AF37"),
		ceilingColor = Color3.fromHex("242530"),
		ceilingMaterial = Enum.Material.SmoothPlastic,
		imageKey = "obsidianGold",
		productId = Universe.pick({ test = 3728485040, main = 3728498631 }), -- тестовая вселенная v2, 199 R$
		robuxPrice = 199, -- подсказка; финальную цену решает владелец
	},
	{
		-- Светлое дерево, розовые вставки, сёдзи и сакура
		id = "sakura",
		suffix = "_Sakura",
		emoji = "🌸",
		color = Color3.fromHex("FFE6EE"),
		accent = Color3.fromHex("E58FB0"),
		ceilingColor = Color3.fromHex("FFF1E8"),
		ceilingMaterial = Enum.Material.SmoothPlastic,
		imageKey = "sakura",
		productId = Universe.pick({ test = 3728485054, main = 3728498643 }), -- тестовая вселенная v2, 199 R$
		robuxPrice = 199, -- подсказка; финальную цену решает владелец
	},
	{
		-- Ледяной синий пол, бирюзовые и сиреневые ленты северного сияния
		id = "aurora",
		suffix = "_Aurora",
		emoji = "🌌",
		color = Color3.fromHex("1E3550"),
		accent = Color3.fromHex("5CE1E6"),
		ceilingColor = Color3.fromHex("23384F"),
		ceilingMaterial = Enum.Material.SmoothPlastic,
		imageKey = "aurora",
		productId = Universe.pick({ test = 3728485064, main = 3728498658 }), -- тестовая вселенная v2, 199 R$
		robuxPrice = 199, -- подсказка; финальную цену решает владелец
	},
} :: { Finish }

function InteriorFinishes.get(id: any): Finish?
	if type(id) ~= "string" then
		return nil
	end
	for _, finish in InteriorFinishes.list do
		if finish.id == id then
			return finish
		end
	end
	return nil
end

-- Отделка за Robux по productId (0 — не создан, не ищем)
function InteriorFinishes.findByProduct(productId: number): Finish?
	if productId == 0 then
		return nil
	end
	for _, finish in InteriorFinishes.list do
		if finish.productId == productId then
			return finish
		end
	end
	return nil
end

-- Бесплатная (открыта у всех): нет продукта и подсказки цены в R$
function InteriorFinishes.isFree(finish: Finish): boolean
	return finish.productId == 0 and finish.robuxPrice == nil
end

return InteriorFinishes
