--!strict
-- 🎥 «Вид студии»: камера над своим участком под углом, узкий FOV — почти изометрия.
-- Включается кнопкой в боковом меню (слот 10) и сама, когда игрок садится за свой ПК
-- (если включён тумблер «авто-вид» рядом с кнопкой). Выход: повторное нажатие, встал из-за ПК,
-- открыл чужую полку (prompt не на своём участке), респаун.
-- В этом режиме передние стены и потолок своего участка локально полупрозрачные.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CameraConfig = require(ReplicatedStorage.Shared.Config.Camera)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local MENU_SLOT = 10
-- Атрибут игрока (только у себя, на сервер не уходит): включён ли авто-вид при посадке за ПК
local AUTO_ATTRIBUTE = "AutoStudioView"

local player = Players.LocalPlayer

local StudioCamera = {}

local active = false
local distance = CameraConfig.distance
local savedFov = 70
local tween: Tween? = nil
local activePlot: BasePart? = nil
-- Детали, которым поставили прозрачность: исходное значение модификатора (слабые ключи)
local faded: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any
local plotConnection: RBXScriptConnection? = nil
local menuButton: TextButton? = nil
local refreshButtons: (() -> ())? = nil
local showHint: (anchor: GuiObject, text: string) -> ()

-- Самая передняя (по +Z) мебель из раскладки: всё, что ближе к входу, — передние стены
local FRONT_Z = (function(): number
	local maxZ = -math.huge
	for _, upgrade in Upgrades do
		local position = upgrade.position
		if position and not upgrade.shellStage and not upgrade.move then
			maxZ = math.max(maxZ, position.Z)
		end
	end
	return (if maxZ == -math.huge then 0 else maxZ) + CameraConfig.frontMargin
end)()

local function ownPlot(): BasePart?
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild(tostring(player:GetAttribute("PlotName")))
	return if plot and plot:IsA("BasePart") then plot else nil
end

function StudioCamera.autoEnabled(): boolean
	local value = player:GetAttribute(AUTO_ATTRIBUTE)
	return if type(value) == "boolean" then value else CameraConfig.autoViewDefault
end

-- ===== Прозрачность передних стен и потолка =====

local function shouldFade(plot: BasePart, part: BasePart): boolean
	if part == plot then
		return false
	end
	-- Сотрудники и прочие персонажи на участке — не стены
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return false
	end
	local localPos = plot.CFrame:PointToObjectSpace(part.Position)
	local height = localPos.Y - plot.Size.Y / 2
	if height > CameraConfig.fadeHeight then
		return true
	end
	return localPos.Z > FRONT_Z and part.Size.Y > CameraConfig.frontMinHeight
end

local function fadePart(plot: BasePart, instance: Instance)
	if not instance:IsA("BasePart") or faded[instance] ~= nil then
		return
	end
	if shouldFade(plot, instance) then
		faded[instance] = instance.LocalTransparencyModifier
		instance.LocalTransparencyModifier = CameraConfig.fadeTransparency
	end
end

local function fadePlot(plot: BasePart)
	for _, descendant in plot:GetDescendants() do
		fadePart(plot, descendant)
	end
	-- Купил апгрейд или переехал, пока смотришь сверху: новые стены тоже прозрачные
	plotConnection = plot.DescendantAdded:Connect(function(descendant)
		task.defer(function()
			if active and activePlot == plot and descendant.Parent then
				fadePart(plot, descendant)
			end
		end)
	end)
end

local function restoreParts()
	if plotConnection then
		plotConnection:Disconnect()
		plotConnection = nil
	end
	for part, original in faded do
		if part.Parent then
			part.LocalTransparencyModifier = original
		end
	end
	table.clear(faded)
end

-- ===== Камера =====

local function viewCFrame(plot: BasePart): CFrame
	local pitch = math.rad(CameraConfig.pitchDegrees)
	local target =
		plot.CFrame:PointToWorldSpace(Vector3.new(0, plot.Size.Y / 2 + CameraConfig.targetHeight, 0))
	-- Камера с переднего края участка (+Z локально), над ним под углом pitch
	local offset = plot.CFrame:VectorToWorldSpace(Vector3.new(0, math.sin(pitch), math.cos(pitch))) * distance
	return CFrame.lookAt(target + offset, target)
end

local function moveCamera(seconds: number)
	local camera = workspace.CurrentCamera
	local plot = activePlot
	if not camera or not plot then
		return
	end
	if tween then
		tween:Cancel()
	end
	local goal = { CFrame = viewCFrame(plot), FieldOfView = CameraConfig.fieldOfView }
	local newTween = TweenService:Create(
		camera,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goal
	)
	tween = newTween
	newTween:Play()
end

function StudioCamera.enter()
	local camera = workspace.CurrentCamera
	local plot = ownPlot()
	if active or not camera or not plot then
		return
	end
	active = true
	activePlot = plot
	distance = CameraConfig.distance
	savedFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	moveCamera(CameraConfig.tweenSeconds)
	fadePlot(plot)
	if refreshButtons then
		refreshButtons()
	end
	local button = menuButton
	if button then
		showHint(button, ClientState.t(if Ui.touch then "camera_view_on_touch" else "camera_view_on"))
	end
end

function StudioCamera.exit()
	if not active then
		return
	end
	active = false
	activePlot = nil
	if tween then
		tween:Cancel()
		tween = nil
	end
	restoreParts()
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = savedFov
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		camera.CameraType = Enum.CameraType.Custom
	end
	if refreshButtons then
		refreshButtons()
	end
end

function StudioCamera.isActive(): boolean
	return active
end

-- Колёсико и щипок: зум в пределах minDistance..maxDistance
local function zoomTo(newDistance: number)
	local clamped = math.clamp(newDistance, CameraConfig.minDistance, CameraConfig.maxDistance)
	if math.abs(clamped - distance) < 0.01 then
		return
	end
	distance = clamped
	moveCamera(CameraConfig.zoomTweenSeconds)
end

-- ===== Кнопки и подсказка =====

function showHint(anchor: GuiObject, text: string)
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = playerGui:FindFirstChild("StudioCameraHint")
	if screen then
		screen:Destroy()
	end
	local newScreen = Instance.new("ScreenGui")
	newScreen.Name = "StudioCameraHint"
	newScreen.ResetOnSpawn = false
	newScreen.DisplayOrder = 2
	local label = Ui.label(newScreen, text, 30, Ui.titleFontFor(ClientState.lang))
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 30)
	label.TextScaled = false
	label.TextSize = 18
	label.BackgroundTransparency = 0.15
	label.BackgroundColor3 = Ui.colors.panel
	label.AnchorPoint = Vector2.new(0, 0.5)
	local pos, size = anchor.AbsolutePosition, anchor.AbsoluteSize
	label.Position = UDim2.fromOffset(pos.X + size.X + 8, pos.Y + size.Y / 2)
	Ui.corner(label, 8)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = label
	newScreen.Parent = playerGui
	task.delay(CameraConfig.hintSeconds, function()
		if newScreen.Parent then
			newScreen:Destroy()
		end
	end)
end

function StudioCamera.start()
	if player:GetAttribute(AUTO_ATTRIBUTE) == nil then
		player:SetAttribute(AUTO_ATTRIBUTE, CameraConfig.autoViewDefault)
	end

	local button = Ui.menuButton(MENU_SLOT, "🎥", function()
		if active then
			StudioCamera.exit()
		elseif ownPlot() then
			StudioCamera.enter()
		end
	end)
	menuButton = button

	-- Маленький тумблер справа от 🎥: авто-вид при посадке за ПК вкл/выкл.
	-- Кнопка 🎥 с UIPadding (8 px по бокам), поэтому 8 + 6 — зазор 6 px от её края
	local toggle = Ui.button(button, "", Ui.colors.good, function()
		local enabled = not StudioCamera.autoEnabled()
		player:SetAttribute(AUTO_ATTRIBUTE, enabled)
		showHint(button, ClientState.t(if enabled then "camera_auto_on" else "camera_auto_off"))
	end)
	toggle.Name = "AutoToggle"
	toggle.AnchorPoint = Vector2.new(0, 0.5)
	toggle.Position = UDim2.new(1, 8 + 6, 0.5, 0)
	toggle.Size = UDim2.fromOffset(28, 28)
	local togglePadding = toggle:FindFirstChildOfClass("UIPadding")
	if togglePadding then
		togglePadding:Destroy()
	end

	refreshButtons = function()
		local auto = StudioCamera.autoEnabled()
		toggle.Text = if auto then "A" else "–"
		toggle.BackgroundColor3 = if auto then Ui.colors.good else Ui.colors.locked
		button.BackgroundColor3 = if active then Ui.colors.primary else Ui.colors.panel
	end
	refreshButtons()
	player:GetAttributeChangedSignal(AUTO_ATTRIBUTE):Connect(function()
		if refreshButtons then
			refreshButtons()
		end
	end)

	-- Сел за свой ПК — вид студии (если включён авто-вид); встал — обычная камера
	local wasSeated = ClientState.atPc()
	ClientState.seatChanged:Connect(function(seated: boolean)
		if seated and not wasSeated and StudioCamera.autoEnabled() then
			-- Общий ноутбук в парке тоже «ПК», но участок там ни при чём
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local seat = humanoid and humanoid.SeatPart
			local plot = ownPlot()
			if seat and plot and seat:IsDescendantOf(plot) then
				StudioCamera.enter()
			end
		elseif not seated and wasSeated then
			StudioCamera.exit()
		end
		wasSeated = seated
	end)

	-- Новый персонаж — камера снова за ним
	player.CharacterAdded:Connect(function()
		wasSeated = false
		StudioCamera.exit()
	end)

	-- Открыл чужую полку (или любой prompt не на своём участке) — выходим, чтобы видеть, что делаешь
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local plot = ownPlot()
		if active and not (plot and prompt:IsDescendantOf(plot)) then
			StudioCamera.exit()
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if active and not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
			zoomTo(distance - input.Position.Z * CameraConfig.zoomStep)
		end
	end)
	local pinchStart = distance
	UserInputService.TouchPinch:Connect(function(_, scale, _, state, processed)
		if not active or processed then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStart = distance
		elseif scale > 0 then
			zoomTo(pinchStart / scale)
		end
	end)

	-- Участок поменялся (переезд на другой участок) — уходим из вида, чтобы не смотреть на чужой
	player:GetAttributeChangedSignal("PlotName"):Connect(function()
		StudioCamera.exit()
	end)
end

return StudioCamera
