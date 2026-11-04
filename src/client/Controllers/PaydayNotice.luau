--!strict
-- Зарплата команде (ExpensesService, раз в Expenses.paydaySeconds): тост «💼 Зарплата команде: −$X»
-- после выплаты и предупреждение за paydayWarnSeconds, если денег на неё не хватает.
-- Сервер даёт атрибуты PaydayAt (серверное время), PaydayAmount, PaydayPaid, PaydayCount.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Expenses = require(ReplicatedStorage.Shared.Config.Expenses)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local TOAST_SECONDS = 3.5
local CHECK_INTERVAL = 1

local player = Players.LocalPlayer

local PaydayNotice = {}
local toastGui: ScreenGui? = nil
local toastToken = 0

local function toast(text: string, color: Color3)
	if toastGui then
		toastGui:Destroy()
	end
	toastToken += 1
	local token = toastToken
	local screen = Instance.new("ScreenGui")
	screen.Name = "PaydayToast"
	-- Под окнами (10+), над HUD — как тосты полки хитов
	screen.DisplayOrder = 4
	screen.ResetOnSpawn = false
	screen.Parent = player:WaitForChild("PlayerGui")
	toastGui = screen
	local label = Ui.label(screen, text, 36, Ui.titleFontFor(ClientState.lang), color)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.22)
	label.Size = UDim2.new(0.9, 0, 0, 36)
	label.BackgroundColor3 = Ui.colors.panel
	label.BackgroundTransparency = 0.2
	Ui.corner(label, 10)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(560, 36)
	limit.Parent = label
	task.delay(TOAST_SECONDS, function()
		if toastToken == token then
			screen:Destroy()
			toastGui = nil
		end
	end)
end

function PaydayNotice.start()
	player:GetAttributeChangedSignal("PaydayCount"):Connect(function()
		local paid = tonumber(player:GetAttribute("PaydayPaid")) or 0
		if paid > 0 then
			toast(ClientState.t("payday_paid", { amount = Texts.money(paid) }), Ui.colors.bad)
		end
	end)
	-- Предупреждаем один раз за каждую зарплату
	local warnedFor: number? = nil
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			local at = tonumber(player:GetAttribute("PaydayAt"))
			local amount = tonumber(player:GetAttribute("PaydayAmount")) or 0
			local cash = if ClientState.data then ClientState.data.cash else 0
			if at and amount > 0 and warnedFor ~= at then
				local left = at - workspace:GetServerTimeNow()
				if left > 0 and left <= Expenses.paydayWarnSeconds and cash < amount then
					warnedFor = at
					toast(
						ClientState.t(
							"payday_soon",
							{ seconds = math.ceil(left), amount = Texts.money(amount) }
						),
						Ui.colors.bad
					)
				end
			end
		end
	end)
end

return PaydayNotice
