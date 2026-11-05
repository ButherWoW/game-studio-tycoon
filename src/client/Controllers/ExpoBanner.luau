--!strict
-- Плашка выставки под плашкой трендов: таймер и текущий лидер; окно с итогами раунда.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Expo = require(ReplicatedStorage.Shared.Config.Expo)
local ExpoRemotes = require(ReplicatedStorage.Shared.ExpoRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local FeatureGate = require(script.Parent.FeatureGate)

-- Плашка и итоги — в общем стеке под HUD (Ui.bannerStack): тренд 1, выставка 2, итоги 3.
-- Размеры небольшие: стек не должен закрывать студию (отчёт #2, п. 14)
local BANNER_HEIGHT = 28
local BANNER_WIDTH = 400
local RESULT_HEIGHT = 52
local RESULT_WIDTH = 420
-- Обложка игры-победителя (V20) слева в плашке итогов; 0 — плашка как раньше
local COVER_SIZE = 44

local ExpoBanner = {}

local function timeLeft(endsAt: number): string
	local left = math.max(endsAt - os.time(), 0)
	return string.format("%d:%02d", left // 60, left % 60)
end

local function showResult(stack: Frame, result: any)
	-- Итоги могут быть в объявлении или карточке лотка, не на складе
	local old = Ui.bannerFind("ExpoResult")
	if old then
		old:Destroy()
	end
	local panel = Ui.label(stack, "", RESULT_HEIGHT, Ui.titleFontFor(ClientState.lang))
	panel.Name = "ExpoResult"
	panel.LayoutOrder = 3
	panel.Size = UDim2.fromOffset(RESULT_WIDTH, RESULT_HEIGHT)
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
		local coverId = if type(result.genreId) == "string" then Images.covers[result.genreId] or 0 else 0
		if coverId > 0 then
			local thumb = Instance.new("Frame")
			thumb.Name = "Cover"
			thumb.BackgroundTransparency = 1
			thumb.AnchorPoint = Vector2.new(0, 0.5)
			thumb.Size = UDim2.fromOffset(COVER_SIZE, COVER_SIZE)
			thumb.Parent = panel
			Ui.artImage(thumb, coverId)
			local padding = Instance.new("UIPadding")
			padding.PaddingLeft = UDim.new(0, COVER_SIZE + 8)
			padding.Parent = panel
			-- Дети тоже сдвинуты отступом: возвращаем обложку к левому краю
			thumb.Position = UDim2.new(0, -(COVER_SIZE + 4), 0.5, 0)
		end
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
	local banner = Ui.label(stack, "", BANNER_HEIGHT, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	banner.Name = "ExpoBanner"
	banner.LayoutOrder = 2
	banner.Size = UDim2.fromOffset(BANNER_WIDTH, BANNER_HEIGHT)
	banner.BackgroundTransparency = 0.25
	banner.BackgroundColor3 = Ui.colors.panel
	banner.TextXAlignment = Enum.TextXAlignment.Center
	Ui.corner(banner, 10)
	-- Выставка новичку — с офиса (Config/Unlocks.expo)
	Ui.gate(banner, "expo")
	Ui.bannerMeta(banner, "expo", "🏆")

	ExpoRemotes.ExpoResult.OnClientEvent:Connect(function(result)
		if FeatureGate.isOpen("expo") then
			showResult(stack, result)
		end
	end)

	task.spawn(function()
		while true do
			local endsAt = ReplicatedStorage:GetAttribute("ExpoEndsAt")
			if type(endsAt) == "number" then
				banner.Visible = true
				banner.Font = Ui.titleFontFor(ClientState.lang)
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
