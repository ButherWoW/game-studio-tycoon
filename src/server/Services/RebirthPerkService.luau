--!strict
-- Дерево перков Rebirth (роадмап 7.19, Config/RebirthPerks): покупка уровней за «звёзды студии»
-- и один бесплатный сброс. Звёзды не хранятся: rebirths − цена купленного (задним числом для
-- старых профилей). Эффекты читают сами сервисы через RebirthPerks.forProfile(profile):
-- DevelopmentService (время), ExpensesService (аренда/зарплаты), RebirthService (стартовые деньги),
-- HitService (полка), OfflineService (офлайн), ResearchService (скидка). Здесь — только покупка.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthPerks = require(ReplicatedStorage.Shared.Config.RebirthPerks)
local RebirthPerkRemotes = require(ReplicatedStorage.Shared.RebirthPerkRemotes)
local DataService = require(script.Parent.DataService)

type PerkData = { levels: { [string]: number }, respecUsed: boolean }

local ACTION_COOLDOWN = 0.3 -- секунд между покупками/сбросом одного игрока
local REQUEST_COOLDOWN = 1 -- секунд между запросами состояния

local RebirthPerkService = {}
local lastAction: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}

-- Данные перков (формат чинит DataService при загрузке; здесь — страховка)
local function dataOf(profile: DataService.Profile): PerkData
	local p = profile :: any
	if type(p.rebirthPerks) ~= "table" then
		p.rebirthPerks = { levels = {}, respecUsed = false }
	end
	local data = p.rebirthPerks
	if type(data.levels) ~= "table" then
		data.levels = {}
	end
	return data :: PerkData
end

local function throttled(map: { [Player]: number }, player: Player, seconds: number): boolean
	local now = os.clock()
	if (map[player] or 0) + seconds > now then
		return true
	end
	map[player] = now
	return false
end

-- Необязательный модуль соседней фичи (нет или упал — тихо пропускаем)
local function call(name: string, fnName: string, ...: any)
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return
	end
	local args = table.pack(...)
	local ok, err = pcall(function()
		local service = require(module) :: any
		if type(service[fnName]) == "function" then
			service[fnName](table.unpack(args, 1, args.n))
		end
	end)
	if not ok then
		warn("[RebirthPerkService] " .. name .. "." .. fnName .. " failed:", err)
	end
end

function RebirthPerkService.sync(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = dataOf(profile)
	local levels = {}
	for _, branch in RebirthPerks.branches do
		levels[branch.id] = RebirthPerks.levelOf(data.levels, branch.id)
	end
	RebirthPerkRemotes.RebirthPerkState:FireClient(player, {
		stars = RebirthPerks.available(profile.rebirths, data.levels),
		earned = math.max(math.floor(profile.rebirths), 0) * RebirthPerks.starsPerRebirth,
		levels = levels,
		respecLeft = if data.respecUsed then 0 else RebirthPerks.freeRespecs,
	})
end

-- Эффекты, которые сервисы считают не на лету, а при событии: обновить сразу
local function applyNow(player: Player)
	call("HitService", "refreshShelf", player) -- места на полке
	call("ResearchService", "sync", player) -- цены исследований в окне
end

local function onBuy(player: Player, branchId: any)
	if type(branchId) ~= "string" or #branchId > 32 or throttled(lastAction, player, ACTION_COOLDOWN) then
		return
	end
	local profile = DataService.get(player)
	if not profile or not RebirthPerks.byId[branchId] then
		return
	end
	local data = dataOf(profile)
	local cost = RebirthPerks.nextCost(data.levels, branchId)
	-- Без yield между проверкой и записью: двойной клик не купит дважды
	if cost and RebirthPerks.available(profile.rebirths, data.levels) >= cost then
		data.levels[branchId] = RebirthPerks.levelOf(data.levels, branchId) + 1
		applyNow(player)
	end
	RebirthPerkService.sync(player)
end

local function onRespec(player: Player)
	if throttled(lastAction, player, ACTION_COOLDOWN) then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = dataOf(profile)
	if not data.respecUsed and RebirthPerks.spent(data.levels) > 0 then
		-- Сбрасываем только ветки из конфига: чужие/будущие id не трогаем
		for _, branch in RebirthPerks.branches do
			data.levels[branch.id] = nil
		end
		data.respecUsed = true
		applyNow(player)
	end
	RebirthPerkService.sync(player)
end

function RebirthPerkService.start()
	RebirthPerkRemotes.BuyRebirthPerk.OnServerEvent:Connect(onBuy)
	RebirthPerkRemotes.RespecRebirthPerks.OnServerEvent:Connect(onRespec)
	RebirthPerkRemotes.RequestRebirthPerks.OnServerEvent:Connect(function(player)
		if not throttled(lastRequest, player, REQUEST_COOLDOWN) then
			RebirthPerkService.sync(player)
		end
	end)
	DataService.onProfileLoaded(function(player)
		RebirthPerkService.sync(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		lastRequest[player] = nil
	end)
end

return RebirthPerkService
