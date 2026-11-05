--!strict
-- Применение настроек, которые касаются мира (Config/Settings, окно — LanguageController):
-- «Меньше эффектов» — гасим частицы, искры, огонь, дым и следы в Workspace (свои и серверные:
-- пыль приставов, искры VIP и парада маскотов, монетки…); «Скрыть чужих маскотов» — модели
-- workspace.Mascots чужих игроков становятся невидимыми только у нас (LocalTransparencyModifier).
-- Всё локально: сервер и другие игроки ничего не замечают. Громкость — SoundController, титулы — TitleTags.

local Players = game:GetService("Players")

local ClientSettings = require(script.Parent.Parent.ClientSettings)

local MASCOT_FOLDER = "Mascots" -- как FOLDER_NAME в MascotService

local SettingsController = {}

local localPlayer = Players.LocalPlayer

-- Почему эффект выключен: «меньше эффектов» и/или он на скрытом маскоте. original — Enabled до нас
type Reasons = { low: boolean, mascot: boolean, original: boolean }
local effects: { [Instance]: Reasons } = {}
local hiddenParts: { [Instance]: boolean } = {}

local function isEffect(object: Instance): boolean
	return object:IsA("ParticleEmitter")
		or object:IsA("Sparkles")
		or object:IsA("Fire")
		or object:IsA("Smoke")
		or object:IsA("Trail")
		or object:IsA("Beam")
end

local function setReason(object: Instance, reason: "low" | "mascot", on: boolean)
	local entry = effects[object]
	if not entry then
		if not on then
			return
		end
		entry = { low = false, mascot = false, original = (object :: any).Enabled == true }
		effects[object] = entry
		object.Destroying:Connect(function()
			effects[object] = nil
		end)
	end
	local current = entry :: Reasons
	if reason == "low" then
		current.low = on
	else
		current.mascot = on
	end
	if current.low or current.mascot then
		(object :: any).Enabled = false
	else
		(object :: any).Enabled = current.original
		effects[object] = nil
	end
end

-- Модель чужого маскота, в которой лежит object (nil — не маскот или наш)
local function foreignMascot(object: Instance): Model?
	local folder = workspace:FindFirstChild(MASCOT_FOLDER)
	if not folder or not object:IsDescendantOf(folder) then
		return nil
	end
	local node: Instance? = object
	while node and node.Parent ~= folder do
		node = node.Parent
	end
	if not node or not node:IsA("Model") then
		return nil
	end
	local owner = node:GetAttribute("OwnerUserId")
	return if owner ~= localPlayer.UserId then node else nil
end

local function setHidden(object: Instance, hidden: boolean)
	if object:IsA("BasePart") or object:IsA("Decal") or object:IsA("Texture") then
		(object :: any).LocalTransparencyModifier = if hidden then 1 else 0
		hiddenParts[object] = if hidden then true else nil
	elseif object:IsA("BillboardGui") or object:IsA("SurfaceGui") then
		(object :: any).Enabled = not hidden
		hiddenParts[object] = if hidden then true else nil
	elseif isEffect(object) then
		setReason(object, "mascot", hidden)
	end
end

local function applyLowGraphics(on: boolean)
	if on then
		for _, object in workspace:GetDescendants() do
			if isEffect(object) then
				setReason(object, "low", true)
			end
		end
	else
		for object in table.clone(effects) do
			setReason(object, "low", false)
		end
	end
end

local function applyHideMascots(on: boolean)
	if on then
		local folder = workspace:FindFirstChild(MASCOT_FOLDER)
		if folder then
			for _, object in folder:GetDescendants() do
				if foreignMascot(object) then
					setHidden(object, true)
				end
			end
		end
	else
		for object in table.clone(hiddenParts) do
			if object.Parent then
				setHidden(object, false)
			end
		end
		table.clear(hiddenParts)
		for object, entry in table.clone(effects) do
			if entry.mascot then
				setReason(object, "mascot", false)
			end
		end
	end
end

local function onAdded(object: Instance)
	local settings = ClientSettings.values
	if not settings.lowGraphics and not settings.hideMascots then
		return
	end
	if settings.lowGraphics and isEffect(object) then
		setReason(object, "low", true)
	end
	if settings.hideMascots and foreignMascot(object) then
		setHidden(object, true)
	end
end

function SettingsController.start()
	ClientSettings.changed:Connect(function(key: string)
		if key == "lowGraphics" then
			applyLowGraphics(ClientSettings.values.lowGraphics)
		elseif key == "hideMascots" then
			applyHideMascots(ClientSettings.values.hideMascots)
		end
	end)
	workspace.DescendantAdded:Connect(onAdded)
	ClientSettings.load()
end

return SettingsController
