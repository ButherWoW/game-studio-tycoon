--!strict
-- Переезд в новое помещение (studioLevel вырос) — праздник: крупная плашка, конфетти, звук.
-- Раньше переезд в офис проходил незаметно (отчёт #42).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Images = require(ReplicatedStorage.Shared.Config.Images)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local SHOW_SECONDS = 4
local CONFETTI = 60
local COLORS = {
	Ui.colors.money,
	Ui.colors.primary,
	Ui.colors.good,
	Color3.fromRGB(255, 110, 180),
	Color3.fromRGB(150, 80, 220),
}

local MoveCelebration = {}
-- Какие этапы уже отпраздновали в этой сессии: после стройки (V29) праздник зовут и по
-- событию «построено» (ConstructionBanner), и по росту studioLevel — второй раз не показываем
local celebrated: { [number]: boolean } = {}

local function confetti(gui: ScreenGui)
	local rng = Random.new()
	-- Конфетти Астры (Images.fx.confetti1/2, V24): картинки вместо цветных прямоугольников
	local textures = {}
	for _, id in { Images.fx.confetti1, Images.fx.confetti2 } do
		if id > 0 then
			table.insert(textures, "rbxassetid://" .. id)
		end
	end
	for _ = 1, CONFETTI do
		local piece: GuiObject
		if #textures > 0 then
			local image = Instance.new("ImageLabel")
			image.BackgroundTransparency = 1
			image.Image = textures[rng:NextInteger(1, #textures)]
			local side = rng:NextInteger(14, 22)
			image.Size = UDim2.fromOffset(side, side)
			piece = image
		else
			local frame = Instance.new("Frame")
			frame.BorderSizePixel = 0
			frame.BackgroundColor3 = COLORS[rng:NextInteger(1, #COLORS)]
			frame.Size = UDim2.fromOffset(rng:NextInteger(6, 12), rng:NextInteger(10, 18))
			piece = frame
		end
		piece.Position = UDim2.new(rng:NextNumber(), 0, -0.05, 0)
		piece.Rotation = rng:NextInteger(0, 360)
		piece.Parent = gui
		local fall = TweenInfo.new(rng:NextNumber(2, 3.5), Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(piece, fall, {
			Position = UDim2.new(piece.Position.X.Scale + rng:NextNumber(-0.1, 0.1), 0, 1.05, 0),
			Rotation = piece.Rotation + rng:NextInteger(180, 720),
		}):Play()
	end
end

local function celebrate(level: number)
	local stage = Stages[level]
	if not stage or celebrated[level] then
		return
	end
	celebrated[level] = true
	local gui = Instance.new("ScreenGui")
	gui.Name = "MoveCelebration"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local banner = Ui.label(
		gui,
		ClientState.t("move_celebrate", { stage = ClientState.localName(stage) }),
		80,
		Ui.titleFontFor(ClientState.lang),
		Ui.colors.money
	)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.35)
	banner.Size = UDim2.new(0.8, 0, 0, 80)
	banner.TextXAlignment = Enum.TextXAlignment.Center
	banner.TextStrokeTransparency = 0.3
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = banner
	TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	-- «Меньше эффектов» (настройки): без конфетти
	if Players.LocalPlayer:GetAttribute("LowGraphics") ~= true then
		confetti(gui)
	end

	-- Хлопушка конфетти (звук играет и при «Меньше эффектов»)
	local popModule = script.Parent:FindFirstChild("SoundController")
	if popModule and popModule:IsA("ModuleScript") then
		pcall(function()
			(require(popModule) :: any).play("confetti_pop")
		end)
	end

	-- Звук переезда, если SoundController подключён (ID присылает Dev 1)
	-- (переезд в офис — это покупка апгрейда office, его звук уже играет SoundController)
	local soundModule = script.Parent:FindFirstChild("SoundController")
	if level > 2 and soundModule and soundModule:IsA("ModuleScript") then
		pcall(function()
			(require(soundModule) :: any).play("move_office")
		end)
	end
	task.delay(SHOW_SECONDS, function()
		gui:Destroy()
	end)
end

-- Праздник переезда на этап level (ConstructionBanner: стройка закончилась, пока игрок входил)
function MoveCelebration.celebrate(level: number)
	celebrate(level)
end

function MoveCelebration.start()
	local lastLevel: number? = nil
	ClientState.changed:Connect(function()
		local data = ClientState.data
		local level = data and tonumber(data.studioLevel)
		if not level then
			return
		end
		-- Первый снимок после входа — не переезд
		if lastLevel and level > lastLevel then
			celebrate(level)
		elseif lastLevel and level < lastLevel then
			-- Rebirth: этапы можно отпраздновать снова
			table.clear(celebrated)
		end
		lastLevel = level
	end)
end

return MoveCelebration
