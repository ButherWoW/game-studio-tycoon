--!strict
-- События компании на клиенте (CompanyEventService): карточка события и плашки активных эффектов.
-- Карточка: эмодзи (или иконка Images.events), заголовок, текст, эффект в цифрах, 1–2 кнопки.
-- Хорошее — зелёное/золотое, плохое — красное, катастрофа — тёмно-красная с тряской.
-- Не поверх других окон, не в туториале, не во время событий разработки и не сразу после
-- предложения доната: ждёт в очереди.
-- Решает и применяет всё сервер; на выбор время идёт с момента показа (CompanyEventSeen).
-- Плашки под HUD (Ui.bannerStack): «📉 −20% 12:30», «🛡 25:00», «⭐ +0.5»…

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local CompanyEvents = require(Shared.Config.CompanyEvents)
local CompanyEventRemotes = require(Shared.CompanyEventRemotes)
local Images = require(Shared.Config.Images)
local Texts = require(Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local CompanyEventState = require(script.Parent.Parent.CompanyEventState)
local OfferClient = require(script.Parent.Parent.OfferClient)
local PopupQueue = require(script.Parent.Parent.PopupQueue)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

-- Не сразу после окна предложения доната и не давать ему всплыть сразу после карточки
local AFTER_OFFER_SECONDS = 20
local HOLD_OFFERS_SECONDS = 90
local CARD_SIZE = Vector2.new(560, 440)
local BADGE_HEIGHT = 26

local COLORS: { [string]: Color3 } = {
	good = Color3.fromRGB(61, 220, 132),
	choice = Color3.fromRGB(255, 201, 60),
	bad = Color3.fromRGB(255, 90, 95),
	catastrophic = Color3.fromRGB(150, 20, 30),
}
local BACKGROUNDS: { [string]: Color3 } = {
	good = Color3.fromRGB(24, 46, 38),
	choice = Color3.fromRGB(46, 40, 22),
	bad = Color3.fromRGB(52, 24, 30),
	catastrophic = Color3.fromRGB(40, 6, 10),
}

local CompanyEventController = {}
local queue: { any } = {}
local gui: ScreenGui? = nil
local current: any = nil -- показанная карточка (info с сервера)

local function busy(): boolean
	-- Окна, туториал, предложение, событие разработки на экране (PopupQueue.busy);
	-- окна входа в очереди (награда, «пока тебя не было») — сначала они
	if PopupQueue.busy() or PopupQueue.pending() then
		return true
	end
	return OfferClient.secondsSincePopup() < AFTER_OFFER_SECONDS
end

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		current = nil
		Ui.windowClosed()
	end
end

local function kindOf(info: any): string
	local kind = info.kind
	return if COLORS[kind] then kind else "bad"
end

local function text(
	parent: Instance,
	value: string,
	height: number,
	order: number,
	color: Color3?,
	font: Enum.Font?
)
	local label = Ui.label(parent, value, height, font or Enum.Font.GothamMedium, color)
	label.TextScaled = false
	label.TextSize = height
	label.TextWrapped = true
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.LayoutOrder = order
	return label
end

local function shake(frame: Frame)
	task.spawn(function()
		local base = frame.Position
		for i = 1, 14 do
			if not frame.Parent then
				return
			end
			local power = (14 - i) * 1.2
			frame.Position = base
				+ UDim2.fromOffset(math.random(-10, 10) * power / 10, math.random(-6, 6) * power / 10)
			task.wait(0.04)
		end
		frame.Position = base
	end)
end

-- Нарисовать карточку. lines — эффект в цифрах; options — кнопки выбора (иначе ОК/починка)
local function render(info: any, lines: { any }?, result: boolean)
	local old = gui
	if old then
		local window = old:FindFirstChild("Window")
		if window then
			window:Destroy()
		end
	else
		local screen = Instance.new("ScreenGui")
		screen.Name = "CompanyEventCard"
		screen.ResetOnSpawn = false
		screen.DisplayOrder = 21
		screen.Parent = player:WaitForChild("PlayerGui")
		gui = screen
		Ui.windowOpened()
	end
	local kind = kindOf(info)
	local id: string = tostring(info.id)
	local window = Ui.window(gui :: ScreenGui, "Window", CARD_SIZE)
	window.BackgroundColor3 = BACKGROUNDS[kind]
	local stroke = window:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = COLORS[kind]
		stroke.Thickness = if kind == "catastrophic" then 4 else 3
	end
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(18, 12)
	body.Size = UDim2.new(1, -36, 1, -24)
	local layout = Ui.list(body, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	body.Parent = window

	local optionVars = type(info.options) == "table" and info.options or nil
	-- Переменные текста (имя сотрудника) — с сервера
	local textVars = CompanyEventState.vars(if type(info.textVars) == "table" then info.textVars else nil)
	text(body, ClientState.t("cev_kind_" .. kind), 18, 1, COLORS[kind], Ui.titleFontFor(ClientState.lang))
	local emoji = Ui.label(body, tostring(info.emoji or "❗"), 54, Ui.titleFont)
	emoji.TextXAlignment = Enum.TextXAlignment.Center
	emoji.LayoutOrder = 2
	-- Иконка события (Config/Images.events, V19); 0 — остаётся эмодзи
	if Ui.artImage(emoji, Images.events[id]) then
		emoji.Text = ""
	end
	text(body, ClientState.t("cev_" .. id .. "_title"), 30, 3, nil, Ui.titleFontFor(ClientState.lang))
	text(body, ClientState.t("cev_" .. id .. "_text", textVars), 18, 4, Ui.colors.muted)

	local order = 10
	for _, line in lines or {} do
		if type(line) == "table" and type(line.key) == "string" then
			order += 1
			text(body, CompanyEventState.lineText(line), 20, order, Ui.colors.text, Ui.bodyFont)
		end
	end
	if info.insured then
		text(body, ClientState.t("cev_insured"), 16, 40, Ui.colors.good)
	end
	if result and info.auto then
		text(body, ClientState.t("cev_auto"), 15, 41, Ui.colors.muted)
	end

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 52)
	buttons.LayoutOrder = 60
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.Padding = UDim.new(0, 10)
	row.Parent = buttons
	buttons.Parent = body

	if optionVars and not result then
		local token = info.token
		local function choose(choice: string)
			CompanyEventRemotes.CompanyEventChoice:FireServer(token, choice)
			-- Ждём результат с сервера: кнопки прячем
			buttons.Visible = false
		end
		for _, choice in { "a", "b" } do
			local vars = CompanyEventState.vars(optionVars[choice])
			local b = Ui.button(
				buttons,
				ClientState.t("cev_" .. id .. "_" .. choice, vars),
				if choice == "a" then Ui.colors.primary else Ui.colors.locked,
				function()
					choose(choice)
				end
			)
			b.Size = UDim2.new(0.5, -5, 1, 0)
		end
		-- Полоска времени на ответ
		local seconds = tonumber(info.answerSeconds) or CompanyEvents.answerSeconds
		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = COLORS[kind]
		bar.BorderSizePixel = 0
		bar.Size = UDim2.new(1, 0, 0, 6)
		bar.LayoutOrder = 70
		Ui.corner(bar, 3)
		bar.Parent = body
		TweenService
			:Create(bar, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 6) })
			:Play()
	else
		local repair = tonumber(info.repair)
		if repair and repair > 0 and not result then
			local data = ClientState.data
			local canPay = data ~= nil and (tonumber(data.cash) or 0) >= repair
			local b = Ui.button(
				buttons,
				ClientState.t("cev_repair", { money = Texts.money(repair) }),
				if canPay then Ui.colors.money else Ui.colors.locked,
				function()
					if canPay then
						CompanyEventState.repair()
						close()
					end
				end
			)
			b.Size = UDim2.new(0.5, -5, 1, 0)
		end
		local ok = Ui.button(buttons, ClientState.t("cev_ok"), Ui.colors.good, close)
		ok.Size = UDim2.new(if repair and repair > 0 and not result then 0.4 else 0.5, -5, 1, 0)
	end
	if kind == "catastrophic" and not result then
		shake(window)
	end
end

local function show(info: any)
	current = info
	OfferClient.holdPopups(HOLD_OFFERS_SECONDS)
	render(info, if type(info.lines) == "table" then info.lines else nil, false)
	if type(info.options) == "table" then
		CompanyEventRemotes.CompanyEventSeen:FireServer(info.token)
	end
end

local function onEvent(info: any)
	if type(info) ~= "table" or type(info.id) ~= "string" then
		return
	end
	table.insert(queue, info)
end

local function onResult(result: any)
	if type(result) ~= "table" or type(result.id) ~= "string" then
		return
	end
	-- Выбор ещё в очереди (не показан) — убрать его, результат покажем вместо него
	for i = #queue, 1, -1 do
		if queue[i].token == result.token then
			table.remove(queue, i)
		end
	end
	local lines = if type(result.lines) == "table" then result.lines else {}
	if current and current.token == result.token then
		-- Та же карточка: текст и эмодзи остаются, вместо кнопок — итог
		local merged = table.clone(current)
		merged.auto = result.auto
		merged.insured = result.insured
		render(merged, lines, true)
	else
		-- Карточки не было (вышел, не ответив, — результат пришёл при входе): показать в очереди
		table.insert(queue, {
			token = result.token,
			id = result.id,
			kind = result.kind,
			emoji = result.emoji,
			insured = result.insured,
			auto = result.auto,
			textVars = result.textVars,
			lines = lines,
			isResult = true,
		})
	end
end

-- ===== Плашки активных эффектов =====

local function signed(n: number, digits: string?): string
	local value = string.format(digits or "%.1f", math.abs(n)):gsub("%.0$", "")
	return (if n < 0 then "−" else "+") .. value
end

local function badgeTexts(): { { text: string, color: Color3 } }
	local state = CompanyEventState.state
	local now = CompanyEventState.now()
	local result = {}
	for _, effect in state.effects do
		local left = effect.endsAt - now
		if left <= 0 then
			continue
		end
		local time = CompanyEvents.clock(left)
		local entry: { text: string, color: Color3 }? = nil
		if effect.kind == "revenue" then
			local pct = math.floor(math.abs(effect.value - 1) * 100 + 0.5)
			local up = effect.value >= 1
			entry = {
				text = (if up then "📈 +" else "📉 −") .. pct .. "% " .. time,
				color = if up then Ui.colors.good else Ui.colors.bad,
			}
		elseif effect.kind == "rentFree" then
			entry = { text = "🏠 $0 " .. time, color = Ui.colors.good }
		elseif effect.kind == "pause" then
			entry = { text = "🔌 " .. time, color = Ui.colors.bad }
		elseif effect.kind == "broken" then
			entry = { text = "🔧 " .. time, color = Ui.colors.bad }
		elseif effect.kind == "mood" then
			entry = { text = "😩 " .. signed(effect.value, "%d") .. " " .. time, color = Ui.colors.bad }
		elseif effect.kind == "walkout" then
			entry = { text = "✊ " .. time, color = Ui.colors.bad }
		end
		if entry then
			table.insert(result, entry)
		end
	end
	if state.nextScore ~= 0 then
		table.insert(result, {
			text = "⭐ " .. signed(state.nextScore),
			color = if state.nextScore > 0 then Ui.colors.good else Ui.colors.bad,
		})
	end
	if state.nextRevenue ~= 1 then
		table.insert(result, {
			text = "🚀 ×" .. (string.format("%.1f", state.nextRevenue):gsub("%.0$", "")),
			color = Ui.colors.money,
		})
	end
	local insurance = CompanyEventState.insuranceLeft()
	if insurance > 0 then
		table.insert(result, { text = "🛡 " .. CompanyEvents.clock(insurance), color = Ui.colors.primary })
	end
	return result
end

local function startBadges()
	local bar = Instance.new("Frame")
	bar.Name = "CompanyEventBadges"
	bar.BackgroundTransparency = 1
	bar.LayoutOrder = 4
	bar.Size = UDim2.fromOffset(0, BADGE_HEIGHT)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.Visible = false
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar
	bar.Parent = Ui.bannerStack()
	-- Значок в лотке — эмодзи первой метки (📉 / 🛡 / ⭐)
	Ui.bannerMeta(bar, "companyEvents", nil, nil, Ui.colors.primary)

	local labels: { TextLabel } = {}
	local function refresh()
		local entries = badgeTexts()
		bar.Visible = #entries > 0
		for i, entry in entries do
			local label = labels[i]
			if not label then
				label = Ui.label(bar, "", BADGE_HEIGHT, Ui.bodyFont)
				label.TextScaled = false
				label.TextSize = 17
				label.AutomaticSize = Enum.AutomaticSize.X
				label.Size = UDim2.fromOffset(0, BADGE_HEIGHT)
				label.TextXAlignment = Enum.TextXAlignment.Center
				label.BackgroundTransparency = 0.25
				label.BackgroundColor3 = Ui.colors.panel
				label.LayoutOrder = i
				Ui.corner(label, 10)
				local padding = Instance.new("UIPadding")
				padding.PaddingLeft = UDim.new(0, 8)
				padding.PaddingRight = UDim.new(0, 8)
				padding.Parent = label
				labels[i] = label
			end
			label.Visible = true
			label.Text = entry.text
			label.TextColor3 = entry.color
		end
		for i = #entries + 1, #labels do
			labels[i].Visible = false
		end
	end
	CompanyEventState.changed:Connect(refresh)
	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)
end

function CompanyEventController.start()
	CompanyEventRemotes.CompanyEvent.OnClientEvent:Connect(onEvent)
	CompanyEventRemotes.CompanyEventResult.OnClientEvent:Connect(onResult)
	startBadges()
	-- Очередь карточек: показываем, когда экран свободен
	task.spawn(function()
		while true do
			task.wait(0.5)
			if not gui and #queue > 0 and not busy() then
				local info = table.remove(queue, 1)
				if info.isResult then
					current = info
					render(info, info.lines, true)
				else
					show(info)
				end
			end
		end
	end)
end

return CompanyEventController
