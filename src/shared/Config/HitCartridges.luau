--!strict
-- Картриджи-хиты (HitService): пассивный доход от игр с оценкой >= minScore и воровство.
-- Ориентир дохода: оценка 7 в гараже даёт за релиз 15 × 7² = $735 (Config/Economy),
-- картридж 7 приносит ~10% этого в минуту, 10 — втрое больше, чем 7.

export type Rarity = {
	id: string,
	multiplier: number, -- доход в минуту = baseIncome × multiplier
	color: Color3,
	glow: boolean, -- Neon + PointLight
}

local HitCartridges = {
	minScore = 7,
	baseIncome = 75, -- $/мин у картриджа с множителем 1
	incomeInterval = 60, -- общий цикл начисления, секунд

	-- Полка: слотов на старте и прибавка за каждый этап студии после первого (studioLevel)
	baseSlots = 4,
	slotsPerStage = 2,
	-- Полка у левой стены, лицом в комнату (+X). Свободно на всех этапах:
	-- стеллаж гаража z −9..1, доска z 8..16, экран небоскрёба z 0.5..11.5, растение (−26, −26)
	shelfPosition = Vector3.new(-27.6, 0.5, -15),
	shelfRotation = 90,
	maxSlots = 10, -- столько мест на модели HitShelf (2 ряда по 5, ModelFactory.hitShelfSlot)

	-- Кража
	holdDuration = 2,
	promptDistance = 8,
	carrySpeed = 12, -- WalkSpeed вора с картриджем
	thiefCooldown = 90, -- секунд между попытками одного вора
	victimImmunity = 120, -- после удачной кражи жертву нельзя обокрасть
	newbieGames = 3, -- с меньшим числом выпущенных игр нельзя красть и быть обокраденным
	catchDistance = 5, -- хозяин подошёл к вору ближе — поймал
	deliverDistance = 7, -- вор у своей полки ближе — донёс
	carryTimeout = 120, -- не донёс за это время — картридж возвращается
	maxMapDistance = 400, -- вор дальше от центра карты (или упал ниже fallY) — возврат
	fallY = -30,
	penaltyMinutes = 2, -- штраф пойманному вору: N минут его пассивного дохода
	penaltyMin = 200,
	-- Быстрее этого (studs/с по горизонтали) вор с картриджем не бегает: телепорт/спидхак — возврат
	maxCarrySpeed = 30,

	-- «Закрыть студию»
	lockSeconds = 60,
	lockCooldown = 300, -- от момента закрытия

	-- Таблица воров
	boardWriteInterval = 60,
	boardReadInterval = 120,
	boardSize = 10,
}

-- Редкость по оценке
local RARITIES: { [number]: Rarity } = {
	[7] = { id = "blue", multiplier = 1, color = Color3.fromRGB(70, 140, 255), glow = false },
	[8] = { id = "blue", multiplier = 1.4, color = Color3.fromRGB(70, 140, 255), glow = false },
	[9] = { id = "purple", multiplier = 2, color = Color3.fromRGB(170, 80, 255), glow = false },
	[10] = { id = "gold", multiplier = 3, color = Color3.fromRGB(255, 200, 50), glow = true },
}

function HitCartridges.rarity(score: number): Rarity
	return RARITIES[math.clamp(math.floor(score), 7, 10)]
end

function HitCartridges.income(score: number): number
	return math.floor(HitCartridges.baseIncome * HitCartridges.rarity(score).multiplier)
end

function HitCartridges.slots(studioLevel: number): number
	local slots = HitCartridges.baseSlots
		+ HitCartridges.slotsPerStage * math.max(math.floor(studioLevel) - 1, 0)
	return math.min(slots, HitCartridges.maxSlots)
end

return HitCartridges
