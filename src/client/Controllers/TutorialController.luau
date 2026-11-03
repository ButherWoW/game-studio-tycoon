--!strict
-- Туториал для нового игрока: плашка-подсказка внизу экрана и стрелка к цели.
-- Шаг вычисляется из текущего состояния игры (данные, окна), чужие окна не правим.
-- Сервер включает туториал атрибутом TutorialActive и сам выдаёт награду.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TutorialRemotes = require(ReplicatedStorage.Shared.TutorialRemotes)
local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

-- Порядок шагов; номер шага — индекс в этом списке
local STEP_DESK, STEP_OPEN, STEP_PICK, STEP_START, STEP_WAIT, STEP_RELEASE, STEP_DONE = 1, 2, 3, 4, 5, 6, 7
local STEP_TEXT = {
	"tutorial_desk",
	"tutorial_open",
	"tutorial_pick",
	"tutorial_start",
	"tutorial_wait",
	"tutorial_release",
	"tutorial_done",
}
local ARROW = "⬇"
local ARROW_SIZE = 48
local BOB_HEIGHT = 8
local BOB_SPEED = 4

local TutorialController = {}

local running = false
local released = false
local finalReached = false

-- Кнопка покупки апгрейда на своём участке (её пересоздаёт сервер после каждой покупки)
local function plotButton(upgradeId: string): BasePart?
	local plotName = player:GetAttribute("PlotName")
	local plots = workspace:FindFirstChild("Plots")
	if type(plotName) ~= "string" or not plots then
		return nil
	end
	local plot = plots:FindFirstChild(plotName)
	local buttons = plot and plot:FindFirstChild("Buttons")
	local button = buttons and buttons:FindFirstChild("Buy_" .. upgradeId)
	return if button and button:IsA("BasePart") then button else nil
end

-- Кнопки окон ищем по имени (HUD: CreateGameButton, окно: StartButton), а не по тексту:
-- тексты переводятся на 30 языков
local function findButton(root: Instance?, name: string): GuiButton?
	if not root then
		return nil
	end
	local button = root:FindFirstChild(name, true)
	if button and button:IsA("GuiButton") and button.Visible then
		return button
	end
	return nil
end

local function owns(upgradeId: string): boolean
	local data = ClientState.data
	return data ~= nil and data.upgrades ~= nil and data.upgrades[upgradeId] == true
end

local function currentStep(playerGui: Instance): number
	if finalReached then
		return STEP_DONE
	end
	if released then
		if playerGui:FindFirstChild("ReleaseWindow") then
			return STEP_RELEASE
		end
		finalReached = true
		return STEP_DONE
	end
	if ClientState.developing then
		return STEP_WAIT
	end
	if not owns("desk1") then
		return STEP_DESK
	end
	local window = playerGui:FindFirstChild("CreateGameWindow")
	if not window then
		return STEP_OPEN
	end
	-- Кнопка старта показывает «Начать разработку», только когда жанр и тема выбраны
	local start = findButton(window, "StartButton")
	if start and start:GetAttribute("Ready") == true then
		return STEP_START
	end
	return STEP_PICK
end

local function run()
	if running then
		return
	end
	running = true
	released = false
	finalReached = false
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30 -- поверх окон «Создать игру» (10) и «Релиз» (20)
	gui.Parent = playerGui

	local plate = Instance.new("Frame")
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.new(0.5, 0, 1, -92)
	plate.Size = UDim2.new(0.9, 0, 0, 56)
	plate.BackgroundColor3 = Ui.colors.panel
	plate.BackgroundTransparency = 0.1
	Ui.corner(plate)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 56)
	limit.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.money
	stroke.Parent = plate
	plate.Parent = gui

	local hint = Ui.label(plate, "", 40, Ui.titleFont)
	hint.Position = UDim2.fromOffset(14, 8)
	hint.Size = UDim2.new(1, -150, 0, 40)

	local finished = false
	local function finish(completed: boolean)
		if finished then
			return
		end
		finished = true
		TutorialRemotes.TutorialFinish:FireServer(completed)
	end

	local action = Ui.button(plate, ClientState.t("tutorial_skip"), Ui.colors.locked, function()
		finish(finalReached)
	end)
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -8, 0.5, 0)
	action.Size = UDim2.fromOffset(120, 40)

	-- Стрелка к кнопке интерфейса
	local arrow2d = Ui.label(gui, ARROW, ARROW_SIZE, Ui.titleFont, Ui.colors.money)
	arrow2d.TextXAlignment = Enum.TextXAlignment.Center
	arrow2d.AnchorPoint = Vector2.new(0.5, 1)
	arrow2d.Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE)
	arrow2d.Visible = false

	-- Подсветка и стрелка над кнопкой на участке (локальные, другим игрокам не видны)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Ui.colors.money
	highlight.OutlineColor = Ui.colors.money
	highlight.FillTransparency = 0.5
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(ARROW_SIZE * 2, ARROW_SIZE * 2)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	local arrow3d = Ui.label(billboard, ARROW, ARROW_SIZE * 2, Ui.titleFont, Ui.colors.money)
	arrow3d.Size = UDim2.fromScale(1, 1)
	arrow3d.TextXAlignment = Enum.TextXAlignment.Center

	local function point3d(target: BasePart?)
		highlight.Adornee = target
		highlight.Parent = target
		billboard.Adornee = target
		billboard.Parent = if target then gui else nil
	end

	local function point2d(target: GuiButton?, t: number)
		if not target then
			arrow2d.Visible = false
			return
		end
		local pos, size = target.AbsolutePosition, target.AbsoluteSize
		local bob = math.abs(math.sin(t * BOB_SPEED)) * BOB_HEIGHT
		arrow2d.Position = UDim2.fromOffset(pos.X + size.X / 2, pos.Y - bob)
		arrow2d.Visible = true
	end

	local releasedConn = Remotes.GameReleased.OnClientEvent:Connect(function()
		released = true
	end)
	local finalAt: number? = nil
	local shownStep = 0

	task.spawn(function()
		while not finished and player:GetAttribute("TutorialActive") == true do
			local now = os.clock()
			local step = currentStep(playerGui)
			if step ~= shownStep then
				shownStep = step
				hint.Text = ClientState.t(STEP_TEXT[step], { money = Texts.money(Tutorial.reward) })
				if step == STEP_DONE then
					finalAt = now
					action.Text = ClientState.t("tutorial_ok")
					action.BackgroundColor3 = Ui.colors.good
				end
			end

			local target3d: BasePart? = nil
			local target2d: GuiButton? = nil
			if step == STEP_DESK then
				target3d = plotButton("desk1")
			elseif step == STEP_OPEN then
				target2d = findButton(playerGui:FindFirstChild("Hud"), "CreateGameButton")
			elseif step == STEP_START then
				target2d = findButton(playerGui:FindFirstChild("CreateGameWindow"), "StartButton")
			elseif step == STEP_WAIT and not owns("pc1") then
				target3d = plotButton("pc1")
			end
			point3d(target3d)
			point2d(target2d, now)

			if finalAt and now - finalAt >= Tutorial.finalStepSeconds then
				finish(true)
			end
			task.wait(if target2d then 0 else Tutorial.checkInterval)
		end
		releasedConn:Disconnect()
		highlight:Destroy()
		billboard:Destroy()
		gui:Destroy()
		running = false
	end)
end

function TutorialController.start()
	local function check()
		if player:GetAttribute("TutorialActive") == true then
			run()
		end
	end
	player:GetAttributeChangedSignal("TutorialActive"):Connect(check)
	check()
end

return TutorialController
