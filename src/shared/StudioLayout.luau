--!strict
-- Что из Config/Upgrades видно на текущем этапе студии и кто за какой стол может сесть.
-- Общие правила для сервера (PlotService, StaffService) и окна «Команда».

local Upgrades = require(script.Parent.Config.Upgrades)

local StudioLayout = {}

-- Предмет стоит на участке при этом studioLevel: с этапа stage и до этапа shellStage включительно
function StudioLayout.isVisible(upgrade: Upgrades.Upgrade, studioLevel: number): boolean
	if (upgrade.stage or 1) > studioLevel then
		return false
	end
	return upgrade.shellStage == nil or upgrade.shellStage >= studioLevel
end

-- Этап, к которому относится стол (гаражный desk2 — 1)
function StudioLayout.deskStage(upgrade: Upgrades.Upgrade): number
	return upgrade.stage or 1
end

-- Сотрудник этапа N садится только за столы этапа N и позже: гаражные сотрудники пересаживаются
-- в офис и выше, а сотрудник этажа за гаражный стол не сядет
function StudioLayout.canSit(employeeStage: number, desk: Upgrades.Upgrade): boolean
	return desk.desk == true and StudioLayout.deskStage(desk) >= employeeStage
end

-- Купленные столы сотрудников, которые стоят на участке сейчас
function StudioLayout.visibleDesks(upgrades: { [string]: boolean }, studioLevel: number): { Upgrades.Upgrade }
	local result = {}
	for _, upgrade in Upgrades do
		if upgrade.desk and upgrades[upgrade.id] and StudioLayout.isVisible(upgrade, studioLevel) then
			table.insert(result, upgrade)
		end
	end
	return result
end

local byId: { [string]: Upgrades.Upgrade } = {}
for _, upgrade in Upgrades do
	byId[upgrade.id] = upgrade
end

function StudioLayout.get(id: string): Upgrades.Upgrade?
	return byId[id]
end

return StudioLayout
