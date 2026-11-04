--!strict
-- Путеводная нить новичка (отчёт #3, P1-1): пока у игрока нет гаража, от персонажа тянется
-- луч к табличке «Гараж продаётся» на его участке, над табличкой — 🏠.
-- Всё локальное (видит только сам игрок); пропадает, когда OwnsGarage = true.

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local CHECK_INTERVAL = 0.5 -- секунд: кнопку сервер пересоздаёт, персонаж возрождается
local BEAM_COLOR = Color3.fromRGB(255, 201, 60)
local MARK_SIZE = 72
local MARK_OFFSET = 7 -- studs над табличкой

local GarageGuide = {}

-- Табличка покупки гаража на своём участке: Plots/<PlotName>/Buttons/Buy_garage
local function garageButton(): BasePart?
	local plotName = player:GetAttribute("PlotName")
	local plots = workspace:FindFirstChild("Plots")
	if type(plotName) ~= "string" or not plots then
		return nil
	end
	local plot = plots:FindFirstChild(plotName)
	local buttons = plot and plot:FindFirstChild("Buttons")
	local button = buttons and buttons:FindFirstChild("Buy_garage")
	return if button and button:IsA("BasePart") then button else nil
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Луч живёт внутри таблички: сервер пересоздаёт кнопки — луч создаём заново
local function makeBeam(from: Attachment, button: BasePart): Beam
	local to = Instance.new("Attachment")
	to.Name = "GarageGuideTo"
	to.Parent = button
	local beam = Instance.new("Beam")
	beam.Name = "GarageGuideBeam"
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Color = ColorSequence.new(BEAM_COLOR)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	beam.Parent = to
	return beam
end

function GarageGuide.start()
	local mark = Instance.new("BillboardGui")
	mark.Name = "GarageGuideMark"
	mark.Size = UDim2.fromOffset(MARK_SIZE, MARK_SIZE)
	mark.StudsOffset = Vector3.new(0, MARK_OFFSET, 0)
	mark.AlwaysOnTop = true
	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.TextScaled = true
	icon.Text = "🏠"
	icon.Parent = mark

	-- Текущие цели: при смене персонажа или таблички пересобираем луч
	local shownRoot: BasePart? = nil
	local shownButton: BasePart? = nil
	local from: Attachment? = nil
	local beam: Beam? = nil

	local function clear()
		local oldBeam = beam
		if oldBeam then
			-- Вместе с точкой крепления на табличке
			local holder = oldBeam.Parent
			oldBeam:Destroy()
			if holder then
				holder:Destroy()
			end
			beam = nil
		end
		if from then
			from:Destroy()
			from = nil
		end
		shownRoot, shownButton = nil, nil
		mark.Adornee = nil
		mark.Parent = nil
	end

	local function update()
		local button = if player:GetAttribute("OwnsGarage") == true then nil else garageButton()
		local root = rootPart()
		if not button or not root then
			clear()
			return
		end
		if root ~= shownRoot or button ~= shownButton or not (beam and beam.Parent) then
			clear()
			local attachment = Instance.new("Attachment")
			attachment.Name = "GarageGuideFrom"
			attachment.Parent = root
			from = attachment
			beam = makeBeam(attachment, button)
			shownRoot, shownButton = root, button
		end
		mark.Adornee = button
		mark.Parent = player:FindFirstChildOfClass("PlayerGui")
	end

	player:GetAttributeChangedSignal("OwnsGarage"):Connect(update)
	task.spawn(function()
		while true do
			update()
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return GarageGuide
