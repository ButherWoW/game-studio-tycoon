--!strict
-- Сейф в парке (7.16, SafeService) на клиенте:
--   * табличка над сейфом на языке игрока — по атрибутам модели SafeState / SafeCash;
--   * окно-клавиатура (0–9, ⌫, ✓): игрок набирает 6 цифр, сервер проверяет (SafeTry → SafeResult);
--     без кода или когда приз разобран — ввод выключен;
--   * лампочка Indicator: красная — неверно, зелёная — открыт (только у себя), дверца открывается;
--   * баннер «🔐 В сейфе новый приз!» и ответы владельцу на /safe (системное сообщение в чате, видно только ему).
-- Кода на клиенте нет: сюда приходят только результат и сумма приза.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Safe = require(Shared.Config.Safe)
local Texts = require(Shared.Config.Texts)
local Images = require(Shared.Config.Images)
local SafeRemotes = require(Shared.SafeRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local FeatureGate = require(script.Parent.FeatureGate)
local ArtIcon = require(script.Parent.Parent.ArtIcon)
local DepthToast = require(script.Parent.Parent.DepthToast)

local MODEL_NAME = "ParkSafe"
-- Окно 380×460 (было 600): на телефоне 844×390 масштаб ~0.66 вместо ~0.51, клавиши ≥ 36 px (аудит P2-18)
local KEY_SIZE = 56
local KEY_GAP = 8
local GREEN = Color3.fromRGB(60, 230, 110)
local RED = Color3.fromRGB(255, 50, 50)
local OFF_COLOR = Color3.fromRGB(150, 30, 30)
local FLASH_SECONDS = 1.2
local DOOR_OPEN_SECONDS = 6
local DOOR_ANGLE = 100

local player = Players.LocalPlayer

local SafeController = {}
local gui: ScreenGui? = nil
local entered = ""
local claimed = false
local waiting = false
local display: TextLabel? = nil
local result: TextLabel? = nil
local flashToken = 0

local function safeModel(): Model?
	local park = workspace:FindFirstChild("StartPark")
	local m = park and park:FindFirstChild(MODEL_NAME)
	return if m and m:IsA("Model") then m else nil
end

local function stateOf(m: Model?): (string, number)
	if not m then
		return "off", Safe.defaultCash
	end
	local state = m:GetAttribute("SafeState")
	local cash = tonumber(m:GetAttribute("SafeCash")) or Safe.defaultCash
	return if type(state) == "string" then state else "off", cash
end

-- ===== Табличка =====

local function signText(state: string, cash: number): string
	if state == "on" then
		return ClientState.t("safe_sign", { money = Texts.money(cash) })
	elseif state == "empty" then
		return ClientState.t("safe_sign_empty")
	end
	return ClientState.t("safe_sign_off")
end

local function relabelSign()
	local m = safeModel()
	if not m then
		return
	end
	local state, cash = stateOf(m)
	for _, d in m:GetDescendants() do
		if d:IsA("TextLabel") and d.Name == "SignText" then
			d.Text = signText(state, cash)
		end
	end
end

-- ===== Лампочка и дверца (только у себя) =====

local function indicator(): BasePart?
	local m = safeModel()
	local part = m and m:FindFirstChild("Indicator", true)
	return if part and part:IsA("BasePart") then part else nil
end

local function flash(color: Color3)
	local part = indicator()
	if not part then
		return
	end
	flashToken += 1
	local token = flashToken
	part.Color = color
	task.delay(FLASH_SECONDS, function()
		if flashToken == token and part.Parent then
			part.Color = OFF_COLOR
		end
	end)
end

-- Дверца: модель Door (детали + Hinge) или деталь Door; ось — Hinge или левый край дверцы
local function openDoor()
	local m = safeModel()
	local door = m and m:FindFirstChild("Door", true)
	if not m or not door then
		return
	end
	local parts: { BasePart } = {}
	if door:IsA("BasePart") then
		table.insert(parts, door)
	end
	for _, d in door:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if #parts == 0 then
		return
	end
	local hinge = m:FindFirstChild("Hinge", true)
	local axis: CFrame
	if hinge and hinge:IsA("BasePart") then
		axis = hinge.CFrame
	else
		local base = parts[1]
		axis = base.CFrame * CFrame.new(-base.Size.X / 2, 0, 0)
	end
	local originals: { [BasePart]: CFrame } = {}
	local offsets: { [BasePart]: CFrame } = {}
	for _, p in parts do
		originals[p] = p.CFrame
		offsets[p] = axis:ToObjectSpace(p.CFrame)
	end
	local angle = Instance.new("NumberValue")
	angle.Changed:Connect(function(value: number)
		local turned = axis * CFrame.Angles(0, math.rad(-value), 0)
		for p, offset in offsets do
			p.CFrame = turned * offset
		end
	end)
	local info = TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(angle, info, { Value = DOOR_ANGLE }):Play()
	task.delay(DOOR_OPEN_SECONDS, function()
		local closing = TweenService:Create(angle, TweenInfo.new(0.8), { Value = 0 })
		closing.Completed:Connect(function()
			for p, cframe in originals do
				p.CFrame = cframe
			end
			angle:Destroy()
		end)
		closing:Play()
	end)
end

-- ===== Окно-клавиатура =====

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		display = nil
		result = nil
		Ui.windowClosed()
	end
end

local function showResult(text: string, color: Color3)
	local label = result
	if label then
		label.Text = text
		label.TextColor3 = color
	end
end

local function refreshDisplay()
	local label = display
	if not label then
		return
	end
	local cells = {}
	for i = 1, Safe.codeLength do
		table.insert(cells, if i <= #entered then entered:sub(i, i) else "•")
	end
	label.Text = table.concat(cells, " ")
end

-- Почему ввод закрыт (nil — открыт)
local function lockedText(): string?
	local state = stateOf(safeModel())
	if state == "off" then
		return ClientState.t("safe_sign_off")
	elseif state == "empty" then
		return ClientState.t("safe_sign_empty")
	elseif claimed then
		return ClientState.t("safe_used")
	end
	return nil
end

local function press(key: string)
	if waiting or lockedText() then
		return
	end
	if key == "back" then
		entered = entered:sub(1, -2)
	elseif key == "ok" then
		if #entered ~= Safe.codeLength then
			showResult(ClientState.t("safe_hint"), Ui.colors.muted)
			return
		end
		waiting = true
		showResult("…", Ui.colors.muted)
		SafeRemotes.SafeTry:FireServer(entered)
	elseif #entered < Safe.codeLength then
		entered ..= key
	end
	refreshDisplay()
end

local function open()
	close()
	entered = ""
	waiting = false
	local screen = Instance.new("ScreenGui")
	screen.Name = "SafeWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened(close)

	local window = Ui.window(screen, "Window", Vector2.new(380, 460))
	if Images.safe.keypadBg > 0 then
		local bg = Instance.new("ImageLabel")
		bg.Name = "Background"
		bg.BackgroundTransparency = 1
		bg.Size = UDim2.fromScale(1, 1)
		bg.ScaleType = Enum.ScaleType.Crop
		bg.Image = "rbxassetid://" .. Images.safe.keypadBg
		bg.ImageTransparency = 0.15
		bg.ZIndex = 0
		Ui.corner(bg, 12)
		bg.Parent = window
	end
	local title = Ui.label(window, ClientState.t("safe_title"), 34, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 34)
	ArtIcon.prefix(title, "🔐", Images.safe.icon, 34)
	local closeButton = Ui.button(window, ClientState.t("create_close"), Ui.colors.locked, close)
	Ui.headerClose(closeButton)

	local _, cash = stateOf(safeModel())
	local prize = Ui.label(
		window,
		ClientState.t("safe_prize", { money = Texts.money(cash) }),
		26,
		Ui.bodyFont,
		Ui.colors.money
	)
	prize.Position = UDim2.fromOffset(16, 50)
	prize.Size = UDim2.new(1, -32, 0, 26)
	prize.TextXAlignment = Enum.TextXAlignment.Center

	local screenLabel = Ui.label(window, "", 48, Enum.Font.Code, Ui.colors.good)
	screenLabel.Position = UDim2.fromOffset(16, 80)
	screenLabel.Size = UDim2.new(1, -32, 0, 48)
	screenLabel.TextXAlignment = Enum.TextXAlignment.Center
	screenLabel.BackgroundColor3 = Color3.fromRGB(16, 20, 18)
	screenLabel.BackgroundTransparency = 0
	Ui.corner(screenLabel, 10)
	display = screenLabel
	refreshDisplay()

	local grid = Instance.new("Frame")
	grid.Name = "Keys"
	grid.BackgroundTransparency = 1
	grid.AnchorPoint = Vector2.new(0.5, 0)
	grid.Position = UDim2.new(0.5, 0, 0, 136)
	grid.Size = UDim2.fromOffset(KEY_SIZE * 3 + KEY_GAP * 2, KEY_SIZE * 4 + KEY_GAP * 3)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(KEY_SIZE, KEY_SIZE)
	layout.CellPadding = UDim2.fromOffset(KEY_GAP, KEY_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	grid.Parent = window
	local locked = lockedText() ~= nil
	local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "back", "0", "ok" }
	for i, key in keys do
		local label = if key == "back" then "⌫" elseif key == "ok" then "✓" else key
		local color = if locked
			then Ui.colors.locked
			elseif key == "ok" then Ui.colors.good
			elseif key == "back" then Ui.colors.bad
			else Ui.colors.primary
		local button = Ui.button(grid, label, color, function()
			press(key)
		end)
		button.LayoutOrder = i
		button.TextSize = 30
		button.AutoButtonColor = not locked
		button:SetAttribute("SoundKey", "safe_beep")
	end

	local resultLabel = Ui.label(window, "", 26, Enum.Font.GothamMedium, Ui.colors.muted)
	resultLabel.Position = UDim2.new(0, 16, 1, -68)
	resultLabel.Size = UDim2.new(1, -32, 0, 60)
	resultLabel.TextWrapped = true
	resultLabel.TextXAlignment = Enum.TextXAlignment.Center
	result = resultLabel
	local why = lockedText()
	showResult(why or ClientState.t("safe_hint"), if why then Ui.colors.money else Ui.colors.muted)
end

local function onResult(info: any)
	waiting = false
	if type(info) ~= "table" then
		return
	end
	local reason = if type(info.reason) == "string" then info.reason else "error"
	if reason == "ok" then
		claimed = true
		local cash = tonumber(info.cash) or 0
		flash(GREEN)
		openDoor()
		showResult(ClientState.t("safe_ok", { money = Texts.money(cash) }), Ui.colors.good)
		DepthToast.show(
			ClientState.t("safe_ok", { money = Texts.money(cash) }),
			Ui.colors.money,
			Images.safe.icon
		)
		entered = ""
		refreshDisplay()
		return
	end
	flash(RED)
	entered = ""
	refreshDisplay()
	if reason == "wrong" then
		showResult(ClientState.t("safe_wrong"), Ui.colors.bad)
	elseif reason == "used" then
		claimed = true
		showResult(ClientState.t("safe_used"), Ui.colors.money)
	elseif reason == "slow" then
		local minutes = math.max(math.ceil((tonumber(info.wait) or 60) / 60), 1)
		showResult(ClientState.t("safe_slow", { minutes = minutes }), Ui.colors.money)
	elseif reason == "empty" then
		showResult(ClientState.t("safe_sign_empty"), Ui.colors.money)
	elseif reason == "off" then
		showResult(ClientState.t("safe_sign_off"), Ui.colors.money)
	elseif reason == "far" then
		showResult(ClientState.t("safe_far"), Ui.colors.bad)
	else
		showResult(ClientState.t("safe_error"), Ui.colors.bad)
	end
end

-- Ответ владельцу на /safe: системное сообщение в своём чате (другие его не видят)
local function adminMessage(text: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local system = channels and channels:FindFirstChild("RBXSystem")
	if system and system:IsA("TextChannel") then
		local safeText = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
		system:DisplaySystemMessage("[🔐 Safe] " .. safeText)
	else
		DepthToast.show(text, Ui.colors.money)
	end
end

local function onNotice(info: any)
	if type(info) ~= "table" then
		return
	end
	if info.kind == "new" then
		claimed = false
		-- Новичку в парке баннер сейфа не показываем (Config/Unlocks.safe): сейф виден в мире и так
		if not FeatureGate.isOpen("safe") then
			return
		end
		DepthToast.show(ClientState.t("safe_banner"), Ui.colors.money, Images.safe.icon)
	elseif info.kind == "admin" and type(info.text) == "string" then
		adminMessage(info.text)
	end
end

local function watchModel(m: Model)
	m:GetAttributeChangedSignal("SafeState"):Connect(relabelSign)
	m:GetAttributeChangedSignal("SafeCash"):Connect(relabelSign)
	-- Табличку создают после модели: подписываемся и на новые детали
	m.DescendantAdded:Connect(function(d)
		if d:IsA("TextLabel") and d.Name == "SignText" then
			task.defer(relabelSign)
		end
	end)
	relabelSign()
end

function SafeController.start()
	SafeRemotes.SafeOpen.OnClientEvent:Connect(function(info: any)
		claimed = type(info) == "table" and info.claimed == true
		open()
	end)
	SafeRemotes.SafeResult.OnClientEvent:Connect(onResult)
	SafeRemotes.SafeNotice.OnClientEvent:Connect(onNotice)
	ClientState.langChanged:Connect(function()
		relabelSign()
		if gui then
			open()
		end
	end)
	local park = workspace:WaitForChild("StartPark", 30)
	if not park then
		return
	end
	local m = park:FindFirstChild(MODEL_NAME)
	if m and m:IsA("Model") then
		watchModel(m)
	else
		park.ChildAdded:Connect(function(child)
			if child.Name == MODEL_NAME and child:IsA("Model") then
				watchModel(child)
			end
		end)
	end
end

return SafeController
