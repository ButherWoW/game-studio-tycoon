--!strict
-- HD-материалы (Config/Materials): для каждого набора с загруженной цветовой картой создаёт MaterialVariant в
-- MaterialService и назначает его материалом по умолчанию (SetBaseMaterialOverride). Наборов с ID 0 нет в игре,
-- поэтому, пока Астра и Dev 1 не сдали текстуры, сервис ничего не меняет. Любая ошибка API — предупреждение,
-- игра идёт дальше со стандартными материалами.

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Materials = require(ReplicatedStorage.Shared.Config.Materials)

local MaterialsService = {}

local function asset(id: number): string
	return if id > 0 then "rbxassetid://" .. id else ""
end

function MaterialsService.start()
	for _, item in Materials.list do
		if not Materials.ready(item) then
			continue
		end
		local ok, err = pcall(function()
			local found = MaterialService:FindFirstChild(item.name)
			local v: MaterialVariant
			if found and found:IsA("MaterialVariant") then
				v = found
			else
				v = Instance.new("MaterialVariant")
				v.Name = item.name
				v.Parent = MaterialService
			end
			v.BaseMaterial = item.base
			v.StudsPerTile = item.studsPerTile
			v.ColorMap = asset(item.colorMap)
			v.NormalMap = asset(item.normalMap)
			v.RoughnessMap = asset(item.roughnessMap)
			v.MetalnessMap = asset(item.metalnessMap)
			MaterialService:SetBaseMaterialOverride(item.base, item.name)
		end)
		if not ok then
			warn("[MaterialsService] набор " .. item.name .. " не применён:", err)
		end
	end
end

return MaterialsService
