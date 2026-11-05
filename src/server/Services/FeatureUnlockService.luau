--!strict
-- Постепенное открытие систем (Config/Unlocks) на сервере: помнит, какие системы игрок уже видел
-- открытыми (profile.features.seen), и отдаёт клиенту атрибутом FeaturesSeen ("id,id,...").
-- Старые сохранения (features.init = false, уже есть выпущенные игры) при первой загрузке
-- размечаются «видел всё»: у тестеров ничего не пропадает и нет пачки тостов «🆕 Открыто».
-- Решает, показывать ли кнопку, клиент (FeatureGate); сервер проверяет только то, что влияет
-- на других игроков (обмен — TradeService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Unlocks = require(ReplicatedStorage.Shared.Config.Unlocks)
local FeatureRemotes = require(ReplicatedStorage.Shared.FeatureRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local MAX_IDS = 64 -- больше систем за один запрос не бывает

local FeatureUnlockService = {}

type State = { seen: { [string]: boolean }, init: boolean }

local function stateOf(profile: DataService.Profile): State
	local raw: any = (profile :: any).features
	if type(raw) ~= "table" then
		raw = { seen = {}, init = false }
		profile.features = raw
	end
	if type(raw.seen) ~= "table" then
		raw.seen = {}
	end
	raw.init = raw.init == true
	return raw
end

local function progressOf(player: Player, profile: DataService.Profile): Unlocks.Progress
	return {
		ownsGarage = PlotService.ownsGarage(player),
		studioLevel = tonumber(profile.studioLevel) or 1,
		gamesReleased = tonumber(profile.gamesReleased) or 0,
		hitsReleased = tonumber(profile.hitsReleased) or 0,
		rebirths = tonumber(profile.rebirths) or 0,
	}
end

local function publish(player: Player, state: State)
	local ids = {}
	for id, value in state.seen do
		if value == true and Unlocks.features[id] then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	player:SetAttribute(Unlocks.SEEN_ATTRIBUTE, table.concat(ids, ","))
end

-- Открыта ли система игроку: условия выполнены сейчас или уже открывалась раньше
function FeatureUnlockService.isOpen(player: Player, id: string): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	if stateOf(profile).seen[id] == true then
		return true
	end
	return Unlocks.meets(id, progressOf(player, profile))
end

local function onLoaded(player: Player, profile: DataService.Profile)
	local state = stateOf(profile)
	if not state.init then
		-- Сохранение до онбординга (уже выпускал игры): всё как было — открыто и без тостов.
		-- Новый профиль (0 игр): видел только то, что открыто по условиям (в парке — ничего)
		local progress = progressOf(player, profile)
		local veteran = progress.gamesReleased > 0
		for id in Unlocks.features do
			if veteran or Unlocks.meets(id, progress) then
				state.seen[id] = true
			end
		end
		state.init = true
	end
	publish(player, state)
end

local function onSeen(player: Player, ids: any)
	if type(ids) ~= "table" then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local state = stateOf(profile)
	local progress = progressOf(player, profile)
	local changed = false
	local count = 0
	for _, id in ids do
		count += 1
		if count > MAX_IDS then
			break
		end
		if
			type(id) == "string"
			and Unlocks.features[id]
			and not state.seen[id]
			and Unlocks.meets(id, progress)
		then
			state.seen[id] = true
			changed = true
		end
	end
	if changed then
		publish(player, state)
	end
end

function FeatureUnlockService.start()
	FeatureRemotes.FeatureSeen.OnServerEvent:Connect(onSeen)
	DataService.onProfileLoaded(onLoaded)
end

return FeatureUnlockService
