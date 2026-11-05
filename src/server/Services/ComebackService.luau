--!strict
-- Бонус возвращения (7.21, Config/Comeback). Кого не было minAwayDays дней (по profile.lastLogout,
-- его DataService пишет при каждом сохранении), при входе получает incomeMinutes минут дохода
-- и coffeeMinutes минут кофе. Бонус ждёт в профиле (comebackPending) до «Забрать» в окне
-- «С возвращением!» (ComebackWindow, очередь окон входа) и переживает выход без «Забрать».
-- Один раз на возвращение: lastLogout считаем сразу после загрузки, до первого автосейва;
-- новое возвращение заменяет несобранный бонус, а не складывается с ним.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comeback = require(ReplicatedStorage.Shared.Config.Comeback)
local RetentionRemotes = require(ReplicatedStorage.Shared.RetentionRemotes)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)

local DAY = 24 * 60 * 60
local CLAIM_COOLDOWN = 1

type Pending = { cash: number, coffee: number, days: number }

local ComebackService = {}
local lastClaim: { [Player]: number } = {}

local function pendingOf(profile: DataService.Profile): Pending?
	local raw = (profile :: any).comebackPending
	if type(raw) ~= "table" then
		return nil
	end
	local cash, coffee, days = tonumber(raw.cash), tonumber(raw.coffee), tonumber(raw.days)
	if not cash or not coffee or not days or cash ~= cash or cash < 0 or coffee < 0 then
		return nil
	end
	return { cash = math.floor(cash), coffee = math.floor(coffee), days = math.floor(days) }
end

-- Атрибуты для окна: ComebackDays > 0 — есть что забрать
local function publish(player: Player, pending: Pending?)
	player:SetAttribute("ComebackCash", if pending then pending.cash else 0)
	player:SetAttribute("ComebackCoffee", if pending then pending.coffee else 0)
	player:SetAttribute("ComebackDays", if pending then pending.days else 0)
end

local function onProfileLoaded(player: Player, profile: DataService.Profile)
	local data = profile :: any
	-- Сразу, до первого сохранения: оно перепишет lastLogout текущим временем
	local lastLogout = tonumber(data.lastLogout)
	local away = if lastLogout then os.time() - lastLogout else 0
	if away >= Comeback.minAwayDays * DAY then
		local cash = math.floor(RewardService.incomeForMinutes(player, profile, Comeback.incomeMinutes))
		data.comebackPending = {
			cash = math.max(cash, 0),
			coffee = Comeback.coffeeMinutes,
			days = away // DAY,
		}
		local module = script.Parent:FindFirstChild("AnalyticsService")
		if module and module:IsA("ModuleScript") then
			pcall((require(module) :: any).logLiveOps, player, "comeback", away // DAY, "shown")
		end
	end
	publish(player, pendingOf(profile))
end

local function onClaim(player: Player)
	local now = os.clock()
	if (lastClaim[player] or 0) + CLAIM_COOLDOWN > now then
		return
	end
	lastClaim[player] = now
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local pending = pendingOf(profile)
	if not pending then
		return
	end
	(profile :: any).comebackPending = nil
	publish(player, nil)
	if pending.cash > 0 then
		-- Не заработок за игру: в задания «заработай» не идёт
		RewardService.noteNonEarned(player, pending.cash)
		DataService.addCash(player, pending.cash)
	end
	if pending.coffee > 0 then
		RewardService.grant(player, { coffeeMinutes = pending.coffee })
	end
	local module = script.Parent:FindFirstChild("AnalyticsService")
	if module and module:IsA("ModuleScript") then
		pcall((require(module) :: any).logLiveOps, player, "comeback", pending.days, "claimed")
	end
	task.spawn(DataService.save, player)
end

function ComebackService.start()
	DataService.onProfileLoaded(onProfileLoaded)
	RetentionRemotes.ClaimComeback.OnServerEvent:Connect(onClaim)
	Players.PlayerRemoving:Connect(function(player)
		lastClaim[player] = nil
	end)
end

return ComebackService
