--!strict
-- «События дня» (роадмап 7.15): каждый час в hh:30 UTC одно хорошее событие на 15 минут
-- (выставка подводит итоги на границе часа — не пересекаемся). Какое событие — детерминированно
-- от номера часа (os.time() // 3600: час + день недели), поэтому на всех серверах одно и то же
-- и его можно заранее анонсировать в группе и Discord. Плюс раз в день «Золотой час»
-- (доход ×2 у всех на 20 минут) и «Ночная смена» — это хакатон (Config/Hackathon), он только
-- показывается в общем расписании.
-- Сервер — DailyEventService (атрибуты ReplicatedStorage DailyEvent*, DailyGolden*), клиент —
-- DailyEventBanner. Плохих событий здесь нет: они в событиях компании (Config/CompanyEvents).
-- График контента (Config/ContentDrops): событие, которое ещё не вышло к часу слота, не выпадает
-- (выбор среди вышедших; решает время слота — на всех серверах одинаково). Критики — только по
-- вышедшим жанрам.
-- Админ-панель (AdminService) может запустить событие или золотой час на одном сервере: атрибуты
-- ReplicatedStorage AdminEventId / AdminEventStartsAt / AdminEventEndsAt и AdminGoldenStartsAt /
-- AdminGoldenEndsAt (ставит только сервер) — пока окно идёт, оно вместо расписания (adminSlot).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ContentDrops = require(script.Parent.ContentDrops)
local Debug = require(script.Parent.Debug)
local Genres = require(script.Parent.Genres)

export type EventId =
	"coffeeRush"
	| "investors"
	| "bugHunt"
	| "cartridgeRush"
	| "blitzJam"
	| "critics"
	| "pizza"
	| "talentHunt"
	| "flashSale"
	| "mascotParade"

export type Event = { id: EventId, icon: string, weight: number }

-- Слот расписания: событие, окно и параметры (жанр критиков, тема блиц-джема)
export type Slot = {
	index: number, -- номер часа (os.time() // slotSeconds)
	id: EventId,
	startsAt: number,
	endsAt: number,
	announceSeconds: number,
	genreId: string?, -- critics, blitzJam
	topicId: string?, -- blitzJam
}

export type Window = { startsAt: number, endsAt: number, announceSeconds: number }

local DailyEvents = {
	slotSeconds = 60 * 60,
	offsetSeconds = 30 * 60, -- старт в hh:30 UTC
	durationSeconds = 15 * 60,
	announceSeconds = 2 * 60, -- баннер «Через 2 мин» и пинг
	-- Общие лимиты: событие не поднимает множитель выше этого вместе с праздником / хакатоном.
	-- Если праздник уже выше лимита — событие ничего не добавляет (но и не отнимает)
	maxRevenueMultiplier = 2,
	maxDevSpeed = 2.5, -- хакатон ×2 × кофе-раш ×1.25

	-- Золотой час: раз в день, вечер EU и день US (19:00 UTC = 20:00 Берлин, 14:00 Нью-Йорк)
	golden = {
		hourUtc = 19,
		minuteUtc = 0,
		-- Релизный проход 05.11 (docs/BALANCE.md): 20 → 15 мин. Для игрока, который застаёт его
		-- через день, ×2 на 20 мин = +8% всех денег и 1-й Rebirth ~2.5 ч раньше; 15 мин (как у
		-- остальных событий дня) оставляют «×2» для анонсов и возвращают 1-й Rebirth к ~27 ч
		durationSeconds = 15 * 60,
		announceSeconds = 2 * 60,
		revenueMultiplier = 2,
	},

	-- Список событий. weight — относительная частота (1 — обычная)
	events = {
		{ id = "coffeeRush", icon = "☕", weight = 1 },
		{ id = "investors", icon = "📈", weight = 1 },
		{ id = "bugHunt", icon = "🐞", weight = 1 },
		{ id = "cartridgeRush", icon = "💾", weight = 1 },
		{ id = "blitzJam", icon = "⚡", weight = 1 },
		{ id = "critics", icon = "🎤", weight = 1 },
		{ id = "pizza", icon = "🍕", weight = 1 },
		{ id = "talentHunt", icon = "🔍", weight = 1 },
		{ id = "flashSale", icon = "🏷️", weight = 1 },
		{ id = "mascotParade", icon = "🐾", weight = 1 },
	} :: { Event },

	-- Эффекты событий
	coffeeRush = {
		devSpeed = 1.25, -- разработка +25% быстрее (вместе с хакатоном — не выше maxDevSpeed)
		-- Кофе за Robux цену в Dashboard менять нельзя: магазин продаёт скидочную копию
		-- «Сделки дня» (Products.deals[dealKey], выдаёт OfferService как обычный кофе)
		dealKey = "coffee",
	},
	investors = {
		grants = 10, -- первые N игроков сервера
		incomeMinutes = 10, -- грант: N минут дохода (RewardService)
		reachDistance = 14, -- ProximityPrompt 10 + запас на лаги
		-- Модель ServerStorage.DailyEvents.Investor или InvestorNPC Астры (V27: ServerStorage.Upgrades /
		-- ServerStorage / DailyEvents; одежда — Images.investor, кейс — Accessory InvestorCase);
		-- нет — заглушка из деталей
		modelFolder = "DailyEvents",
		modelName = "Investor",
	},
	bugHunt = {
		count = 30, -- столько жуков одновременно (пойманного сменяет новый)
		respawnSeconds = 4,
		incomeMinutes = 0.5, -- за жука
		-- Релизный проход 05.11 (docs/BALANCE.md): без лимита один игрок за 15 мин ловил сотни жуков
		-- (клик раз в 0.25 с, 30 жуков, новый через 4 с) — до 100–300 минут дохода за событие,
		-- больше всей игровой сессии. Лимит на игрока (по UserId, перезаход не сбрасывает) —
		-- 30 жуков = 15 минут дохода, плюс бонус топ-3. Дальше жуки идут только в зачёт топа
		maxCatchesPerPlayer = 30,
		catchDistance = 40, -- ClickDetector 32 + запас на лаги
		catchCooldown = 0.25, -- секунд между поимками одного игрока
		topBonusMinutes = { 10, 6, 3 }, -- лучшим трём ловцам в конце
		parkRadiusMin = 12,
		parkRadiusMax = 100,
		plotShare = 0.4, -- доля жуков перед участками (остальные — в парке)
		crawlSeconds = 2,
		crawlStep = 3,
		-- Маскот ServerStorage.Mascots.Mascot_bug_beetle; нет — заглушка из деталей
		mascotId = "bug_beetle",
		modelScale = 0.6,
	},
	cartridgeRush = {
		cartridgeMultiplier = 3, -- точек картриджей в парке в 3 раза больше
		pawnMultiplier = 2, -- ломбард платит ×2
	},
	blitzJam = {
		-- Только стартовые жанры и темы: участвовать может каждый
		genres = { "action", "adventure", "casual" },
		topics = { "space", "fantasy", "zombies" },
		trophy = "blitzJam", -- RewardService: rewards.trophies (полка)
		-- Кубок на крыше полки хитов (HitService), если победил хоть раз: модель Астры
		-- ServerStorage.Upgrades.Trophy_Blitz (V27). Нет модели — кубка нет, как раньше
		trophyModel = "Trophy_Blitz",
		trophyOffset = CFrame.new(-4.4, 5, 0), -- слева на крыше HitShelf (справа — Trophy_GOTW)
		winnerIncomeMinutes = 20,
		titleId = "blitz_champion", -- временный титул (Config/Titles, TitleService.grant)
		titleSeconds = 24 * 60 * 60,
		boardSize = 3,
	},
	critics = {
		reviewBonus = 1, -- игры жанра дня +1 к оценке
	},
	pizza = {
		moodKey = "devent_mood_pizza", -- строка в разборе настроения
	},
	talentHunt = {
		discount = 0.5, -- «звезда» найма за полцены
	},
	flashSale = {
		cashDiscount = 0.3, -- декор и стили за $ дешевле на 30%
	},
	mascotParade = {
		bonusMultiplier = 2, -- бонус маскота ×2 (DevelopmentService всё равно режет до +100%)
	},

	-- В Studio (Config/Debug.dailyEventShort) — короткий цикл
	studioSlotSeconds = 6 * 60,
	studioOffsetSeconds = 60,
	studioDurationSeconds = 3 * 60,
	studioAnnounceSeconds = 30,
	studioGoldenSlotSeconds = 10 * 60, -- золотой час каждые 10 мин на 2 мин
	studioGoldenDurationSeconds = 2 * 60,
}

local byId: { [string]: Event } = {}
local totalWeight = 0
for _, event in DailyEvents.events do
	byId[event.id] = event
	totalWeight += event.weight
end

-- Все жанры по алфавиту (критики): порядок одинаковый на всех серверах
local GENRE_IDS: { string } = {}
for id in Genres do
	table.insert(GENRE_IDS, id)
end
table.sort(GENRE_IDS)

local function studio(): boolean
	return RunService:IsStudio()
end

local function short(): boolean
	return studio() and Debug.dailyEventShort == true
end

function DailyEvents.get(id: any): Event?
	return if type(id) == "string" then byId[id] else nil
end

-- Принудительное событие в Studio (Config/Debug.dailyEventForce), иначе nil
local function forced(): EventId?
	local id = Debug.dailyEventForce
	if studio() and id and byId[id] then
		return id :: EventId
	end
	return nil
end

-- События, вышедшие к моменту at (Config/ContentDrops); все вышли — весь список как есть
local function releasedEvents(at: number): ({ Event }, number)
	local list: { Event } = {}
	local weight = 0
	for _, event in DailyEvents.events do
		if ContentDrops.isReleased("dailyEvent", event.id, at) then
			table.insert(list, event)
			weight += event.weight
		end
	end
	if #list == 0 then
		return DailyEvents.events, totalWeight
	end
	return list, weight
end

-- Взвешенный выбор по случайному числу 0..1 среди list (сумма весов weight)
local function pick(roll: number, list: { Event }, weight: number): EventId
	local acc = 0
	for _, event in list do
		acc += event.weight / weight
		if roll < acc then
			return event.id
		end
	end
	return list[#list].id
end

-- Параметры события: жанр критиков (из вышедших к at), жанр и тема блиц-джема
local function slotParams(id: EventId, rng: Random, at: number): (string?, string?)
	local genreId: string?, topicId: string? = nil, nil
	local genres: { string } = {}
	for _, gid in GENRE_IDS do
		if ContentDrops.isReleased("genre", gid, at) then
			table.insert(genres, gid)
		end
	end
	if id == "critics" and #genres > 0 then
		genreId = genres[rng:NextInteger(1, #genres)]
	elseif id == "blitzJam" then
		local cfg = DailyEvents.blitzJam
		genreId = cfg.genres[rng:NextInteger(1, #cfg.genres)]
		topicId = cfg.topics[rng:NextInteger(1, #cfg.topics)]
	end
	return genreId, topicId
end

-- Событие и параметры часа index (начинается в at). Random с числом-зерном одинаков на всех
-- серверах; подряд одно и то же событие не повторяем (берём следующее по списку)
local function slotContent(index: number, at: number): (EventId, string?, string?)
	local rng = Random.new(index * 7919 + 17)
	local list, weight = releasedEvents(at)
	local id = forced() or pick(rng:NextNumber(), list, weight)
	if not forced() then
		local prev = pick(Random.new((index - 1) * 7919 + 17):NextNumber(), list, weight)
		if prev == id then
			for i, event in list do
				if event.id == id then
					id = list[i % #list + 1].id
					break
				end
			end
		end
	end
	return id, slotParams(id, rng, at)
end

-- Окно события из админ-панели (атрибуты AdminEvent*), если оно идёт в момент t. Номер слота —
-- минута старта: не совпадает с номерами часов расписания (лимиты выплат slotPaid — свои)
local function adminSlot(t: number): Slot?
	local id = ReplicatedStorage:GetAttribute("AdminEventId")
	local startsAt = ReplicatedStorage:GetAttribute("AdminEventStartsAt")
	local endsAt = ReplicatedStorage:GetAttribute("AdminEventEndsAt")
	if
		type(id) ~= "string"
		or not byId[id]
		or type(startsAt) ~= "number"
		or type(endsAt) ~= "number"
		or t < startsAt
		or t >= endsAt
	then
		return nil
	end
	local index = startsAt // 60
	local genreId, topicId = slotParams(id :: EventId, Random.new(index * 7919 + 17), startsAt)
	return {
		index = index,
		id = id :: EventId,
		startsAt = startsAt,
		endsAt = endsAt,
		announceSeconds = 0,
		genreId = genreId,
		topicId = topicId,
	}
end

local function timings(): (number, number, number, number)
	if short() then
		return DailyEvents.studioSlotSeconds,
			DailyEvents.studioOffsetSeconds,
			DailyEvents.studioDurationSeconds,
			DailyEvents.studioAnnounceSeconds
	end
	return DailyEvents.slotSeconds,
		DailyEvents.offsetSeconds,
		DailyEvents.durationSeconds,
		DailyEvents.announceSeconds
end

-- Слот номер index (index-й час с 1970 года, в Studio с dailyEventShort — короткий цикл)
function DailyEvents.slotAt(index: number): Slot
	local interval, offset, duration, announce = timings()
	local startsAt = index * interval + offset
	local id, genreId, topicId = slotContent(index, startsAt)
	return {
		index = index,
		id = id,
		startsAt = startsAt,
		endsAt = startsAt + duration,
		announceSeconds = announce,
		genreId = genreId,
		topicId = topicId,
	}
end

-- Слот, который идёт сейчас, или ближайший следующий
function DailyEvents.slot(now: number?): Slot
	local t = now or os.time()
	local admin = adminSlot(t)
	if admin then
		return admin
	end
	local interval, offset, duration = timings()
	if forced() and not short() then
		-- Без короткого цикла принудительное событие идёт всё время: окно от границы часа на 2 часа
		local startsAt = t // 3600 * 3600
		local id, genreId, topicId = slotContent(startsAt // 3600, startsAt)
		return {
			index = startsAt // 3600,
			id = id,
			startsAt = startsAt,
			endsAt = startsAt + 7200,
			announceSeconds = 0,
			genreId = genreId,
			topicId = topicId,
		}
	end
	local index = (t - offset) // interval
	if t >= index * interval + offset + duration then
		index += 1
	end
	return DailyEvents.slotAt(index)
end

-- Ближайшие count слотов начиная с текущего (окно расписания)
function DailyEvents.upcoming(count: number, now: number?): { Slot }
	local first = DailyEvents.slot(now)
	local list = { first }
	if forced() and not short() then
		return list
	end
	-- Событие из админ-панели: после него — расписание с ближайшего слота после его конца
	local nextIndex = first.index + 1
	if adminSlot(now or os.time()) then
		nextIndex = DailyEvents.slot(first.endsAt).index
	end
	for i = 0, count - 2 do
		table.insert(list, DailyEvents.slotAt(nextIndex + i))
	end
	return list
end

-- Золотой час: текущее окно или ближайшее следующее
function DailyEvents.goldenWindow(now: number?): Window
	local t = now or os.time()
	local cfg = DailyEvents.golden
	local adminStart = ReplicatedStorage:GetAttribute("AdminGoldenStartsAt")
	local adminEnd = ReplicatedStorage:GetAttribute("AdminGoldenEndsAt")
	if type(adminStart) == "number" and type(adminEnd) == "number" and t >= adminStart and t < adminEnd then
		return { startsAt = adminStart, endsAt = adminEnd, announceSeconds = 0 }
	end
	if studio() and Debug.dailyGoldenForce then
		local startsAt = t // 3600 * 3600
		return { startsAt = startsAt, endsAt = startsAt + 7200, announceSeconds = 0 }
	end
	local interval = 24 * 60 * 60
	local offset = cfg.hourUtc * 3600 + cfg.minuteUtc * 60
	local duration = cfg.durationSeconds
	local announce = cfg.announceSeconds
	if short() then
		interval = DailyEvents.studioGoldenSlotSeconds
		offset = 0
		duration = DailyEvents.studioGoldenDurationSeconds
		announce = DailyEvents.studioAnnounceSeconds
	end
	local startsAt = (t - offset) // interval * interval + offset
	if t >= startsAt + duration then
		startsAt += interval
	end
	return { startsAt = startsAt, endsAt = startsAt + duration, announceSeconds = announce }
end

-- ===== Для клиента и сервера: что сейчас идёт (атрибуты ставит DailyEventService) =====

-- Идёт ли событие id. Сервер выставляет атрибуты каждую секунду; клиент видит то же самое
function DailyEvents.isActive(id: EventId): boolean
	return ReplicatedStorage:GetAttribute("DailyEventActive") == true
		and ReplicatedStorage:GetAttribute("DailyEventId") == id
end

-- Цена товара за $ с учётом «Флеш-распродажи» (декор и стили мебели; Robux не трогаем)
function DailyEvents.cashPrice(cost: number): number
	if cost <= 0 or not DailyEvents.isActive("flashSale") then
		return cost
	end
	return math.floor(cost * (1 - math.clamp(DailyEvents.flashSale.cashDiscount, 0, 0.9)))
end

return DailyEvents
