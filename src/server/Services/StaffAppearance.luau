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
-- Причёска садится на макушку (владелец 09.11: «слишком высоко» — между головой и Crown зазор):
-- голова NPC меньше той, под которую делали модель (пропорции тела владельца). Считаем, где окажутся
-- детали над головой, и опускаем крепление на зазор (с нахлёстом 0.05)
local HAIR_OVERLAP = 0.05
local function seatOnHead(model: Model, accessory: Accessory)
	local head = model:FindFirstChild("Head")
	local handle = accessory:FindFirstChild("Handle")
	if not head or not head:IsA("BasePart") or not handle or not handle:IsA("BasePart") then
		return
	end
	local own = handle:FindFirstChildOfClass("Attachment")
	local target = own and head:FindFirstChild(own.Name)
	if not own or not target or not target:IsA("Attachment") then
		return
	end
	local handleWorld = target.WorldCFrame * own.CFrame:Inverse()
	local half = head.Size / 2
	local lowest = math.huge
	for _, part in accessory:GetDescendants() do
		if part:IsA("BasePart") and part ~= handle and part.Transparency < 1 then
			local world = handleWorld * handle.CFrame:ToObjectSpace(part.CFrame)
			local p = head.CFrame:ToObjectSpace(world).Position
			-- Только то, что над головой и над её серединой (чёлка и хвост сбоку не в счёт)
			if math.abs(p.X) < half.X and math.abs(p.Z) < half.Z and p.Y > half.Y then
				lowest = math.min(lowest, p.Y - part.Size.Y / 2)
			end
		end
	end
	local gap = lowest - half.Y
	if gap > 0 and gap < head.Size.Y then
		own.CFrame = own.CFrame * CFrame.new(0, gap + HAIR_OVERLAP, 0)
	end
end

function StaffAppearance.addAccessory(
	model: Model,
	humanoid: Humanoid,
	source: Accessory,
	fitToHead: boolean?
): Accessory
	local clone = source:Clone()
	if fitToHead then
		seatOnHead(model, clone)
	end
	-- WeldConstraint запоминает смещение при активации, а надеваем мы до Workspace и двигаем Handle
	-- вручную: детали причёски «стягивались» в одну точку (владелец 09.11: коричневая полоса сквозь
	-- голову — Crown hair_mila на уровне глаз). Меняем на Weld с явным смещением из шаблона
	for _, constraint in clone:GetDescendants() do
		if constraint:IsA("WeldConstraint") then
			local part0, part1 = constraint.Part0, constraint.Part1
			if part0 and part1 and part0:IsDescendantOf(clone) and part1:IsDescendantOf(clone) then
				local weld = Instance.new("Weld")
				weld.Name = constraint.Name
				weld.Part0 = part0
				weld.Part1 = part1
				weld.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
				weld.Parent = constraint.Parent
				constraint:Destroy()
			end
		end
	end
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

-- Защита от «рамки на лице» (владелец 07.11: у NPC плоская коричневая рамка на уровне глаз): деталь
-- причёски или аксессуара головы, которая лежит перед лицом в зоне глаз и шире половины головы,
-- закрывает лицо — делаем её невидимой. Экран-лицо робота (FaceScreen) и аксессуары не головы не трогаем.
-- В лог пишем сотрудника и деталь, чтобы Астра/Dev 1 поправили модель
local function hideFaceCovering(model: Model, accessory: Accessory, employeeId: string)
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local headSize = head.Size
	for _, part in accessory:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "FaceScreen" and part.Transparency < 1 then
			local center = head.CFrame:ToObjectSpace(part.CFrame).Position
			local inFront = center.Z < -headSize.Z / 2 + 0.15
			local eyeBand = math.abs(center.Y) < headSize.Y * 0.4
			local wide = part.Size.X > headSize.X * 0.6 or part.Size.Y > headSize.Y * 0.6
			if inFront and eyeBand and wide then
				part.Transparency = 1
				warn(
					"[StaffAppearance] деталь "
						.. part.Name
						.. " аксессуара "
						.. accessory.Name
						.. " закрывает лицо "
						.. employeeId
						.. " — скрыта"
				)
			end
		end
	end
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
	local hair = if hairSource then StaffAppearance.addAccessory(model, humanoid, hairSource, true) else nil
	if hair and not look.faceOnScreen then
		hideFaceCovering(model, hair, employeeId)
	end
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
