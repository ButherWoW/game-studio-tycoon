--!strict
-- Маскоты на клиенте: вкладка «🐾 Маскоты» окна магазина (ShopWindow).
-- Что открыто и кто надет, решает сервер (MascotService); за Robux клиент только открывает
-- окно покупки Roblox. productId 0 — кнопка «Скоро». Бонус даёт только надетый маскот.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MascotRemotes = require(Shared.MascotRemotes)
local Mascots = require(Shared.Config.Mascots)
local Achievements = require(Shared.Config.Achievements)
local Images = require(Shared.Config.Images)
local Texts = require(Shared.Config.Texts)
local Social = require(Shared.Config.Social)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)
local GiftPicker = require(script.Parent.GiftPicker)

type State = { owned: { [string]: boolean }, equipped: string? }

local CELL = Vector2.new(152, 262)
local ICON = 96
local BUTTON_HEIGHT = 40

local MascotShop = {}
MascotShop.state = { owned = {}, equipped = nil } :: State
local listeners: { () -> () } = {}

function MascotShop.name(mascot: Mascots.Mascot): string
	return ClientState.localText("mascot_" .. mascot.id, mascot.name, mascot.nameEn)
end

-- Текст бонуса: «+5% к скорости разработки»
function MascotShop.bonusText(mascot: Mascots.Mascot): string
	local bonus = mascot.bonus
	local value: string
	if bonus.kind == "mood" then
		value = tostring(math.floor(bonus.value))
	elseif bonus.kind == "review" then
		value = string.format("%.2f", bonus.value)
	else
		value = tostring(math.floor(bonus.value * 100 + 0.5))
	end
	return ClientState.t("mascot_bonus_" .. bonus.kind, { value = value })
end

local function icon(parent: Instance, mascot: Mascots.Mascot): Frame
	local rarityColor = Mascots.rarityColors[mascot.rarity]
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(ICON, ICON)
	frame.BackgroundColor3 = mascot.color:Lerp(Color3.fromRGB(30, 30, 46), 0.55)
	frame.BorderSizePixel = 0
	Ui.corner(frame, 48)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = if mascot.rarity == "legendary" then 4 else 3
	stroke.Color = rarityColor
	stroke.Parent = frame
	local imageId = Images.mascots[mascot.id] or 0
	if imageId > 0 then
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = "rbxassetid://" .. imageId
		image.Parent = frame
	else
		local emoji = Ui.label(frame, mascot.emoji, ICON * 0.6)
		emoji.AnchorPoint = Vector2.new(0.5, 0.5)
		emoji.Position = UDim2.fromScale(0.5, 0.5)
		emoji.Size = UDim2.fromScale(0.65, 0.65)
		emoji.TextXAlignment = Enum.TextXAlignment.Center
	end
	frame.Parent = parent
	return frame
end

-- Кнопка под маскотом: взять/убрать, купить ($ или R$) или как получить
local function actionButton(cell: Frame, mascot: Mascots.Mascot)
	local state = MascotShop.state
	local owned = state.owned[mascot.id] == true
	local text: string
	local color: Color3
	local dark = false
	local onClick: () -> () = function() end
	if owned and state.equipped == mascot.id then
		text, color = ClientState.t("mascots_equipped"), Ui.colors.good
		onClick = function()
			MascotRemotes.EquipMascot:FireServer(nil)
		end
	elseif owned then
		text, color = ClientState.t("mascots_equip"), Ui.colors.primary
		onClick = function()
			MascotRemotes.EquipMascot:FireServer(mascot.id)
		end
	elseif mascot.how == "cash" then
		local cost = mascot.cost or 0
		local data = ClientState.data
		local canPay = data ~= nil and (tonumber(data.cash) or 0) >= cost
		text = Texts.money(cost)
		color = if canPay then Ui.colors.money else Ui.colors.locked
		dark = true
		onClick = function()
			if canPay then
				MascotRemotes.BuyMascot:FireServer(mascot.id)
			end
		end
	elseif mascot.how == "robux" then
		local soon = mascot.productId == 0
		text = if soon
			then ClientState.t("shop_soon")
			else ClientState.t("shop_robux", { price = mascot.robuxPrice or 0 })
		color = if soon then Ui.colors.locked else Ui.colors.good
		onClick = function()
			if not soon then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, mascot.productId)
			end
		end
	elseif mascot.how == "achievement" then
		local a = mascot.achievement and Achievements.find(mascot.achievement)
		local achName = if a then ClientState.localText("ach_" .. a.id, a.name, a.nameEn) else "?"
		text, color = ClientState.t("mascots_achievement", { name = achName }), Ui.colors.locked
	elseif mascot.how == "group" then
		text, color = ClientState.t("mascots_group"), Ui.colors.locked
	else
		text, color = ClientState.t("shop_soon"), Ui.colors.locked
	end
	local b = Ui.button(cell, text, color, onClick)
	if dark then
		b.TextColor3 = if color == Ui.colors.money then Color3.fromRGB(40, 30, 0) else Ui.colors.muted
	end
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, -6)
	b.Size = UDim2.new(1, -12, 0, BUTTON_HEIGHT)
end

local function cellFor(parent: Instance, mascot: Mascots.Mascot, order: number)
	local rarityColor = Mascots.rarityColors[mascot.rarity]
	local cell = Instance.new("Frame")
	cell.LayoutOrder = order
	cell.BackgroundColor3 = if mascot.rarity == "legendary"
		then Color3.fromRGB(66, 56, 36)
		elseif mascot.rarity == "epic" then Color3.fromRGB(58, 44, 82)
		else Color3.fromRGB(44, 46, 66)
	Ui.corner(cell, 10)
	if MascotShop.state.equipped == mascot.id then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Ui.colors.good
		stroke.Parent = cell
	end
	local i = icon(cell, mascot)
	i.AnchorPoint = Vector2.new(0.5, 0)
	i.Position = UDim2.new(0.5, 0, 0, 8)
	local y = ICON + 12
	local name = Ui.label(cell, MascotShop.name(mascot), 34, Enum.Font.GothamMedium)
	name.Position = UDim2.fromOffset(6, y)
	name.Size = UDim2.new(1, -12, 0, 36)
	name.TextWrapped = true
	name.TextXAlignment = Enum.TextXAlignment.Center
	local rarity = Ui.label(cell, ClientState.t("mascot_rarity_" .. mascot.rarity), 18, nil, rarityColor)
	rarity.Position = UDim2.fromOffset(6, y + 38)
	rarity.Size = UDim2.new(1, -12, 0, 18)
	rarity.TextXAlignment = Enum.TextXAlignment.Center
	local bonus = Ui.label(cell, MascotShop.bonusText(mascot), 36, Enum.Font.GothamMedium, Ui.colors.muted)
	bonus.Position = UDim2.fromOffset(6, y + 58)
	bonus.Size = UDim2.new(1, -12, 0, 38)
	bonus.TextWrapped = true
	bonus.TextXAlignment = Enum.TextXAlignment.Center
	actionButton(cell, mascot)
	-- Маскота за Robux можно подарить другому игроку на сервере
	local gift = if mascot.how == "robux" then Social.giftFor("mascot", mascot.id) else nil
	if gift then
		GiftPicker.button(cell, gift, MascotShop.name(mascot), 8 + ICON)
	end
	cell.Parent = parent
end

-- Вкладка магазина в body (ScrollingFrame с UIListLayout окна магазина)
function MascotShop.build(body: Instance)
	local hint = Ui.label(body, ClientState.t("mascots_hint"), 22, Enum.Font.GothamMedium, Ui.colors.muted)
	hint.LayoutOrder = 0
	local grid = Instance.new("Frame")
	grid.LayoutOrder = 1
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, -8, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL.X, CELL.Y)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for i, mascot in Mascots.list do
		cellFor(grid, mascot, i)
	end
	grid.Parent = body
end

-- Свежее состояние с сервера (при открытии магазина)
function MascotShop.request()
	MascotRemotes.MascotStateRequest:FireServer()
end

function MascotShop.listen(changed: () -> ())
	table.insert(listeners, changed)
end

MascotRemotes.MascotState.OnClientEvent:Connect(function(newState: any)
	if type(newState) ~= "table" or type(newState.owned) ~= "table" then
		return
	end
	MascotShop.state = {
		owned = newState.owned,
		equipped = if type(newState.equipped) == "string" then newState.equipped else nil,
	}
	for _, changed in listeners do
		changed()
	end
end)

return MascotShop
