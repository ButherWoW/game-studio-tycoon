--!strict
-- Декор студии (Config/Decor) и окно «Студия»: покупка декора на этаж, модели на участке,
-- снимок для окна (декор, настроение из MoodService, интерьер этажей из PlotService.studioOffers).
-- PlotService.rebuild сносит все модели участка — декор ставим заново по plotChanged (как постеры).
-- Данные: profile.decor = { owned = { ["<id>@<этаж>"]: true } }. Rebirth декор не трогает:
-- после него виден декор 1-го этажа (в гараже, на гаражных местах), верхние — с этажами.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local Decor = require(Shared.Config.Decor)
local Stages = require(Shared.Config.Stages)
local DecorRemotes = require(Shared.DecorRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local MoodService = require(script.Parent.MoodService)
local ModelFactory = require(script.Parent.ModelFactory)
local StyleModels = require(script.Parent.StyleModels)

local MODEL_NAME = "PlayerDecor"
local FLOOR_LEVEL = 0.5 -- пол участка над его центром (как y = 0.5 в Config/Upgrades)
local ACTION_COOLDOWN = 0.25
local STATE_REQUEST_COOLDOWN = 1

local DecorService = {}
local lastAction: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
local generated: { [string]: Model } = {}

-- Поле профиля в порядке: старые сохранения без него, мусор, удалённые из Config предметы
local function owned(profile: DataService.Profile): { [string]: boolean }
	local raw = (profile :: any).decor
	local clean: { [string]: boolean } = {}
	if type(raw) == "table" and type(raw.owned) == "table" then
		for key, value in raw.owned do
			local item, floor = Decor.parseKey(key)
			if value == true and item and floor then
				clean[Decor.key(item.id, floor)] = true
			end
		end
	end
	(profile :: any).decor = { owned = clean }
	return clean
end

-- Шаблон: импортированная модель из ServerStorage.Upgrades (Астра) в стиле мебели игрока
-- (Plant_Cozy, StyleModels), иначе классика, иначе из деталей (ModelFactory)
local function template(item: Decor.Item, profile: DataService.Profile): (Model?, boolean)
	local folder = ServerStorage:FindFirstChild("Upgrades")
	local imported = StyleModels.find(folder, item.model, profile)
	if imported and imported:IsA("Model") and imported:GetAttribute("Generated") ~= true then
		return imported, true
	end
	local cached = generated[item.model]
	if not cached then
		cached = ModelFactory.build(item.model)
		if not cached then
			warn("[DecorService] Missing model", item.model)
			return nil, false
		end
		generated[item.model] = cached
	end
	return cached, false
end

-- Снести и заново поставить декор игрока на его участке
local function place(player: Player)
	local plot = PlotService.getPlot(player)
	if not plot then
		return
	end
	local old = plot:FindFirstChild(MODEL_NAME)
	if old then
		old:Destroy()
	end
	local profile = DataService.get(player)
	if not profile or not PlotService.ownsGarage(player) then
		return
	end
	local container = Instance.new("Model")
	container.Name = MODEL_NAME
	for _, entry in Decor.placed(owned(profile), profile.studioLevel) do
		local source, imported = template(entry.item, profile)
		if not source then
			continue
		end
		local model = source:Clone()
		model.Name = entry.item.id .. "_" .. entry.floor
		if imported and entry.item.importScale then
			model:ScaleTo(model:GetScale() * entry.item.importScale)
		end
		local stage = Stages[entry.stage]
		local y = FLOOR_LEVEL + (if stage then stage.floorY else 0) + (entry.slot.y or 0)
		model:PivotTo(
			plot.CFrame
				* CFrame.new(entry.slot.x, y, entry.slot.z)
				* CFrame.Angles(0, math.rad(entry.slot.rotation), 0)
		)
		model:SetAttribute("DecorId", entry.item.id)
		model.Parent = container
	end
	container.Parent = plot
end

local function pushState(player: Player)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	local okOffers, offers = pcall(PlotService.studioOffers, player)
	DecorRemotes.StudioState:FireClient(player, {
		owned = owned(profile),
		floorsOpen = Decor.floorsOpen(profile.studioLevel),
		studioLevel = profile.studioLevel,
		ownsGarage = PlotService.ownsGarage(player),
		mood = MoodService.breakdown(player),
		offers = if okOffers then offers else {},
	})
end

local function throttled(map: { [Player]: number }, player: Player, seconds: number): boolean
	local now = os.clock()
	if (map[player] or 0) + seconds > now then
		return true
	end
	map[player] = now
	return false
end

local function onBuy(player: Player, itemId: any, floor: any)
	if throttled(lastAction, player, ACTION_COOLDOWN) then
		return
	end
	local item = Decor.get(itemId)
	local profile = DataService.get(player)
	if not item or not profile or not PlotService.ownsGarage(player) or not PlotService.getPlot(player) then
		return
	end
	if
		type(floor) ~= "number"
		or floor % 1 ~= 0
		or floor < 1
		or floor > Decor.floorsOpen(profile.studioLevel)
	then
		return
	end
	-- Места для этого этажа нет — не продаём
	if not item.slots[Decor.stageFor(floor, profile.studioLevel)] then
		return
	end
	local list = owned(profile)
	local key = Decor.key(item.id, floor)
	if list[key] then
		return
	end
	if DataService.trySpend(player, Decor.cost(item, floor)) then
		list[key] = true
		place(player)
		MoodService.refresh(player)
		pushState(player)
	end
end

local function onStateRequest(player: Player)
	if throttled(lastRequest, player, STATE_REQUEST_COOLDOWN) then
		return
	end
	pushState(player)
end

function DecorService.start()
	DecorRemotes.BuyDecor.OnServerEvent:Connect(onBuy)
	DecorRemotes.StudioStateRequest.OnServerEvent:Connect(onStateRequest)
	-- Участок собран заново (вход, переезд, Rebirth, покупка интерьера) — декор и места этапа
	PlotService.plotChanged:Connect(function(player: Player)
		place(player)
		MoodService.refresh(player)
		pushState(player)
	end)
	MoodService.changed:Connect(pushState)
	DataService.onProfileLoaded(function(player: Player, profile: DataService.Profile)
		owned(profile)
		pushState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		lastRequest[player] = nil
	end)
end

return DecorService
