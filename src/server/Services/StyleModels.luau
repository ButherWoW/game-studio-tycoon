--!strict
-- Стиль мебели игрока (Config/FurnitureStyles) для тех, кто ставит модели на участок:
-- PlotService (интерьер и мебель этажей), DecorService (декор V9), HitService (полка хитов).
-- Отдельный модуль без PlotService: его требуют сам PlotService и сервисы под ним.
-- Подмена: при стиле не «Классика» сначала ищем шаблон <Имя><suffix> (Desk1_Neon), нет — классику.
-- Клон ставящий переименовывает в классическое имя: по нему находят модели StaffService
-- (сидушки столов), VipService (кресло), BailiffService, PlotService (PcSeat у Desk1).
-- Данные: profile.furniture = { owned = { [styleId]: true }, selected = styleId }.
-- Отделка студии (Config/InteriorFinishes) — отдельный выбор с тем же поиском шаблона: оболочки
-- этапов (InteriorFinishes.SHELLS) берут суффикс отделки, мебель — суффикс стиля мебели, а при
-- «Классике» — суффикс отделки (мебель в тон отделке, если шаблон <Имя><suffix> импортирован).
-- Данные: profile.interior = { owned = { [finishId]: true }, selected = finishId }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureStyles = require(ReplicatedStorage.Shared.Config.FurnitureStyles)
local InteriorFinishes = require(ReplicatedStorage.Shared.Config.InteriorFinishes)
local DataService = require(script.Parent.DataService)

export type Data = { owned: { [string]: boolean }, selected: string }

local StyleModels = {}

-- Поле профиля в порядке: старые сохранения без него, мусор, удалённые из Config стили.
-- Бесплатные (классика) открыты всегда; выбранный — только из открытых
function StyleModels.data(profile: DataService.Profile): Data
	local raw = (profile :: any).furniture
	local owned: { [string]: boolean } = {}
	if type(raw) == "table" and type(raw.owned) == "table" then
		for id, value in raw.owned do
			-- Неизвестные id тоже храним (как SkinService/PosterService/MascotService): стиль
			-- переименовали или временно убрали из Config — купленное за Robux не пропадает.
			-- Выбор и интерфейс — только из Config
			if value == true and type(id) == "string" and #id <= 64 then
				owned[id] = true
			end
		end
	end
	for _, style in FurnitureStyles.list do
		if FurnitureStyles.isFree(style) then
			owned[style.id] = true
		end
	end
	local selected = if type(raw) == "table" then raw.selected else nil
	if type(selected) ~= "string" or not owned[selected] or not FurnitureStyles.get(selected) then
		selected = FurnitureStyles.default
	end
	local clean = { owned = owned, selected = selected }
	profile.furniture = clean
	return clean
end

-- Суффикс выбранного стиля без пересборки поля ("" — классика). Только чтение: зовётся на каждую модель
function StyleModels.suffix(profile: DataService.Profile?): string
	local raw = if profile then (profile :: any).furniture else nil
	if type(raw) ~= "table" or type(raw.owned) ~= "table" or raw.owned[raw.selected] ~= true then
		return ""
	end
	local style = FurnitureStyles.get(raw.selected)
	return if style then style.suffix else ""
end

-- Поле profile.interior в порядке: старые сохранения без него, мусор. Неизвестные id храним
-- (отделку переименовали или временно убрали из Config — купленное за Robux не пропадает),
-- выбранная — только открытая и есть в Config. Классика открыта всегда
function StyleModels.finishData(profile: DataService.Profile): Data
	local raw = (profile :: any).interior
	local owned: { [string]: boolean } = {}
	if type(raw) == "table" and type(raw.owned) == "table" then
		for id, value in raw.owned do
			if value == true and type(id) == "string" and #id <= 64 then
				owned[id] = true
			end
		end
	end
	for _, finish in InteriorFinishes.list do
		if InteriorFinishes.isFree(finish) then
			owned[finish.id] = true
		end
	end
	local selected = if type(raw) == "table" then raw.selected else nil
	if type(selected) ~= "string" or not owned[selected] or not InteriorFinishes.get(selected) then
		selected = InteriorFinishes.default
	end
	local clean = { owned = owned, selected = selected }
	profile.interior = clean
	return clean
end

-- Выбранная отделка без пересборки поля (nil — классика). Только чтение: зовётся на каждую оболочку
function StyleModels.finish(profile: DataService.Profile?): InteriorFinishes.Finish?
	local raw = if profile then (profile :: any).interior else nil
	if type(raw) ~= "table" or type(raw.owned) ~= "table" or raw.owned[raw.selected] ~= true then
		return nil
	end
	return InteriorFinishes.get(raw.selected)
end

-- Импортированный шаблон <name><suffix> (не заглушка Generated) или nil
local function variant(folder: Instance, name: string, suffix: string): Instance?
	if suffix == "" then
		return nil
	end
	local styled = folder:FindFirstChild(name .. suffix)
	if styled and styled:IsA("Model") and styled:GetAttribute("Generated") ~= true then
		return styled
	end
	return nil
end

-- Шаблон модели name из папки folder с учётом выбора игрока: оболочка этапа — в его отделке
-- (Garage — по шаблону GarageWalls_<suffix>), остальное — в его стиле мебели. Импортированного
-- варианта нет (или это заглушка Generated) — классический name. Возвращает шаблон или nil
function StyleModels.find(folder: Instance?, name: string, profile: DataService.Profile?): Instance?
	if not folder then
		return nil
	end
	local shell = InteriorFinishes.SHELLS[name]
	local styled: Instance?
	if shell then
		local finish = StyleModels.finish(profile)
		styled = if finish then variant(folder, shell, finish.suffix) else nil
	else
		-- Мебель: купленный стиль мебели важнее; при «Классике» — мебель в тон отделке
		-- (Desk1_Sakura от Астры), если такой шаблон импортирован
		styled = variant(folder, name, StyleModels.suffix(profile))
		if not styled and StyleModels.suffix(profile) == "" then
			local finish = StyleModels.finish(profile)
			styled = if finish then variant(folder, name, finish.suffix) else nil
		end
	end
	return styled or folder:FindFirstChild(name)
end

return StyleModels
