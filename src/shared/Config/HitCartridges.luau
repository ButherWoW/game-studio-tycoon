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
	-- Быстрее этого (studs/с по горизонтали, в среднем за speedWindow) вор с картриджем не бегает:
	-- телепорт/спидхак — возврат. Запас над carrySpeed (×1.2) на лаги и спуски; ниже обычных 16,
	-- чтобы читер с WalkSpeed 18 не уходил от жертвы
	maxCarrySpeed = 14.5,
	speedWindow = 1, -- секунд: окно усреднения скорости
	walkSpeedTolerance = 0.5, -- Humanoid.WalkSpeed вора выше carrySpeed + допуск — кража отменяется
	-- Вор с картриджем должен идти по земле: выше над полом — полёт, кража отменяется
	maxCarryHeight = 9,
	-- Ловить по горизонтали, по высоте с запасом (прыжки, лестницы)
	catchHeight = 12,
	-- Охранник студии (GuardService): выбегает от полки, когда вор уносит картридж. Ловит не наверняка:
	-- каждая попытка удаётся с шансом catchChance, при промахе охранник спотыкается на stunSeconds
	-- (вор уходит), после maxAttempts попыток сдаётся; дальше leashDistance от полки не гонится.
	-- Скорость выше carrySpeed (12), поэтому догоняет, но вор с запасом или хорошим маршрутом может уйти
	guard = {
		enabled = true,
		reactionSeconds = 1.5,
		speed = 15,
		catchDistance = 4,
		catchChance = 0.5,
		maxAttempts = 2,
		stunSeconds = 3,
		leashDistance = 110,
	},
	-- Одна пара «вор → жертва» не чаще раза в это время: против накрутки на альтах
	pairCooldown = 10 * 60,
	-- Картридж, который отобрали у тебя, нельзя сразу утащить обратно (пинг-понг альтов)
	stealBackCooldown = 30 * 60,

	-- «Закрыть студию»
	lockSeconds = 60,
	lockCooldown = 300, -- от момента закрытия

	-- «Обновление / DLC» хита (кнопка в окне 🔒): раз в UTC-день на картридж.
	-- Доход картриджа ×updateBoost на updateBoostMinutes, оценка +updateScore (не выше updateMaxScore).
	-- Цена — updatePriceMinutes минут дохода студии (ShopService.incomePerMinute), не меньше updateMinPrice
	updateBoost = 2,
	updateBoostMinutes = 30,
	updateScore = 0.5,
	updateMaxScore = 10,
	updatePriceMinutes = 8,
	updateMinPrice = 500,
	updateCooldown = 1, -- секунд между запросами игрока

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

-- Цена обновления хита по доходу студии в минуту
function HitCartridges.updatePrice(incomePerMinute: number): number
	local income = if incomePerMinute == incomePerMinute and incomePerMinute < math.huge
		then math.max(incomePerMinute, 0)
		else 0
	return math.max(math.floor(income * HitCartridges.updatePriceMinutes), HitCartridges.updateMinPrice)
end

function HitCartridges.slots(studioLevel: number): number
	local slots = HitCartridges.baseSlots
		+ HitCartridges.slotsPerStage * math.max(math.floor(studioLevel) - 1, 0)
	return math.min(slots, HitCartridges.maxSlots)
end

return HitCartridges
