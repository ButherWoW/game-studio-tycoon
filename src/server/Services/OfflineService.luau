--!strict
-- Офлайн-доход (шаг 4.4). При входе, если lastLogout был больше Config/Offline.minSeconds назад,
-- начисляем min(время, maxSeconds) × доход_в_минуту × rate. Сумма ждёт в профиле
-- (offlinePending — переживёт выход без «Забрать»), клиент видит её в атрибуте OfflinePending.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Offline = require(ReplicatedStorage.Shared.Config.Offline)
local Rebirth = require(ReplicatedStorage.Shared.Config.Rebirth)
local RetentionRemotes = require(ReplicatedStorage.Shared.RetentionRemotes)
local DataService = require(script.Parent.DataService)

local PROFILE_WAIT = 0.2

local OfflineService = {}

-- Сколько заработала бы студия за seconds офлайна
function OfflineService.earnings(profile: DataService.Profile, seconds: number): number
	local capped = math.min(seconds, Offline.maxSeconds)
	if capped < Offline.minSeconds then
		return 0
	end
	local perGame = Formulas.revenue(
		math.max(profile.bestScore, 1),
		profile.studioLevel,
		0,
		Rebirth.multiplier(profile.rebirths)
	)
	local perMinute = perGame / Offline.gameMinutes
	return math.floor(capped / 60 * perMinute * Offline.rate)
end

local function onPlayerAdded(player: Player)
	-- Профиль грузится асинхронно в DataService
	local profile = DataService.get(player)
	while not profile and player.Parent do
		task.wait(PROFILE_WAIT)
		profile = DataService.get(player)
	end
	if not profile then
		return
	end
	local data = profile :: any
	-- Считаем сразу после загрузки: автосейв перезапишет lastLogout текущим временем.
	-- lastLogout обновляется и при автосейве, так что «уход» точен до 60 с.
	local away = os.time() - (tonumber(data.lastLogout) or os.time())
	local pending = (tonumber(data.offlinePending) or 0) + OfflineService.earnings(profile, away)
	data.offlinePending = pending
	player:SetAttribute("OfflinePending", pending)
end

local function onClaim(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local data = profile :: any
	local pending = tonumber(data.offlinePending) or 0
	if pending <= 0 then
		return
	end
	data.offlinePending = 0
	player:SetAttribute("OfflinePending", 0)
	DataService.addCash(player, pending)
end

function OfflineService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	RetentionRemotes.ClaimOffline.OnServerEvent:Connect(onClaim)
end

return OfflineService
