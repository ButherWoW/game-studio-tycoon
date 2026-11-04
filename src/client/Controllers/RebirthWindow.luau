--!strict
-- Окно Rebirth (шаг 4.4): слот меню 5. Условия, что сбросится/останется,
-- подтверждение в два клика. Решение и сброс — на сервере (RebirthService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rebirth = require(ReplicatedStorage.Shared.Config.Rebirth)
local RetentionRemotes = require(ReplicatedStorage.Shared.RetentionRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local CONFIRM_SECONDS = 3 -- сколько ждём второй клик

local RebirthWindow = {}
local gui: ScreenGui? = nil
local refresh: (() -> ())? = nil

local function multText(rebirths: number): string
	-- 1.5 -> "1.5", 2 -> "2"
	return (string.format("%.1f", Rebirth.multiplier(rebirths)):gsub("%.0$", ""))
end

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		refresh = nil
		Ui.windowClosed()
	end
end

function RebirthWindow.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "RebirthWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 15
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local window = Ui.window(screen, "Window", Vector2.new(520, 440))
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	Ui.list(body, 8)
	body.Parent = window

	local title = Ui.label(body, ClientState.t("rebirth_title"), 40, Ui.titleFontFor(ClientState.lang))
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 1
	local count = Ui.label(body, "", 24, nil, Ui.colors.muted)
	count.TextXAlignment = Enum.TextXAlignment.Center
	count.LayoutOrder = 2
	local nextLine = Ui.label(body, "", 26, nil, Ui.colors.money)
	nextLine.TextXAlignment = Enum.TextXAlignment.Center
	nextLine.LayoutOrder = 3
	local office = Ui.label(body, "", 24)
	office.LayoutOrder = 4
	local cash = Ui.label(body, "", 24)
	cash.LayoutOrder = 5
	local resets =
		Ui.label(body, ClientState.t("rebirth_resets"), 36, Enum.Font.GothamMedium, Ui.colors.muted)
	resets.TextWrapped = true
	resets.LayoutOrder = 6
	local keeps = Ui.label(body, ClientState.t("rebirth_keeps"), 20, Enum.Font.GothamMedium, Ui.colors.muted)
	keeps.LayoutOrder = 7

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 52)
	buttons.LayoutOrder = 8
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = buttons
	buttons.Parent = body

	local armedAt: number? = nil
	local canRebirth = false
	local action: TextButton

	local function update()
		local data = ClientState.data
		if not data then
			return
		end
		local rebirths = data.rebirths or 0
		-- Долг банка гасится вместе с ребёрзом (LoanService)
		local cost = Rebirth.cost(rebirths) + (tonumber(Players.LocalPlayer:GetAttribute("LoanDebt")) or 0)
		local hasOffice = data.upgrades and data.upgrades[Rebirth.requiredUpgrade] == true
		local hasCash = data.cash >= cost
		canRebirth = hasOffice and hasCash

		count.Text = ClientState.t("rebirth_count", { count = rebirths, mult = multText(rebirths) })
		nextLine.Text = ClientState.t("rebirth_next", { mult = multText(rebirths + 1) })
		office.Text = (if hasOffice then "✅ " else "❌ ") .. ClientState.t("rebirth_need_office")
		office.TextColor3 = if hasOffice then Ui.colors.good else Ui.colors.bad
		cash.Text = (if hasCash then "✅ " else "❌ ")
			.. ClientState.t("rebirth_need_cash", { price = Texts.money(cost) })
		cash.TextColor3 = if hasCash then Ui.colors.good else Ui.colors.bad

		if not canRebirth then
			armedAt = nil
			action.Text = ClientState.t("rebirth_locked")
			action.BackgroundColor3 = Ui.colors.locked
		elseif armedAt then
			action.Text = ClientState.t("rebirth_confirm")
			action.BackgroundColor3 = Ui.colors.bad
		else
			action.Text = ClientState.t("rebirth_button")
			action.BackgroundColor3 = Ui.colors.primary
		end
	end

	action = Ui.button(buttons, "", Ui.colors.locked, function()
		if not canRebirth then
			return
		end
		local now = os.clock()
		if armedAt and now - armedAt <= CONFIRM_SECONDS then
			armedAt = nil
			RetentionRemotes.RequestRebirth:FireServer()
			action.Text = "…"
			return
		end
		-- Первый клик: просим подтвердить; через CONFIRM_SECONDS кнопка остывает
		local stamp = now
		armedAt = stamp
		update()
		task.delay(CONFIRM_SECONDS, function()
			if gui == screen and armedAt == stamp then
				armedAt = nil
				update()
			end
		end)
	end)
	action.Size = UDim2.new(0.6, 0, 1, 0)
	Ui.button(buttons, ClientState.t("rebirth_close"), Ui.colors.locked, close).Size =
		UDim2.new(0.35, 0, 1, 0)

	refresh = update
	update()
end

function RebirthWindow.start()
	Ui.menuButton(5, "♻️", function()
		if gui then
			close()
		else
			RebirthWindow.open()
		end
	end)

	ClientState.changed:Connect(function()
		if refresh then
			refresh()
		end
	end)

	RetentionRemotes.RebirthResult.OnClientEvent:Connect(function(result)
		if type(result) ~= "table" then
			return
		end
		if result.ok then
			close()
			-- Короткое уведомление в центре экрана
			local screen = Instance.new("ScreenGui")
			screen.Name = "RebirthDone"
			screen.ResetOnSpawn = false
			screen.DisplayOrder = 15
			screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
			local toast = Ui.label(
				screen,
				ClientState.t("rebirth_done", { mult = multText(tonumber(result.rebirths) or 0) }),
				48,
				Ui.titleFont,
				Ui.colors.money
			)
			toast.TextXAlignment = Enum.TextXAlignment.Center
			toast.AnchorPoint = Vector2.new(0.5, 0.5)
			toast.Position = UDim2.fromScale(0.5, 0.35)
			toast.Size = UDim2.fromOffset(520, 48)
			task.delay(4, function()
				screen:Destroy()
			end)
		elseif refresh then
			refresh()
		end
	end)
end

return RebirthWindow
