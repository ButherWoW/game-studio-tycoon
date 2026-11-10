--!strict
-- Над головой каждого игрока: имя и «Капитал: $X» (1.2K / 3.4M). Выше таблички титула (TitleTags).
-- Сумму ставит сервер (CapitalService, атрибут игрока "Capital"). Настройка «Скрыть имя и капитал»
-- (атрибут LocalPlayer "HideCapital") убирает таблички и возвращает стандартное имя Roblox.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Titles = require(ReplicatedStorage.Shared.Config.Titles)
local ClientState = require(script.Parent.Parent.ClientState)

local ATTRIBUTE = "Capital"
local HIDE_ATTRIBUTE = "HideCapital"
local HEAD_WAIT = 10
local EXTRA_OFFSET = 3.1 -- выше титула (offsetY 1.5) и таблички VIP над головой (VipService, 3 studs)
local NAME_COLOR = Color3.fromRGB(255, 255, 255)
local CAPITAL_COLOR = Color3.fromRGB(255, 214, 90)
local STROKE = Color3.fromRGB(20, 20, 30)

local CapitalTags = {}
local localPlayer = Players.LocalPlayer
local tags: { [Player]: BillboardGui } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}

local SUFFIXES = { "", "K", "M", "B", "T" }

-- 950 → "950", 1234 → "1.2K", 3_400_000 → "3.4M"
local function short(amount: number): string
	local index = 1
	local value = amount
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	if index == 1 then
		return tostring(math.floor(value))
	end
	local text = string.format(if value < 10 then "%.1f" else "%.0f", math.floor(value * 10) / 10)
	return text:gsub("%.0$", "") .. SUFFIXES[index]
end

local function setDefaultName(player: Player, shown: boolean)
	local humanoid = if player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid.DisplayDistanceType = if shown
			then Enum.HumanoidDisplayDistanceType.Viewer
			else Enum.HumanoidDisplayDistanceType.None
	end
end

local function removeTag(player: Player)
	local tag = tags[player]
	if tag then
		tag:Destroy()
		tags[player] = nil
	end
end

local function line(parent: Instance, y: number, text: string, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.5)
	label.Position = UDim2.fromScale(0, y)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = STROKE
	label.TextStrokeTransparency = 0.25
	label.Text = text
	label.Parent = parent
	return label
end

local function update(player: Player)
	removeTag(player)
	if localPlayer:GetAttribute(HIDE_ATTRIBUTE) == true then
		setDefaultName(player, true)
		return
	end
	local head = if player.Character then player.Character:FindFirstChild("Head") else nil
	local capital = tonumber(player:GetAttribute(ATTRIBUTE))
	if not head or not head:IsA("BasePart") or not capital then
		return
	end
	setDefaultName(player, false)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CapitalTag_" .. player.UserId
	gui.ResetOnSpawn = false
	gui.Adornee = head
	gui.Size = UDim2.fromScale(Titles.tag.width, 2.2)
	gui.StudsOffset = Vector3.new(0, Titles.tag.offsetY + EXTRA_OFFSET, 0)
	gui.MaxDistance = Titles.tag.maxDistance
	gui.LightInfluence = 0
	line(gui, 0, player.DisplayName, NAME_COLOR)
	line(gui, 0.5, ClientState.t("capital_label", { amount = short(capital) }), CAPITAL_COLOR)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	tags[player] = gui
end

local function watch(player: Player)
	local list: { RBXScriptConnection } = {}
	table.insert(
		list,
		player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
			update(player)
		end)
	)
	table.insert(
		list,
		player.CharacterAdded:Connect(function(character)
			removeTag(player)
			character:WaitForChild("Head", HEAD_WAIT)
			if player.Parent then
				update(player)
			end
		end)
	)
	table.insert(
		list,
		player.CharacterRemoving:Connect(function()
			removeTag(player)
		end)
	)
	connections[player] = list
	task.spawn(function()
		if player.Character then
			player.Character:WaitForChild("Head", HEAD_WAIT)
		end
		if player.Parent then
			update(player)
		end
	end)
end

function CapitalTags.start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		removeTag(player)
		for _, connection in connections[player] or {} do
			connection:Disconnect()
		end
		connections[player] = nil
	end)
	local function updateAll()
		for _, player in Players:GetPlayers() do
			update(player)
		end
	end
	ClientState.langChanged:Connect(updateAll)
	localPlayer:GetAttributeChangedSignal(HIDE_ATTRIBUTE):Connect(updateAll)
end

return CapitalTags
