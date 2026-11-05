--!strict
-- Стили мебели (docs/VISUAL.md, V15): один стиль на всю студию — мебель гаража, этажей 1–3
-- и декор V9. Только внешний вид, на работу предметов не влияет.
-- Модель стиля — ServerStorage.Upgrades.<Имя><suffix> (Desk1_Neon рядом с Desk1); нет такой —
-- ставится классика. Размеры, pivot и рабочие детали у стилей те же (правила V15).
-- Как получить: cost — за $; productId — Developer Product (0 = ещё не создан: «Скоро»;
-- robuxPrice — только подсказка цены, финальную решает владелец). Классика бесплатна.
-- Цены за $ — поздняя трата денег (cash sink), как один предмет интерьера 2-го этажа
-- (Config/Upgrades: 920k–2.9M, этаж ~8 ч игры): к этому моменту интерьер обычно куплен,
-- а деньги копятся. Декор V9 стоит 300–20k ×этаж — стиль меняет весь офис, поэтому дороже.
-- Уют дешевле Минимала: ближе к классике, первый шаг; Минимал — как дорогой стол 2-го этажа.
-- Названия и строка настроения — ключи fstyle_<id> и fstyle_<id>_desc в Texts и Locales.

export type Style = {
	id: string,
	suffix: string, -- "" у классики
	emoji: string, -- знак на карточке
	color: Color3, -- рамка карточки
	cost: number?, -- цена в $; nil и без productId — бесплатно
	productId: number, -- Developer Product, 0 = не создан
	robuxPrice: number?, -- подсказка цены в R$
}

local FurnitureStyles = {}

FurnitureStyles.default = "classic"

FurnitureStyles.list = {
	{
		id = "classic",
		suffix = "",
		emoji = "🪑",
		color = Color3.fromHex("8A8FA8"),
		productId = 0,
	},
	{
		id = "cozy",
		suffix = "_Cozy",
		emoji = "🧸",
		color = Color3.fromHex("C8A27A"),
		cost = 1_000_000,
		productId = 0,
	},
	{
		id = "minimal",
		suffix = "_Minimal",
		emoji = "🤍",
		color = Color3.fromHex("F2F2F2"),
		cost = 1_500_000,
		productId = 0,
	},
	{
		id = "neon",
		suffix = "_Neon",
		emoji = "💜",
		color = Color3.fromHex("7C4DFF"),
		productId = 0, -- Dev 1 впишет ID из Creator Dashboard
		robuxPrice = 149,
	},
} :: { Style }

function FurnitureStyles.get(id: any): Style?
	if type(id) ~= "string" then
		return nil
	end
	for _, style in FurnitureStyles.list do
		if style.id == id then
			return style
		end
	end
	return nil
end

-- Стиль за Robux по productId (0 — не создан, не ищем)
function FurnitureStyles.findByProduct(productId: number): Style?
	if productId == 0 then
		return nil
	end
	for _, style in FurnitureStyles.list do
		if style.productId == productId then
			return style
		end
	end
	return nil
end

-- За Robux (а не за $): есть productId или подсказка цены в R$
function FurnitureStyles.isPremium(style: Style): boolean
	return style.productId ~= 0 or style.robuxPrice ~= nil
end

-- Бесплатный (открыт у всех)
function FurnitureStyles.isFree(style: Style): boolean
	return style.cost == nil and not FurnitureStyles.isPremium(style)
end

return FurnitureStyles
