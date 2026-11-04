--!strict
-- Подарки на клиенте: кнопка «🎁 Подарить» на премиум-скинах и премиум-постерах (SkinShop,
-- PosterShop) и окно выбора получателя из игроков на сервере. Выбор уходит на сервер
-- (GiftSelect) — GiftService проверяет и сам открывает окно покупки Roblox.
-- Себе подарить нельзя: себя в списке нет, сервер тоже проверяет.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Social = require(Shared.Config.Social)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local ROW_HEIGHT = 48
local GIFT_COLOR = Color3.fromRGB(214, 92, 168)

local GiftPicker = {}
local gui: ScreenGui? = nil
local connections: { RBXScriptConnection } = {}

local function close()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if gui then
		gui:Destroy()
		gui = nil
	end
end

-- Remotes берём при нажатии: если серверный модуль упал, магазин всё равно открывается
local function sendChoice(gift: Social.Gift, userId: number)
	local SocialRemotes = require(Shared.SocialRemotes) :: any
	SocialRemotes.GiftSelect:FireServer(gift.id, userId)
end

local function render(gift: Social.Gift, itemName: string)
	local screen = gui
	if not screen then
		return
	end
	local old = screen:FindFirstChild("Window")
	if old then
		old:Destroy()
	end
	local window = Ui.window(screen, "Window", Vector2.new(460, 440))
	local title = Ui.label(
		window,
		ClientState.t("gift_title", { item = itemName }),
		30,
		Ui.titleFontFor(ClientState.lang)
	)
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.new(1, -80, 0, 30)
	local closeButton = Ui.button(window, "×", Ui.colors.bad, close)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 8)
	closeButton.Size = UDim2.fromOffset(40, 40)

	local body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(16, 60)
	body.Size = UDim2.new(1, -32, 1, -76)
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 6
	Ui.list(body, 8)
	body.Parent = window

	local me = Players.LocalPlayer
	local any = false
	for i, other in Players:GetPlayers() do
		if other == me then
			continue
		end
		any = true
		local crown = if other:GetAttribute("IsVip") == true then "👑 " else ""
		local b = Ui.button(
			body,
			crown .. other.DisplayName .. " (@" .. other.Name .. ")",
			GIFT_COLOR,
			function()
				sendChoice(gift, other.UserId)
				close()
			end
		)
		b.LayoutOrder = i
		b.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	end
	if not any then
		local none = Ui.label(body, ClientState.t("gift_nobody"), 24, nil, Ui.colors.muted)
		none.TextWrapped = true
	end
end

function GiftPicker.open(gift: Social.Gift, itemName: string)
	close()
	local screen = Instance.new("ScreenGui")
	screen.Name = "GiftPicker"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20 -- над магазином (10)
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	render(gift, itemName)
	-- Кто-то зашёл или вышел, пока окно открыто
	local function rerender()
		task.defer(render, gift, itemName)
	end
	table.insert(connections, Players.PlayerAdded:Connect(rerender))
	table.insert(connections, Players.PlayerRemoving:Connect(rerender))
end

-- Кнопка «🎁 Подарить» поверх низа превью карточки (bottomY — низ превью в px от верха ячейки).
-- productId 0 — подарок ещё не создан: кнопка серая и не нажимается
function GiftPicker.button(cell: Frame, gift: Social.Gift, itemName: string, bottomY: number)
	local soon = gift.productId == 0
	local b = Ui.button(
		cell,
		ClientState.t("gift_button"),
		if soon then Ui.colors.locked else GIFT_COLOR,
		function()
			if not soon then
				GiftPicker.open(gift, itemName)
			end
		end
	)
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 0, bottomY - 4)
	b.Size = UDim2.new(1, -28, 0, 30)
	b.ZIndex = 3
	return b
end

return GiftPicker
