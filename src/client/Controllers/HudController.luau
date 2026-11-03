--!strict
-- Временный HUD из кода, чтобы core loop можно было проверить без дизайна.
-- В Фазе 2 UI-дизайнер заменит его на нормальные ScreenGui.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local HudController = {}

local function label(parent: Instance, name: string, y: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = UDim2.fromOffset(320, 28)
	l.Position = UDim2.fromOffset(12, y)
	l.BackgroundTransparency = 0.4
	l.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, y: number, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(320, 36)
	b.Position = UDim2.fromOffset(12, y)
	b.BackgroundColor3 = Color3.fromRGB(70, 130, 255)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.Text = text
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

function HudController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DebugHud"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local cash = label(gui, "Cash", 12)
	local progress = label(gui, "Progress", 44)
	local result = label(gui, "Result", 76)

	button(gui, "Сделать игру: Космос + Экшен", 116, function()
		Remotes.StartDevelopment:FireServer({
			name = "Space Blaster",
			genreId = "action",
			topicId = "space",
			focus = { gameplay = 4, graphics = 3, sound = 2, story = 1 },
		})
	end)
	button(gui, "Купить стол (бесплатно)", 158, function()
		Remotes.BuyUpgrade:FireServer("desk1")
	end)
	button(gui, "Реклама: соцсети (+30%) за 50 000", 200, function()
		Remotes.BuyAdCampaignWithCash:FireServer("social")
	end)

	Remotes.DataChanged.OnClientEvent:Connect(function(data)
		local ad = ""
		if data.activeAd and data.activeAd.expiresAt > os.time() then
			ad = string.format("  | реклама +%d%%", data.activeAd.bonus * 100)
		end
		cash.Text = string.format("  $ %d  | игр: %d%s", data.cash, data.gamesReleased, ad)
	end)

	Remotes.DevelopmentProgress.OnClientEvent:Connect(function(info)
		progress.Text = string.format("  Разработка: %d%%", math.floor(info.progress * 100))
	end)

	Remotes.GameReleased.OnClientEvent:Connect(function(info)
		result.Text = string.format("  «%s»: %d/10, +$%d", info.name, info.score, info.revenue)
		progress.Text = ""
	end)
end

return HudController
