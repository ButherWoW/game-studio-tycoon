--!strict
-- Титулы над головой (роадмап 7.21, Config/Titles). Сервер открывает титулы по условиям
-- (достижения, Rebirth, гейм-джем, сезон, Roblox Premium) и проверяет выбор игрока.
-- Выбранный титул — атрибут игрока "Title" (id): табличку рисует каждый клиент сам
-- (TitleTags) — на языке смотрящего. Другие фичи выдают титулы через TitleService.grant.
-- profile.titles = { owned = { [id]: os.time }, selected = id?, expires = { [id]: os.time }?,
-- restore = id? } (формат чинит DataService). expires — временные титулы (блиц-джем, «Игра
-- недели»): grant с untilAt сразу надевает титул, а в untilAt он снимается и возвращается restore.
-- Атрибут "TitleUntil" — конец выбранного временного титула (TitleTags прячет табличку вовремя).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Titles = require(ReplicatedStorage.Shared.Config.Titles)
local TitleRemotes = require(ReplicatedStorage.Shared.TitleRemotes)
local DataService = require(script.Parent.DataService)

type TitleData = {
	owned: { [string]: number },
	selected: string?,
	expires: { [string]: number }?,
	restore: string?,
}

local SELECT_COOLDOWN = 1 -- секунд между сменами титула одного игрока
local REQUEST_COOLDOWN = 1
local ATTRIBUTE = "Title"
local UNTIL_ATTRIBUTE = "TitleUntil"

local TitleService = {}
local lastSelect: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}

local function dataOf(profile: DataService.Profile): TitleData
	local p = profile :: any
	if type(p.titles) ~= "table" then
		p.titles = { owned = {}, selected = nil }
	end
	if type(p.titles.owned) ~= "table" then
		p.titles.owned = {}
	end
	if p.titles.expires ~= nil and type(p.titles.expires) ~= "table" then
		p.titles.expires = nil
	end
	return p.titles :: TitleData
end

local function isPremium(player: Player): boolean
	return player.MembershipType == Enum.MembershipType.Premium
end

-- Постоянное условие выполнено по профилю (premium и grant сюда не входят)
local function earned(profile: DataService.Profile, title: Titles.Title): boolean
	local c = title.cond
	local p = profile :: any
	if c.achievement then
		local ach = p.achievements
		return type(ach) == "table" and type(ach.done) == "table" and ach.done[c.achievement] ~= nil
	elseif c.rebirths then
		return (tonumber(profile.rebirths) or 0) >= c.rebirths
	elseif c.jamFlag then
		local jam = p.gameJam
		return type(jam) == "table" and type(jam.flags) == "table" and jam.flags[c.jamFlag] == true
	elseif c.season then
		if type(p.seasonTitles) ~= "table" then
			return false
		end
		for _, value in p.seasonTitles do
			if value == true then
				return true
			end
		end
	end
	return false
end

-- Можно ли сейчас носить титул
local function available(player: Player, data: TitleData, title: Titles.Title): boolean
	if title.cond.premium then
		return isPremium(player)
	end
	return data.owned[title.id] ~= nil
end

local function applyAttribute(player: Player, data: TitleData)
	local selected = data.selected
	local title = if selected then Titles.byId[selected] else nil
	local show = if title and available(player, data, title) then title.id else nil
	if player:GetAttribute(ATTRIBUTE) ~= show then
		player:SetAttribute(ATTRIBUTE, show)
	end
	local expires = data.expires
	local untilAt = if show and expires then expires[show] else nil
	if player:GetAttribute(UNTIL_ATTRIBUTE) ~= untilAt then
		player:SetAttribute(UNTIL_ATTRIBUTE, untilAt)
	end
end

-- Самый поздний ещё действующий временный титул — его надеваем, когда снят другой
local function activeTimed(data: TitleData): string?
	local best: string? = nil
	local bestUntil = 0
	for id, untilAt in data.expires or {} do
		if untilAt > bestUntil and data.owned[id] ~= nil then
			best, bestUntil = id, untilAt
		end
	end
	return best
end

-- Снять истёкшие временные титулы. true — что-то изменилось
local function prune(data: TitleData): boolean
	local expires = data.expires
	if not expires then
		return false
	end
	local now = os.time()
	local changed = false
	for id, untilAt in expires do
		if type(untilAt) ~= "number" or untilAt <= now or not Titles.byId[id] then
			expires[id] = nil
			data.owned[id] = nil
			changed = true
		end
	end
	if changed then
		local selected = data.selected
		local title = if selected then Titles.byId[selected] else nil
		-- Сняли надетый временный: следующий действующий временный или прежний выбор игрока.
		-- Premium в owned не пишется — его выбор не трогаем
		if selected and data.owned[selected] == nil and not (title and title.cond.premium) then
			local nextTimed = activeTimed(data)
			if nextTimed then
				data.selected = nextTimed
			else
				data.selected = data.restore
				data.restore = nil
			end
		end
	end
	if next(expires) == nil then
		data.expires = nil
		data.restore = nil
	end
	return changed
end

local function sendState(player: Player, data: TitleData, new: { string }?)
	local owned = {}
	for _, title in Titles.list do
		if available(player, data, title) then
			owned[title.id] = true
		end
	end
	TitleRemotes.TitleState:FireClient(player, {
		owned = owned,
		selected = data.selected,
		expires = data.expires, -- окно 🏆 показывает, сколько ещё действует временный титул
		new = if new and #new > 0 then new else nil,
	})
end

-- Перепроверить условия; announce — прислать клиенту тост о новых
function TitleService.refresh(player: Player, announce: boolean?)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	local data = dataOf(profile)
	local pruned = prune(data)
	local new: { string } = {}
	for _, title in Titles.list do
		if data.owned[title.id] == nil and not title.cond.premium and earned(profile, title) then
			data.owned[title.id] = os.time()
			table.insert(new, title.id)
		end
	end
	applyAttribute(player, data)
	if #new > 0 or announce == nil or pruned then
		sendState(player, data, if announce then new else nil)
	end
end

-- Выдать титул из другой фичи (ежедневные события, сейф и т.п.). true — выдан сейчас.
-- untilAt (os.time) — временный титул: сразу надевается, в untilAt снимается (прежний выбор
-- возвращается). Повторная выдача уже действующего временного титула только продлевает его
function TitleService.grant(player: Player, titleId: string, untilAt: number?): boolean
	local profile = DataService.get(player)
	if type(titleId) ~= "string" or not Titles.byId[titleId] or not profile then
		return false
	end
	local data = dataOf(profile)
	prune(data)
	local had = data.owned[titleId] ~= nil
	local expires = data.expires
	if untilAt == nil then
		-- Постоянный: временный того же id становится постоянным
		if had and not (expires and expires[titleId]) then
			return false
		end
		if expires then
			expires[titleId] = nil
		end
	else
		if untilAt <= os.time() or (had and not (expires and expires[titleId])) then
			return false -- уже истёк или титул и так постоянный
		end
		if had and expires and expires[titleId] >= math.floor(untilAt) then
			return false -- уже действует не меньше: ничего не меняем и не шлём
		end
		local list = expires or {}
		data.expires = list
		list[titleId] = math.max(list[titleId] or 0, math.floor(untilAt))
		if not had and data.selected ~= titleId then
			-- Запоминаем постоянный выбор игрока, чтобы вернуть его после всех временных
			local selected = data.selected
			if not (selected and list[selected]) then
				data.restore = selected
			end
			data.selected = titleId
		end
	end
	data.owned[titleId] = data.owned[titleId] or os.time()
	applyAttribute(player, data)
	sendState(player, data, if had then nil else { titleId })
	return not had
end

function TitleService.owns(player: Player, titleId: string): boolean
	local profile = DataService.get(player)
	local title = Titles.byId[titleId]
	return profile ~= nil and title ~= nil and available(player, dataOf(profile), title)
end

local function onSelect(player: Player, titleId: any)
	if type(titleId) ~= "string" or #titleId > 64 then
		return
	end
	local now = os.clock()
	if (lastSelect[player] or 0) + SELECT_COOLDOWN > now then
		return
	end
	lastSelect[player] = now
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = dataOf(profile)
	-- Игрок сам выбрал: после временных титулов возвращать прежний выбор уже не нужно
	data.restore = nil
	if titleId == "" then
		data.selected = nil
	else
		local title = Titles.byId[titleId]
		if not title or not available(player, data, title) then
			sendState(player, data)
			return
		end
		data.selected = titleId
	end
	applyAttribute(player, data)
	sendState(player, data)
end

function TitleService.start()
	TitleRemotes.SelectTitle.OnServerEvent:Connect(onSelect)
	TitleRemotes.RequestTitles.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
			return
		end
		lastRequest[player] = now
		TitleService.refresh(player)
	end)
	-- Первый вход: титулы за уже полученные достижения — без тоста
	DataService.onProfileLoaded(function(player)
		TitleService.refresh(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSelect[player] = nil
		lastRequest[player] = nil
	end)
	-- Достижения, джем и сезон пишут в профиль сами: опрос дешёвый (только сравнения)
	task.spawn(function()
		while true do
			task.wait(Titles.checkSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(TitleService.refresh, player, true)
				if not ok then
					warn("[TitleService] refresh failed:", err)
				end
			end
		end
	end)
end

return TitleService
