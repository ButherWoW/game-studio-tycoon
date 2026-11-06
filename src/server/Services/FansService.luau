--!strict
-- Фанаты студии (Config/Fans): общий счётчик profile.fans. Растут от хороших релизов и выставок,
-- уходят после плохих игр (Formulas.fanChange / expoFans); от числа фанатов зависят продажи
-- релизов и полки хитов (Formulas.fanMultiplier). Клиент видит fans в DataChanged (HUD 👥),
-- таблица лидеров — LeaderboardService. Rebirth оставляет Fans.rebirthKeep (RebirthService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fans = require(ReplicatedStorage.Shared.Config.Fans)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local HitRemotes = require(ReplicatedStorage.Shared.HitRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local DataService = require(script.Parent.DataService)

local FansService = {}

-- Аналитика без жёсткой зависимости (AnalyticsService тянет много модулей)
local function logFans(player: Player, amount: number, field: string)
	local module = script.Parent:FindFirstChild("AnalyticsService")
	if module and module:IsA("ModuleScript") then
		local ok, analytics = pcall(require, module)
		if ok and type(analytics) == "table" and type((analytics :: any).logLiveOps) == "function" then
			pcall((analytics :: any).logLiveOps, player, "fans", amount, field)
		end
	end
end

-- Значение из сохранения: целое 0..maxFans (старые сохранения без поля — 0)
function FansService.sanitize(value: any): number
	local n = tonumber(value)
	if not n or n ~= n then
		return 0
	end
	return math.clamp(math.floor(n), 0, Fans.maxFans)
end

function FansService.get(player: Player): number
	local profile = DataService.get(player)
	return if profile then FansService.sanitize(profile.fans) else 0
end

-- Множитель продаж игрока (релизы, полка хитов); без профиля — ×1
function FansService.multiplier(player: Player): number
	return Formulas.fanMultiplier(FansService.get(player))
end

-- Изменить фанатов на delta (не ниже 0). source — для аналитики: release / expo_win / rebirth…
-- Возвращает, на сколько изменилось на самом деле
function FansService.change(player: Player, delta: number, source: string): number
	local profile = DataService.get(player)
	if not profile or delta ~= delta then
		return 0
	end
	local before = FansService.sanitize(profile.fans)
	local after = math.clamp(math.floor(before + delta), 0, Fans.maxFans)
	profile.fans = after
	local applied = after - before
	if applied ~= 0 then
		DataService.replicate(player)
		logFans(player, math.abs(applied), source .. (if applied > 0 then "_gain" else "_loss"))
	end
	return applied
end

-- Релиз (DevelopmentService.release): изменение по оценке. adBonus — активная реклама
function FansService.onGameReleased(player: Player, score: number, adBonus: number): number
	local profile = DataService.get(player)
	if not profile then
		return 0
	end
	local delta = Formulas.fanChange(score, FansService.sanitize(profile.fans), profile.studioLevel, adBonus)
	return FansService.change(player, delta, "release")
end

-- Выставка (ExpoService): place 1..3 или nil, score — оценка игры игрока в раунде. Тост «🏆 +N»
function FansService.onExpo(player: Player, place: number?, score: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local gain = Formulas.expoFans(place, score, profile.studioLevel)
	if gain <= 0 then
		return
	end
	local source = if place then "expo_place" .. place else "expo_high"
	local applied = FansService.change(player, gain, source)
	if applied > 0 and player.Parent then
		HitRemotes.HitToast:FireClient(player, {
			key = "fans_expo",
			vars = { n = Texts.money(applied):sub(2) },
		})
	end
end

-- Rebirth (RebirthService): остаётся Fans.rebirthKeep
function FansService.onRebirth(player: Player)
	local current = FansService.get(player)
	local keep = math.floor(current * math.clamp(Fans.rebirthKeep, 0, 1))
	FansService.change(player, keep - current, "rebirth")
end

return FansService
