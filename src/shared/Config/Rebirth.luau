--!strict
-- Rebirth (шаг 4.4): начать студию заново ради постоянного бонуса к доходу.

local Rebirth = {
	-- Условие для MVP: куплен этот апгрейд из Config/Upgrades («Переезд в офис»)
	requiredUpgrade = "office",
	-- Цена: baseCost × (rebirths + 1). Было $50k — перерождались в начале офиса. $10M копится
	-- ~3 ч дохода 3-го этажа: первый Rebirth ~20–27 ч игры, когда интерьер 3-го этажа почти куплен
	baseCost = 10_000_000,
	-- Сколько денег остаётся после ребёрза
	cashAfter = 100,
	-- Множитель дохода: 1 + incomeBonusPerRebirth × rebirths (так же считает DevelopmentService)
	incomeBonusPerRebirth = 0.5,
}

function Rebirth.cost(rebirths: number): number
	return Rebirth.baseCost * (rebirths + 1)
end

function Rebirth.multiplier(rebirths: number): number
	return 1 + Rebirth.incomeBonusPerRebirth * rebirths
end

return Rebirth
