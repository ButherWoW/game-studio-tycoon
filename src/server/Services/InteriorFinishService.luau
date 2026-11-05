--!strict
-- Отделка студии (Config/InteriorFinishes, наборы Астры assets/models/astra-interior-*):
-- пол, стены, окна и свет оболочек этапов. Отдельно от стиля мебели (FurnitureStyleService):
-- смена отделки не трогает profile.furniture, а смена стиля — profile.interior.
-- Премиум-отделки — только за Robux: квитанцию принимает MonetizationService и зовёт grantProduct
-- (эффект в профиле, сохраняет MonetizationService до PurchaseGranted). Выбор открытой — бесплатно.
-- Модели подменяет PlotService (StyleModels.find по InteriorFinishes.SHELLS), потолок этажей —
-- OfficeFloors; смена отделки пересобирает участок (PlotService.rebuild, как у стиля мебели).
-- Косметика: на доход, мебель, сотрудников и этажи не влияет. Rebirth не сбрасывает.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local InteriorFinishes = require(Shared.Config.InteriorFinishes)
local StyleRemotes = require(Shared.StyleRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StyleModels = require(script.Parent.StyleModels)

-- Смена отделки пересобирает весь участок: не чаще раза в SELECT_COOLDOWN секунд
local SELECT_COOLDOWN = 2
local STATE_REQUEST_COOLDOWN = 1

local InteriorFinishService = {}
local lastSelect: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}

local function pushState(player: Player)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	local finishes = StyleModels.finishData(profile)
	StyleRemotes.FinishState:FireClient(player, { owned = finishes.owned, selected = finishes.selected })
end

local function logFinish(player: Player, finishId: string)
	local analytics = script.Parent:FindFirstChild("AnalyticsService")
	if analytics and analytics:IsA("ModuleScript") then
		pcall((require(analytics) :: any).logInteriorFinish, player, finishId)
	end
end

-- Поставить отделку и пересобрать участок (без гаража оболочек нет — только запомнить)
local function apply(player: Player, profile: DataService.Profile, finishId: string)
	local finishes = StyleModels.finishData(profile)
	if finishes.selected == finishId then
		pushState(player)
		return
	end
	finishes.selected = finishId
	pushState(player)
	if PlotService.ownsGarage(player) then
		PlotService.rebuild(player)
	end
end

-- Отделка за Robux (зовёт MonetizationService.ProcessReceipt). false — это не отделка.
-- Повторная выдача безопасна: отделка просто остаётся открытой. Купленную сразу ставим
function InteriorFinishService.grantProduct(
	player: Player,
	profile: DataService.Profile,
	productId: number
): boolean
	local finish = InteriorFinishes.findByProduct(productId)
	if not finish then
		return false
	end
	StyleModels.finishData(profile).owned[finish.id] = true
	logFinish(player, finish.id)
	-- Пересборка участка — не внутри ProcessReceipt: квитанцию подтверждаем без задержки
	task.defer(function()
		if player.Parent and DataService.get(player) == profile then
			lastSelect[player] = os.clock()
			apply(player, profile, finish.id)
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

local function onSelect(player: Player, finishId: any)
	local finish = InteriorFinishes.get(finishId)
	local profile = DataService.get(player)
	if not finish or not profile then
		return
	end
	if throttled(lastSelect, player, SELECT_COOLDOWN) then
		-- Клиент мог уже перерисовать выбор: вернём правду
		pushState(player)
		return
	end
	if not StyleModels.finishData(profile).owned[finish.id] then
		return
	end
	apply(player, profile, finish.id)
end

local function onStateRequest(player: Player)
	if throttled(lastRequest, player, STATE_REQUEST_COOLDOWN) then
		return
	end
	pushState(player)
end

function InteriorFinishService.start()
	StyleRemotes.SelectFinish.OnServerEvent:Connect(onSelect)
	StyleRemotes.FinishStateRequest.OnServerEvent:Connect(onStateRequest)
	DataService.onProfileLoaded(function(player: Player, profile: DataService.Profile)
		StyleModels.finishData(profile)
		pushState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSelect[player] = nil
		lastRequest[player] = nil
	end)
end

return InteriorFinishService
