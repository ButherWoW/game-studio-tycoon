--!strict
-- Стиль мебели игрока (Config/FurnitureStyles) для тех, кто ставит модели на участок:
-- PlotService (интерьер и мебель этажей), DecorService (декор V9), HitService (полка хитов).
-- Отдельный модуль без PlotService: его требуют сам PlotService и сервисы под ним.
-- Подмена: при стиле не «Классика» сначала ищем шаблон <Имя><suffix> (Desk1_Neon), нет — классику.
-- Клон ставящий переименовывает в классическое имя: по нему находят модели StaffService
-- (сидушки столов), VipService (кресло), BailiffService, PlotService (PcSeat у Desk1).
-- Данные: profile.furniture = { owned = { [styleId]: true }, selected = styleId }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureStyles = require(ReplicatedStorage.Shared.Config.FurnitureStyles)
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

-- Шаблон модели name из папки folder с учётом стиля игрока: <name><suffix>, если он импортирован
-- (не заглушка Generated), иначе классический name. Возвращает шаблон или nil
function StyleModels.find(folder: Instance?, name: string, profile: DataService.Profile?): Instance?
	if not folder then
		return nil
	end
	local suffix = StyleModels.suffix(profile)
	if suffix ~= "" then
		local styled = folder:FindFirstChild(name .. suffix)
		if styled and styled:IsA("Model") and styled:GetAttribute("Generated") ~= true then
			return styled
		end
	end
	return folder:FindFirstChild(name)
end

return StyleModels
