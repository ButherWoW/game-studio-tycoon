--!strict
-- Разовая подсказка при первой забастовке команды: почему встали и что делать.
-- Забастовку ставит ExpensesService (атрибут игрока StaffStrike), «видел ли» — StaffService
-- (атрибут StrikeTipSeen: false — ещё не видел, nil — профиль не загружен, ждём).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StaffRemotes = require(ReplicatedStorage.Shared.StaffRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local StrikeTip = {}
local gui: ScreenGui? = nil
local dismissed = false -- закрыли в этой сессии (сервер ещё мог не ответить)

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

local function show()
	close()
	local screen = Instance.new("ScreenGui")
	screen.Name = "StrikeTip"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 25
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local window = Ui.window(screen, "Window", Vector2.new(480, 330))
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	local layout = Ui.list(body, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	body.Parent = window

	local title = Ui.label(
		body,
		ClientState.t("strike_tip_title"),
		36,
		Ui.titleFontFor(ClientState.lang),
		Ui.colors.bad
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 1
	local text = Ui.label(body, ClientState.t("strike_tip_text"), 170, Enum.Font.GothamMedium)
	text.TextScaled = false
	text.TextSize = 20
	text.TextWrapped = true
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.LayoutOrder = 2

	local ok = Ui.button(body, ClientState.t("strike_tip_ok"), Ui.colors.primary, function()
		dismissed = true
		StaffRemotes.StrikeTipSeen:FireServer()
		close()
	end)
	ok.Size = UDim2.new(0.6, 0, 0, 52)
	ok.LayoutOrder = 3
end

function StrikeTip.start()
	local player = Players.LocalPlayer
	local function check()
		if dismissed or gui then
			return
		end
		if player:GetAttribute("StaffStrike") == true and player:GetAttribute("StrikeTipSeen") == false then
			show()
		end
	end
	player:GetAttributeChangedSignal("StaffStrike"):Connect(check)
	player:GetAttributeChangedSignal("StrikeTipSeen"):Connect(check)
	-- Язык приходит после входа — перерисовать открытую подсказку
	ClientState.langChanged:Connect(function()
		if gui then
			show()
		end
	end)
	check()
end

return StrikeTip
