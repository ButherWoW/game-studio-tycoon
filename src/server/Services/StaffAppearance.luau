--!strict
-- Базовая внешность сотрудника (Config/StaffLooks, V13): лицо, причёска, одежда, особые случаи
-- (робот — лицо на экране, призрак — полупрозрачный, Мастер Пиксель — плащ).
-- Зовёт StaffService.buildNpc до рассадки; платный скин (SkinService.decorate) идёт после и
-- перекрывает одежду. Модуль без start(): загрузчик сервера просто его подключит.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StaffLooks = require(ReplicatedStorage.Shared.Config.StaffLooks)

local StaffAppearance = {}

-- Ручное крепление, если AddAccessory не сварил (модель ещё не в Workspace)
local function weldByAttachment(model: Model, accessory: Accessory)
	local handle = accessory:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") or handle:FindFirstChild("AccessoryWeld") then
		return
	end
	local own = handle:FindFirstChildOfClass("Attachment")
	if not own then
		return
	end
	for _, part in model:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local target = part:FindFirstChild(own.Name)
		if target and target:IsA("Attachment") then
			handle.CFrame = target.WorldCFrame * own.CFrame:Inverse()
			local weld = Instance.new("WeldConstraint")
			weld.Name = "AccessoryWeld"
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = handle
			return
		end
	end
end

-- Надеть копию аксессуара на NPC (и для скинов: SkinService)
function StaffAppearance.addAccessory(model: Model, humanoid: Humanoid, source: Accessory): Accessory
	local clone = source:Clone()
	local ok = pcall(function()
		humanoid:AddAccessory(clone)
	end)
	if not ok then
		clone.Parent = model
	end
	weldByAttachment(model, clone)
	return clone
end

local function template(name: string): Accessory?
	local folder = ServerStorage:FindFirstChild(StaffLooks.folder)
	local item = folder and folder:FindFirstChild(name)
	return if item and item:IsA("Accessory") then item else nil
end

local function setFace(target: BasePart, imageId: number)
	local decal = target:FindFirstChild("face")
	if not decal or not decal:IsA("Decal") then
		local fresh = Instance.new("Decal")
		fresh.Name = "face"
		fresh.Face = Enum.NormalId.Front
		fresh.Parent = target
		decal = fresh
	end
	(decal :: Decal).Texture = "rbxassetid://" .. imageId
end

-- Цвет кожи по умолчанию (Внешность → кожа 0)
function StaffAppearance.bodyColor(employeeId: string): Color3?
	local look = StaffLooks.get(employeeId)
	return if look then look.body else nil
end

function StaffAppearance.pantsColor(employeeId: string): Color3?
	local look = StaffLooks.get(employeeId)
	return if look then look.pantsColor else nil
end

-- ownShirt — игрок выбрал свой цвет футболки: рубашку-картинку не надеваем, штаны оставляем
function StaffAppearance.apply(model: Model, employeeId: string, ownShirt: boolean)
	local look = StaffLooks.get(employeeId)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not look or not humanoid then
		return
	end
	if look.shirt > 0 and not ownShirt then
		local shirt = model:FindFirstChildOfClass("Shirt") or Instance.new("Shirt")
		shirt.ShirtTemplate = "rbxassetid://" .. look.shirt
		shirt.Parent = model
	end
	if look.pants > 0 then
		local pants = model:FindFirstChildOfClass("Pants") or Instance.new("Pants")
		pants.PantsTemplate = "rbxassetid://" .. look.pants
		pants.Parent = model
	end
	local hairSource = template("hair_" .. employeeId)
	local hair = if hairSource then StaffAppearance.addAccessory(model, humanoid, hairSource) else nil
	if look.cape then
		local cape = template(look.cape)
		if cape then
			StaffAppearance.addAccessory(model, humanoid, cape)
		end
	end
	local head = model:FindFirstChild("Head")
	if look.face > 0 then
		local screen = if look.faceOnScreen and hair then hair:FindFirstChild("FaceScreen", true) else nil
		if screen and screen:IsA("BasePart") then
			setFace(screen, look.face)
			local headFace = head and head:FindFirstChild("face")
			if headFace and headFace:IsA("Decal") then
				headFace.Transparency = 1
			end
		elseif head and head:IsA("BasePart") then
			setFace(head, look.face)
		end
	end
	if look.transparency then
		-- Только тело: у причёски-капюшона и светящихся глаз своя прозрачность
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.Transparency = look.transparency
			end
		end
	end
end

return StaffAppearance
