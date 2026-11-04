--!strict
-- Всплывающее событие разработки (Config/DevEvents): вопрос, два варианта, полоска времени.
-- Решает сервер; без ответа он сам применяет спокойный вариант b.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local RESULT_SECONDS = 2.5

local DevEventPopup = {}
local gui: ScreenGui? = nil

local function clear()
	local root = gui
	if root then
		for _, child in root:GetChildren() do
			child:Destroy()
		end
	end
end

local function panel(height: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -96) -- над кнопкой «Создать игру»
	frame.Size = UDim2.fromOffset(440, height)
	frame.BackgroundColor3 = Ui.colors.panel
	frame.BackgroundTransparency = 0.05
	Ui.corner(frame)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.money
	stroke.Parent = frame
	frame.Parent = gui
	return frame
end

local function show(info: any)
	if type(info) ~= "table" or type(info.id) ~= "string" then
		return
	end
	clear()
	local id: string = info.id
	local frame = panel(150)
	local title =
		Ui.label(frame, ClientState.t("devevent_" .. id .. "_title"), 44, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -28, 0, 44)
	title.TextXAlignment = Enum.TextXAlignment.Center

	local function choose(choice: string)
		Remotes.DevEventChoice:FireServer(id, choice)
		clear()
	end
	local a = Ui.button(frame, ClientState.t("devevent_" .. id .. "_a"), Ui.colors.primary, function()
		choose("a")
	end)
	a.Position = UDim2.fromOffset(14, 62)
	a.Size = UDim2.new(0.5, -21, 0, 52)
	local b = Ui.button(frame, ClientState.t("devevent_" .. id .. "_b"), Ui.colors.locked, function()
		choose("b")
	end)
	b.Position = UDim2.new(0.5, 7, 0, 62)
	b.Size = UDim2.new(0.5, -21, 0, 52)

	-- Полоска оставшегося времени
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Ui.colors.money
	bar.BorderSizePixel = 0
	bar.Position = UDim2.new(0, 14, 1, -18)
	bar.Size = UDim2.new(1, -28, 0, 6)
	Ui.corner(bar, 3)
	bar.Parent = frame
	local seconds = tonumber(info.answerSeconds) or 6
	TweenService
		:Create(bar, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 6) })
		:Play()
end

local function showResult(info: any)
	if type(info) ~= "table" or type(info.id) ~= "string" then
		return
	end
	clear()
	local key = if info.ok then "devevent_ok" else "devevent_fail"
	if info.choice == "b" and info.ok then
		key = "devevent_skip"
	end
	local frame = panel(50)
	local label = Ui.label(frame, ClientState.t(key), 34, Ui.titleFontFor(ClientState.lang))
	label.Position = UDim2.fromOffset(14, 8)
	label.Size = UDim2.new(1, -28, 0, 34)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextColor3 = if info.ok then Ui.colors.good else Ui.colors.bad
	task.delay(RESULT_SECONDS, function()
		if frame.Parent then
			frame:Destroy()
		end
	end)
end

function DevEventPopup.start()
	local screen = Instance.new("ScreenGui")
	screen.Name = "DevEventPopup"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 15
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Remotes.DevEvent.OnClientEvent:Connect(show)
	Remotes.DevEventResult.OnClientEvent:Connect(showResult)
	Remotes.GameReleased.OnClientEvent:Connect(function(info: any)
		-- Вторая игра ещё в разработке: её событие не прячем (событие вышедшей игры
		-- сервер закрыл раньше — пришёл DevEventResult)
		if type(info) == "table" and (tonumber(info.activeProjects) or 0) > 0 then
			return
		end
		clear()
	end)
end

return DevEventPopup
