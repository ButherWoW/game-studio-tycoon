--!strict
-- Кнопка 🏠 в боковом меню (слот 12): перенести персонажа к воротам своего гаража.
-- Видна всем: без гаража ведёт к своему участку с табличкой «Гараж продаётся». Проверки — на сервере (PlotService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StartRemotes = require(ReplicatedStorage.Shared.StartRemotes)
local Ui = require(script.Parent.Parent.Ui)
local StudioCamera = require(script.Parent.StudioCamera)

local MENU_SLOT = 12
-- Сервер всё равно режет чаще раза в 2 с; здесь — чтобы не слать лишнего
local CLICK_COOLDOWN = 1

local HomeButton = {}

function HomeButton.start()
	local player = Players.LocalPlayer
	local lastClick = 0
	local menu = Ui.menuButton(MENU_SLOT, "🏠", function()
		local now = os.clock()
		if now - lastClick < CLICK_COOLDOWN then
			return
		end
		lastClick = now
		-- Вид сверху показывает только свой этаж: после переноса ко входу он прятал бы верхние
		-- этажи (отчёт владельца) — выходим из него
		StudioCamera.exit()
		StartRemotes.GoHome:FireServer()
	end, "home")
	-- Пока участок не выдан (все заняты) — вести некуда
	local function refresh()
		menu.Visible = player:GetAttribute("PlotName") ~= nil
	end
	player:GetAttributeChangedSignal("PlotName"):Connect(refresh)
	refresh()
end

return HomeButton
