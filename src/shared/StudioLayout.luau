--!strict
-- Что из Config/Upgrades видно на текущем этапе студии и кто за какой стол может сесть.
-- Общие правила для сервера (PlotService, StaffService) и окна «Команда».

local Upgrades = require(script.Parent.Config.Upgrades)
local Stages = require(script.Parent.Config.Stages)
local Texts = require(script.Parent.Config.Texts)
local Features = require(script.Parent.Config.Features)

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

-- ===== Этажи офиса =====
-- Этаж N (1..3) — этап N + 1 (гараж — тоже «1-й этаж», но без лифта и других этажей)

StudioLayout.FLOOR_COUNT = #Stages - 1
StudioLayout.FLOOR_HEIGHT = Stages[3].floorY - Stages[2].floorY
-- Лифт: зона 6×6 studs на каждом этаже (центр в координатах участка, слева у входа)
StudioLayout.ELEVATOR = Vector3.new(-20, 0, 24)

-- Сколько этажей открыто при этом studioLevel (гараж — 1)
function StudioLayout.floorsUnlocked(studioLevel: number): number
	return math.clamp(math.floor(studioLevel) - 1, 1, StudioLayout.FLOOR_COUNT)
end

-- Высота пола этажа над полом участка
function StudioLayout.floorY(floor: number): number
	local stage = Stages[floor + 1]
	return if stage then stage.floorY else 0
end

-- Этап, который открывает этаж (для цены и условий на табличке)
function StudioLayout.floorStage(floor: number): Stages.Stage?
	return Stages[floor + 1]
end

-- На каком этаже предмет (кнопка покупки ставится туда же)
function StudioLayout.upgradeFloor(upgrade: Upgrades.Upgrade): number
	return math.max((upgrade.stage or 1) - 1, 1)
end

-- Этаж по высоте над полом участка (персонаж, деталь)
function StudioLayout.floorAt(height: number): number
	return math.clamp(math.floor(height / StudioLayout.FLOOR_HEIGHT) + 1, 1, StudioLayout.FLOOR_COUNT)
end

-- Подписи этажей: сервер пишет по-русски, клиент (PlotLabels) переписывает на язык игрока
function StudioLayout.floorName(lang: string, floor: number): string
	return Texts.format(lang, "floor_name_" .. floor)
end

function StudioLayout.floorSign(lang: string, floor: number): string
	local stage = StudioLayout.floorStage(floor)
	-- Этаж выходит обновлением по средам (Config/Features.stages): «🔒 Скоро: в среду…»
	if stage and not Features.stageReleased(stage.level) then
		local days = Features.daysUntil(Features.stages[stage.level])
		return "🔒 "
			.. StudioLayout.floorName(lang, floor)
			.. "\n"
			.. Texts.format(lang, "upd_soon", { days = days })
	end
	return Texts.format(lang, "floor_sign", {
		floor = StudioLayout.floorName(lang, floor),
		price = Texts.money(if stage then stage.cost else 0),
		games = if stage then stage.gamesRequired else 0,
	})
end

local byId: { [string]: Upgrades.Upgrade } = {}
for _, upgrade in Upgrades do
	byId[upgrade.id] = upgrade
end

function StudioLayout.get(id: string): Upgrades.Upgrade?
	return byId[id]
end

return StudioLayout
