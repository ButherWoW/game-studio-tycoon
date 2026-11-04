--!strict
-- Туториал для нового игрока: плашка-подсказка внизу экрана и стрелка к цели.
-- Шаг вычисляется из текущего состояния игры (данные, окна), чужие окна не правим.
-- Сервер включает туториал атрибутом TutorialActive и сам выдаёт награду.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TutorialRemotes = require(ReplicatedStorage.Shared.TutorialRemotes)
local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local StartPark = require(ReplicatedStorage.Shared.Config.StartPark)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

-- Порядок шагов; номер шага — индекс в этом списке
local STEP_DESK, STEP_OPEN, STEP_PICK, STEP_START, STEP_WAIT, STEP_RELEASE, STEP_DONE = 1, 2, 3, 4, 5, 6, 7
-- «Инди в парке»: шаги до покупки гаража
local STEP_LAPTOP, STEP_FIRST_GAME, STEP_SAVE, STEP_BUY_GARAGE = 8, 9, 10, 11
local STEP_TEXT = {
	"tutorial_desk",
	"tutorial_open",
	"tutorial_pick",
	"tutorial_start",
	"tutorial_wait",
	"tutorial_release",
	"tutorial_done",
	"tutorial_laptop",
	"tutorial_first_game",
	"tutorial_save",
	"tutorial_buy_garage",
}
local ARROW = "⬇"
local ARROW_SIZE = 48
local BOB_HEIGHT = 8
local BOB_SPEED = 4
-- Плашка внизу экрана; если поверх неё окно «Создать игру» / «Релиз» — ставим её под окно
-- или над ним, а если места нет — убираем за окно (отчёт #2, п. 4: закрывала ползунки и кнопки)
local PLATE_HEIGHT = 56
local PLATE_BOTTOM = 92
local PLATE_GAP = 8
local PLATE_ORDER = 30 -- над HUD и обычными окнами
local PLATE_BEHIND_ORDER = 5 -- под окнами «Создать игру» (10) и «Релиз» (20)
local TUTORIAL_WINDOWS = { "CreateGameWindow", "ReleaseWindow" }

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

-- Место игрока за компьютером на своём участке (Seat «PcSeat» в столе или кресле)
local function pcSeat(): BasePart?
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild(tostring(Players.LocalPlayer:GetAttribute("PlotName")))
	local seat = plot and plot:FindFirstChild("PcSeat", true)
	return if seat and seat:IsA("BasePart") then seat else nil
end

-- Ближайший свободный ноутбук в парке (Seat «PcSeat» с атрибутом Public)
local function laptopSeat(): BasePart?
	local park = workspace:FindFirstChild("StartPark")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not park or not root or not root:IsA("BasePart") then
		return nil
	end
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, d in park:GetDescendants() do
		if d:IsA("Seat") and d.Name == "PcSeat" and d:GetAttribute("Public") == true and not d.Occupant then
			local distance = (d.Position - (root :: BasePart).Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = d, distance
			end
		end
	end
	return best
end

local function parkPart(modelName: string, partName: string): BasePart?
	local park = workspace:FindFirstChild("StartPark")
	local model = park and park:FindFirstChild(modelName)
	local p = model and model:FindFirstChild(partName, true)
	return if p and p:IsA("BasePart") then p else nil
end

local function ownsGarage(): boolean
	return player:GetAttribute("OwnsGarage") == true
end

local function owns(upgradeId: string): boolean
	local data = ClientState.data
	return data ~= nil and data.upgrades ~= nil and data.upgrades[upgradeId] == true
end

local function currentStep(playerGui: Instance): number
	if finalReached then
		return STEP_DONE
	end
	-- До гаража: ноутбук в парке → первая игра → накопить → купить гараж
	if not ownsGarage() then
		if playerGui:FindFirstChild("ReleaseWindow") then
			return STEP_RELEASE
		end
		local data = ClientState.data
		if data and (tonumber(data.gamesReleased) or 0) > 0 then
			return if (tonumber(data.cash) or 0) >= StartPark.garagePrice then STEP_BUY_GARAGE else STEP_SAVE
		end
		if ClientState.developing or ClientState.atPc() then
			return STEP_FIRST_GAME
		end
		return STEP_LAPTOP
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
	gui.DisplayOrder = PLATE_ORDER
	gui.Parent = playerGui
	-- Стрелки — отдельно и всегда поверх окон: они показывают на кнопки внутри них
	local arrowGui = Instance.new("ScreenGui")
	arrowGui.Name = "TutorialArrow"
	arrowGui.ResetOnSpawn = false
	arrowGui.DisplayOrder = PLATE_ORDER
	arrowGui.Parent = playerGui

	local plate = Instance.new("Frame")
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.new(0.5, 0, 1, -PLATE_BOTTOM)
	plate.Size = UDim2.new(0.9, 0, 0, PLATE_HEIGHT)
	plate.BackgroundColor3 = Ui.colors.panel
	plate.BackgroundTransparency = 0.1
	Ui.corner(plate)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, PLATE_HEIGHT)
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
	local arrow2d = Ui.label(arrowGui, ARROW, ARROW_SIZE, Ui.titleFont, Ui.colors.money)
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
		billboard.Parent = if target then arrowGui else nil
	end

	-- Плашка не должна закрывать окно обучения: под окном, над ним или за ним
	local function placePlate()
		local window: GuiObject? = nil
		for _, name in TUTORIAL_WINDOWS do
			local screen = playerGui:FindFirstChild(name)
			local frame = screen and screen:FindFirstChild("Window")
			if frame and frame:IsA("GuiObject") and frame.Visible then
				window = frame
			end
		end
		local screenHeight = gui.AbsoluteSize.Y
		if not window or screenHeight <= 0 then
			plate.AnchorPoint = Vector2.new(0.5, 1)
			plate.Position = UDim2.new(0.5, 0, 1, -PLATE_BOTTOM)
			gui.DisplayOrder = PLATE_ORDER
			return
		end
		local top = window.AbsolutePosition.Y
		local bottom = top + window.AbsoluteSize.Y
		if screenHeight - bottom >= PLATE_HEIGHT + PLATE_GAP * 2 then
			plate.AnchorPoint = Vector2.new(0.5, 0)
			plate.Position = UDim2.new(0.5, 0, 0, bottom + PLATE_GAP)
			gui.DisplayOrder = PLATE_ORDER
		elseif top >= PLATE_HEIGHT + PLATE_GAP * 2 then
			plate.AnchorPoint = Vector2.new(0.5, 1)
			plate.Position = UDim2.new(0.5, 0, 0, top - PLATE_GAP)
			gui.DisplayOrder = PLATE_ORDER
		else
			-- Места нет (низкий экран): плашка уходит за окно, стрелка остаётся сверху
			plate.AnchorPoint = Vector2.new(0.5, 1)
			plate.Position = UDim2.new(0.5, 0, 1, -PLATE_BOTTOM)
			gui.DisplayOrder = PLATE_BEHIND_ORDER
		end
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
		-- Игры на ноутбуке не завершают туториал: дальше ещё гараж и первая игра в нём
		if ownsGarage() then
			released = true
		end
	end)
	local finalAt: number? = nil
	local shownStep = 0
	-- Сменили язык: подсказка перерисуется на следующем шаге цикла, кнопка — сразу
	local langConn = ClientState.langChanged:Connect(function()
		shownStep = 0
		hint.Font = Ui.titleFontFor(ClientState.lang)
		action.Text = ClientState.t(if finalAt then "tutorial_ok" else "tutorial_skip")
	end)
	hint.Font = Ui.titleFontFor(ClientState.lang)

	task.spawn(function()
		while not finished and player:GetAttribute("TutorialActive") == true do
			local now = os.clock()
			local step = currentStep(playerGui)
			if step ~= shownStep then
				shownStep = step
				hint.Text = ClientState.t(STEP_TEXT[step], {
					money = Texts.money(Tutorial.reward),
					price = Texts.money(StartPark.garagePrice),
				})
				if step == STEP_DONE then
					-- После смены языка шаг показывается заново: таймер финала не сбрасываем
					finalAt = finalAt or now
					action.Text = ClientState.t("tutorial_ok")
					action.BackgroundColor3 = Ui.colors.good
				end
			end

			local target3d: BasePart? = nil
			local target2d: GuiButton? = nil
			if step == STEP_LAPTOP then
				target3d = laptopSeat()
			elseif step == STEP_FIRST_GAME then
				local window = playerGui:FindFirstChild("CreateGameWindow")
				local start = findButton(window, "StartButton")
				if start and start:GetAttribute("Ready") == true then
					target2d = start
				elseif not window and ClientState.atPc() and not ClientState.developing then
					target2d = findButton(playerGui:FindFirstChild("Hud"), "CreateGameButton")
				elseif not ClientState.atPc() then
					-- Встал посреди разработки — вернуть за ноутбук
					target3d = laptopSeat()
				end
			elseif step == STEP_SAVE then
				target3d = parkPart("JobBoard", "Board")
			elseif step == STEP_BUY_GARAGE then
				target3d = plotButton("garage")
			elseif step == STEP_DESK then
				target3d = plotButton("desk1")
			elseif step == STEP_OPEN then
				-- Сначала сесть за стол: окно «Создать игру» откроется само
				target3d = pcSeat()
				if ClientState.atPc() then
					target2d = findButton(playerGui:FindFirstChild("Hud"), "CreateGameButton")
				end
			elseif step == STEP_START then
				target2d = findButton(playerGui:FindFirstChild("CreateGameWindow"), "StartButton")
			elseif step == STEP_WAIT and not owns("pc1") then
				target3d = plotButton("pc1")
			end
			-- Поверх других окон (награда за вход, офлайн-доход и т.п.) подсказка не лезет:
			-- прячем её, пока такое окно открыто (окна «Создать игру» и «Релиз» — часть обучения)
			local covered = false
			for _, child in playerGui:GetChildren() do
				if
					child:IsA("ScreenGui")
					and child.Enabled
					and child.Name:sub(-6) == "Window"
					and child.Name ~= "CreateGameWindow"
					and child.Name ~= "ReleaseWindow"
				then
					-- Окно может жить постоянно и прятать содержимое через Visible — считаем только видимое
					for _, frame in child:GetChildren() do
						if frame:IsA("GuiObject") and frame.Visible then
							covered = true
							break
						end
					end
				end
			end
			plate.Visible = not covered
			placePlate()
			if covered then
				target2d, target3d = nil, nil
			end
			point3d(target3d)
			point2d(target2d, now)

			if finalAt and now - finalAt >= Tutorial.finalStepSeconds then
				finish(true)
			end
			task.wait(if target2d then 0 else Tutorial.checkInterval)
		end
		releasedConn:Disconnect()
		langConn:Disconnect()
		highlight:Destroy()
		billboard:Destroy()
		gui:Destroy()
		arrowGui:Destroy()
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
