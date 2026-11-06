--!strict
-- Вкладка «Постеры» окна магазина (ShopWindow): сетка постеров с превью, цена ($ или R$),
-- «Повесить» и выбор места на стене. Что куплено и где висит, решает сервер (PosterService);
-- за Robux клиент только открывает окно покупки Roblox. productId 0 — кнопка «Скоро».

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local PosterRemotes = require(Shared.PosterRemotes)
local Posters = require(Shared.Config.Posters)
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
	equipped: { [string]: string },
	slots: { string },
}

local CELL = Vector2.new(152, 292)
local PREVIEW = Vector2.new(120, 160) -- 3:4, как картинка 768×1024
local BUTTON_HEIGHT = 40

local PosterShop = {}
local state: State = { owned = {}, equipped = {}, slots = {} }
local picking: string? = nil -- постер, для которого выбираем место
local onChanged: () -> () = function() end

local function posterName(poster: Posters.Poster): string
	return ClientState.localText("poster_" .. poster.id, poster.name, poster.nameEn)
end

-- На каком месте висит постер (nil — не висит)
local function slotOf(posterId: string): string?
	for slotId, id in state.equipped do
		if id == posterId then
			return slotId
		end
	end
	return nil
end

-- Превью: картинка, если загружена, иначе цвет, эмодзи и название (как на стене)
local function preview(parent: Instance, poster: Posters.Poster, size: Vector2): Frame
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundColor3 = poster.background
	frame.BorderSizePixel = 0
	Ui.corner(frame, 6)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = if poster.premium then 3 else 2
	stroke.Color = if poster.premium then poster.accent else Color3.fromRGB(20, 20, 26)
	stroke.Parent = frame

	local imageId = Images.posters[poster.id] or 0
	if imageId > 0 then
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Crop
		image.Image = "rbxassetid://" .. imageId
		Ui.corner(image, 6)
		image.Parent = frame
	else
		if poster.premium then
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = 90
			gradient.Color = ColorSequence.new(poster.background:Lerp(poster.accent, 0.35), poster.background)
			gradient.Parent = frame
		end
		local emoji = Ui.label(frame, poster.emoji, size.Y * 0.5)
		emoji.Position = UDim2.fromScale(0.1, 0.08)
		emoji.Size = UDim2.fromScale(0.8, 0.55)
		emoji.TextXAlignment = Enum.TextXAlignment.Center
		local title = Ui.label(frame, poster.title, size.Y * 0.2, Ui.titleFont, poster.accent)
		title.Position = UDim2.fromScale(0.06, 0.68)
		title.Size = UDim2.fromScale(0.88, 0.26)
		title.TextXAlignment = Enum.TextXAlignment.Center
		title.TextWrapped = true
		title.TextStrokeTransparency = 0.5
	end
	if poster.premium then
		local badge = Ui.label(frame, "✨", 26)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -2, 0, 2)
		badge.Size = UDim2.fromOffset(26, 26)
		badge.TextXAlignment = Enum.TextXAlignment.Center
	end
	frame.Parent = parent
	return frame
end

-- Кнопка под постером: купить ($ или R$), «Повесить» или «✓ Висит»
local function actionButton(cell: Frame, poster: Posters.Poster)
	local owned = state.owned[poster.id] == true
	local text: string
	local color: Color3
	local onClick: () -> ()
	if owned then
		local hung = slotOf(poster.id) ~= nil
		text = ClientState.t(if hung then "posters_hung" else "posters_hang")
		color = if hung then Ui.colors.locked else Ui.colors.primary
		onClick = function()
			picking = poster.id
			onChanged()
		end
	elseif poster.premium then
		local soon = poster.productId == 0
		text = if soon
			then ClientState.t("shop_soon")
			else ClientState.t(
				"shop_robux",
				{ price = RobuxPrice.of(poster.productId, poster.robuxPrice) }
			)
		color = if soon then Ui.colors.locked else Ui.colors.good
		onClick = function()
			if not soon then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, poster.productId)
			end
		end
	else
		local cost = poster.cost or 0
		local data = ClientState.data
		local canPay = data ~= nil and (tonumber(data.cash) or 0) >= cost
		text = Texts.money(cost)
		color = if canPay then Ui.colors.money else Ui.colors.locked
		onClick = function()
			if canPay then
				PosterRemotes.BuyPoster:FireServer(poster.id)
			end
		end
	end
	local b = Ui.button(cell, text, color, onClick)
	if not owned and not poster.premium then
		b.TextColor3 = if color == Ui.colors.money then Color3.fromRGB(40, 30, 0) else Ui.colors.muted
	end
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, -6)
	b.Size = UDim2.new(1, -12, 0, BUTTON_HEIGHT)
end

local function cellFor(parent: Instance, poster: Posters.Poster, order: number)
	local cell = Instance.new("Frame")
	cell.LayoutOrder = order
	cell.BackgroundColor3 = if poster.premium then Color3.fromRGB(58, 44, 82) else Color3.fromRGB(44, 46, 66)
	Ui.corner(cell, 10)
	local p = preview(cell, poster, PREVIEW)
	p.AnchorPoint = Vector2.new(0.5, 0)
	p.Position = UDim2.new(0.5, 0, 0, 8)
	local name = Ui.label(cell, posterName(poster), 36, Enum.Font.GothamMedium)
	name.Position = UDim2.fromOffset(6, PREVIEW.Y + 14)
	name.Size = UDim2.new(1, -12, 0, 40)
	name.TextWrapped = true
	name.TextXAlignment = Enum.TextXAlignment.Center
	-- Характеристика постера (Config/Posters.stat): «⭐ +0.05 к оценке», «💰 +1% к доходу», «😊 +2 настроения»
	local stat = poster.stat
	local value = if stat.kind == "revenue"
		then tostring(math.floor(stat.value * 100 + 0.5))
		elseif stat.kind == "review" then string.format("%.2f", stat.value)
		else tostring(math.floor(stat.value))
	local statLabel = Ui.label(
		cell,
		ClientState.t("poster_stat_" .. stat.kind, { value = value }),
		20,
		Enum.Font.GothamMedium,
		Ui.colors.money
	)
	statLabel.Position = UDim2.fromOffset(6, PREVIEW.Y + 56)
	statLabel.Size = UDim2.new(1, -12, 0, 22)
	statLabel.TextXAlignment = Enum.TextXAlignment.Center
	actionButton(cell, poster)
	-- Премиум-постер можно подарить другому игроку на сервере
	local gift = if poster.premium then Social.giftFor("poster", poster.id) else nil
	if gift then
		GiftPicker.button(cell, gift, posterName(poster), 8 + PREVIEW.Y)
	end
	cell.Parent = parent
end

-- Выбор места для постера picking: кнопки «Место N» (с эмодзи того, что там висит), «Снять», «Отмена»
local function slotPicker(body: Instance, posterId: string)
	local poster = Posters.get(posterId)
	if not poster then
		picking = nil
		return
	end
	local panel = Instance.new("Frame")
	panel.LayoutOrder = 1
	panel.BackgroundColor3 = Color3.fromRGB(52, 56, 84)
	panel.Size = UDim2.new(1, -8, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	Ui.corner(panel, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = panel
	Ui.list(panel, 8)

	local title =
		Ui.label(panel, ClientState.t("posters_pick", { name = posterName(poster) }), 28, Ui.titleFont)
	title.LayoutOrder = 1

	local grid = Instance.new("Frame")
	grid.LayoutOrder = 2
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(142, 44)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	grid.Parent = panel

	local current = slotOf(posterId)
	for i, slotId in state.slots do
		local occupant = Posters.get(state.equipped[slotId])
		local text = ClientState.t("posters_slot", { n = i })
		if occupant then
			text ..= " " .. occupant.emoji
		end
		local b = Ui.button(
			grid,
			text,
			if slotId == current then Ui.colors.good else Ui.colors.primary,
			function()
				picking = nil
				PosterRemotes.EquipPoster:FireServer(slotId, posterId)
				onChanged()
			end
		)
		b.LayoutOrder = i
	end
	if current then
		local remove = Ui.button(grid, ClientState.t("posters_remove"), Ui.colors.bad, function()
			picking = nil
			PosterRemotes.EquipPoster:FireServer(current, nil)
			onChanged()
		end)
		remove.LayoutOrder = #state.slots + 1
	end
	local cancel = Ui.button(grid, ClientState.t("posters_cancel"), Ui.colors.locked, function()
		picking = nil
		onChanged()
	end)
	cancel.LayoutOrder = #state.slots + 2
	panel.Parent = body
end

-- Содержимое вкладки в body (ScrollingFrame с UIListLayout окна магазина)
function PosterShop.build(body: Instance)
	local hint = Ui.label(
		body,
		ClientState.t(if #state.slots > 0 then "posters_hint" else "posters_no_slots"),
		22,
		Enum.Font.GothamMedium,
		Ui.colors.muted
	)
	hint.LayoutOrder = 0
	ContentDropClient.nextLine(body, 0)
	if picking and #state.slots > 0 then
		slotPicker(body, picking)
	end

	local grid = Instance.new("Frame")
	grid.LayoutOrder = 2
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, -8, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL.X, CELL.Y)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for i, poster in Posters.list do
		-- График контента: невышедшие постеры не показываем (купленные — всегда)
		if state.owned[poster.id] == true or ContentDropClient.isReleased("poster", poster.id) then
			cellFor(grid, poster, i)
		end
	end
	grid.Parent = body
end

-- Свежее состояние с сервера (при открытии магазина)
function PosterShop.request()
	PosterRemotes.PosterStateRequest:FireServer()
end

-- Подписка один раз из ShopWindow.start: changed — перерисовать окно
function PosterShop.listen(changed: () -> ())
	onChanged = changed
	PosterRemotes.PosterState.OnClientEvent:Connect(function(newState: any)
		if
			type(newState) ~= "table"
			or type(newState.owned) ~= "table"
			or type(newState.equipped) ~= "table"
			or type(newState.slots) ~= "table"
		then
			return
		end
		state = newState
		changed()
	end)
end

return PosterShop
