--!strict
-- Тестовые деньги в Studio, чтобы проверять покупки без разработки игр.
-- На живых серверах выключено.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Debug = require(ReplicatedStorage.Shared.Config.Debug)
local DataService = require(script.Parent.DataService)

local DebugService = {}

local function onPlayerAdded(player: Player)
	-- Профиль грузится асинхронно в DataService
	local profile = DataService.get(player)
	while not profile and player.Parent do
		task.wait(0.2)
		profile = DataService.get(player)
	end
	if profile and profile.cash < Debug.studioStartCash then
		local amount = Debug.studioStartCash - profile.cash
		DataService.addCash(player, amount);
		(require(script.Parent.RewardService) :: any).noteNonEarned(player, amount)
		warn("[DebugService] Studio: выдано $" .. Debug.studioStartCash .. " для теста")
	end
end

-- Studio: ServerStorage.StudioDebug (BindableFunction) для проверок из командной строки Studio
-- (у командной строки свои копии модулей, к живым профилям так не добраться):
--   Invoke("set", "studioLevel", 4)           — поле профиля первого игрока (путь через точку)
--   Invoke("get", "stocks.listed")
--   Invoke("call", "TaxService", "fn", ...)   — функция сервиса
--   Invoke("phase7")                          — 3-й этаж, весь интерьер, оценки 9, $40M (IPO)
local function resolve(root: any, path: string): (any, string)
	local parts = string.split(path, ".")
	local node = root
	for i = 1, #parts - 1 do
		local key: any = tonumber(parts[i]) or parts[i]
		if type(node[key]) ~= "table" then
			node[key] = {}
		end
		node = node[key]
	end
	return node, parts[#parts]
end

local function debugInvoke(action: string, ...: any): any
	local player = Players:GetPlayers()[1]
	local profile = player and DataService.get(player)
	if not player or not profile then
		return "no player"
	end
	local args = { ... }
	if action == "set" then
		local node, key = resolve(profile, args[1])
		node[key] = args[2]
		DataService.replicate(player)
		return "ok"
	elseif action == "get" then
		local node, key = resolve(profile, args[1])
		return node[key]
	elseif action == "call" then
		local module = script.Parent:FindFirstChild(args[1])
		local service = module and (require(module) :: any)
		local fn = service and service[args[2]]
		if type(fn) ~= "function" then
			return "no function"
		end
		return fn(table.unpack(args, 3))
	elseif action == "phase7" then
		local p = profile :: any
		p.ownsGarage = true
		p.studioLevel = 4
		for _, upgrade in require(ReplicatedStorage.Shared.Config.Upgrades) :: any do
			p.upgrades[upgrade.id] = true
		end
		p.runBestScore = 10
		p.bestScore = math.max(p.bestScore, 10)
		p.gamesReleased = math.max(p.gamesReleased, 3000)
		p.cash = 40_000_000
		p.stocks = p.stocks or {}
		p.stocks.recent = table.create(20, 9)
		DataService.replicate(player)
		local plot = script.Parent:FindFirstChild("PlotService")
		if plot then
			pcall((require(plot) :: any).rebuild, player)
		end
		return "ok"
	end
	return "unknown action"
end

function DebugService.start()
	if not RunService:IsStudio() then
		return
	end
	local ServerStorage = game:GetService("ServerStorage")
	local bindable = ServerStorage:FindFirstChild("StudioDebug") :: BindableFunction?
	if not bindable then
		local created = Instance.new("BindableFunction")
		created.Name = "StudioDebug"
		created.Parent = ServerStorage
		bindable = created
	end
	(bindable :: BindableFunction).OnInvoke = debugInvoke
	if Debug.studioStartCash <= 0 then
		return
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DebugService
