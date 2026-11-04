--!strict
-- Настроение команды (Config/Mood): цель из удобств, постеров, декора, тесноты и забастовки;
-- текущее значение плавно идёт к цели раз в Mood.tickSeconds. Без сотрудников значение сразу
-- равно цели и ни на что не влияет (соло в гараже). Клиенту — атрибут игрока TeamMood
-- (nil — сотрудников нет), разбор по причинам — в StudioState (DecorService).
-- Данные: (profile :: any).mood = { value: number, aftermath: number } — aftermath — «осадок»
-- после забастовки, тает со временем.
-- Для других сервисов: speedMultiplier(player) — во сколько раз быстрее разработка (DevelopmentService
-- делит на него время), reviewBonus(player) — прибавка к оценке, breakdown(player) — для окна.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Mood = require(Shared.Config.Mood)
local Decor = require(Shared.Config.Decor)
local Posters = require(Shared.Config.Posters)
local Employees = require(Shared.Config.Employees)
local StudioLayout = require(Shared.StudioLayout)
local DataService = require(script.Parent.DataService)

export type Part = { key: string, value: number, vars: { [string]: any }? }
export type Breakdown = {
	value: number,
	target: number,
	staff: number,
	active: boolean, -- есть сотрудники: настроение действует
	speed: number,
	review: number,
	parts: { Part },
}

local MoodService = {}
local changedEvent = Instance.new("BindableEvent")
-- Разбор настроения игрока поменялся (DecorService пересылает окно «Студия»)
MoodService.changed = changedEvent.Event
local lastSignature: { [Player]: string } = {}
-- Временные поправки цели (найм, увольнение): не сохраняются, живут seconds секунд
type Temporary = { key: string, value: number, expires: number }
local temporary: { [Player]: { Temporary } } = {}

-- Действующие поправки игрока (просроченные выбрасываем)
local function activeTemporary(player: Player?): { Temporary }
	local list = player and temporary[player]
	if not list then
		return {}
	end
	local now = os.clock()
	for i = #list, 1, -1 do
		if list[i].expires <= now then
			table.remove(list, i)
		end
	end
	return list
end

type MoodData = { value: number, aftermath: number }

local function moodData(profile: DataService.Profile): MoodData
	local p = profile :: any
	local raw = p.mood
	if type(raw) ~= "table" then
		raw = {}
		p.mood = raw
	end
	-- Правим на месте: tick держит ссылку на эту таблицу и между вызовами compute()
	-- (новая таблица теряла бы записанное значение — отчёт #4, P1-1). −1 — «ещё не считали»
	local value = tonumber(raw.value)
	raw.value = if value and value == value and value >= 0 then math.clamp(value, Mood.min, Mood.max) else -1
	local aftermath = tonumber(raw.aftermath) or 0
	raw.aftermath = if aftermath == aftermath then math.clamp(aftermath, 0, Mood.strikeAftermath) else 0
	return raw :: MoodData
end

-- Нанятые сотрудники (и те, кто ждёт стол): StaffService хранит profile.staff
local function headcount(profile: DataService.Profile): number
	local staff = (profile :: any).staff
	local count = 0
	if type(staff) == "table" then
		for employeeId in staff do
			if Employees.get(employeeId) then
				count += 1
			end
		end
	end
	return count
end

-- Постеры, которые висят на стенах сейчас (PosterService чистит profile.posters)
local function posterPoints(profile: DataService.Profile): number
	local posters = (profile :: any).posters
	local equipped = type(posters) == "table" and posters.equipped
	local total = 0
	if type(equipped) == "table" then
		for slotId, posterId in equipped do
			local slot = Posters.getSlot(slotId)
			local poster = Posters.get(posterId)
			if slot and poster and Posters.slotVisible(slot, profile.studioLevel) then
				total += if poster.premium then Mood.posterPremium else Mood.posterCash
			end
		end
	end
	return math.min(total, Mood.posterCap)
end

function MoodService.decorOwned(profile: DataService.Profile): { [string]: boolean }
	local decor = (profile :: any).decor
	local owned = type(decor) == "table" and decor.owned
	return if type(owned) == "table" then owned else {}
end

-- Цель и из чего она сложилась
local function compute(profile: DataService.Profile, player: Player?): ({ Part }, number, number)
	local parts: { Part } = { { key = "mood_part_base", value = Mood.base } }
	local amenities = 0
	for id, points in Mood.upgrades do
		local upgrade = StudioLayout.get(id)
		if upgrade and profile.upgrades[id] and StudioLayout.isVisible(upgrade, profile.studioLevel) then
			amenities += points
		end
	end
	if amenities > 0 then
		table.insert(parts, { key = "mood_part_amenities", value = amenities })
	end
	local posters = posterPoints(profile)
	if posters > 0 then
		table.insert(parts, { key = "mood_part_posters", value = posters })
	end
	local placed = Decor.placed(MoodService.decorOwned(profile), profile.studioLevel)
	local decorPoints = 0
	for _, entry in placed do
		decorPoints += entry.item.mood
	end
	if decorPoints > 0 then
		table.insert(parts, { key = "mood_part_decor", value = decorPoints, vars = { count = #placed } })
	end
	local staff = headcount(profile)
	local comfort = Mood.comfortBase + Mood.comfortPerDecor * #placed
	local crowded = math.max(staff - comfort, 0)
	if crowded > 0 then
		local penalty = math.min(crowded * Mood.crowdingPerEmployee, Mood.crowdingCap)
		table.insert(parts, { key = "mood_part_crowding", value = -penalty, vars = { count = crowded } })
	end
	local data = moodData(profile)
	if (profile :: any).staffStrike == true then
		table.insert(parts, { key = "mood_part_strike", value = -Mood.strikePenalty })
	end
	local aftermath = math.floor(data.aftermath + 0.5)
	-- Во время забастовки осадок не показываем отдельно: он начнёт таять, когда заплатят
	if aftermath > 0 and (profile :: any).staffStrike ~= true then
		table.insert(parts, { key = "mood_part_aftermath", value = -aftermath })
	end
	-- Временные события команды (Config/Mood.newcomer / fired): одинаковые складываются в одну строку
	local sums: { [string]: number } = {}
	local order: { string } = {}
	for _, entry in activeTemporary(player) do
		if sums[entry.key] == nil then
			sums[entry.key] = 0
			table.insert(order, entry.key)
		end
		sums[entry.key] += entry.value
	end
	for _, key in order do
		table.insert(parts, { key = key, value = sums[key] })
	end
	local target = 0
	for _, part in parts do
		target += part.value
	end
	return parts, math.clamp(target, Mood.min, Mood.max), staff
end

local function publish(player: Player, profile: DataService.Profile, staff: number)
	local data = moodData(profile)
	player:SetAttribute("TeamMood", if staff > 0 then math.floor(data.value + 0.5) else nil)
end

local function tick(player: Player, profile: DataService.Profile, dt: number)
	local data = moodData(profile)
	local strike = (profile :: any).staffStrike == true
	if strike then
		data.aftermath = Mood.strikeAftermath
	else
		data.aftermath = math.max(data.aftermath - Mood.aftermathDecayPerMinute * dt / 60, 0)
	end
	local parts, target, staff = compute(profile, player)
	if staff == 0 or data.value < 0 then
		-- Нет команды (или первый вход): нанятый сотрудник придёт в уже сложившуюся атмосферу
		data.value = target
	elseif data.value < target then
		data.value = math.min(data.value + Mood.risePerMinute * dt / 60, target)
	elseif data.value > target then
		data.value = math.max(data.value - Mood.fallPerMinute * dt / 60, target)
	end
	publish(player, profile, staff)
	-- Окно «Студия» пересылаем, только когда видимое (округлённое) поменялось
	local signature = `{math.floor(data.value + 0.5)}:{target}:{staff}`
	for _, part in parts do
		signature ..= ":" .. part.key .. "=" .. part.value
	end
	if lastSignature[player] ~= signature then
		lastSignature[player] = signature
		changedEvent:Fire(player)
	end
end

local function active(profile: DataService.Profile): boolean
	return headcount(profile) > 0
end

-- Множитель скорости разработки (1 — без сотрудников)
function MoodService.speedMultiplier(player: Player): number
	local profile = DataService.get(player)
	if not profile or not active(profile) then
		return 1
	end
	local data = moodData(profile)
	return if data.value >= 0 then Mood.speedMultiplier(data.value) else 1
end

-- Прибавка к оценке игры (0 — без сотрудников или настроение обычное)
function MoodService.reviewBonus(player: Player): number
	local profile = DataService.get(player)
	if not profile or not active(profile) then
		return 0
	end
	local data = moodData(profile)
	return if data.value >= 0 then Mood.reviewBonus(data.value) else 0
end

function MoodService.breakdown(player: Player): Breakdown?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local parts, target, staff = compute(profile, player)
	local data = moodData(profile)
	local value = if data.value >= 0 then data.value else target
	return {
		value = math.floor(value + 0.5),
		target = target,
		staff = staff,
		active = staff > 0,
		speed = Mood.speedMultiplier(value),
		review = Mood.reviewBonus(value),
		parts = parts,
	}
end

-- Пересчитать сразу (купили декор, повесили постер) — без ожидания тика
function MoodService.refresh(player: Player)
	local profile = DataService.get(player)
	if profile then
		tick(player, profile, 0)
	end
end

-- Временное событие команды: сразу сдвигает настроение на value и держит поправку цели
-- seconds секунд (key — текст строки в разборе, mood_part_*). Без сотрудников ничего не делает.
-- noShift — только поправка цели, без сдвига (вернуть после перезахода: значение уже сохранено)
function MoodService.addTemporary(
	player: Player,
	key: string,
	value: number,
	seconds: number,
	noShift: boolean?
)
	local profile = DataService.get(player)
	if not profile or not active(profile) then
		return
	end
	local list = temporary[player] or {}
	temporary[player] = list
	table.insert(list, { key = key, value = value, expires = os.clock() + seconds })
	local data = moodData(profile)
	if data.value >= 0 and not noShift then
		data.value = math.clamp(data.value + value, Mood.min, Mood.max)
	end
	tick(player, profile, 0)
end

function MoodService.start()
	DataService.onProfileLoaded(function(player: Player, profile: DataService.Profile)
		tick(player, profile, 0)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSignature[player] = nil
		temporary[player] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Mood.tickSeconds)
			local now = os.clock()
			local dt = math.min(now - last, Mood.tickSeconds * 4)
			last = now
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile then
					local ok, err = pcall(tick, player, profile, dt)
					if not ok then
						warn("[MoodService] tick failed:", err)
					end
				end
			end
		end
	end)
end

return MoodService
