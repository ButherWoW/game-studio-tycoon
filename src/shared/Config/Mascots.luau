--!strict
-- Маскоты студии (docs/VISUAL.md, V16): питомец ходит за игроком и даёт маленький бонус.
-- Бонус даёт только ОДИН надетый маскот (MascotService). Без сундуков: каждого получают напрямую.
-- Как получить (how):
--   "cash" — за $ (cost); "robux" — Developer Product (productId, 0 = ещё не создан: «Скоро»;
--   robuxPrice — только подсказка цены, финальную решает владелец); "achievement" — открыт,
--   когда получено достижение achievement; "group" — награда за вступление в группу
--   (Config/Social.groupReward, SocialService); "season" — выдаст сезон (MascotService.grant).
-- Модель: ServerStorage.Mascots.Mascot_<id> с деталью Body (нет модели — заглушка из шаров
-- цветом color). Иконка: Images.mascots[id] (0 — эмодзи на карточке).
-- Бонусы (bonus.kind): devSpeed — доля к скорости разработки (0.05 = +5%), mood — очки
-- настроения команды, perfect — доля к окну «Отлично» быстрых событий, revenue — доля к доходу
-- релиза, review — прибавка к оценке до округления (чаще хиты). Легендарные чуть сильнее,
-- но не pay-to-win: бонус меньше, чем у одного апгрейда студии.
-- Переводы названий — ключи mascot_<id> в Texts и Locales.

local Universe = require(script.Parent.Universe)

export type Rarity = "common" | "rare" | "epic" | "legendary"
export type How = "cash" | "robux" | "achievement" | "group" | "season"
export type BonusKind = "devSpeed" | "mood" | "perfect" | "revenue" | "review"

export type Mascot = {
	id: string,
	name: string,
	nameEn: string,
	rarity: Rarity,
	how: How,
	cost: number?, -- цена в $ (how = "cash")
	productId: number, -- Developer Product (how = "robux"), 0 = не создан
	robuxPrice: number?, -- подсказка цены в R$
	achievement: string?, -- id из Config/Achievements (how = "achievement")
	bonus: { kind: BonusKind, value: number },
	emoji: string, -- знак на карточке без иконки
	color: Color3, -- цвет заглушки и рамки
}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local list: { Mascot } = {
	-- Обычные
	{
		id = "pixel_cat",
		name = "Пиксельный котик",
		nameEn = "Pixel Cat",
		rarity = "common",
		how = "cash",
		cost = 10_000,
		productId = 0,
		bonus = { kind = "devSpeed", value = 0.03 },
		emoji = "🐱",
		color = hex("FF9F43"),
	},
	{
		id = "bug_beetle",
		name = "Жучок-баг",
		nameEn = "Bug Beetle",
		rarity = "common",
		how = "cash",
		cost = 25_000,
		productId = 0,
		bonus = { kind = "perfect", value = 0.1 },
		emoji = "🐞",
		color = hex("E8463C"),
	},
	{
		id = "coffee_cup",
		name = "Живая чашка кофе",
		nameEn = "Coffee Cup",
		rarity = "common",
		how = "cash",
		cost = 40_000,
		productId = 0,
		bonus = { kind = "mood", value = 4 },
		emoji = "☕",
		color = hex("A0673C"),
	},
	{
		id = "floppy_dog",
		name = "Щенок-дискета",
		nameEn = "Floppy Dog",
		rarity = "common",
		how = "cash",
		cost = 60_000,
		productId = 0,
		bonus = { kind = "revenue", value = 0.03 },
		emoji = "🐶",
		color = hex("4A7BD0"),
	},
	{
		id = "cloud_ghost",
		name = "Облачко-привидение",
		nameEn = "Cloud Ghost",
		rarity = "common",
		how = "achievement",
		achievement = "days_7", -- «неделя в игре»
		productId = 0,
		bonus = { kind = "mood", value = 3 },
		emoji = "👻",
		color = hex("E6ECF5"),
	},
	-- Редкие
	{
		id = "controller_bunny",
		name = "Зайчик-геймпад",
		nameEn = "Controller Bunny",
		rarity = "rare",
		how = "cash",
		cost = 250_000,
		productId = 0,
		bonus = { kind = "perfect", value = 0.15 },
		emoji = "🐰",
		color = hex("F2F2F7"),
	},
	{
		id = "robo_owl",
		name = "Сова-робот",
		nameEn = "Robo Owl",
		rarity = "rare",
		how = "cash",
		cost = 400_000,
		productId = 0,
		bonus = { kind = "review", value = 0.15 },
		emoji = "🦉",
		color = hex("8A97A8"),
	},
	{
		id = "slime_star",
		name = "Слайм со звездой",
		nameEn = "Star Slime",
		rarity = "rare",
		how = "group",
		productId = 0,
		bonus = { kind = "mood", value = 6 },
		emoji = "⭐",
		color = hex("5FD38D"),
	},
	-- Эпические (Robux)
	{
		id = "neon_fox",
		name = "Неоновая лиса",
		nameEn = "Neon Fox",
		rarity = "epic",
		how = "robux",
		productId = Universe.pick({ test = 3728447955, main = 3728498102 }),
		robuxPrice = 99,
		bonus = { kind = "devSpeed", value = 0.06 },
		emoji = "🦊",
		color = hex("FF6EB4"),
	},
	{
		id = "dragon_byte",
		name = "Дракончик-байт",
		nameEn = "Byte Dragon",
		rarity = "epic",
		how = "robux",
		productId = Universe.pick({ test = 3728447957, main = 3728498122 }),
		robuxPrice = 149,
		bonus = { kind = "revenue", value = 0.05 },
		emoji = "🐉",
		color = hex("3DC86E"),
	},
	-- Легендарные (Robux)
	{
		id = "golden_trophy",
		name = "Золотой кубок",
		nameEn = "Golden Trophy",
		rarity = "legendary",
		how = "robux",
		productId = Universe.pick({ test = 3728447964, main = 3728498132 }),
		robuxPrice = 249,
		bonus = { kind = "review", value = 0.25 },
		emoji = "🏆",
		color = hex("FFC93C"),
	},
	{
		id = "cosmic_whale",
		name = "Космический кит",
		nameEn = "Cosmic Whale",
		rarity = "legendary",
		how = "robux",
		productId = Universe.pick({ test = 3728447966, main = 3728498151 }),
		robuxPrice = 349,
		bonus = { kind = "devSpeed", value = 0.08 },
		emoji = "🐋",
		color = hex("5B5FE8"),
	},
}

local byId: { [string]: Mascot } = {}
for _, mascot in list do
	byId[mascot.id] = mascot
end

local Mascots = {
	list = list,
	folder = "Mascots", -- папка моделей в ServerStorage
	-- Цвет редкости (рамка карточки, подпись)
	rarityColors = {
		common = Color3.fromRGB(184, 188, 208),
		rare = Color3.fromRGB(61, 160, 255),
		epic = Color3.fromRGB(190, 110, 255),
		legendary = Color3.fromRGB(255, 201, 60),
	} :: { [Rarity]: Color3 },
	-- Следование за игроком: точка сзади-слева, шаг обновления и прыжок при ходьбе
	follow = {
		tickSeconds = 0.2,
		behind = 3, -- studs за спиной
		side = -2, -- влево
		hopHeight = 0.6,
		maxStep = 14, -- studs за тик; дальше — телепорт (игрок прыгнул или переместился)
	},
}

function Mascots.get(id: any): Mascot?
	return if type(id) == "string" then byId[id] else nil
end

function Mascots.findByProduct(productId: number): Mascot?
	if productId == 0 then
		return nil
	end
	for _, mascot in list do
		if mascot.how == "robux" and mascot.productId == productId then
			return mascot
		end
	end
	return nil
end

return Mascots
