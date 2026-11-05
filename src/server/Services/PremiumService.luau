--!strict
-- Бонус Roblox Premium (7.17, Config/Premium): +incomeBonus к доходу релиза (DevelopmentService
-- берёт revenueMultiplier рядом с налогом и биржей), атрибут игрока IsPremium (клиент: подсказка
-- в магазине и ⭐ в чате), ⭐ над головой и перед названием на вывеске студии (StartParkService).
-- Статус меняется на лету: Players.PlayerMembershipChanged (купил Premium, не выходя из игры).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Premium = require(ReplicatedStorage.Shared.Config.Premium)
local StartParkService = require(script.Parent.StartParkService)

local TAG_NAME = "PremiumTag"
local HEAD_WAIT = 10

local PremiumService = {}
local status: { [Player]: boolean } = {}

function PremiumService.isPremium(player: Player): boolean
	return player.MembershipType == Enum.MembershipType.Premium
end

-- Множитель дохода релиза: 1 или 1 + incomeBonus (бонус не больше +100%, даже если ошиблись в Config)
function PremiumService.revenueMultiplier(player: Player): number
	if not PremiumService.isPremium(player) then
		return 1
	end
	return 1 + math.clamp(Premium.incomeBonus, 0, 1)
end

-- ⭐ над головой: выше таблички VIP (VipService), маленькая
local function setTag(player: Player, on: boolean)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local existing = head:FindFirstChild(TAG_NAME)
	if not on then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = TAG_NAME
	gui.Adornee = head
	gui.Size = UDim2.fromScale(1.2, 1.2)
	gui.StudsOffset = Vector3.new(0, Premium.tagOffset, 0)
	gui.MaxDistance = Premium.tagMaxDistance
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = Premium.marker
	label.Parent = gui
	gui.Parent = head
end

-- Вывеска студии: ⭐ перед названием (после 👑 VIP, если он есть)
local function decorateSign(player: Player, model: Model, _board: BasePart)
	if not status[player] then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("TextLabel") and d.Name == "StudioName" then
			d.Text = Premium.marker .. " " .. d.Text
		end
	end
end

local function refresh(player: Player)
	local on = PremiumService.isPremium(player)
	if status[player] == on then
		return
	end
	status[player] = on
	player:SetAttribute("IsPremium", on)
	setTag(player, on)
	StartParkService.refreshSigns(player)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			character:WaitForChild("Head", HEAD_WAIT)
			if status[player] then
				setTag(player, true)
			end
		end)
	end)
	refresh(player)
	if status[player] and player.Character then
		setTag(player, true)
	end
end

function PremiumService.start()
	table.insert(StartParkService.signDecorators, decorateSign)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerMembershipChanged:Connect(refresh)
	Players.PlayerRemoving:Connect(function(player)
		status[player] = nil
	end)
end

return PremiumService
