--!strict
-- Обучение по ходу игры (GuideController, GuideService): игре много систем, и рассказываем о них
-- постепенно — одна карточка «Как это работает» (заголовок + 3 пункта) за раз, когда игрок до
-- системы дошёл, а не всё сразу.
-- Два вида карточек:
--   menuSlot — показывается, когда игрок впервые нажал кнопку системы в боковом меню (сразу,
--              поверх окна: он сам туда пришёл и хочет понять, что это);
--   when     — сама, по условию (этап студии, выпущено игр, открыта система Config/Unlocks), через
--              очередь всплывашек (PopupQueue) и не чаще одной в autoGapSeconds.
-- Тексты: guide_<id>_title, guide_<id>_1.._3 в Config/Texts (+ Locales). Прочитанное сервер
-- помнит в profile.guides.seen (атрибут GuidesSeen); перечитать можно в окне «📖 Справочник».

export type When = {
	stage: number?, -- Config/Unlocks.stageOf: 0 парк, 1 гараж, 2 офис, 3 2-й этаж, 4 3-й этаж
	games: number?, -- выпущено игр (profile.gamesReleased) не меньше
	feature: string?, -- открыта система Config/Unlocks (FeatureGate.isOpen)
}

export type Guide = {
	id: string,
	icon: string,
	menuSlot: number?,
	when: When?,
}

local Guides = {}

-- Пауза между авто-карточками и после карточки из меню: не больше одной новой мысли за раз
Guides.autoGapSeconds = 180
-- Первая авто-карточка — не раньше, чем через столько секунд в сессии (сначала оглядеться)
Guides.sessionDelaySeconds = 60
-- Как часто клиент проверяет условия авто-карточек
Guides.checkSeconds = 2
-- Слот кнопки «📖 Справочник» в боковом меню (Ui.menuButton)
Guides.bookSlot = 20
-- Атрибут игрока: id прочитанных карточек через запятую (ставит сервер)
Guides.SEEN_ATTRIBUTE = "GuidesSeen"

-- Порядок списка = порядок в справочнике и приоритет авто-карточек (раньше в списке — раньше покажем)
Guides.list = {
	-- Ядро: как делать хорошие игры — после пары первых игр в гараже
	{ id = "critics", icon = "⭐", when = { stage = 1, games = 2 } },
	{ id = "trends", icon = "🔥", when = { feature = "trends", games = 4 } },
	{ id = "payday", icon = "💸", when = { stage = 1, games = 6 } },
	{ id = "dailyEvents", icon = "📅", when = { feature = "dailyEvents", games = 8 } },
	{ id = "move", icon = "🚚", when = { stage = 1, games = 10 } },
	-- Сразу после покупки офиса: где и как открыть 2-й этаж (отчёт v71, №3)
	{ id = "floor2", icon = "🛗", when = { stage = 2 } },

	-- Кнопки меню гаража
	{ id = "team", icon = "👥", menuSlot = 2 },
	{ id = "quests", icon = "📋", menuSlot = 3 },
	{ id = "shop", icon = "🛒", menuSlot = 4 },
	{ id = "camera", icon = "🎥", menuSlot = 10 },
	{ id = "research", icon = "🔬", menuSlot = 1 },
	{ id = "hits", icon = "📀", menuSlot = 7 },
	{ id = "bank", icon = "🏦", menuSlot = 11 },
	{ id = "tax", icon = "🧾", menuSlot = 18 },

	-- Офис
	{ id = "studio", icon = "🛋️", menuSlot = 13 },
	{ id = "achievements", icon = "🏆", menuSlot = 14 },
	{ id = "tours", icon = "🏘", menuSlot = 15 },
	{ id = "season", icon = "🎫", menuSlot = 16 },
	{ id = "thieves", icon = "😈", menuSlot = 8 },
	{ id = "expo", icon = "🏆", when = { feature = "expo" } },
	{ id = "coop", icon = "🤝", when = { feature = "coop", games = 30 } },
	{ id = "events", icon = "📰", when = { stage = 2, games = 40 } },
	{ id = "safe", icon = "🔐", when = { feature = "safe", stage = 2 } },

	-- 2-й этаж и дальше
	{ id = "rivals", icon = "📊", menuSlot = 17 },
	{ id = "stocks", icon = "📈", menuSlot = 19 },
	{ id = "rebirth", icon = "♻️", menuSlot = 5 },
	{ id = "gotw", icon = "🏆", when = { feature = "gotw" } },
	{ id = "trade", icon = "🔁", when = { feature = "trade" } },
	{ id = "console", icon = "🎮", when = { stage = 3, games = 120 } },
	{ id = "bailiffs", icon = "⚖️" }, -- только в справочнике и по событию (долг), см. GuideController
} :: { Guide }

local byId: { [string]: Guide } = {}
local bySlot: { [number]: Guide } = {}
for _, guide in Guides.list do
	byId[guide.id] = guide
	if guide.menuSlot then
		bySlot[guide.menuSlot] = guide
	end
end

function Guides.get(id: string): Guide?
	return byId[id]
end

function Guides.forSlot(slot: number): Guide?
	return bySlot[slot]
end

return Guides
