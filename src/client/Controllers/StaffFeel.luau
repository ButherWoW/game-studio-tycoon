--!strict
-- Ощущение команды (StaffRemotes.StaffFeel): найм, прокачка навыка и увольнение заметны.
-- Тост «было → стало» (скорость, оценка по направлениям, возврат, настроение) и эффекты над NPC
-- у владельца: новичку — конфетти и «Привет, команда!», навыку — вспышка и «+1 🎨» вверх.
-- Уход уволенного с коробкой — на сервере (StaffLife), его видят все. Эффекты живут 1–3 с.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local StaffRemotes = require(ReplicatedStorage.Shared.StaffRemotes)
local Employees = require(ReplicatedStorage.Shared.Config.Employees)
local Skills = require(ReplicatedStorage.Shared.Config.Skills)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local ArtIcon = require(script.Parent.Parent.ArtIcon)
local ClientState = require(script.Parent.Parent.ClientState)
local StaffPower = require(script.Parent.Parent.StaffPower)
local Ui = require(script.Parent.Parent.Ui)
local SoundController = require(script.Parent.SoundController)

local TOAST_SECONDS = 4
local TOAST_WIDTH = 460
local LINE_HEIGHT = 24
local CONFETTI_COUNT = 45
local CONFETTI_LIFE = 2.5
local HELLO_SECONDS = 3
local FLOAT_SECONDS = 1.6
local GLOW_SECONDS = 1.1
local EPSILON = 0.004
local HEART_COOLDOWN = 30

local player = Players.LocalPlayer

local StaffFeel = {}

type Toast = { title: string, lines: { string }, color: Color3 }
local queue: { Toast } = {}
local showing = false

local function showNext()
	local toast = table.remove(queue, 1)
	if not toast then
		showing = false
		return
	end
	showing = true
	local screen = Instance.new("ScreenGui")
	screen.Name = "StaffFeelToast"
	-- Над окном «Команда» (10): найм и прокачка идут из него
	screen.DisplayOrder = 12
	screen.ResetOnSpawn = false
	screen.Parent = player:WaitForChild("PlayerGui")

	local height = 44 + LINE_HEIGHT * #toast.lines + 12
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 12)
	frame.Size = UDim2.new(0.92, 0, 0, height)
	frame.BackgroundColor3 = Ui.colors.panel
	frame.BackgroundTransparency = 0.08
	Ui.corner(frame, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = toast.color
	stroke.Thickness = 2
	stroke.Parent = frame
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(TOAST_WIDTH, height)
	limit.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame
	Ui.list(frame, 0)
	local title = Ui.label(frame, toast.title, 36, Ui.titleFontFor(ClientState.lang), toast.color)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 0
	for i, line in toast.lines do
		local label = Ui.label(frame, line, LINE_HEIGHT)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.LayoutOrder = i
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = frame
	frame.Parent = screen
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(TOAST_SECONDS, function()
		screen:Destroy()
		showNext()
	end)
end

local function toast(title: string, lines: { string }, color: Color3)
	table.insert(queue, { title = title, lines = lines, color = color })
	if not showing then
		showNext()
	end
end

local function employeeName(employeeId: string): string
	local employee = Employees.get(employeeId)
	if not employee then
		return employeeId
	end
	return ClientState.localText("employee_" .. employee.id, employee.name, employee.nameEn)
end

-- Строки «было → стало»: скорость, направления (только изменившиеся), прибавка к оценке
local function changeLines(before: StaffPower.Power, after: StaffPower.Power, onlyKey: string?): { string }
	local lines = {
		ClientState.t(
			"staff_feel_speed",
			{ before = StaffPower.percent(before.speed), after = StaffPower.percent(after.speed) }
		),
	}
	for _, key in Skills.keys do
		local delta = (after.quality[key] or 0) - (before.quality[key] or 0)
		if (onlyKey == nil or onlyKey == key) and math.abs(delta) > EPSILON then
			table.insert(
				lines,
				ClientState.t("staff_feel_area", {
					icon = StaffPower.icons[key],
					skill = ClientState.t("focus_" .. key),
					delta = StaffPower.score(delta),
				})
			)
		end
	end
	if math.abs(after.review - before.review) > EPSILON then
		table.insert(
			lines,
			ClientState.t(
				"staff_feel_review",
				{ before = StaffPower.score(before.review), after = StaffPower.score(after.review) }
			)
		)
	end
	return lines
end

-- ===== Эффекты над NPC (только у владельца, короткие) =====

local function npcPart(npc: Instance, name: string): BasePart?
	local part = npc:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

-- «Меньше эффектов» (настройки, атрибут ставит ClientSettings): без конфетти, вспышек и полёта надписей
local function lowGraphics(): boolean
	return player:GetAttribute("LowGraphics") == true
end

local function confetti(npc: Model)
	if lowGraphics() then
		return
	end
	local root = npcPart(npc, "HumanoidRootPart") or npcPart(npc, "Head")
	if not root then
		return
	end
	-- Конфетти Астры (Images.fx, V24); нет текстур — цветные квадратики, как раньше
	if ArtIcon.burst({ Images.fx.confetti1, Images.fx.confetti2 }, CONFETTI_COUNT, root) then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 2, 0)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(1, 1.6)
	emitter.Speed = NumberRange.new(10, 16)
	emitter.SpreadAngle = Vector2.new(55, 55)
	emitter.Acceleration = Vector3.new(0, -24, 0)
	emitter.Drag = 1.5
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.Size = NumberSequence.new(0.35, 0.15)
	emitter.LightEmission = 0.4
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 95)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 201, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(61, 220, 132)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(61, 123, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 110, 190)),
	})
	emitter.Parent = attachment
	attachment.Parent = root
	emitter:Emit(CONFETTI_COUNT)
	task.delay(CONFETTI_LIFE, function()
		attachment:Destroy()
	end)
end

local function billboard(
	npc: Model,
	text: string,
	color: Color3,
	background: boolean
): (BillboardGui?, TextLabel?)
	local head = npcPart(npc, "Head")
	if not head then
		return nil, nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 44)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.Adornee = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.new(1, 1, 1)
	label.BackgroundTransparency = if background then 0.05 else 1
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Ui.titleFontFor(ClientState.lang)
	label.Text = text
	if background then
		Ui.corner(label, 14)
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.PaddingTop = UDim.new(0, 4)
		padding.PaddingBottom = UDim.new(0, 4)
		padding.Parent = label
	else
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = label
	end
	label.Parent = gui
	gui.Parent = head
	return gui, label
end

-- Облачко со словами над головой
local function say(npc: Model, text: string, seconds: number)
	local gui = billboard(npc, text, Color3.fromRGB(30, 30, 46), true)
	if gui then
		task.delay(seconds, function()
			gui:Destroy()
		end)
	end
end

-- Надпись взлетает и тает («+1 🎨»)
local function floatUp(npc: Model, text: string, color: Color3)
	local gui, label = billboard(npc, text, color, false)
	if not gui or not label then
		return
	end
	if lowGraphics() then
		-- Без анимации: надпись просто висит и исчезает
		task.delay(FLOAT_SECONDS, function()
			gui:Destroy()
		end)
		return
	end
	local info = TweenInfo.new(FLOAT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = Vector3.new(0, 6.5, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	task.delay(FLOAT_SECONDS, function()
		gui:Destroy()
	end)
end

-- Вспышка контура
local function glow(npc: Model, color: Color3)
	if lowGraphics() then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.35
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = npc
	highlight.Parent = npc
	TweenService
		:Create(highlight, TweenInfo.new(GLOW_SECONDS), { FillTransparency = 1, OutlineTransparency = 1 })
		:Play()
	task.delay(GLOW_SECONDS, function()
		highlight:Destroy()
	end)
end

local function onFeel(event: any)
	if type(event) ~= "table" or type(event.employeeId) ~= "string" then
		return
	end
	local kind = event.kind
	local npc = if typeof(event.npc) == "Instance" and (event.npc :: Instance):IsA("Model")
		then event.npc :: Model
		else nil
	local name = employeeName(event.employeeId)
	if kind == "arrive" then
		if npc then
			confetti(npc)
			glow(npc, Ui.colors.good)
			say(npc, ClientState.t("staff_hello"), HELLO_SECONDS)
		end
		return
	end
	local before = StaffPower.parse(event.before)
	local after = StaffPower.parse(event.after)
	local mood = if type(event.mood) == "number" then event.mood else 0
	if kind == "hire" then
		local lines = changeLines(before, after)
		if mood ~= 0 then
			table.insert(lines, ClientState.t("staff_feel_mood_newbie", { n = "+" .. mood }))
		end
		toast(ClientState.t("staff_feel_hire", { name = name }), lines, Ui.colors.good)
		SoundController.play("buy")
	elseif kind == "skill" and Skills.isKey(event.key) then
		local key = event.key :: string
		local from = if type(event.from) == "number" then event.from else 0
		local to = if type(event.to) == "number" then event.to else from + 1
		toast(
			ClientState.t("staff_feel_skill", {
				name = name,
				skill = StaffPower.icons[key] .. " " .. ClientState.t("focus_" .. key),
				from = from,
				to = to,
			}),
			changeLines(before, after, key),
			Ui.colors.money
		)
		SoundController.play("level_up")
		if npc then
			glow(npc, Ui.colors.money)
			floatUp(npc, "+1 " .. StaffPower.icons[key], Ui.colors.money)
			-- Искры повышения (Images.fx.sparkle, V24); 0 — только вспышка контура
			ArtIcon.burst({ Images.fx.sparkle }, 16, npcPart(npc, "HumanoidRootPart") or npcPart(npc, "Head"))
		end
	elseif kind == "fire" then
		local lines = changeLines(before, after)
		local refund = if type(event.refund) == "number" then event.refund else 0
		if refund > 0 then
			table.insert(lines, ClientState.t("staff_feel_refund", { price = Texts.money(refund) }))
		end
		if mood ~= 0 then
			table.insert(lines, ClientState.t("staff_feel_mood_fired", { n = "−" .. math.abs(mood) }))
		end
		toast(ClientState.t("staff_feel_fire", { name = name }), lines, Ui.colors.bad)
		SoundController.play("click")
	end
end

function StaffFeel.start()
	StaffRemotes.StaffFeel.OnClientEvent:Connect(function(event: any)
		local ok, err = pcall(onFeel, event)
		if not ok then
			warn("[StaffFeel] failed:", err)
		end
	end)
	-- Настроение команды выросло (атрибут TeamMood, MoodService) — сердечки над игроком
	-- (Images.fx.heart, V24), не чаще раза в HEART_COOLDOWN с. 0 — эффекта нет, как раньше
	local lastMood = tonumber(player:GetAttribute("TeamMood"))
	local heartAt = -math.huge
	player:GetAttributeChangedSignal("TeamMood"):Connect(function()
		local mood = tonumber(player:GetAttribute("TeamMood"))
		if mood and lastMood and mood > lastMood and os.clock() - heartAt >= HEART_COOLDOWN then
			if ArtIcon.burst({ Images.fx.heart }, 8) then
				heartAt = os.clock()
			end
		end
		lastMood = mood
	end)
end

return StaffFeel
