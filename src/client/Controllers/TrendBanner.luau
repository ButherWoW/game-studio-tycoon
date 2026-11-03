--!strict
-- Плашка «🔥 В тренде: Хоррор + Призраки, ещё 7:12» под HUD (шаг 4.3).
-- Тренд выбирает сервер (TrendService) и кладёт в атрибуты ReplicatedStorage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local BANNER_Y = 140 -- HUD занимает y 12..132 (3 плашки по 40 px)
local BANNER_HEIGHT = 32

local TrendBanner = {}

local function formatTime(seconds: number): string
	local s = math.max(math.floor(seconds), 0)
	return string.format("%d:%02d", s // 60, s % 60)
end

function TrendBanner.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TrendBanner"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local banner = Ui.label(gui, "", BANNER_HEIGHT, Ui.titleFont, Color3.fromRGB(255, 160, 70))
	banner.TextXAlignment = Enum.TextXAlignment.Center
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Size = UDim2.fromOffset(380, BANNER_HEIGHT)
	banner.Position = UDim2.new(0.5, 0, 0, BANNER_Y)
	banner.BackgroundTransparency = 0.25
	banner.BackgroundColor3 = Ui.colors.panel
	banner.Visible = false
	Ui.corner(banner, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = banner

	local function refresh()
		local genre = Genres[ReplicatedStorage:GetAttribute("TrendGenre") :: any]
		local topic = Topics[ReplicatedStorage:GetAttribute("TrendTopic") :: any]
		local endsAt = ReplicatedStorage:GetAttribute("TrendEndsAt")
		if not genre or not topic or type(endsAt) ~= "number" then
			banner.Visible = false
			return
		end
		banner.Visible = true
		banner.Text = ClientState.t("trend_banner", {
			genre = ClientState.localName(genre),
			topic = ClientState.localName(topic),
			-- Серверное время: часы клиента могут спешить
			time = formatTime(endsAt - workspace:GetServerTimeNow()),
		})
	end

	ReplicatedStorage:GetAttributeChangedSignal("TrendGenre"):Connect(refresh)
	ReplicatedStorage:GetAttributeChangedSignal("TrendTopic"):Connect(refresh)
	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)
end

return TrendBanner
