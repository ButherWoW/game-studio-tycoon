--!strict
-- Стройка следующего этапа (V29, Config/Construction, ConstructionService) на клиенте:
--   • плашка в общем стеке «🏗️ Стройка офиса — 7:42» с кнопкой «⚡ Ускорить» → окошко ускорений
--     за Robux (−5 мин, −30 мин — только если осталось больше 5 мин, «Достроить сейчас»; товара ещё
--     нет — «Скоро»);
--   • тосты «🏢 Офис построен!» (дальше обычный праздник MoveCelebration), «ускорено», «уже готово»;
--   • таблички площадок (деталь Screen с атрибутами BuildStage / BuildStart / BuildEnd): заголовок
--     на языке игрока, полоса прогресса и сколько осталось — на всех участках, не только своём;
--   • руки и ноги строителей (модели с атрибутом Builder, Work = hammer / carry / walk / run):
--     повороты суставов Motor6D локально, только рядом с камерой — сервер кадров не шлёт;
--   • пыль у лесов (ParticleEmitter BuildDust) — только без «Меньше эффектов» (LowGraphics).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Construction = require(ReplicatedStorage.Shared.Config.Construction)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local StudioLayout = require(ReplicatedStorage.Shared.StudioLayout)
local ConstructionRemotes = require(ReplicatedStorage.Shared.ConstructionRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local MoveCelebration = require(script.Parent.MoveCelebration)
local SoundController = require(script.Parent.SoundController)

local WIDTH = 460
local HEIGHT = 44
local TOAST_HEIGHT = 34
local TOAST_SECONDS = 5
local PICKER_WIDTH = 340
local ROW_HEIGHT = 44
local REFRESH = 0.5
local CELEBRATE_DELAY = 0.8
-- Анимация строителей: только ближе стольких studs к камере
local ANIMATE_DISTANCE = 140
local HAMMER_RATE = 9
local WALK_RATE = 9
local RUN_RATE = 14

local ConstructionController = {}

local player = Players.LocalPlayer

local function now(): number
	return workspace:GetServerTimeNow()
end

local function construction(): { stage: number, startedAt: number, endsAt: number }?
	local data = ClientState.data
	local c = data and data.construction
	if type(c) == "table" and type(c.stage) == "number" and type(c.endsAt) == "number" then
		return c
	end
	return nil
end

local function floorName(stage: number): string
	return StudioLayout.floorName(ClientState.lang, math.max(stage - 1, 1))
end

local function stageTitle(stage: number): string
	local info = Stages[stage]
	return if info then ClientState.localName(info) else tostring(stage)
end

-- ===== Плашка, тосты и окно ускорений =====

local picker: ScreenGui? = nil

local function closePicker()
	if picker then
		picker:Destroy()
		picker = nil
	end
end

local function openPicker()
	closePicker()
	local c = construction()
	if not c then
		return
	end
	local left = c.endsAt - now()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuildSpeedPicker"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.IgnoreGuiInset = true
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(PICKER_WIDTH, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Ui.colors.panel
	Ui.corner(frame, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Ui.colors.money
	stroke.Thickness = 2
	stroke.Parent = frame
	local padding = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(padding :: any)[side] = UDim.new(0, 10)
	end
	padding.Parent = frame
	local layout = Ui.list(frame, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	frame.Parent = gui

	local title = Ui.label(frame, ClientState.t("build_picker_title"), 30, Ui.titleFontFor(ClientState.lang))
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 0

	for i, speedup in Construction.speedups do
		if speedup.minLeftSeconds and left <= speedup.minLeftSeconds then
			continue
		end
		local name = if speedup.kind == "skip"
			then ClientState.t("build_skip_now", { icon = speedup.icon })
			else ClientState.t(
				"build_speed_minutes",
				{ icon = speedup.icon, minutes = speedup.minutes or 0 }
			)
		local soon = speedup.productId == 0
		local price = if soon
			then ClientState.t("build_soon")
			else ClientState.t("build_price", { price = speedup.robuxPrice })
		local button = Ui.button(
			frame,
			name .. " · " .. price,
			if soon then Ui.colors.locked else Ui.colors.good,
			function()
				if soon then
					return
				end
				closePicker()
				MarketplaceService:PromptProductPurchase(player, speedup.productId)
			end
		)
		button.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		button.LayoutOrder = i
		if soon then
			button.TextColor3 = Ui.colors.muted
		end
	end
	local close = Ui.button(frame, ClientState.t("build_close"), Ui.colors.locked, closePicker)
	close.Size = UDim2.new(0.5, 0, 0, 36)
	close.LayoutOrder = 100

	gui.Parent = player:WaitForChild("PlayerGui")
	picker = gui
end

local function startBanner()
	local stack = Ui.bannerStack()
	local panel = Instance.new("Frame")
	panel.Name = "ConstructionBanner"
	panel.LayoutOrder = 4
	panel.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	panel.BackgroundColor3 = Ui.colors.panel
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	Ui.corner(panel, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Ui.colors.money
	stroke.Thickness = 2
	stroke.Parent = panel
	panel.Parent = stack
	Ui.bannerMeta(panel, "construction", "🏗️", nil, Ui.colors.money)

	local text = Ui.label(panel, "", HEIGHT - 12, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	text.Position = UDim2.fromOffset(10, 6)
	text.Size = UDim2.new(0.66, -10, 1, -12)
	local speed = Ui.button(panel, "", Ui.colors.good, openPicker)
	speed.AnchorPoint = Vector2.new(1, 0.5)
	speed.Position = UDim2.new(1, -6, 0.5, 0)
	speed.Size = UDim2.new(0.32, -6, 1, -10)

	local function refresh()
		local c = construction()
		panel.Visible = c ~= nil
		if not c then
			closePicker()
			return
		end
		local vars = { time = Construction.clock(c.endsAt - now()), floor = floorName(c.stage) }
		text.Font = Ui.titleFontFor(ClientState.lang)
		text.Text = ClientState.t(if c.stage == 2 then "build_banner_office" else "build_banner_floor", vars)
		speed.Text = ClientState.t("build_speed")
	end
	ClientState.changed:Connect(refresh)
	ClientState.langChanged:Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(REFRESH)
			if panel.Visible then
				refresh()
			end
		end
	end)
	refresh()

	local function toast(message: string, color: Color3)
		local label = Ui.label(stack, message, TOAST_HEIGHT, Ui.titleFontFor(ClientState.lang), color)
		label.Size = UDim2.fromOffset(WIDTH, TOAST_HEIGHT)
		label.LayoutOrder = 4
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.BackgroundTransparency = 0.15
		label.BackgroundColor3 = Ui.colors.panel
		Ui.corner(label, 10)
		task.delay(TOAST_SECONDS, function()
			label:Destroy()
		end)
	end

	ConstructionRemotes.BuildEvent.OnClientEvent:Connect(function(event)
		if type(event) ~= "table" then
			return
		end
		if event.kind == "done" and type(event.stage) == "number" then
			local stage = event.stage
			closePicker()
			toast(
				if stage == 2
					then ClientState.t("build_done_office")
					else ClientState.t("build_done_floor", { floor = floorName(stage) }),
				Ui.colors.good
			)
			SoundController.play("construction_done")
			task.delay(CELEBRATE_DELAY, MoveCelebration.celebrate, stage)
		elseif event.kind == "speed" and event.skip ~= true then
			toast(
				ClientState.t("build_speed_done", { minutes = tonumber(event.minutes) or 0 }),
				Ui.colors.money
			)
		elseif event.kind == "fallback" then
			toast(
				ClientState.t("build_fallback", { amount = Texts.money(tonumber(event.amount) or 0) }),
				Ui.colors.money
			)
		end
	end)
end

-- ===== Таблички, строители и пыль на участках =====

type Rig = {
	model: Model,
	phase: number,
	motors: { [string]: Motor6D }?,
	base: { [string]: CFrame },
}

local screens: { [BasePart]: boolean } = {}
local rigs: { [Model]: Rig } = {}
local dust: { [ParticleEmitter]: boolean } = {}

local function lowGraphics(): boolean
	return player:GetAttribute("LowGraphics") == true
end

local function track(item: Instance)
	if item:IsA("BasePart") and item.Name == "Screen" then
		screens[item] = true
	elseif item:IsA("Model") and item:GetAttribute("Builder") == true then
		rigs[item] = { model = item, phase = math.random() * 10, motors = nil, base = {} }
	elseif item:IsA("ParticleEmitter") and item.Name == "BuildDust" then
		dust[item] = true
		item.Enabled = not lowGraphics()
	end
end

local function updateSign(screen: BasePart)
	local stage = tonumber(screen:GetAttribute("BuildStage"))
	local startedAt = tonumber(screen:GetAttribute("BuildStart"))
	local endsAt = tonumber(screen:GetAttribute("BuildEnd"))
	local gui = screen:FindFirstChild("BuildSign")
	if not stage or not startedAt or not endsAt or not gui then
		return
	end
	local title = gui:FindFirstChild("Title")
	local timeLabel = gui:FindFirstChild("Time")
	local bar = gui:FindFirstChild("Bar")
	local fill = bar and bar:FindFirstChild("Fill")
	local left = endsAt - now()
	local total = math.max(endsAt - startedAt, 1)
	if title and title:IsA("TextLabel") then
		title.Text = "🏗️ " .. ClientState.t("build_sign_title", { stage = stageTitle(stage) })
	end
	if timeLabel and timeLabel:IsA("TextLabel") then
		timeLabel.Text = if left > 0
			then ClientState.t("build_sign_left", { time = Construction.clock(left) })
			else ClientState.t("build_sign_done")
	end
	if fill and fill:IsA("Frame") then
		fill.Size = UDim2.fromScale(math.clamp(1 - left / total, 0, 1), 1)
	end
end

local MOTORS = { "RightShoulder", "LeftShoulder", "RightHip", "LeftHip", "RightElbow" }

local function findMotors(rig: Rig): { [string]: Motor6D }?
	local found: { [string]: Motor6D } = {}
	for _, item in rig.model:GetDescendants() do
		if item:IsA("Motor6D") and table.find(MOTORS, item.Name) then
			found[item.Name] = item
			rig.base[item.Name] = item.C0
		end
	end
	if found.RightShoulder and found.LeftShoulder then
		return found
	end
	return nil
end

local function pose(rig: Rig, t: number)
	local motors = rig.motors
	if not motors then
		motors = findMotors(rig)
		rig.motors = motors
		if not motors then
			return
		end
	end
	local work = rig.model:GetAttribute("Work")
	local phase = t + rig.phase
	local right, left, rightHip, leftHip, elbow = 0, 0, 0, 0, 0
	if work == "hammer" then
		-- Рука вперёд и вниз-вверх, как молотком по доске
		right = math.rad(80) + math.rad(40) * math.sin(phase * HAMMER_RATE)
		elbow = math.rad(25) + math.rad(25) * math.sin(phase * HAMMER_RATE)
		left = math.rad(25)
	elseif work == "carry" then
		-- Правая рука придерживает доску на плече, левая и ноги — шаг
		right = math.rad(160)
		elbow = math.rad(40)
		left = math.rad(20) * math.sin(phase * WALK_RATE)
		rightHip = math.rad(22) * math.sin(phase * WALK_RATE)
		leftHip = -rightHip
	elseif work == "walk" or work == "run" then
		local rate = if work == "run" then RUN_RATE else WALK_RATE
		local swing = if work == "run" then math.rad(45) else math.rad(25)
		right = swing * math.sin(phase * rate)
		left = -right
		rightHip = -right
		leftHip = right
	end
	local function set(name: string, angle: number)
		local motor = (motors :: { [string]: Motor6D })[name]
		local base = rig.base[name]
		if motor and base then
			motor.C0 = base * CFrame.Angles(angle, 0, 0)
		end
	end
	set("RightShoulder", right)
	set("LeftShoulder", left)
	set("RightHip", rightHip)
	set("LeftHip", leftHip)
	set("RightElbow", elbow)
end

local function startFx()
	local function watch(root: Instance)
		for _, item in root:GetDescendants() do
			track(item)
		end
		root.DescendantAdded:Connect(function(item)
			-- Атрибуты и дети приходят вместе с моделью, но имя/атрибут проверяем следующим кадром
			task.defer(track, item)
		end)
	end
	local plots = workspace:WaitForChild("Plots", 30)
	if not plots then
		return
	end
	watch(plots)

	player:GetAttributeChangedSignal("LowGraphics"):Connect(function()
		local on = not lowGraphics()
		for emitter in dust do
			if emitter.Parent then
				emitter.Enabled = on
			else
				dust[emitter] = nil
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(REFRESH)
			for screen in screens do
				if screen:IsDescendantOf(workspace) then
					updateSign(screen)
				else
					screens[screen] = nil
				end
			end
			for emitter in dust do
				if not emitter.Parent then
					dust[emitter] = nil
				end
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		if next(rigs) == nil then
			return
		end
		local camera = workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		local t = os.clock()
		for model, rig in rigs do
			if not model.Parent then
				rigs[model] = nil
			elseif (model:GetPivot().Position - eye).Magnitude <= ANIMATE_DISTANCE then
				pose(rig, t)
			end
		end
	end)
end

function ConstructionController.start()
	task.spawn(startFx)
	startBanner()
end

return ConstructionController
