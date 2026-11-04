--!strict
-- Окно банка (Config/Loans). Сервер кладёт в атрибуты игрока LoanOffer (сколько готов дать)
-- и LoanDebt (сколько осталось вернуть). Предложение всплывает само, когда денег меньше $50;
-- «Не сейчас» — больше не всплывает, пока предложение не снимется. С долгом — кнопка 🏦 в меню.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loans = require(ReplicatedStorage.Shared.Config.Loans)
local LoanRemotes = require(ReplicatedStorage.Shared.LoanRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local MENU_SLOT = 11

local LoanWindow = {}
local gui: ScreenGui? = nil

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

local function attr(name: string): number
	return tonumber(Players.LocalPlayer:GetAttribute(name)) or 0
end

local function show()
	close()
	local offer = attr("LoanOffer")
	local debt = attr("LoanDebt")
	if offer <= 0 and debt <= 0 then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "LoanWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 25
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local window = Ui.window(screen, "Window", Vector2.new(460, 330))
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	local layout = Ui.list(body, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	body.Parent = window

	local percent = math.floor(Loans.repayShare * 100)
	local title = Ui.label(body, ClientState.t("loan_title"), 36, Ui.titleFontFor(ClientState.lang))
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 1

	local text, amountText, hintText, actionText, actionColor
	if debt > 0 then
		text = ClientState.t("loan_debt_text")
		amountText = Texts.money(debt)
		hintText = ClientState.t("loan_auto_hint", { percent = percent })
		local cash = if ClientState.data then ClientState.data.cash else 0
		actionText = ClientState.t("loan_pay", { amount = Texts.money(math.min(cash, debt)) })
		actionColor = if cash > 0 then Ui.colors.good else Ui.colors.locked
	else
		text = ClientState.t("loan_offer")
		amountText = "+" .. Texts.money(offer)
		hintText =
			ClientState.t("loan_terms", { repay = Texts.money(Loans.repayFor(offer)), percent = percent })
		actionText = ClientState.t("loan_take")
		actionColor = Ui.colors.good
	end

	local line = Ui.label(body, text, 26, Enum.Font.GothamMedium)
	line.TextXAlignment = Enum.TextXAlignment.Center
	line.LayoutOrder = 2
	local money = Ui.label(
		body,
		amountText,
		52,
		Ui.titleFontFor(ClientState.lang),
		if debt > 0 then Ui.colors.bad else Ui.colors.money
	)
	money.TextXAlignment = Enum.TextXAlignment.Center
	money.LayoutOrder = 3
	local hint = Ui.label(body, hintText, 40, Enum.Font.GothamMedium, Ui.colors.muted)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.TextWrapped = true
	hint.LayoutOrder = 4

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

	local action = Ui.button(buttons, actionText, actionColor, function()
		if debt > 0 then
			LoanRemotes.RepayLoan:FireServer()
		else
			LoanRemotes.TakeLoan:FireServer()
		end
		close()
	end)
	action.Size = UDim2.new(0.55, 0, 1, 0)
	local later = Ui.button(
		buttons,
		ClientState.t(if debt > 0 then "loan_close" else "loan_later"),
		Ui.colors.locked,
		close
	)
	later.Size = UDim2.new(0.35, 0, 1, 0)
end

function LoanWindow.start()
	local player = Players.LocalPlayer
	local menu = Ui.menuButton(MENU_SLOT, "🏦", show)
	-- Предложение всплывает один раз за «провал» денег; снимется (LoanOffer = 0) — снова взведётся
	local offered = false
	local function check()
		local offer = attr("LoanOffer")
		menu.Visible = attr("LoanDebt") > 0
		if offer > 0 and not offered then
			offered = true
			if not gui then
				show()
			end
		elseif offer <= 0 then
			offered = false
		end
	end
	player:GetAttributeChangedSignal("LoanOffer"):Connect(check)
	player:GetAttributeChangedSignal("LoanDebt"):Connect(check)
	-- Предложение может всплыть при входе, до прихода сохранённого языка (отчёт #2, п. 3)
	ClientState.langChanged:Connect(function()
		if gui then
			show()
		end
	end)
	check()
end

return LoanWindow
