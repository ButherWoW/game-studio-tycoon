--!strict
-- HD-материалы (владелец 07.11: «модельки реалистичнее, HD-текстуры»). Наборы PBR-текстур Астры (V38,
-- docs/VISUAL.md): бесшовные 1024×1024 карты color / normal / roughness / metalness для встроенных материалов
-- Roblox. Сервер (Services/MaterialsService) собирает из них MaterialVariant в MaterialService и назначает
-- набор материалом по умолчанию (SetBaseMaterialOverride), поэтому все детали с этим материалом (пол,
-- стены, мебель) получают реалистичную текстуру без новых моделей.
-- Пока ID равны 0, набор пропускается и в игре ничего не меняется. Dev 1: загрузить карты как Image и
-- вписать ID. Для телефонов карты не больше 1024; studsPerTile — сколько studs занимает одна плитка текстуры.

export type MaterialSet = {
	name: string, -- имя MaterialVariant и набора Астры
	base: Enum.Material, -- встроенный материал, который получает набор
	studsPerTile: number,
	colorMap: number,
	normalMap: number,
	roughnessMap: number,
	metalnessMap: number,
}

local function set(name: string, base: Enum.Material, studsPerTile: number): MaterialSet
	return {
		name = name,
		base = base,
		studsPerTile = studsPerTile,
		colorMap = 0, -- <name>_color.png
		normalMap = 0, -- <name>_normal.png
		roughnessMap = 0, -- <name>_roughness.png
		metalnessMap = 0, -- <name>_metalness.png
	}
end

local Materials = {
	list = {
		set("wood_floor", Enum.Material.WoodPlanks, 8),
		set("wood_dark", Enum.Material.Wood, 8),
		set("concrete_wall", Enum.Material.Concrete, 10),
		set("fabric_carpet", Enum.Material.Fabric, 6),
		set("brushed_metal", Enum.Material.Metal, 6),
		set("brick_warm", Enum.Material.Brick, 8),
		set("plastic_soft", Enum.Material.SmoothPlastic, 6),
		set("marble_light", Enum.Material.Marble, 10),
	} :: { MaterialSet },
}

-- Набор готов к применению: есть хотя бы цветовая карта
function Materials.ready(item: MaterialSet): boolean
	return item.colorMap > 0
end

return Materials
