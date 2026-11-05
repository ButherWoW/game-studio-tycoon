--!strict
-- Покупка жанров и тем за игровую валюту. Цены — Config/Genres и Config/Topics.
-- Купить можно только после выполнения условий requires (shared/UnlockRules).
-- Открытие идёт через лабораторию (ResearchService.startCategory, Config/Research.TIMING):
-- деньги списываются сразу, жанр/тема открываются, когда кончится таймер. Пока идёт другое
-- исследование — не начинаем. Автоматические открытия (стартовые бесплатные, сезонные темы
-- HolidayService, жанры исследований после Rebirth) остаются мгновенными: это не действие игрока.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local UnlockRules = require(ReplicatedStorage.Shared.UnlockRules)
local DataService = require(script.Parent.DataService)
local ResearchService = require(script.Parent.ResearchService)

local UnlockService = {}

local function onUnlock(player: Player, kind: any, id: any)
	if type(kind) ~= "string" or type(id) ~= "string" then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local item: Genres.Genre | Topics.Topic
	local unlocked: { [string]: boolean }
	if kind == "genre" and Genres[id] then
		item, unlocked = Genres[id], profile.unlockedGenres
	elseif kind == "topic" and Topics[id] and not Topics[id].seasonal then
		-- Сезонные темы не продаются: их выдаёт и забирает HolidayService
		item, unlocked = Topics[id], profile.unlockedTopics
	else
		return
	end

	-- Ранние этапы: пока условия не выполнены, не продаём ни за какие деньги
	if unlocked[id] or not UnlockRules.check(item, profile) then
		return
	end
	-- Бесплатное (unlockCost = 0) открыто со старта; на всякий случай — сразу, без таймера
	if item.unlockCost <= 0 then
		unlocked[id] = true
		DataService.replicate(player)
		return
	end
	ResearchService.startCategory(player, if kind == "genre" then "genre" else "topic", id, item.unlockCost)
end

function UnlockService.start()
	Remotes.UnlockContent.OnServerEvent:Connect(onUnlock)
end

return UnlockService
