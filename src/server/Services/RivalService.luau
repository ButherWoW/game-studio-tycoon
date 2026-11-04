--!strict
-- Студии-конкуренты (Config/Rivals): «Топ-10 индустрии» по стоимости студии, награда за обгон,
-- хиты конкурентов (доход жанра ниже на время). Хит — на весь сервер: атрибуты ReplicatedStorage
-- RivalHitStudio, RivalHitGenre, RivalHitEndsAt (os.time).
-- Данные: profile.rivals = { minutes, passed = { [rivalId] = true } }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Rivals = require(Shared.Config.Rivals)
local Upgrades = require(Shared.Config.Upgrades)
local Stages = require(Shared.Config.Stages)
local Genres = require(Shared.Config.Genres)
local Debug = require(Shared.Config.Debug)
local DepthRemotes = require(Shared.DepthRemotes)
local DataService = require(script.Parent.DataService)

type Data = { minutes: number, passed: { [string]: boolean } }

local CHECK_SECONDS = 10
local REQUEST_COOLDOWN = 1

local RivalService = {}
local lastRequest: { [Player]: number } = {}
local hitGenre: string? = nil
local hitEndsAt = 0
local rng = Random.new()

local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

local function data(profile: DataService.Profile): Data
	local raw = profile.rivals
	if type(raw) ~= "table" then
		raw = {}
	end
	local minutes = tonumber(raw.minutes)
	local passed: { [string]: boolean } = {}
	if type(raw.passed) == "table" then
		for id, value in raw.passed do
			if type(id) == "string" and value == true and Rivals.byId(id) then
				passed[id] = true
			end
		end
	end
	local fixed: Data = {
		minutes = if minutes and minutes == minutes and minutes >= 0 then minutes else 0,
		passed = passed,
	}
	profile.rivals = fixed
	return fixed
end

-- Стоимость студии игрока: деньги + купленные апгрейды + оплаченные переезды
function RivalService.studioValue(profile: DataService.Profile): number
	local value = math.max(profile.cash, 0)
	for _, upgrade in Upgrades do
		if profile.upgrades[upgrade.id] then
			value += upgrade.cost
		end
	end
	for _, stage in Stages do
		if stage.level <= profile.studioLevel then
			value += stage.cost
		end
	end
	return math.floor(value)
end

-- Множитель дохода игры жанра: идёт хит конкурента в этом жанре — ниже
function RivalService.genreMultiplier(genreId: string): number
	if hitGenre == genreId and os.time() < hitEndsAt then
		return Rivals.hitRevenueMultiplier
	end
	return 1
end

local function incomePerMinute(player: Player, profile: DataService.Profile): number
	local shop = optional("ShopService")
	local ok, value = pcall(function()
		return shop and shop.incomePerMinute(player, profile)
	end)
	return if ok and type(value) == "number" then value else 0
end

function RivalService.pushState(player: Player)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	local d = data(profile)
	local you = RivalService.studioValue(profile)
	local rows = {}
	for _, rival in Rivals.list do
		table.insert(rows, {
			id = rival.id,
			name = rival.name,
			icon = rival.icon,
			value = Rivals.valueOf(rival, d.minutes),
		})
	end
	table.insert(rows, { name = player.DisplayName, icon = "⭐", value = you, you = true })
	table.sort(rows, function(a: any, b: any)
		return a.value > b.value
	end)
	local rank = 0
	local nextRow: any = nil
	for i, row in rows do
		if row.you then
			rank = i
			nextRow = rows[i - 1]
			break
		end
	end
	local top = {}
	for i = 1, math.min(Rivals.topSize, #rows) do
		table.insert(top, rows[i])
	end
	DepthRemotes.RivalState:FireClient(player, {
		top = top,
		rank = rank,
		nextName = if nextRow then nextRow.name else nil,
		nextGap = if nextRow then nextRow.value - you else nil,
	})
end

-- Обогнал студию впервые — тост и награда
local function checkPasses(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local d = data(profile)
	local you = RivalService.studioValue(profile)
	local any = false
	for _, rival in Rivals.list do
		if not d.passed[rival.id] and you > Rivals.valueOf(rival, d.minutes) then
			d.passed[rival.id] = true
			any = true
			local reward = incomePerMinute(player, profile) * Rivals.passRewardMinutes
			if reward > 0 then
				DataService.addCash(player, reward)
				local rewards = optional("RewardService")
				if rewards and type(rewards.noteNonEarned) == "function" then
					pcall(rewards.noteNonEarned, player, reward)
				end
			end
			DepthRemotes.RivalNotice:FireClient(player, {
				passed = { name = rival.name, icon = rival.icon, reward = reward },
			})
			local analytics = optional("AnalyticsService")
			if analytics and type(analytics.logDepth) == "function" then
				pcall(analytics.logDepth, player, "rivalPassed", rival.id)
			end
		end
	end
	if any then
		RivalService.pushState(player)
	end
end

local function releaseHit()
	local rival = Rivals.list[rng:NextInteger(1, #Rivals.list)]
	local genreId = if Genres[rival.genre] then rival.genre else "action"
	hitGenre = genreId
	hitEndsAt = os.time() + Rivals.hitSeconds
	ReplicatedStorage:SetAttribute("RivalHitStudio", rival.name)
	ReplicatedStorage:SetAttribute("RivalHitIcon", rival.icon)
	ReplicatedStorage:SetAttribute("RivalHitGenre", genreId)
	ReplicatedStorage:SetAttribute("RivalHitEndsAt", hitEndsAt)
	DepthRemotes.RivalNotice:FireAllClients({
		hit = { name = rival.name, icon = rival.icon, genreId = genreId },
	})
end

local function onRequest(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	RivalService.pushState(player)
end

function RivalService.start()
	DepthRemotes.RivalRequest.OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)

	-- Минуты игры (рост конкурентов) и обгоны
	task.spawn(function()
		local elapsed = 0
		while true do
			task.wait(CHECK_SECONDS)
			elapsed += CHECK_SECONDS
			local addMinute = elapsed >= 60
			if addMinute then
				elapsed = 0
			end
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile then
					if addMinute then
						local d = data(profile)
						d.minutes += 1
					end
					local ok, err = pcall(checkPasses, player)
					if not ok then
						warn("[RivalService] check failed:", err)
					end
				end
			end
		end
	end)

	-- Хиты конкурентов
	task.spawn(function()
		local forced = RunService:IsStudio() and Debug.rivalForceHit == true
		task.wait(if forced then 20 else rng:NextNumber(Rivals.hitIntervalMin, Rivals.hitIntervalMax))
		while true do
			pcall(releaseHit)
			task.wait(rng:NextNumber(Rivals.hitIntervalMin, Rivals.hitIntervalMax))
		end
	end)
end

return RivalService
