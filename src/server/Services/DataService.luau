--!strict
-- Загрузка/сохранение профиля игрока в DataStore.
-- Для MVP хватает этого; позже можно перейти на ProfileStore (защита от двойных сессий).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

export type Profile = {
	cash: number,
	studioLevel: number,
	rebirths: number,
	upgrades: { [string]: boolean },
	unlockedGenres: { [string]: boolean },
	unlockedTopics: { [string]: boolean },
	gamesReleased: number,
	bestScore: number,
	activeAd: { bonus: number, expiresAt: number }?,
	processedReceipts: { [string]: boolean },
	lastLogout: number,
}

local STORE_VERSION = "v1"
local store = DataStoreService:GetDataStore("PlayerData_" .. STORE_VERSION)
local AUTOSAVE_SECONDS = 60

local function defaultProfile(): Profile
	return {
		cash = 100,
		studioLevel = 1,
		rebirths = 0,
		upgrades = {},
		unlockedGenres = { action = true, adventure = true, casual = true },
		unlockedTopics = { space = true, fantasy = true, zombies = true },
		gamesReleased = 0,
		bestScore = 0,
		activeAd = nil,
		processedReceipts = {},
		lastLogout = os.time(),
	}
end

local DataService = {}
local profiles: { [Player]: Profile } = {}

local function withRetries<T>(fn: () -> T): (boolean, T | string)
	local lastErr: any
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(attempt)
	end
	return false, tostring(lastErr)
end

local function key(player: Player): string
	return "user_" .. player.UserId
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

-- Отправить клиенту публичный снимок данных (без квитанций)
function DataService.replicate(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	Remotes.DataChanged:FireClient(player, {
		cash = p.cash,
		studioLevel = p.studioLevel,
		rebirths = p.rebirths,
		upgrades = p.upgrades,
		unlockedGenres = p.unlockedGenres,
		unlockedTopics = p.unlockedTopics,
		gamesReleased = p.gamesReleased,
		bestScore = p.bestScore,
		activeAd = p.activeAd,
	})
	local leaderstats = player:FindFirstChild("leaderstats")
	local cashValue = leaderstats and leaderstats:FindFirstChild("Cash") :: NumberValue?
	if cashValue then
		cashValue.Value = p.cash
	end
end

function DataService.addCash(player: Player, amount: number)
	local p = profiles[player]
	if p then
		p.cash += amount
		DataService.replicate(player)
	end
end

function DataService.trySpend(player: Player, amount: number): boolean
	local p = profiles[player]
	if not p or amount < 0 or p.cash < amount then
		return false
	end
	p.cash -= amount
	DataService.replicate(player)
	return true
end

function DataService.save(player: Player): boolean
	local p = profiles[player]
	if not p then
		return false
	end
	p.lastLogout = os.time()
	local ok, err = withRetries(function()
		store:SetAsync(key(player), p, { player.UserId })
		return true
	end)
	if not ok then
		warn("[DataService] Save failed for", player.Name, err)
	end
	return ok
end

local function onPlayerAdded(player: Player)
	local ok, result = withRetries(function()
		return store:GetAsync(key(player))
	end)
	if not ok then
		if RunService:IsStudio() then
			-- В Studio без публикации/доступа к API DataStore недоступен: играем без сохранений
			warn(
				"[DataService] DataStore недоступен в Studio, профиль не сохранится:",
				result
			)
			result = nil
		else
			player:Kick(
				"Не удалось загрузить сохранение. Попробуйте зайти ещё раз."
			)
			return
		end
	end

	local profile = defaultProfile()
	if type(result) == "table" then
		for k, v in result :: any do
			(profile :: any)[k] = v
		end
	end
	profiles[player] = profile

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("NumberValue")
	cash.Name = "Cash"
	cash.Value = profile.cash
	cash.Parent = leaderstats
	leaderstats.Parent = player

	DataService.replicate(player)
end

local function onPlayerRemoving(player: Player)
	DataService.save(player)
	profiles[player] = nil
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player in profiles do
				task.spawn(DataService.save, player)
			end
		end
	end)

	game:BindToClose(function()
		for player in profiles do
			DataService.save(player)
		end
	end)
end

return DataService
