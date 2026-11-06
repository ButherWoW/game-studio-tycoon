--!strict
-- Формулы оценки и дохода. Общие для сервера и клиента (клиент — только для подсказок).
-- Решение всегда принимает сервер.

local Genres = require(script.Parent.Config.Genres)
local Topics = require(script.Parent.Config.Topics)
local Economy = require(script.Parent.Config.Economy)
local Fans = require(script.Parent.Config.Fans)

export type Points = { gameplay: number, graphics: number, sound: number, story: number }

local Formulas = {}

-- Насколько распределение очков похоже на «идеал» жанра: 0..1
function Formulas.balanceScore(genreId: string, points: Points): number
	local genre = Genres[genreId]
	assert(genre, "Unknown genre " .. genreId)
	local total = points.gameplay + points.graphics + points.sound + points.story
	if total <= 0 then
		return 0
	end
	local diff = math.abs(points.gameplay / total - genre.weights.gameplay)
		+ math.abs(points.graphics / total - genre.weights.graphics)
		+ math.abs(points.sound / total - genre.weights.sound)
		+ math.abs(points.story / total - genre.weights.story)
	-- diff от 0 (идеально) до 2 (всё мимо)
	return math.clamp(1 - diff, 0, 1)
end

function Formulas.topicFit(topicId: string, genreId: string): number
	local topic = Topics[topicId]
	assert(topic, "Unknown topic " .. topicId)
	return topic.fit[genreId] or 1.0
end

-- Оценка 1..10. rng передаётся снаружи, чтобы формулу можно было тестировать.
-- bonus — прибавка к оценке до округления (декор и техника студии, Config/Upgrades.reviewBonus);
-- DevelopmentService вычитает из неё criticExpectation и repeatPenalty
function Formulas.review(
	genreId: string,
	topicId: string,
	points: Points,
	rng: Random,
	bonus: number?
): number
	local total = points.gameplay + points.graphics + points.sound + points.story
	-- больше очков — лучше, но с затуханием
	local quality = math.min(math.log10(1 + total) / Economy.qualityLogDivisor, 1)
	local raw = 10
		* (Economy.balanceWeight * Formulas.balanceScore(genreId, points) + Economy.qualityWeight * quality)
	-- Тема — бонус или штраф, а не множитель всей оценки
	raw += (Formulas.topicFit(topicId, genreId) - 1) * Economy.topicFitStrength
	raw += rng:NextNumber(-Economy.reviewNoise, Economy.reviewNoise)
	raw += bonus or 0
	return math.clamp(math.floor(raw + 0.5), 1, 10)
end

-- Ключ сочетания для истории повторов
function Formulas.comboKey(genreId: string, topicId: string): string
	return genreId .. "/" .. topicId
end

-- Сколько вычесть из оценки (до округления) на этапе studioLevel: ожидания критиков от студии
function Formulas.criticExpectation(studioLevel: number): number
	local list = Economy.criticExpectation
	return list[math.clamp(math.floor(studioLevel), 1, #list)] or 0
end

-- Штраф за повтор: history — сочетания последних игр (Formulas.comboKey), новые в конце.
-- За каждое совпадение среди последних Economy.repeatHistory — repeatPenalty, не больше repeatPenaltyMax
function Formulas.repeatPenalty(history: { string }?, genreId: string, topicId: string): number
	if not history then
		return 0
	end
	local key = Formulas.comboKey(genreId, topicId)
	local count = 0
	for i = math.max(#history - Economy.repeatHistory + 1, 1), #history do
		if history[i] == key then
			count += 1
		end
	end
	return math.min(count * Economy.repeatPenalty, Economy.repeatPenaltyMax)
end

-- Запомнить сочетание выпущенной игры; храним только последние Economy.repeatHistory
function Formulas.rememberCombo(history: { string }, genreId: string, topicId: string)
	table.insert(history, Formulas.comboKey(genreId, topicId))
	while #history > Economy.repeatHistory do
		table.remove(history, 1)
	end
end

-- Доход от релиза. adBonus: 0.3 = +30%. rebirthMultiplier >= 1.
function Formulas.revenue(
	score: number,
	studioLevel: number,
	adBonus: number,
	rebirthMultiplier: number
): number
	local base = Economy.revenueBase * (score ^ 2) * (1 + Economy.studioLevelBonus * (studioLevel - 1))
	return math.floor(base * (1 + math.min(adBonus, 1)) * rebirthMultiplier)
end

-- ===== Фанаты студии (Config/Fans) =====

local function fanStage(studioLevel: number): number
	local list = Fans.stageGain
	return list[math.clamp(math.floor(studioLevel), 1, #list)] or 1
end

-- Множитель продаж от фанатов: ×1 при 0, к 1 + maxBonus только приближается
function Formulas.fanMultiplier(fans: number): number
	local f = math.max(if fans == fans then fans else 0, 0)
	return math.max(Fans.floor, 1 + Fans.maxBonus * f / (f + Fans.halfFans))
end

-- Изменение фанатов за релиз (целое, может быть < 0; fans + результат >= 0).
-- adBonus — активная реклама (0.3 = +30%): немного ускоряет только прирост
function Formulas.fanChange(score: number, fans: number, studioLevel: number, adBonus: number?): number
	local s = math.clamp(math.floor(score), 1, 10)
	local current = math.max(math.floor(fans), 0)
	local stage = fanStage(studioLevel)
	local share = Fans.lossShare[s]
	if share then
		local loss = math.max(current * share, (Fans.lossMin[s] or 0) * stage)
		return -math.min(math.floor(loss + 0.5), current)
	end
	local gain = (Fans.gain[s] or 0) * stage * (1 + math.clamp(adBonus or 0, 0, 1) * Fans.adGainShare)
	return math.floor(gain + 0.5)
end

-- Фанаты за выставку: place 1..3 (nil — без места), score — оценка игры игрока в раунде
function Formulas.expoFans(place: number?, score: number, studioLevel: number): number
	local base = if place == 1
		then Fans.expoWin
		elseif place == 2 then Fans.expoSecond
		elseif place == 3 then Fans.expoThird
		elseif score >= Fans.expoHighScore then Fans.expoHigh
		else 0
	return math.floor(base * fanStage(studioLevel) + 0.5)
end

return Formulas
