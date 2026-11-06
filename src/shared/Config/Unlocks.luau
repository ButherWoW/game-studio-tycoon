--!strict
-- Постепенное открытие систем для новичка (онбординг): кнопки бокового меню, плашки под HUD
-- и всплывашки появляются по мере роста студии, а не все 20 сразу в парке.
-- Этап (Unlocks.stageOf): 0 — парк (гаража нет), 1 — гараж, 2 — офис (1-й этаж),
-- 3 — 2-й этаж, 4 — 3-й этаж (= profile.studioLevel, когда гараж куплен).
-- Система открыта, если этап >= stage И выпущено игр >= games И хитов >= hits.
-- Один раз открытая система больше не прячется (profile.features.seen, FeatureUnlockService),
-- после Rebirth открыто всё. Системы не из списка (язык, домой, банк с долгом) видны всегда.
-- Свои ворота систем (Holdings.minStudioLevel, Contracts.minStage, CompanyEvents.minStage,
-- Stocks.ipo.requiresLevel, гараж в TourService/CoopService) остаются: здесь только не раньше них.

export type Feature = {
	stage: number,
	games: number?, -- profile.gamesReleased (игры в парке тоже считаются)
	hits: number?, -- profile.hitsReleased
	menuSlot: number?, -- кнопка бокового меню (Ui.menuButton): прячется, пока закрыто
	toast: boolean, -- тост «🆕 Открыто: …» и значок 🆕 на кнопке при открытии
	textKey: string?, -- имя в тосте (Texts), нужно при toast = true
}

export type Progress = {
	ownsGarage: boolean,
	studioLevel: number,
	gamesReleased: number,
	hitsReleased: number,
	rebirths: number,
}

local PARK, GARAGE, OFFICE, FLOOR2 = 0, 1, 2, 3

local Unlocks = {}

Unlocks.PARK = PARK
Unlocks.GARAGE = GARAGE
Unlocks.OFFICE = OFFICE
Unlocks.FLOOR2 = FLOOR2

-- Атрибут игрока: какие системы игрок уже видел открытыми, id через запятую (ставит сервер)
Unlocks.SEEN_ATTRIBUTE = "FeaturesSeen"

Unlocks.features = {
	-- Гараж: своя студия — команда, магазин, задания, вид студии; плашки событий дня и трендов
	team = { stage = GARAGE, menuSlot = 2, toast = true, textKey = "unlock_name_team" },
	quests = { stage = GARAGE, menuSlot = 3, toast = true, textKey = "unlock_name_quests" },
	shop = { stage = GARAGE, menuSlot = 4, toast = true, textKey = "unlock_name_shop" },
	camera = { stage = GARAGE, menuSlot = 10, toast = true, textKey = "unlock_name_camera" },
	-- События дня, «Золотой час» и хакатон «Ночная смена» (плашки и их тосты)
	dailyEvents = { stage = GARAGE, toast = true, textKey = "unlock_name_daily_events" },
	trends = { stage = GARAGE, toast = true, textKey = "unlock_name_trends" },
	-- Праздничный ивент: кнопка видна только во время ивента — тост был бы непонятен
	holiday = { stage = GARAGE, menuSlot = 9, toast = false },
	-- Налоговая: кнопка только со счётом; в гараже ставка 0 (Config/Tax), фактически с офиса
	tax = { stage = GARAGE, menuSlot = 18, toast = false },
	-- Баннер «в сейфе новый приз» (сам сейф в парке виден всем)
	safe = { stage = GARAGE, toast = false },
	-- «📖 Справочник» обучения (Config/Guides, GuideController): с гаража, когда есть что читать
	guides = { stage = GARAGE, menuSlot = 20, toast = false },
	-- Исследования: ОИ копятся с первой игры, а тратить есть смысл, когда их набралось
	research = { stage = GARAGE, games = 12, menuSlot = 1, toast = true, textKey = "unlock_name_research" },
	-- Хиты: окно со списком своих картриджей — с первого хита
	hits = { stage = GARAGE, hits = 1, menuSlot = 7, toast = true, textKey = "unlock_name_hits" },

	-- Офис: интерьер/декор, достижения, студии игроков, сезон, воры, выставка
	studio = { stage = OFFICE, menuSlot = 13, toast = true, textKey = "unlock_name_studio" },
	achievements = { stage = OFFICE, menuSlot = 14, toast = true, textKey = "unlock_name_achievements" },
	tours = { stage = OFFICE, menuSlot = 15, toast = true, textKey = "unlock_name_tours" },
	season = { stage = OFFICE, menuSlot = 16, toast = true, textKey = "unlock_name_season" },
	thieves = { stage = OFFICE, menuSlot = 8, toast = true, textKey = "unlock_name_thieves" },
	expo = { stage = OFFICE, toast = true, textKey = "unlock_name_expo" },
	-- Кнопка «🤝 Позвать в проект» у «Создать игру» (принять приглашение можно и раньше)
	coop = { stage = OFFICE, toast = false },

	-- 2-й этаж: индустрия и экономика — конкуренты, «Игра недели», биржа, обмен, Rebirth
	rivals = { stage = FLOOR2, menuSlot = 17, toast = true, textKey = "unlock_name_rivals" },
	gotw = { stage = FLOOR2, toast = false },
	stocks = { stage = FLOOR2, menuSlot = 19, toast = true, textKey = "unlock_name_stocks" },
	trade = { stage = FLOOR2, toast = true, textKey = "unlock_name_trade" },
	-- Rebirth стоит $11.5M с офисом (Config/Rebirth) — раньше 2-го этажа окно только пугает
	rebirth = { stage = FLOOR2, menuSlot = 5, toast = true, textKey = "unlock_name_rebirth" },
} :: { [string]: Feature }

-- Слот меню -> id системы
local bySlot: { [number]: string } = {}
for id, feature in Unlocks.features do
	if feature.menuSlot then
		bySlot[feature.menuSlot] = id
	end
end

function Unlocks.menuFeature(slot: number): string?
	return bySlot[slot]
end

function Unlocks.stageOf(progress: Progress): number
	if not progress.ownsGarage then
		return PARK
	end
	return math.max(math.floor(progress.studioLevel), GARAGE)
end

-- Выполнены ли условия сейчас (без учёта «уже видел»). Неизвестный id — открыт
function Unlocks.meets(id: string, progress: Progress): boolean
	local feature = Unlocks.features[id]
	if not feature or progress.rebirths > 0 then
		return true
	end
	return Unlocks.stageOf(progress) >= feature.stage
		and progress.gamesReleased >= (feature.games or 0)
		and progress.hitsReleased >= (feature.hits or 0)
end

return Unlocks
