--!strict
-- Плашка выставки под плашкой трендов: таймер и текущий лидер; окно с итогами раунда.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Expo = require(ReplicatedStorage.Shared.Config.Expo)
local ExpoRemotes = require(ReplicatedStorage.Shared.ExpoRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

-- Плашка и итоги — в общем стеке под HUD (Ui.bannerStack): тренд 1, выставка 2, итоги 3

local ExpoBanner = {}

local function timeLeft(endsAt: number): string
	local left = math.max(endsAt - os.time(), 0)
	return string.format("%d:%02d", left // 60, left % 60)
end

local function showResult(stack: Frame, result: any)
	local old = stack:FindFirstChild("ExpoResult")
	if old then
		old:Destroy()
	end
	local panel = Ui.label(stack, "", 64, Ui.titleFontFor(ClientState.lang))
	panel.Name = "ExpoResult"
	panel.LayoutOrder = 3
	panel.Size = UDim2.fromOffset(460, 64)
	panel.BackgroundTransparency = 0.1
	panel.BackgroundColor3 = Ui.colors.panel
	panel.TextXAlignment = Enum.TextXAlignment.Center
	Ui.corner(panel, 12)
	local isMe = result.winnerId == Players.LocalPlayer.UserId
	if result.tooFew then
		panel.TextColor3 = Ui.colors.muted
		panel.Text = ClientState.t("expo_too_few", { need = result.need })
	elseif result.winner then
		panel.TextColor3 = if isMe then Ui.colors.good else Ui.colors.money
		panel.Text = ClientState.t(if isMe then "expo_you_won" else "expo_winner", {
			player = result.winner,
			name = result.game,
			score = result.score,
			prize = Texts.money(result.prize),
		})
	else
		panel.TextColor3 = Ui.colors.muted
		panel.Text = ClientState.t("expo_no_games")
	end
	task.delay(Expo.resultSeconds, function()
		if panel.Parent then
			panel:Destroy()
		end
	end)
end

function ExpoBanner.start()
	local stack = Ui.bannerStack()
	local banner = Ui.label(stack, "", 34, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	banner.Name = "ExpoBanner"
	banner.LayoutOrder = 2
	banner.Size = UDim2.fromOffset(460, 34)
	banner.BackgroundTransparency = 0.25
	banner.BackgroundColor3 = Ui.colors.panel
	banner.TextXAlignment = Enum.TextXAlignment.Center
	Ui.corner(banner, 10)

	ExpoRemotes.ExpoResult.OnClientEvent:Connect(function(result)
		showResult(stack, result)
	end)

	task.spawn(function()
		while true do
			local endsAt = ReplicatedStorage:GetAttribute("ExpoEndsAt")
			if type(endsAt) == "number" then
				banner.Visible = true
				local leaderGame = ReplicatedStorage:GetAttribute("ExpoLeaderGame")
				local vars = {
					time = timeLeft(endsAt),
					prize = Texts.money(Expo.prize),
					name = leaderGame,
					score = ReplicatedStorage:GetAttribute("ExpoLeaderScore"),
					player = ReplicatedStorage:GetAttribute("ExpoLeaderPlayer"),
				}
				banner.Text = ClientState.t(if leaderGame then "expo_banner_leader" else "expo_banner", vars)
			else
				banner.Visible = false
			end
			task.wait(1)
		end
	end)
end

return ExpoBanner
