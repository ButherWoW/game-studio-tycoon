--!strict
-- Промокоды (Config/Codes): игрок вводит код в окне «🎟 Коды» (кнопка в шапке магазина).
-- Проверки: не чаще Codes.cooldown, не больше Codes.perSession попыток за вход, код есть,
-- не истёк, этим игроком ещё не активирован. Ответ — CodeResult { reason, reward? }:
-- ok / invalid / used / expired / limit.
-- Данные: profile.codes = { [КОД]: os.time() активации }. Rebirth не трогает.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Codes = require(Shared.Config.Codes)
local Skins = require(Shared.Config.Skins)
local Posters = require(Shared.Config.Posters)
local CodeRemotes = require(Shared.CodeRemotes)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)

local CodeService = {}
local lastTry: { [Player]: number } = {}
local tries: { [Player]: number } = {}

local function used(profile: DataService.Profile): { [string]: number }
	local p = profile :: any
	if type(p.codes) ~= "table" then
		p.codes = {}
	end
	return p.codes
end

-- Ленивый модуль другой фичи (скины, постеры, аналитика): его ошибка не ломает код
local function call(name: string, fnName: string, ...: any): any
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(function(...)
		local fn = (require(module) :: any)[fnName]
		return if type(fn) == "function" then fn(...) else nil
	end, ...)
	if not ok then
		warn("[CodeService] " .. name .. "." .. fnName .. " failed:", result)
		return nil
	end
	return result
end

-- Выдать награду; вернуть, что выдано (для текста на клиенте)
local function grant(
	player: Player,
	profile: DataService.Profile,
	reward: Codes.CodeReward
): { [string]: any }
	local given: { [string]: any } = {}
	local cash = 0
	if reward.incomeMinutes then
		cash += RewardService.incomeForMinutes(player, profile, reward.incomeMinutes)
	end
	if reward.minCash then
		cash = math.max(cash, reward.minCash)
	end
	if reward.cash then
		cash += reward.cash
	end
	cash = math.floor(cash)
	if cash > 0 then
		-- Не заработок за игру: в задания «заработай» не идёт
		RewardService.noteNonEarned(player, cash)
		DataService.addCash(player, cash)
		given.cash = cash
	end
	if reward.coffeeMinutes then
		RewardService.grant(player, { coffeeMinutes = reward.coffeeMinutes })
		given.coffeeMinutes = reward.coffeeMinutes
	end
	-- Скин или постер уже есть — в ответе его нет (игрок не увидит «получено» впустую)
	if reward.skin and Skins.get(reward.skin) then
		if call("SkinService", "grantSkin", player, profile, reward.skin) == true then
			given.skin = reward.skin
		end
	end
	if reward.poster and Posters.get(reward.poster) then
		if call("PosterService", "grantPoster", player, profile, reward.poster) == true then
			given.poster = reward.poster
		end
	end
	return given
end

local function reply(player: Player, reason: string, reward: { [string]: any }?)
	CodeRemotes.CodeResult:FireClient(player, { reason = reason, reward = reward })
end

local function onRedeem(player: Player, raw: any)
	local now = os.clock()
	if (lastTry[player] or 0) + Codes.cooldown > now or (tries[player] or 0) >= Codes.perSession then
		reply(player, "limit")
		return
	end
	lastTry[player] = now
	tries[player] = (tries[player] or 0) + 1
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local key = Codes.normalize(raw)
	local code = key and Codes.list[key]
	if not key or not code then
		reply(player, "invalid")
		return
	end
	local codes = used(profile)
	if codes[key] ~= nil then
		reply(player, "used")
		return
	end
	if code.expiresAt and os.time() > code.expiresAt then
		reply(player, "expired")
		return
	end
	codes[key] = os.time()
	local given = grant(player, profile, code.reward)
	reply(player, "ok", given)
	call("AnalyticsService", "logCode", player, key)
	-- Код — разовая награда: сохраняем сразу, не ждём автосейва
	task.spawn(DataService.save, player)
end

function CodeService.start()
	CodeRemotes.RedeemCode.OnServerEvent:Connect(onRedeem)
	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
		tries[player] = nil
	end)
end

return CodeService
