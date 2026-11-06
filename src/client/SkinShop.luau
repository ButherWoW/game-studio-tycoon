--!strict
-- Скины сотрудников на клиенте: вкладка «👕 Скины» окна магазина (ShopWindow) и выбор скина
-- в карточке сотрудника (TeamWindow). Что открыто и кто что носит, решает сервер (SkinService);
-- за Robux клиент только открывает окно покупки Roblox. productId 0 — кнопка «Скоро».

local GroupService = game:GetService("GroupService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local SkinRemotes = require(Shared.SkinRemotes)
local Skins = require(Shared.Config.Skins)
local Images = require(Shared.Config.Images)
local Texts = require(Shared.Config.Texts)
local Social = require(Shared.Config.Social)
local ClientState = require(script.Parent.ClientState)
local RobuxPrice = require(script.Parent.RobuxPrice)
local Ui = require(script.Parent.Ui)
local GiftPicker = require(script.Parent.GiftPicker)
local ContentDropClient = require(script.Parent.ContentDropClient)

type State = {
	owned: { [string]: boolean },
	assigned: { [string]: string },
}

local CELL = Vector2.new(152, 236)
local PREVIEW = 128 -- квадрат, как превью 512×512
local BUTTON_HEIGHT = 40
local PICK_HEIGHT = 44

local SkinShop = {}
SkinShop.state = { owned = {}, assigned = {} } :: State
local listeners: { () -> () } = {}

function SkinShop.name(skin: Skins.Skin): string
	return ClientState.localText("skin_" .. skin.id, skin.name, skin.nameEn)
end

-- Скин сотрудника (nil — свой вид)
function SkinShop.skinOf(employeeId: string): Skins.Skin?
	return Skins.get(SkinShop.state.assigned[employeeId])
end

-- Превью: картинка, если загружена, иначе карточка цветами скина (верх — рубашка, низ — штаны) с эмодзи
local function preview(parent: Instance, skin: Skins.Skin, size: number): Frame
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundColor3 = skin.shirt
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	Ui.corner(frame, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = if skin.premium then 3 else 2
	stroke.Color = skin.accent
	stroke.Parent = frame

	local images = Images.skins[skin.id]
	local imageId = if images then images.preview else 0
	if imageId > 0 then
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = "rbxassetid://" .. imageId
		Ui.corner(image, 8)
		image.Parent = frame
	else
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, skin.shirt),
			ColorSequenceKeypoint.new(0.6, skin.shirt),
			ColorSequenceKeypoint.new(0.61, skin.pants),
			ColorSequenceKeypoint.new(1, skin.pants),
		})
		gradient.Parent = frame
		local emoji = Ui.label(frame, skin.emoji, size * 0.55)
		emoji.AnchorPoint = Vector2.new(0.5, 0.5)
		emoji.Position = UDim2.fromScale(0.5, 0.45)
		emoji.Size = UDim2.fromScale(0.6, 0.6)
		emoji.TextXAlignment = Enum.TextXAlignment.Center
	end
	if skin.premium then
		local badge = Ui.label(frame, "✨", 26)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -2, 0, 2)
		badge.Size = UDim2.fromOffset(26, 26)
		badge.TextXAlignment = Enum.TextXAlignment.Center
	end
	frame.Parent = parent
	return frame
end

-- Кнопка под скином: купить ($ или R$) или «✓ Открыт»
local function actionButton(cell: Frame, skin: Skins.Skin)
	local owned = SkinShop.state.owned[skin.id] == true
	local text: string
	local color: Color3
	local onClick: () -> ()
	-- График контента: ещё не вышел — тизер «Скоро: через N дн.» без покупки
	local teaser = ContentDropClient.teaser("skin", skin.id, owned)
	if owned then
		text, color = ClientState.t("skins_owned"), Ui.colors.good
		onClick = function() end
	elseif teaser then
		text, color = teaser, Ui.colors.locked
		onClick = function() end
	elseif skin.premium then
		local soon = skin.productId == 0
		text = if soon
			then ClientState.t("shop_soon")
			else ClientState.t("shop_robux", { price = RobuxPrice.of(skin.productId, skin.robuxPrice) })
		color = if soon then Ui.colors.locked else Ui.colors.good
		onClick = function()
			if not soon then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, skin.productId)
			end
		end
	else
		local cost = skin.cost or 0
		local data = ClientState.data
		local canPay = data ~= nil and (tonumber(data.cash) or 0) >= cost
		text = Texts.money(cost)
		color = if canPay then Ui.colors.money else Ui.colors.locked
		onClick = function()
			if canPay then
				SkinRemotes.BuySkin:FireServer(skin.id)
			end
		end
	end
	local b = Ui.button(cell, text, color, onClick)
	if not owned and not skin.premium and not teaser then
		b.TextColor3 = if color == Ui.colors.money then Color3.fromRGB(40, 30, 0) else Ui.colors.muted
	end
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, -6)
	b.Size = UDim2.new(1, -12, 0, BUTTON_HEIGHT)
end

local function cellFor(parent: Instance, skin: Skins.Skin, order: number)
	local cell = Instance.new("Frame")
	cell.LayoutOrder = order
	cell.BackgroundColor3 = if skin.premium then Color3.fromRGB(58, 44, 82) else Color3.fromRGB(44, 46, 66)
	Ui.corner(cell, 10)
	local p = preview(cell, skin, PREVIEW)
	p.AnchorPoint = Vector2.new(0.5, 0)
	p.Position = UDim2.new(0.5, 0, 0, 8)
	local name = Ui.label(cell, SkinShop.name(skin), 36, Enum.Font.GothamMedium)
	name.Position = UDim2.fromOffset(6, PREVIEW + 14)
	name.Size = UDim2.new(1, -12, 0, 40)
	name.TextWrapped = true
	name.TextXAlignment = Enum.TextXAlignment.Center
	actionButton(cell, skin)
	-- Премиум-скин можно подарить другому игроку на сервере
	local gift = if skin.premium and ContentDropClient.isReleased("skin", skin.id)
		then Social.giftFor("skin", skin.id)
		else nil
	if gift then
		GiftPicker.button(cell, gift, SkinShop.name(skin), 8 + PREVIEW)
	end
	cell.Parent = parent
end

-- Подсказка «Вступи в группу — получи скин» (Config/Social.groupId > 0, награда ещё не получена).
-- Есть баннер группы (Images.monetization.groupBanner, V14) — строка выше, баннер 2:1 слева
local GROUP_BANNER = 80
local function groupHint(body: Instance)
	local groupId = Social.groupId
	if groupId <= 0 or Players.LocalPlayer:GetAttribute("GroupRewarded") == true then
		return
	end
	local reward = Skins.get(Social.groupReward.skin)
	local frame = Instance.new("Frame")
	frame.LayoutOrder = -1
	frame.BackgroundColor3 = Color3.fromRGB(52, 56, 84)
	frame.Size = UDim2.new(1, -8, 0, 56)
	Ui.corner(frame, 10)
	local text = Ui.label(
		frame,
		ClientState.t("group_hint", { skin = if reward then SkinShop.name(reward) else "" }),
		24,
		Enum.Font.GothamMedium
	)
	text.AnchorPoint = Vector2.new(0, 0.5)
	text.Position = UDim2.new(0, 12, 0.5, 0)
	text.Size = UDim2.new(0.7, -16, 0, 24)
	local art = Ui.artImage(frame, Images.monetization.groupBanner, "left")
	if art then
		frame.Size = UDim2.new(1, -8, 0, GROUP_BANNER + 16)
		art.SizeConstraint = Enum.SizeConstraint.RelativeXY
		art.Size = UDim2.fromOffset(GROUP_BANNER * 2, GROUP_BANNER)
		art.Position = UDim2.new(0, 8, 0.5, 0)
		Ui.corner(art, 8)
		-- Текст в две строки справа от баннера
		local left = GROUP_BANNER * 2 + 20
		text.Text = Ui.stripIcon(text.Text, "👥")
		text.TextWrapped = true
		text.Position = UDim2.new(0, left, 0.5, 0)
		text.Size = UDim2.new(0.7, -left - 4, 0, 48)
	end
	local join = Ui.button(frame, ClientState.t("group_join"), Ui.colors.good, function()
		task.spawn(function()
			pcall(function()
				GroupService:PromptJoinAsync(groupId)
			end)
			-- Сервер перепроверит членство и выдаст награду (SocialService)
			local SocialRemotes = require(Shared.SocialRemotes) :: any
			SocialRemotes.GroupCheck:FireServer()
		end)
	end)
	join.AnchorPoint = Vector2.new(1, 0.5)
	join.Position = UDim2.new(1, -8, 0.5, 0)
	join.Size = UDim2.new(0.28, 0, 0, 44)
	frame.Parent = body
end

-- Вкладка магазина в body (ScrollingFrame с UIListLayout окна магазина)
function SkinShop.build(body: Instance)
	local hint = Ui.label(body, ClientState.t("skins_hint"), 22, Enum.Font.GothamMedium, Ui.colors.muted)
	hint.LayoutOrder = 0
	ContentDropClient.nextLine(body, 0)
	groupHint(body)

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
	for i, skin in Skins.list do
		-- Тизеры невышедших — в конце сетки
		local soon = ContentDropClient.teaser("skin", skin.id, SkinShop.state.owned[skin.id] == true) ~= nil
		cellFor(grid, skin, if soon then 1000 + i else i)
	end
	grid.Parent = body
end

-- Выбор скина в карточке сотрудника (TeamWindow): «Свой вид» + открытые скины
function SkinShop.buildPicker(parent: Instance, employeeId: string, order: number)
	local state = SkinShop.state
	local current = state.assigned[employeeId]
	local any = false
	for _, skin in Skins.list do
		if state.owned[skin.id] then
			any = true
			break
		end
	end
	if not any then
		local none = Ui.label(parent, ClientState.t("skins_none"), 22, nil, Ui.colors.muted)
		none.LayoutOrder = order
		return
	end
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = order
	local layout = Instance.new("UIGridLayout")
	-- Два столбца: на телефоне название скина читается
	layout.CellSize = UDim2.new(0.5, -6, 0, PICK_HEIGHT)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	grid.Parent = parent

	local function choice(text: string, skinId: string?, n: number, tint: Color3?)
		local selected = current == skinId
		local b = Ui.button(grid, text, if selected then Ui.colors.good else Ui.colors.primary, function()
			if not selected then
				SkinRemotes.AssignSkin:FireServer(employeeId, skinId)
			end
		end)
		b.LayoutOrder = n
		if tint then
			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Thickness = 2
			stroke.Color = tint
			stroke.Parent = b
		end
	end
	choice(ClientState.t("skins_default"), nil, 0, nil)
	for i, skin in Skins.list do
		if state.owned[skin.id] then
			choice(skin.emoji .. " " .. SkinShop.name(skin), skin.id, i, skin.accent)
		end
	end
end

-- Свежее состояние с сервера (при открытии магазина или команды)
function SkinShop.request()
	SkinRemotes.SkinStateRequest:FireServer()
end

-- Подписка окна (ShopWindow, TeamWindow): changed — перерисовать окно
function SkinShop.listen(changed: () -> ())
	table.insert(listeners, changed)
end

SkinRemotes.SkinState.OnClientEvent:Connect(function(newState: any)
	if type(newState) ~= "table" or type(newState.owned) ~= "table" or type(newState.assigned) ~= "table" then
		return
	end
	SkinShop.state = newState
	for _, changed in listeners do
		changed()
	end
end)

return SkinShop
