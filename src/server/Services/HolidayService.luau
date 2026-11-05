--!strict
-- Праздничные ивенты (шаг 4.9, issue #10): Хэллоуин, Новый год, летние каникулы.
-- Активный ивент — по дате UTC (Config/Holidays), в Studio можно включить studioForce.
-- Что делает сервис (всё на сервере, клиент только показывает):
--   * атрибуты ReplicatedStorage HolidayId / HolidayEndsAt — для плашки и кнопки меню;
--   * бонусы для DevelopmentService: HolidayService.reviewBonus / revenueMultiplier
--     (подключаются одной строкой через optional("HolidayService") — см. PR);
--   * сезонные темы (Config/Topics.seasonal): открыты во время своего ивента, потом забираются;
--   * декор (тыквы, ёлка) в workspace.HolidayDecor — строится при старте ивента, снимается после;
--   * квест ивента — раз за сезон; прогресс — по счётчику релизов QuestService
--     (profile.quests.comboGames), поэтому отдельный хук релиза не нужен;
--   * календарь подарков — один подарок в день UTC, раз за сезон каждый.
-- Профиль: profile.holidays = { quests = { [season] }, calendar = { [season] }, cosmetics = { [id] } }
-- (ленивая инициализация, defaultProfile не трогаем).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Holidays = require(ReplicatedStorage.Shared.Config.Holidays)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local HolidayRemotes = require(ReplicatedStorage.Shared.HolidayRemotes)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local ModelFactory = require(script.Parent.ModelFactory)

local DAY_SECONDS = 86_400
local CLAIM_COOLDOWN = 0.5
local REQUEST_COOLDOWN = 1
local FORCED_DAYS = 7 -- studioForce: сколько дней «длится» ивент (только для таймера)

type Active = { holiday: Holidays.Holiday, season: string, endsAt: number }
type QuestProgress = { progress: number, seen: number, claimed: boolean }
type CalendarProgress = { count: number, lastDay: number }
type HolidayData = {
	quests: { [string]: QuestProgress },
	calendar: { [string]: CalendarProgress },
	cosmetics: { [string]: boolean },
}

local HolidayService = {}

local active: Active? = nil
local decorBuiltFor: string? = nil
local lastSignature: { [Player]: string } = {}
local lastAction: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
local signs: { [number]: { model: Model, plot: string } } = {}

local isStudio = RunService:IsStudio()

-- ===== Дата и активный ивент =====

local function startOfDayUtc(year: number, month: number, day: number): number
	return DateTime.fromUniversalTime(year, month, day).UnixTimestamp
end

local function detect(now: number): Active?
	local date = os.date("!*t", now)
	local year, month, day = date.year, date.month, date.day
	if isStudio and Holidays.studioForce then
		local holiday = Holidays.find(Holidays.studioForce)
		if holiday then
			return {
				holiday = holiday,
				season = holiday.id .. "-" .. year,
				endsAt = startOfDayUtc(year, month, day) + FORCED_DAYS * DAY_SECONDS,
			}
		end
	end
	local today = month * 100 + day
	for _, holiday in Holidays.list do
		local from = holiday.from.month * 100 + holiday.from.day
		local to = holiday.to.month * 100 + holiday.to.day
		local startYear: number? = nil
		if from <= to then
			if today >= from and today <= to then
				startYear = year
			end
		elseif today >= from then
			startYear = year
		elseif today <= to then
			startYear = year - 1 -- январская часть ивента, начавшегося в декабре
		end
		if startYear then
			local endYear = if from <= to then startYear else startYear + 1
			return {
				holiday = holiday,
				season = holiday.id .. "-" .. startYear,
				endsAt = startOfDayUtc(endYear, holiday.to.month, holiday.to.day) + DAY_SECONDS,
			}
		end
	end
	return nil
end

-- «День» календаря подарков: сутки UTC (в Studio — Holidays.studioDaySeconds)
local function dayLength(): number
	return if isStudio and Holidays.studioDaySeconds then Holidays.studioDaySeconds else DAY_SECONDS
end

local function dayNumber(): number
	return os.time() // dayLength()
end

-- ===== Бонусы для DevelopmentService =====

function HolidayService.current(): string?
	return if active then active.holiday.id else nil
end

-- Прибавка к оценке за праздничное сочетание (0, если ивента нет)
function HolidayService.reviewBonus(genreId: string, topicId: string): number
	local a = active
	local holiday = a and a.holiday
	if not holiday or not holiday.reviewBonus then
		return 0
	end
	local genreHit = holiday.bonusGenres ~= nil and table.find(holiday.bonusGenres, genreId) ~= nil
	local topicHit = holiday.bonusTopics ~= nil and table.find(holiday.bonusTopics, topicId) ~= nil
	return if genreHit or topicHit then holiday.reviewBonus else 0
end

-- Множитель дохода релиза (1, если ивента нет или жанр не праздничный)
function HolidayService.revenueMultiplier(genreId: string): number
	local a = active
	local holiday = a and a.holiday
	if not holiday or not holiday.revenueMultiplier or not holiday.revenueGenres then
		return 1
	end
	return if table.find(holiday.revenueGenres, genreId) then holiday.revenueMultiplier else 1
end

-- ===== Профиль =====

local function holidayData(profile: DataService.Profile): HolidayData
	local p = profile :: any
	local d = p.holidays
	if type(d) ~= "table" then
		d = {}
		p.holidays = d
	end
	for _, key in { "quests", "calendar", "cosmetics" } do
		if type(d[key]) ~= "table" then
			d[key] = {}
		end
	end
	return d :: HolidayData
end

-- Релизы, подходящие под квест: из счётчика сочетаний QuestService ("genre/topic" -> игр)
local function matchingReleases(profile: DataService.Profile, quest: Holidays.HolidayQuest): number
	local q = (profile :: any).quests
	local combos = if type(q) == "table" then q.comboGames else nil
	if type(combos) ~= "table" then
		return 0
	end
	local total = 0
	for key, count in combos do
		if type(key) ~= "string" or type(count) ~= "number" then
			continue
		end
		local genreId, topicId = string.match(key, "^([^/]+)/(.+)$")
		if not genreId then
			continue
		end
		local hit = (quest.genres ~= nil and table.find(quest.genres, genreId) ~= nil)
			or (quest.topics ~= nil and table.find(quest.topics, topicId) ~= nil)
		if hit then
			total += count
		end
	end
	return total
end

local function questProgress(profile: DataService.Profile, a: Active): QuestProgress?
	local quest = a.holiday.quest
	if not quest then
		return nil
	end
	local data = holidayData(profile)
	local entry = data.quests[a.season]
	local current = matchingReleases(profile, quest)
	if type(entry) ~= "table" then
		-- Игры, выпущенные до первого захода в этом сезоне, не считаются
		entry = { progress = 0, seen = current, claimed = false }
		data.quests[a.season] = entry
	end
	entry.progress = tonumber(entry.progress) or 0
	entry.seen = tonumber(entry.seen) or current
	entry.claimed = entry.claimed == true
	-- Считаем только прирост: счётчик QuestService мог сброситься — тогда просто догоняем
	if current > entry.seen then
		entry.progress = math.min(entry.progress + (current - entry.seen), quest.target)
	end
	entry.seen = current
	return entry
end

local function calendarProgress(profile: DataService.Profile, a: Active): CalendarProgress?
	if not a.holiday.calendar then
		return nil
	end
	local data = holidayData(profile)
	local entry = data.calendar[a.season]
	if type(entry) ~= "table" then
		entry = { count = 0, lastDay = -1 }
		data.calendar[a.season] = entry
	end
	entry.count = math.max(math.floor(tonumber(entry.count) or 0), 0)
	entry.lastDay = tonumber(entry.lastDay) or -1
	return entry
end

-- Записи прошлых сезонов больше не нужны (ключ с годом не повторится)
local function pruneOldSeasons(profile: DataService.Profile, a: Active)
	local data = holidayData(profile)
	for season in data.quests do
		if season ~= a.season then
			data.quests[season] = nil
		end
	end
	for season in data.calendar do
		if season ~= a.season then
			data.calendar[season] = nil
		end
	end
end

-- Сезонные темы: открыты только во время своего ивента (в том числе после Rebirth)
local function syncTopics(player: Player, profile: DataService.Profile)
	local activeId = HolidayService.current()
	local changed = false
	for id, topic in Topics do
		if topic.seasonal then
			local should = topic.seasonal == activeId
			if (profile.unlockedTopics[id] == true) ~= should then
				profile.unlockedTopics[id] = if should then true else nil
				changed = true
			end
		end
	end
	if changed then
		DataService.replicate(player)
	end
end

-- ===== Состояние для клиента =====

local function sendState(player: Player, force: boolean?)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local a = active
	local data = holidayData(profile)
	local state: { [string]: any } = { cosmetics = data.cosmetics }
	local parts = {}
	if a then
		state.id = a.holiday.id
		state.endsAt = a.endsAt
		table.insert(parts, a.season)
		local quest = questProgress(profile, a)
		if quest and a.holiday.quest then
			state.quest =
				{ progress = quest.progress, target = a.holiday.quest.target, claimed = quest.claimed }
			table.insert(parts, quest.progress .. (if quest.claimed then "+" else "-"))
		end
		local calendar = calendarProgress(profile, a)
		local gifts = a.holiday.calendar
		if calendar and gifts then
			local today = dayNumber()
			state.calendar = {
				count = calendar.count,
				total = #gifts,
				available = calendar.count < #gifts and calendar.lastDay ~= today,
				nextDayAt = (today + 1) * dayLength(),
			}
			table.insert(parts, calendar.count .. "/" .. today .. "/" .. calendar.lastDay)
		end
	end
	for id in data.cosmetics do
		table.insert(parts, id)
	end
	local signature = table.concat(parts, ",")
	if not force and lastSignature[player] == signature then
		return
	end
	lastSignature[player] = signature
	HolidayRemotes.HolidayState:FireClient(player, state)
end

-- ===== Награды =====

local function throttled(player: Player): boolean
	local now = os.clock()
	if (lastAction[player] or 0) + CLAIM_COOLDOWN > now then
		return true
	end
	lastAction[player] = now
	return false
end

local function onClaimQuest(player: Player)
	if throttled(player) then
		return
	end
	local profile = DataService.get(player)
	local a = active
	if not profile or not a or not a.holiday.quest then
		return
	end
	local quest = a.holiday.quest
	local entry = questProgress(profile, a)
	if not entry or entry.claimed or entry.progress < quest.target then
		return
	end
	-- Флаг ставим до выдачи: всё синхронно, повторный запрос не пройдёт
	entry.claimed = true
	if quest.cosmetic then
		holidayData(profile).cosmetics[quest.cosmetic] = true
	end
	RewardService.grant(player, quest.reward)
	sendState(player, true)
end

local function onClaimGift(player: Player)
	if throttled(player) then
		return
	end
	local profile = DataService.get(player)
	local a = active
	local gifts = a and a.holiday.calendar
	if not profile or not a or not gifts then
		return
	end
	local entry = calendarProgress(profile, a)
	local today = dayNumber()
	if not entry or entry.count >= #gifts or entry.lastDay == today then
		return
	end
	entry.count += 1
	entry.lastDay = today
	RewardService.grant(player, gifts[entry.count])
	sendState(player, true)
end

-- ===== Декор =====

local function spawnCenter(): Vector3
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	return if spawn and spawn:IsA("BasePart")
		then Vector3.new(spawn.Position.X, 0, spawn.Position.Z)
		else Vector3.zero
end

-- Декор не мешает ходить и кликать: без столкновений и лучей
local function ghost(model: Model)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
end

-- Модель Астры из ServerStorage.Upgrades (импорт в Studio), иначе запасная из ModelFactory
local function buildModel(name: string): Model?
	local upgrades = ServerStorage:FindFirstChild("Upgrades")
	local template = if upgrades then upgrades:FindFirstChild(name) else nil
	if template and template:IsA("Model") then
		return template:Clone()
	end
	return ModelFactory.build(name)
end

local function placeModel(name: string, cframe: CFrame, parent: Instance, scale: number?): Model?
	local model = buildModel(name)
	if not model then
		return nil
	end
	if scale then
		model:ScaleTo(scale)
	end
	ghost(model)
	model:PivotTo(cframe)
	model.Parent = parent
	return model
end

-- Точка на земле вокруг спавна, «лицом» (+Z модели) к спавну
local function aroundSpawn(center: Vector3, angleDeg: number, radius: number): CFrame
	local angle = math.rad(angleDeg)
	local pos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	return CFrame.lookAt(pos, center) * CFrame.Angles(0, math.pi, 0)
end

local function plotParts(): { BasePart }
	local list = {}
	local folder = workspace:FindFirstChild("Plots")
	if folder then
		for _, plot in folder:GetChildren() do
			if plot:IsA("BasePart") then
				table.insert(list, plot)
			end
		end
	end
	return list
end

local function rebuildDecor(kind: string?)
	local old = workspace:FindFirstChild("HolidayDecor")
	if old then
		old:Destroy()
	end
	decorBuiltFor = kind
	if not kind then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "HolidayDecor"
	local center = spawnCenter()
	if kind == "pumpkins" then
		-- Кольцо тыкв у спавна (между скамейками парка) и по две у переднего края участков,
		-- снаружи участка: там не мешают постройкам и кнопкам покупки
		for i = 1, 6 do
			placeModel("Pumpkin", aroundSpawn(center, i * 60 + 15, 8), folder)
		end
		for _, plot in plotParts() do
			for _, side in { -1, 1 } do
				local offset =
					CFrame.new(side * (plot.Size.X / 2 - 1.5), -plot.Size.Y / 2, plot.Size.Z / 2 + 3)
				placeModel("Pumpkin", plot.CFrame * offset, folder, 1.3)
			end
		end
	elseif kind == "tree" then
		placeModel("HolidayTree", aroundSpawn(center, 30, 17), folder, 1.5)
	end
	folder.Parent = workspace
end

-- Косметика за квест Хэллоуина: вывеска у переднего края участка владельца (навсегда)
local function syncSigns()
	local cosmeticsFolder = workspace:FindFirstChild("HolidayCosmetics")
	local present: { [number]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local profile = DataService.get(player)
		local plotName = player:GetAttribute("PlotName")
		local plotsFolder = workspace:FindFirstChild("Plots")
		local plot = if type(plotName) == "string" and plotsFolder
			then plotsFolder:FindFirstChild(plotName)
			else nil
		local owns = profile ~= nil and holidayData(profile).cosmetics.halloween_sign == true
		local existing = signs[player.UserId]
		if existing and (not owns or not plot or existing.plot ~= plotName or not existing.model.Parent) then
			existing.model:Destroy()
			signs[player.UserId] = nil
			existing = nil
		end
		if owns and plot and plot:IsA("BasePart") and not existing then
			if not cosmeticsFolder then
				local newFolder = Instance.new("Folder")
				newFolder.Name = "HolidayCosmetics"
				newFolder.Parent = workspace
				cosmeticsFolder = newFolder
			end
			local cf = plot.CFrame * CFrame.new(-(plot.Size.X / 2 - 7), -plot.Size.Y / 2, plot.Size.Z / 2 + 4)
			local model = placeModel("HalloweenSign", cf, cosmeticsFolder :: Instance)
			if model then
				model.Name = "HalloweenSign_" .. player.UserId
				signs[player.UserId] = { model = model, plot = plotName :: string }
			end
		end
		present[player.UserId] = true
	end
	for userId, sign in signs do
		if not present[userId] then
			sign.model:Destroy()
			signs[userId] = nil
		end
	end
end

-- ===== Цикл =====

local function refreshActive()
	local now = os.time()
	local a = detect(now)
	local previousId = HolidayService.current()
	active = a
	local id = if a then a.holiday.id else nil
	if
		id ~= previousId
		or ReplicatedStorage:GetAttribute("HolidayEndsAt") ~= (if a then a.endsAt else nil)
	then
		ReplicatedStorage:SetAttribute("HolidayId", id)
		ReplicatedStorage:SetAttribute("HolidayEndsAt", if a then a.endsAt else nil)
	end
	local decor = if a then a.holiday.decor else nil
	if decor ~= decorBuiltFor then
		rebuildDecor(decor)
	end
end

local function tick()
	refreshActive()
	local a = active
	for _, player in Players:GetPlayers() do
		local profile = DataService.get(player)
		if profile then
			syncTopics(player, profile)
			if a then
				pruneOldSeasons(profile, a)
			end
			sendState(player)
		end
	end
	syncSigns()
end

function HolidayService.start()
	refreshActive()
	HolidayRemotes.ClaimHolidayQuest.OnServerEvent:Connect(onClaimQuest)
	HolidayRemotes.ClaimHolidayGift.OnServerEvent:Connect(onClaimGift)
	HolidayRemotes.RequestHolidayState.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
			return
		end
		lastRequest[player] = now
		sendState(player, true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSignature[player] = nil
		lastAction[player] = nil
		lastRequest[player] = nil
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(tick)
			if not ok then
				warn("[HolidayService] Tick failed:", err)
			end
			task.wait(Holidays.pollSeconds)
		end
	end)
end

return HolidayService
