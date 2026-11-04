--!strict
-- Формулы оценки и дохода. Общие для сервера и клиента (клиент — только для подсказок).
-- Решение всегда принимает сервер.

local Genres = require(script.Parent.Config.Genres)
local Topics = require(script.Parent.Config.Topics)
local Economy = require(script.Parent.Config.Economy)

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
-- bonus — прибавка к оценке до округления (декор и техника студии, Config/Upgrades.reviewBonus)
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

return Formulas
