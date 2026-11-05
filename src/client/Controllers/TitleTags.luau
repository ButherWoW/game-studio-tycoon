--!strict
-- Титулы над головой (роадмап 7.21): табличка под ником у каждого игрока с выбранным титулом.
-- Сервер (TitleService) проверяет титул и ставит атрибут игрока "Title" (id из Config/Titles);
-- табличку рисует каждый клиент сам — на своём языке. BillboardGui лежит в PlayerGui
-- (Adornee = голова), поэтому не мешает VIP-табличке VipService в самом персонаже.
-- Настройка «Скрыть титулы других игроков» (атрибут LocalPlayer "HideTitles", ClientSettings):
-- чужие таблички не рисуем, свою — рисуем.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Titles = require(ReplicatedStorage.Shared.Config.Titles)
local ClientState = require(script.Parent.Parent.ClientState)

local ATTRIBUTE = "Title"
local HIDE_ATTRIBUTE = "HideTitles"
local HEAD_WAIT = 10

local TitleTags = {}
local localPlayer = Players.LocalPlayer
local tags: { [Player]: BillboardGui } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}

local function removeTag(player: Player)
	local tag = tags[player]
	if tag then
		tag:Destroy()
		tags[player] = nil
	end
end

local function update(player: Player)
	removeTag(player)
	if player ~= localPlayer and localPlayer:GetAttribute(HIDE_ATTRIBUTE) == true then
		return
	end
	local id = player:GetAttribute(ATTRIBUTE)
	local title = if type(id) == "string" then Titles.byId[id] else nil
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not title or not head or not head:IsA("BasePart") then
		return
	end
	local config = Titles.tag
	local gui = Instance.new("BillboardGui")
	gui.Name = "TitleTag_" .. player.UserId
	gui.ResetOnSpawn = false
	gui.Adornee = head
	gui.Size = UDim2.fromScale(config.width, config.height) -- в studs: издалека меньше
	gui.StudsOffset = Vector3.new(0, config.offsetY, 0)
	gui.MaxDistance = config.maxDistance
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = title.color
	label.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	label.TextStrokeTransparency = 0.3
	label.Text = title.icon .. " " .. ClientState.t("title_" .. title.id)
	label.Parent = gui
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
		local character = player.Character
		if character then
			character:WaitForChild("Head", HEAD_WAIT)
		end
		if player.Parent then
			update(player)
		end
	end)
end

function TitleTags.start()
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
	-- Сменили язык или настройку «скрыть титулы»: перерисовать все таблички
	local function updateAll()
		for _, player in Players:GetPlayers() do
			update(player)
		end
	end
	ClientState.langChanged:Connect(updateAll)
	localPlayer:GetAttributeChangedSignal(HIDE_ATTRIBUTE):Connect(updateAll)
end

return TitleTags
