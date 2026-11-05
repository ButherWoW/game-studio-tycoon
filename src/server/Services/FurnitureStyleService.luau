--!strict
-- Стили мебели (Config/FurnitureStyles, docs/VISUAL.md V15): покупка и выбор стиля студии.
-- За $ — BuyStyle; за Robux — квитанцию принимает MonetizationService и зовёт grantProduct
-- (эффект в профиле, сохраняет MonetizationService до PurchaseGranted). Выбор открытого — бесплатно.
-- Модели подменяют те, кто их ставит (StyleModels.find); смена стиля пересобирает участок
-- (PlotService.rebuild -> plotChanged: декор, полка хитов, VIP-кресло, сотрудники встают заново).
-- Косметика: бонусов нет. Данные: profile.furniture (StyleModels.data), Rebirth не сбрасывает.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local FurnitureStyles = require(Shared.Config.FurnitureStyles)
local StyleRemotes = require(Shared.StyleRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StyleModels = require(script.Parent.StyleModels)

local BUY_COOLDOWN = 0.25
-- Смена стиля пересобирает весь участок: не чаще раза в SELECT_COOLDOWN секунд
local SELECT_COOLDOWN = 2
local STATE_REQUEST_COOLDOWN = 1

local FurnitureStyleService = {}
local lastBuy: { [Player]: number } = {}
local lastSelect: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}

local function pushState(player: Player)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	local styles = StyleModels.data(profile)
	StyleRemotes.StyleState:FireClient(player, { owned = styles.owned, selected = styles.selected })
end

local function logStyle(player: Player, styleId: string, how: string)
	local analytics = script.Parent:FindFirstChild("AnalyticsService")
	if analytics and analytics:IsA("ModuleScript") then
		pcall((require(analytics) :: any).logFurnitureStyle, player, styleId, how)
	end
end

-- Поставить стиль и пересобрать участок (без гаража мебели нет — только запомнить)
local function apply(player: Player, profile: DataService.Profile, styleId: string)
	local styles = StyleModels.data(profile)
	if styles.selected == styleId then
		pushState(player)
		return
	end
	styles.selected = styleId
	pushState(player)
	if PlotService.ownsGarage(player) then
		PlotService.rebuild(player)
	end
end

-- Стиль за Robux (зовёт MonetizationService.ProcessReceipt). false — это не стиль.
-- Повторная выдача безопасна: стиль просто остаётся открытым. Купленный сразу ставим
function FurnitureStyleService.grantProduct(
	player: Player,
	profile: DataService.Profile,
	productId: number
): boolean
	local style = FurnitureStyles.findByProduct(productId)
	if not style then
		return false
	end
	StyleModels.data(profile).owned[style.id] = true
	logStyle(player, style.id, "robux")
	-- Пересборка участка — не внутри ProcessReceipt: квитанцию подтверждаем без задержки
	task.defer(function()
		if player.Parent and DataService.get(player) == profile then
			apply(player, profile, style.id)
		end
	end)
	return true
end

local function throttled(map: { [Player]: number }, player: Player, cooldown: number): boolean
	local now = os.clock()
	if (map[player] or 0) + cooldown > now then
		return true
	end
	map[player] = now
	return false
end

local function onBuy(player: Player, styleId: any)
	if throttled(lastBuy, player, BUY_COOLDOWN) then
		return
	end
	local style = FurnitureStyles.get(styleId)
	local profile = DataService.get(player)
	-- За Robux за $ не продаётся; открытый второй раз не продаём
	if not style or not profile or FurnitureStyles.isPremium(style) then
		return
	end
	local cost = style.cost
	local styles = StyleModels.data(profile)
	if type(cost) ~= "number" or cost < 0 or styles.owned[style.id] then
		return
	end
	if DataService.trySpend(player, cost) then
		styles.owned[style.id] = true
		logStyle(player, style.id, "cash")
		-- Купил — значит хочет увидеть: ставим сразу (лимит выбора не тратим)
		lastSelect[player] = os.clock()
		apply(player, profile, style.id)
		-- Крупная покупка — сохраняем сразу, не ждём автосейва
		task.spawn(DataService.save, player)
	end
end

local function onSelect(player: Player, styleId: any)
	local style = FurnitureStyles.get(styleId)
	local profile = DataService.get(player)
	if not style or not profile then
		return
	end
	if throttled(lastSelect, player, SELECT_COOLDOWN) then
		-- Клиент мог уже перерисовать выбор: вернём правду
		pushState(player)
		return
	end
	if not StyleModels.data(profile).owned[style.id] then
		return
	end
	apply(player, profile, style.id)
end

local function onStateRequest(player: Player)
	if throttled(lastRequest, player, STATE_REQUEST_COOLDOWN) then
		return
	end
	pushState(player)
end

function FurnitureStyleService.start()
	StyleRemotes.BuyStyle.OnServerEvent:Connect(onBuy)
	StyleRemotes.SelectStyle.OnServerEvent:Connect(onSelect)
	StyleRemotes.StyleStateRequest.OnServerEvent:Connect(onStateRequest)
	DataService.onProfileLoaded(function(player: Player, profile: DataService.Profile)
		StyleModels.data(profile)
		pushState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastBuy[player] = nil
		lastSelect[player] = nil
		lastRequest[player] = nil
	end)
end

return FurnitureStyleService
