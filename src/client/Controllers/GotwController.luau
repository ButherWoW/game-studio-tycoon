--!strict
-- «Игра недели» на клиенте: плашка по воскресеньям (UTC) «итоги сегодня, лидер …», тост
-- победителю и титул «🏆 Игра недели #N» над головой победителей (атрибут игрока GotwRank,
-- ставит GotwService). Таблица — вкладка окна 📊 (GotwPanel).

local Players = game:GetService("Players")
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
local TAG_NAME = "GotwTitle"
local TAG_DISTANCE = 60

local player = Players.LocalPlayer

local GotwController = {}

-- ===== Титул над головой =====

local tags: { [Player]: BillboardGui } = {}

local function updateTag(target: Player)
	local rank = tonumber(target:GetAttribute("GotwRank")) or 0
	local character = target.Character
	local head = character and character:FindFirstChild("Head")
	local existing = tags[target]
	if rank <= 0 or not head or not head:IsA("BasePart") then
		if existing then
			existing:Destroy()
			tags[target] = nil
		end
		return
	end
	local gui = existing
	if not gui or gui.Adornee ~= head then
		if gui then
			gui:Destroy()
		end
		local newGui = Instance.new("BillboardGui")
		newGui.Name = TAG_NAME
		newGui.Size = UDim2.fromScale(5, 0.9)
		-- Выше таблички VIP (StudsOffset 3)
		newGui.StudsOffset = Vector3.new(0, 4.1, 0)
		newGui.MaxDistance = TAG_DISTANCE
		newGui.LightInfluence = 0
		newGui.Adornee = head
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 200, 50)
		label.TextStrokeColor3 = Color3.fromRGB(70, 45, 0)
		label.TextStrokeTransparency = 0.2
		label.Parent = newGui
		newGui.Parent = player:WaitForChild("PlayerGui")
		tags[target] = newGui
		gui = newGui
	end
	local label = (gui :: BillboardGui):FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = ClientState.t("gotw_head_title", { rank = rank })
	end
end

local function watchPlayer(target: Player)
	target:GetAttributeChangedSignal("GotwRank"):Connect(function()
		updateTag(target)
	end)
	target.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Head", 10)
		updateTag(target)
	end)
	updateTag(target)
end

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
	Players.PlayerAdded:Connect(watchPlayer)
	for _, other in Players:GetPlayers() do
		task.spawn(watchPlayer, other)
	end
	Players.PlayerRemoving:Connect(function(target: Player)
		local gui = tags[target]
		if gui then
			gui:Destroy()
		end
		tags[target] = nil
	end)
	ClientState.langChanged:Connect(function()
		for target in tags do
			updateTag(target)
		end
	end)
end

return GotwController
