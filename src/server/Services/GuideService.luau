--!strict
-- Обучение по ходу игры (Config/Guides) на сервере: помнит, какие карточки «Как это работает»
-- игрок уже прочитал (profile.guides.seen), и отдаёт клиенту атрибутом GuidesSeen ("id,id,...").
-- Когда и какую карточку показать, решает клиент (GuideController) — карточки ни на что не влияют,
-- сервер только проверяет id и хранит.
-- Старое сохранение (guides.init = false, уже есть выпущенные игры): авто-карточки (when)
-- помечаются прочитанными — у игравших до обновления не выскакивает пачка подсказок про давно
-- знакомое; карточки к кнопкам меню они увидят при первом нажатии, это не мешает.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Guides = require(ReplicatedStorage.Shared.Config.Guides)
local GuideRemotes = require(ReplicatedStorage.Shared.GuideRemotes)
local DataService = require(script.Parent.DataService)

local GuideService = {}

type State = { seen: { [string]: boolean }, init: boolean }

local function stateOf(profile: DataService.Profile): State
	local raw: any = (profile :: any).guides
	if type(raw) ~= "table" then
		raw = { seen = {}, init = false }
		profile.guides = raw
	end
	if type(raw.seen) ~= "table" then
		raw.seen = {}
	end
	raw.init = raw.init == true
	return raw
end

local function publish(player: Player, state: State)
	local ids = {}
	for id, value in state.seen do
		if value == true and Guides.get(id) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	player:SetAttribute(Guides.SEEN_ATTRIBUTE, table.concat(ids, ","))
end

local function onLoaded(player: Player, profile: DataService.Profile)
	local state = stateOf(profile)
	if not state.init then
		if (tonumber(profile.gamesReleased) or 0) > 0 then
			for _, guide in Guides.list do
				if guide.when then
					state.seen[guide.id] = true
				end
			end
		end
		state.init = true
	end
	publish(player, state)
end

local function onSeen(player: Player, id: any)
	if type(id) ~= "string" or not Guides.get(id) then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local state = stateOf(profile)
	if state.seen[id] then
		return
	end
	state.seen[id] = true
	publish(player, state)
end

function GuideService.start()
	GuideRemotes.GuideSeen.OnServerEvent:Connect(onSeen)
	DataService.onProfileLoaded(onLoaded)
end

return GuideService
