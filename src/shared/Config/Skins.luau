--!strict
-- Скины сотрудников (docs/VISUAL.md, V12; арт Астры — docs/visual/astra-2026-11-05-skins).
-- Косметика: бонусов не дают. Обычные — за $ (поздняя трата денег), премиум — за Robux
-- (Developer Products). Купленный скин — открытый стиль: его можно надеть на любое число
-- сотрудников (окно «Команда» → ✏️ → «👕 Скин»).
-- Как надевается (SkinService.decorate): рубашка/штаны — Shirt/Pants с картинками
-- Config/Images.skins (0 = ещё не загружены: тогда торс/руки красятся shirt, ноги — pants);
-- аксессуары — Accessory из модели ServerStorage.Skins[model] (Dev 1 импортирует
-- skin_<id>_acc.rbxmx и переименовывает в Skin_<id>; старое имя skin_<id>_acc тоже подходит).
-- productId — ID из Creator Dashboard (0 = ещё не создан, в магазине кнопка «Скоро»).
-- robuxPrice — предложение, только для показа; финальную цену решает владелец.
-- Переводы названий — ключи skin_<id> в Texts и Locales.

local Universe = require(script.Parent.Universe)

export type Skin = {
	id: string,
	name: string,
	nameEn: string,
	premium: boolean, -- за Robux: неоновые аксессуары
	cost: number?, -- цена в $ (обычные)
	productId: number, -- Developer Product (премиум), 0 = не создан
	robuxPrice: number?, -- подсказка цены в R$ (премиум)
	model: string, -- модель аксессуаров в ServerStorage.Skins
	emoji: string, -- знак на карточке без превью
	shirt: Color3, -- запасной цвет торса и рукавов (пока нет картинки)
	pants: Color3, -- запасной цвет ног
	accent: Color3, -- рамка карточки
}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

-- Цвета — из manifest.json Астры (основной цвет рубашки, штанов и акцент)
local list: { Skin } = {
	-- За $: от офиса ($5k) до 3-го этажа ($150k)
	{
		id = "hoodie_coder",
		name = "Кодер в худи",
		nameEn = "Hoodie Coder",
		premium = false,
		cost = 5_000,
		productId = 0,
		model = "Skin_hoodie_coder",
		emoji = "🎧",
		shirt = hex("26344E"),
		pants = hex("4678B3"),
		accent = hex("3D7BFF"),
	},
	{
		id = "pixel_artist",
		name = "Пиксель-художник",
		nameEn = "Pixel Artist",
		premium = false,
		cost = 10_000,
		productId = 0,
		model = "Skin_pixel_artist",
		emoji = "🎨",
		shirt = hex("FFB2D5"),
		pants = hex("36466F"),
		accent = hex("FF6EB4"),
	},
	{
		id = "sound_nerd",
		name = "Звуковик",
		nameEn = "Sound Nerd",
		premium = false,
		cost = 20_000,
		productId = 0,
		model = "Skin_sound_nerd",
		emoji = "🎚️",
		shirt = hex("326A57"),
		pants = hex("27364D"),
		accent = hex("3DC86E"),
	},
	{
		id = "writer",
		name = "Сценарист",
		nameEn = "Writer",
		premium = false,
		cost = 35_000,
		productId = 0,
		model = "Skin_writer",
		emoji = "✍️",
		shirt = hex("7B4E84"),
		pants = hex("38324F"),
		accent = hex("E7B977"),
	},
	{
		id = "intern",
		name = "Стажёр",
		nameEn = "Intern",
		premium = false,
		cost = 50_000,
		productId = 0,
		model = "Skin_intern",
		emoji = "🎒",
		shirt = hex("2D7689"),
		pants = hex("3A485C"),
		accent = hex("FFC93C"),
	},
	{
		id = "bug_hunter",
		name = "Охотник за багами",
		nameEn = "Bug Hunter",
		premium = false,
		cost = 75_000,
		productId = 0,
		model = "Skin_bug_hunter",
		emoji = "🐞",
		shirt = hex("799B61"),
		pants = hex("3D4941"),
		accent = hex("FFD75E"),
	},
	{
		id = "speedrunner",
		name = "Спидраннер",
		nameEn = "Speedrunner",
		premium = false,
		cost = 100_000,
		productId = 0,
		model = "Skin_speedrunner",
		emoji = "⏱️",
		shirt = hex("2566A7"),
		pants = hex("24354C"),
		accent = hex("00D4CE"),
	},
	{
		id = "retro_gamer",
		name = "Ретро-геймер",
		nameEn = "Retro Gamer",
		premium = false,
		cost = 150_000,
		productId = 0,
		model = "Skin_retro_gamer",
		emoji = "🕹️",
		shirt = hex("8742A4"),
		pants = hex("263D64"),
		accent = hex("FFB845"),
	},
	-- За Robux: светящиеся аксессуары
	{
		id = "neon_streamer",
		name = "Неон-стример",
		nameEn = "Neon Streamer",
		premium = true,
		productId = Universe.pick({ test = 3728448093, main = 0 }),
		robuxPrice = 79,
		model = "Skin_neon_streamer",
		emoji = "📡",
		shirt = hex("302547"),
		pants = hex("27213F"),
		accent = hex("FF6EB4"),
	},
	{
		id = "cyber_dev",
		name = "Кибер-разработчик",
		nameEn = "Cyber Dev",
		premium = true,
		productId = Universe.pick({ test = 3728448098, main = 0 }),
		robuxPrice = 99,
		model = "Skin_cyber_dev",
		emoji = "🤖",
		shirt = hex("1B2C40"),
		pants = hex("172636"),
		accent = hex("00E5FF"),
	},
	{
		id = "space_dev",
		name = "Разработчик-космонавт",
		nameEn = "Space Dev",
		premium = true,
		productId = Universe.pick({ test = 3728448101, main = 0 }),
		robuxPrice = 129,
		model = "Skin_space_dev",
		emoji = "🚀",
		shirt = hex("DFE7EF"),
		pants = hex("BDCCD9"),
		accent = hex("00CFF0"),
	},
	{
		id = "wizard_dev",
		name = "Маг кода",
		nameEn = "Code Wizard",
		premium = true,
		productId = Universe.pick({ test = 3728448105, main = 0 }),
		robuxPrice = 149,
		model = "Skin_wizard_dev",
		emoji = "🧙",
		shirt = hex("493169"),
		pants = hex("35264E"),
		accent = hex("CBA0FF"),
	},
}

local byId: { [string]: Skin } = {}
for _, skin in list do
	byId[skin.id] = skin
end

local Skins = {
	list = list,
	folder = "Skins", -- папка моделей в ServerStorage
}

function Skins.get(id: any): Skin?
	return if type(id) == "string" then byId[id] else nil
end

function Skins.findByProduct(productId: number): Skin?
	if productId == 0 then
		return nil
	end
	for _, skin in list do
		if skin.premium and skin.productId == productId then
			return skin
		end
	end
	return nil
end

return Skins
