--!strict
-- HUD: деньги, число игр, активная реклама, прогресс разработки и кнопка «Создать игру».

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local CreateGameWindow = require(script.Parent.CreateGameWindow)

local HudController = {}

local function plate(parent: Instance, y: number): TextLabel
	local l = Ui.label(parent, "", 34, Ui.titleFont)
	l.Size = UDim2.fromOffset(300, 34)
	l.Position = UDim2.fromOffset(12, y)
	l.BackgroundTransparency = 0.25
	l.BackgroundColor3 = Ui.colors.panel
	Ui.corner(l, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = l
	return l
end

function HudController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local cash = plate(gui, 12)
	cash.TextColor3 = Ui.colors.money
	local info = plate(gui, 52)
	local progress = plate(gui, 92)
	progress.Visible = false

	local create = Ui.button(gui, ClientState.t("hud_create"), Ui.colors.money, function()
		CreateGameWindow.open()
	end)
	create.TextColor3 = Color3.fromRGB(40, 30, 0)
	create.AnchorPoint = Vector2.new(0.5, 1)
	create.Position = UDim2.new(0.5, 0, 1, -24)
	create.Size = UDim2.fromOffset(260, 56)

	local function refresh()
		local data = ClientState.data
		if not data then
			return
		end
		cash.Text = ClientState.t("hud_cash", { cash = Texts.money(data.cash):sub(2) })
		local line = ClientState.t("hud_games", { count = data.gamesReleased })
		if data.activeAd and data.activeAd.expiresAt > os.time() then
			line ..= "  ·  " .. ClientState.t("hud_ad", { percent = math.floor(data.activeAd.bonus * 100) })
		end
		info.Text = line
		create.Visible = not ClientState.developing
		if not ClientState.developing then
			progress.Visible = false
		end
	end

	ClientState.changed:Connect(refresh)
	refresh()

	Remotes.DevelopmentProgress.OnClientEvent:Connect(function(data)
		progress.Visible = true
		progress.Text = ClientState.t("hud_developing", { percent = math.floor(data.progress * 100) })
	end)
end

return HudController
