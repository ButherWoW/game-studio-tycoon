--!strict
-- «Игра недели» на клиенте: плашка по воскресеньям (UTC) «итоги сегодня, лидер …», тост
-- победителю. Титул «🏆 Игра недели #N» над головой — общий титул gotw_winner (TitleService,
-- табличка TitleTags берёт место из атрибута GotwRank). Таблица — вкладка окна 📊 (GotwPanel).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gotw = require(Shared.Config.Gotw)
local GotwRemotes = require(Shared.GotwRemotes)
local Texts = require(Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local DepthToast = require(script.Parent.Parent.DepthToast)
local GotwPanel = require(script.Parent.Parent.GotwPanel)
local Ui = require(script.Parent.Parent.Ui)

local BANNER_HEIGHT = 26
local BANNER_WIDTH = 460

local GotwController = {}

-- ===== Плашка воскресенья =====

local function buildBanner()
	local banner = Ui.label(
		Ui.bannerStack(),
		"",
		BANNER_HEIGHT,
		Ui.titleFontFor(ClientState.lang),
		Color3.fromRGB(255, 200, 50)
	)
	banner.Name = "GotwBanner"
	banner.LayoutOrder = 7
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
	-- Вместе с окном 📊 (вкладка «Игра недели») — со 2-го этажа (Config/Unlocks.gotw)
	Ui.gate(banner, "gotw")

	local requested = false
	local function refresh()
		-- Серверное время: часы клиента могут спешить
		local now = workspace:GetServerTimeNow()
		if not Gotw.isSunday(now) then
			banner.Visible = false
			return
		end
		if not requested then
			requested = true
			GotwPanel.request()
		end
		local s = math.max(math.floor(Gotw.weekLeft(math.floor(now))), 0)
		local time = string.format("%d:%02d", s // 3600, (s % 3600) // 60)
		local leader = GotwPanel.leader()
		banner.Visible = true
		banner.Font = Ui.titleFontFor(ClientState.lang)
		banner.Text = if leader
			then ClientState.t("gotw_banner", {
				time = time,
				name = tostring(leader.name),
				studio = tostring(leader.studio),
			})
			else ClientState.t("gotw_banner_empty", { time = time })
	end
	GotwPanel.changed:Connect(refresh)
	task.spawn(function()
		while true do
			refresh()
			task.wait(5)
		end
	end)
end

function GotwController.start()
	buildBanner()
	GotwRemotes.GotwNotice.OnClientEvent:Connect(function(info: any)
		if type(info) == "table" and info.kind == "winner" then
			DepthToast.show(
				ClientState.t("gotw_toast_winner", {
					rank = tonumber(info.rank) or 0,
					money = Texts.money(tonumber(info.money) or 0),
				}),
				Ui.colors.good
			)
		end
	end)
end

return GotwController
