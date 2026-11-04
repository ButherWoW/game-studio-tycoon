--!strict
-- «😈 Главные воры» (слот меню 8): вкладки «На сервере» (живой топ) и «За всё время»
-- (глобальный топ-10 из OrderedDataStore). Титул «👑 Главный вор» над головой лидера сервера
-- (атрибут ReplicatedStorage «TopThiefUserId», ставит ThiefBoardService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HitRemotes = require(ReplicatedStorage.Shared.HitRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local MENU_SLOT = 8
local ROW_HEIGHT = 30

local player = Players.LocalPlayer

local ThiefWindow = {}

local board: any = nil
local tab: "server" | "global" = "server"
local gui: ScreenGui? = nil
local refresh: (() -> ())? = nil

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		refresh = nil
		Ui.windowClosed()
	end
end

local function open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "ThiefWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 15
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()
	HitRemotes.RequestThiefBoard:FireServer()

	local frame = Ui.window(screen, "Window", Vector2.new(520, 500))
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	Ui.list(body, 8)
	body.Parent = frame

	local title = Ui.label(body, ClientState.t("thief_title"), 38, Ui.titleFontFor(ClientState.lang))
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 1

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, 0, 0, 44)
	tabs.LayoutOrder = 2
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabs
	tabs.Parent = body

	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, 0, 1, -(38 + 44 + 44 + 24))
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.LayoutOrder = 3
	Ui.list(list, 4)
	list.Parent = body

	local serverTab: TextButton
	local globalTab: TextButton

	local function update()
		serverTab.BackgroundColor3 = if tab == "server" then Ui.colors.primary else Ui.colors.locked
		globalTab.BackgroundColor3 = if tab == "global" then Ui.colors.primary else Ui.colors.locked
		for _, child in list:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local rows: { any } = {}
		local message: string? = nil
		if not board then
			message = "…"
		elseif tab == "server" then
			rows = if type(board.server) == "table" then board.server else {}
		else
			local global = board.global
			if type(global) ~= "table" or not global.available then
				message = ClientState.t("thief_unavailable")
			else
				rows = if type(global.rows) == "table" then global.rows else {}
			end
		end
		if not message and (#rows == 0 or (tonumber(rows[1].steals) or 0) <= 0) then
			message = ClientState.t("thief_empty")
		end
		if message then
			local label = Ui.label(list, message, ROW_HEIGHT, Enum.Font.GothamMedium, Ui.colors.muted)
			label.TextXAlignment = Enum.TextXAlignment.Center
		end
		for place, row in rows do
			local isMe = row.userId == player.UserId
			local label = Ui.label(
				list,
				ClientState.t("thief_row", {
					place = place,
					name = row.name,
					steals = row.steals,
					catches = row.catches,
				}),
				ROW_HEIGHT,
				nil,
				if isMe then Ui.colors.money elseif place == 1 then Ui.colors.good else Ui.colors.text
			)
			label.LayoutOrder = place
			-- Себя подсвечиваем фоном
			label.BackgroundTransparency = if isMe then 0.6 else 1
			label.BackgroundColor3 = Ui.colors.primary
			Ui.corner(label, 6)
		end
	end

	serverTab = Ui.button(tabs, ClientState.t("thief_tab_server"), Ui.colors.primary, function()
		tab = "server"
		update()
	end)
	serverTab.Size = UDim2.new(0.48, 0, 1, 0)
	globalTab = Ui.button(tabs, ClientState.t("thief_tab_global"), Ui.colors.locked, function()
		tab = "global"
		update()
	end)
	globalTab.Size = UDim2.new(0.48, 0, 1, 0)

	local closeButton = Ui.button(body, ClientState.t("hit_close"), Ui.colors.locked, close)
	closeButton.Size = UDim2.new(1, 0, 0, 44)
	closeButton.LayoutOrder = 4

	refresh = update
	update()
end

-- ===== Титул лидеру сервера =====

local crown: BillboardGui? = nil

local function updateCrown()
	local id = ReplicatedStorage:GetAttribute("TopThiefUserId")
	local leader = if type(id) == "number" then Players:GetPlayerByUserId(id) else nil
	local character = leader and leader.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		if crown then
			crown:Destroy()
			crown = nil
		end
		return
	end
	if not crown then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "ThiefCrown"
		billboard.Size = UDim2.fromOffset(160, 30)
		billboard.StudsOffset = Vector3.new(0, 2.6, 0)
		billboard.MaxDistance = 60
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Ui.colors.money
		label.TextStrokeTransparency = 0.3
		label.Parent = billboard
		billboard.Parent = player:WaitForChild("PlayerGui")
		crown = billboard
	end
	local current = crown :: BillboardGui
	current.Adornee = head
	local label = current:FindFirstChild("Text") :: TextLabel
	label.Text = ClientState.t("thief_crown")
end

function ThiefWindow.start()
	Ui.menuButton(MENU_SLOT, "😈", function()
		if gui then
			close()
		else
			open()
		end
	end)
	HitRemotes.ThiefBoard.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then
			return
		end
		board = data
		if refresh then
			refresh()
		end
	end)
	ClientState.changed:Connect(updateCrown)
	ReplicatedStorage:GetAttributeChangedSignal("TopThiefUserId"):Connect(updateCrown)
	-- Лидер переродился или вышел: голова сменилась. Дешёвая проверка раз в секунду
	task.spawn(function()
		while true do
			updateCrown()
			task.wait(1)
		end
	end)
	HitRemotes.RequestThiefBoard:FireServer()
end

return ThiefWindow
