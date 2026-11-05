--!strict
-- Плашка «🔬 Логика · 4:07» в общем стеке под HUD, пока идёт исследование (Config/Research.TIMING),
-- и тост «🔬 Исследование готово: …». Закончилось офлайн — тост через PopupQueue, после окон входа.
-- Состояние — атрибуты игрока ResearchKind, ResearchId, ResearchEndsAt (ставит ResearchService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Research = require(ReplicatedStorage.Shared.Config.Research)
local ResearchRemotes = require(ReplicatedStorage.Shared.ResearchRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local DepthToast = require(script.Parent.Parent.DepthToast)
local PopupQueue = require(script.Parent.Parent.PopupQueue)
local Ui = require(script.Parent.Parent.Ui)
local ResearchWindow = require(script.Parent.ResearchWindow)
local SoundController = require(script.Parent.SoundController)

local BANNER_HEIGHT = 26
local BANNER_WIDTH = 340
-- После тренда (1), выставки (2), … «Игры недели» (7)
local BANNER_ORDER = 8
local STEP_SECONDS = 0.5

local ResearchBanner = {}

function ResearchBanner.start()
	local player = Players.LocalPlayer
	local banner =
		Ui.label(Ui.bannerStack(), "", BANNER_HEIGHT, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	banner.Name = "ResearchBanner"
	banner.LayoutOrder = BANNER_ORDER
	banner.TextXAlignment = Enum.TextXAlignment.Center
	banner.Size = UDim2.fromOffset(BANNER_WIDTH, BANNER_HEIGHT)
	banner.BackgroundTransparency = 0.25
	banner.BackgroundColor3 = Ui.colors.panel
	banner.Visible = false
	Ui.corner(banner, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.Parent = banner

	local function refresh()
		local endsAt = player:GetAttribute("ResearchEndsAt")
		local kind = player:GetAttribute("ResearchKind")
		local id = player:GetAttribute("ResearchId")
		if type(endsAt) ~= "number" or type(kind) ~= "string" or type(id) ~= "string" then
			banner.Visible = false
			return
		end
		local left = math.max(endsAt - workspace:GetServerTimeNow(), 0)
		banner.Font = Ui.titleFontFor(ClientState.lang)
		banner.Text = ClientState.t("rtime_banner", {
			name = ResearchWindow.activeName(kind, id),
			time = if left > 0 then Research.formatTime(left) else "0:00",
		})
		banner.Visible = true
	end
	refresh()
	player:GetAttributeChangedSignal("ResearchEndsAt"):Connect(refresh)
	ClientState.changed:Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(STEP_SECONDS)
			if banner.Visible then
				refresh()
			end
		end
	end)

	ResearchRemotes.ResearchFinished.OnClientEvent:Connect(function(info)
		if type(info) ~= "table" then
			return
		end
		local function show()
			-- Узел дерева — «Исследование готово», жанр/тема за $ — «Открыто»
			local key = if info.kind == "node" then "rtime_done" else "rtime_done_unlock"
			DepthToast.show(ClientState.t(key, { name = ResearchWindow.itemName(info.kind, info.id) }))
			SoundController.play("research_done")
		end
		if info.offline == true then
			-- Закончилось, пока игрока не было: после награды за вход и «Пока тебя не было»
			PopupQueue.push("research_done_" .. tostring(info.kind) .. "_" .. tostring(info.id), show)
		else
			show()
		end
	end)
end

return ResearchBanner
