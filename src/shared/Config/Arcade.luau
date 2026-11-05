--!strict
-- Мини-аркада «Сыграй в свою игру» (ArcadeService, ArcadeWindow): после релиза игрок может
-- 20 секунд поиграть в мини-игру по жанру. Медаль даёт небольшой бонус к доходу этого релиза.
-- Расписание объектов строится из seed одинаково на сервере и клиенте: сервер знает максимум очков
-- и обрезает присланный счёт. Бонус — один раз на релиз и только в первые windowSeconds.

export type Kind = "whack" | "lanes" | "puzzle" | "jump" | "catch"
export type Grade = "gold" | "silver" | "bronze"

-- Объект расписания: t — секунда игры, когда он «срабатывает» (мишень появляется, препятствие
-- доезжает до игрока, монета долетает до корзины); lane — лунка/полоса/цвет; x — 0..1 по ширине
export type Spawn = { t: number, lane: number, x: number }

export type GameConfig = {
	lanes: number, -- сколько лунок/полос/цветов
	count: number, -- объектов в расписании не больше
	firstAt: number, -- первый объект, с
	gapMin: number,
	gapMax: number,
	tail: number, -- последний объект не позже duration − tail
	visible: number?, -- тир: сколько секунд видна мишень
	travel: number?, -- гонка/забег/монеты: сколько секунд объект летит до игрока
	jumpTime: number?, -- забег: длительность прыжка
	paddle: number?, -- монеты: ширина корзины (доля поля)
	speed: number?, -- монеты: скорость корзины с клавиш (доля поля в секунду)
	par: number?, -- головоломка: счёт «на 100%» (у остальных — число объектов)
	minInterval: number?, -- головоломка: не чаще одного ответа за столько секунд
	shuffleEvery: number?, -- головоломка: корзины меняют цвета каждые N фишек
	-- Счёт выше par × plausibleShare считается подделкой (без медали). Нет — потолок maxScore
	plausibleShare: number?,
}

local Arcade = {
	enabled = true,
	duration = 20, -- секунд игры
	countdown = 3, -- отсчёт перед стартом
	windowSeconds = 180, -- начать можно в течение стольких секунд после релиза
	startCooldown = 2, -- запрос сессии не чаще, с
	-- Допуск времени отправки результата относительно countdown + duration (задержка сети)
	submitEarly = 1.5,
	submitLate = 30,
	keepReleases = 3, -- сколько последних релизов помнит сервер

	-- Бонус к доходу релиза по медали (доля дохода)
	bonus = {
		gold = 0.05,
		silver = 0.03,
		bronze = 0.01,
	} :: { [Grade]: number },
	-- Медаль по доле от par (по убыванию)
	grades = {
		{ id = "gold" :: Grade, share = 0.85 },
		{ id = "silver" :: Grade, share = 0.6 },
		{ id = "bronze" :: Grade, share = 0.3 },
	},

	-- Жанр → мини-игра (Config/Genres); жанра нет в списке — default
	genres = {
		action = "whack",
		horror = "whack",
		racing = "lanes",
		sports = "lanes",
		puzzle = "puzzle",
		strategy = "puzzle",
		adventure = "jump",
		rpg = "jump",
		casual = "catch",
		simulation = "catch",
	} :: { [string]: Kind },
	default = "catch" :: Kind,

	games = {
		-- Тир: мишени выскакивают в 3 лунках, промах по пустой −1
		whack = {
			lanes = 3,
			count = 26,
			firstAt = 0.6,
			gapMin = 0.5,
			gapMax = 0.8,
			tail = 1,
			visible = 0.95,
		},
		-- Гонка: препятствия едут по 3 полосам, меняй полосу
		lanes = {
			lanes = 3,
			count = 24,
			firstAt = 1.6,
			gapMin = 0.6,
			gapMax = 0.9,
			tail = 0.3,
			travel = 1.6,
		},
		-- Головоломка: фишку — в корзину её цвета (4 стороны), корзины иногда меняются
		puzzle = {
			lanes = 4,
			count = 80,
			firstAt = 0,
			gapMin = 0,
			gapMax = 0,
			tail = 0,
			par = 28,
			minInterval = 0.3,
			shuffleEvery = 8,
			-- Рекорд руками ≈ 2 фишки в секунду (~40 за 20 с); 0.3 с на ответ (66) — только скрипт
			plausibleShare = 1.75,
		},
		-- Забег: ямы подъезжают, прыгай
		jump = {
			lanes = 1,
			count = 14,
			firstAt = 2,
			gapMin = 1.1,
			gapMax = 1.6,
			tail = 0.3,
			travel = 2,
			jumpTime = 0.75,
		},
		-- Монеты: лови корзиной
		catch = {
			lanes = 1,
			count = 22,
			firstAt = 1.8,
			gapMin = 0.6,
			gapMax = 1,
			tail = 0.3,
			travel = 1.8,
			paddle = 0.24,
			speed = 1.4,
		},
	} :: { [Kind]: GameConfig },
}

function Arcade.kindFor(genreId: string): Kind
	return Arcade.genres[genreId] or Arcade.default
end

-- Расписание игры; одинаковое на сервере и клиенте при одном seed
function Arcade.schedule(kind: Kind, seed: number): { Spawn }
	local cfg = Arcade.games[kind]
	local rng = Random.new(seed)
	local list: { Spawn } = {}
	local t = cfg.firstAt
	local last = 0
	for _ = 1, cfg.count do
		if kind ~= "puzzle" and t > Arcade.duration - cfg.tail then
			break
		end
		-- Подряд не в ту же лунку/полосу/цвет
		local lane = rng:NextInteger(1, cfg.lanes)
		if cfg.lanes > 1 and lane == last then
			lane = lane % cfg.lanes + 1
		end
		last = lane
		table.insert(list, { t = t, lane = lane, x = rng:NextNumber(0.08, 0.92) })
		t += rng:NextNumber(cfg.gapMin, cfg.gapMax)
	end
	return list
end

-- Счёт «на 100%»: от него считаются медали
function Arcade.par(kind: Kind, seed: number): number
	local cfg = Arcade.games[kind]
	return cfg.par or #Arcade.schedule(kind, seed)
end

-- Больше этого честно не набрать (сервер обрезает присланный счёт)
function Arcade.maxScore(kind: Kind, seed: number): number
	local cfg = Arcade.games[kind]
	local count = #Arcade.schedule(kind, seed)
	if cfg.minInterval then
		return math.min(count, math.floor(Arcade.duration / cfg.minInterval))
	end
	return count
end

-- Мог ли человек честно набрать score за duration: целое, не меньше 0, не больше maxScore
-- и par × plausibleShare. Неправдоподобный счёт не обрезается до максимума (так подделка
-- получала бы золото), а остаётся без медали
function Arcade.plausible(kind: Kind, seed: number, score: any): boolean
	if type(score) ~= "number" or score ~= score or score % 1 ~= 0 or score < 0 then
		return false
	end
	if score > Arcade.maxScore(kind, seed) then
		return false
	end
	local share = Arcade.games[kind].plausibleShare
	return share == nil or score <= math.floor(Arcade.par(kind, seed) * share)
end

function Arcade.grade(kind: Kind, seed: number, score: number): Grade?
	local par = math.max(Arcade.par(kind, seed), 1)
	for _, step in Arcade.grades do
		if score >= math.ceil(par * step.share) then
			return step.id
		end
	end
	return nil
end

return Arcade
