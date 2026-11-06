--!strict
-- Окно налоговой (Config/Tax, TaxService). Атрибуты игрока: TaxBill, TaxDue, TaxAuditUntil,
-- TaxNextIn, TaxRate. Счёт всплывает сам (PopupQueue); кнопка 🧾 в меню видна, пока есть счёт
-- или идёт налоговая проверка. Тост «осталась минута» перед штрафом.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tax = require(ReplicatedStorage.Shared.Config.Tax)
local TaxRemotes = require(ReplicatedStorage.Shared.TaxRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local ArtIcon = require(script.Parent.Parent.ArtIcon)
local ClientState = require(script.Parent.Parent.ClientState)
local DepthToast = require(script.Parent.Parent.DepthToast)
local PopupQueue = require(script.Parent.Parent.PopupQueue)
local Ui = require(script.Parent.Parent.Ui)

local HEADER_ART = 64 -- V31: картинка Астры над заголовком (Images.windows), если есть ID

local MENU_SLOT = 18

local player = Players.LocalPlayer
local TaxWindow = {}
local gui: ScreenGui? = nil
local timerLabel: TextLabel? = nil

local function now(): number
	-- Сроки в атрибутах — os.time сервера; часы клиента могут отличаться
	return workspace:GetServerTimeNow()
end

local function attr(name: string): number
	return tonumber(player:GetAttribute(name)) or 0
end

local function clock(seconds: number): string
	seconds = math.max(math.floor(seconds), 0)
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		timerLabel = nil
		Ui.windowClosed()
	end
end

local function auditLeft(): number
	return attr("TaxAuditUntil") - now()
end

local function show()
	close()
	PopupQueue.remove("tax")
	local bill = attr("TaxBill")
	local screen = Instance.new("ScreenGui")
	screen.Name = "TaxWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 25
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local window = Ui.window(
		screen,
		"Window",
		Vector2.new(480, 360 + ArtIcon.headerHeight(Images.windows.tax, HEADER_ART, 10))
	)
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	local layout = Ui.list(body, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	body.Parent = window

	local title = Ui.label(body, ClientState.t("tax_title"), 36, Ui.titleFontFor(ClientState.lang))
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 1
	title.Text = ArtIcon.strip(title.Text, "🧾", Images.windows.tax)
	ArtIcon.header(body, Images.windows.tax, HEADER_ART, 0)

	local rate = math.floor(attr("TaxRate") * 100 + 0.5)
	local text, amount, color
	if bill > 0 then
		text = ClientState.t("tax_bill_text", { percent = rate })
		amount = Texts.money(bill)
		color = Ui.colors.bad
	else
		text = ClientState.t("tax_no_bill", { percent = rate })
		amount = clock(attr("TaxNextIn"))
		color = Ui.colors.muted
	end
	local line = Ui.label(body, text, 40, Enum.Font.GothamMedium)
	line.TextXAlignment = Enum.TextXAlignment.Center
	line.TextWrapped = true
	line.LayoutOrder = 2
	local money = Ui.label(body, amount, 52, Ui.titleFontFor(ClientState.lang), color)
	money.TextXAlignment = Enum.TextXAlignment.Center
	money.LayoutOrder = 3
	local timer = Ui.label(body, "", 44, Enum.Font.GothamMedium, Ui.colors.muted)
	timer.TextXAlignment = Enum.TextXAlignment.Center
	timer.TextWrapped = true
	timer.LayoutOrder = 4
	timerLabel = timer

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 52)
	buttons.LayoutOrder = 5
	buttons.Parent = body
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.Padding = UDim.new(0, 12)
	row.Parent = buttons
	if bill > 0 then
		local cash = if ClientState.data then ClientState.data.cash else 0
		local pay = Ui.button(
			buttons,
			ClientState.t("tax_pay", { amount = Texts.money(bill) }),
			if cash >= bill then Ui.colors.good else Ui.colors.locked,
			function()
				TaxRemotes.PayTax:FireServer()
				close()
			end
		)
		pay.Size = UDim2.new(0.55, 0, 1, 0)
	end
	local later = Ui.button(buttons, ClientState.t("loan_close"), Ui.colors.locked, close)
	later.Size = UDim2.new(0.35, 0, 1, 0)
end

local function updateTimer()
	local label = timerLabel
	if not label then
		return
	end
	local bill = attr("TaxBill")
	local parts = {}
	if bill > 0 then
		table.insert(
			parts,
			ClientState.t("tax_due", {
				time = clock(attr("TaxDue") - now()),
				fine = Texts.money(Tax.fineFor(bill)),
				percent = math.floor((1 - Tax.auditRevenueMultiplier) * 100 + 0.5),
			})
		)
	end
	if auditLeft() > 0 then
		table.insert(
			parts,
			ClientState.t("tax_audit", {
				time = clock(auditLeft()),
				percent = math.floor((1 - Tax.auditRevenueMultiplier) * 100 + 0.5),
			})
		)
	end
	label.Text = table.concat(parts, "\n")
end

function TaxWindow.open()
	show()
end

function TaxWindow.start()
	local menu = Ui.menuButton(MENU_SLOT, "🧾", show, "menu_tax")
	local lastBill = 0
	local warned = false
	local function check()
		local bill = attr("TaxBill")
		menu.Visible = bill > 0 or auditLeft() > 0
		if bill > 0 and lastBill <= 0 then
			warned = false
			if not gui then
				PopupQueue.push("tax", function()
					if not gui and attr("TaxBill") > 0 then
						show()
					end
				end)
			end
		elseif bill <= 0 then
			PopupQueue.remove("tax")
			if lastBill > 0 and auditLeft() > 0 then
				-- Счёт пропал, а проверка началась — штраф списан
				DepthToast.show(ClientState.t("tax_fined"), Ui.colors.bad)
			end
		end
		lastBill = bill
	end
	for _, name in { "TaxBill", "TaxAuditUntil" } do
		player:GetAttributeChangedSignal(name):Connect(check)
	end
	ClientState.langChanged:Connect(function()
		if gui then
			show()
		end
	end)
	check()
	task.spawn(function()
		while true do
			task.wait(1)
			updateTimer()
			local bill = attr("TaxBill")
			if bill > 0 and not warned and attr("TaxDue") - now() <= 60 then
				warned = true
				DepthToast.show(ClientState.t("tax_last_minute"), Ui.colors.bad)
			end
			menu.Visible = bill > 0 or auditLeft() > 0
		end
	end)
end

return TaxWindow
