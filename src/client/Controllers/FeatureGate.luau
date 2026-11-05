--!strict
-- Постепенное открытие систем для новичка (Config/Unlocks): считает, какие системы открыты
-- (этап студии, игры, хиты или уже видел раньше — атрибут FeaturesSeen от FeatureUnlockService),
-- и говорит Ui, какие кнопки меню и плашки показывать (Ui.setGateOpen). Когда система открылась
-- впервые — один тост «🆕 Открыто: Команда, Магазин…» (после окна релиза) и значок 🆕 на её
-- кнопке до первого нажатия; сервер запоминает «видел», в следующих сессиях без тоста.
-- Другие контроллеры спрашивают FeatureGate.isOpen(id) для своих тостов и всплывашек.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Unlocks = require(ReplicatedStorage.Shared.Config.Unlocks)
local FeatureRemotes = require(ReplicatedStorage.Shared.FeatureRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local UnlockNotice = require(script.Parent.UnlockNotice)
local SoundController = require(script.Parent.SoundController)

local player = Players.LocalPlayer

local FeatureGate = {}

local changedEvent = Instance.new("BindableEvent")
FeatureGate.changed = changedEvent.Event

local open: { [string]: boolean } = {}
-- Уже объявлено/отправлено в этой сессии: пока сервер не обновил атрибут, не повторяем
local announced: { [string]: boolean } = {}
local started = false

-- Что сервер помнит как «видел» (nil — ещё не прислал: ничего нового не объявляем)
local function readSeen(): { [string]: boolean }?
	local raw = player:GetAttribute(Unlocks.SEEN_ATTRIBUTE)
	if type(raw) ~= "string" then
		return nil
	end
	local set: { [string]: boolean } = {}
	for id in raw:gmatch("[^,]+") do
		set[id] = true
	end
	return set
end

local function progress(): Unlocks.Progress?
	local data = ClientState.data
	if type(data) ~= "table" then
		return nil
	end
	return {
		ownsGarage = player:GetAttribute("OwnsGarage") == true,
		studioLevel = tonumber(data.studioLevel) or 1,
		gamesReleased = tonumber(data.gamesReleased) or 0,
		hitsReleased = tonumber(data.hitsReleased) or 0,
		rebirths = tonumber(data.rebirths) or 0,
	}
end

-- Открыта ли система сейчас (id не из Config/Unlocks — всегда)
function FeatureGate.isOpen(id: string): boolean
	if not Unlocks.features[id] then
		return true
	end
	return open[id] == true
end

-- Порядок в тосте — как кнопки в меню (по слоту), плашки после них
local function announceOrder(a: string, b: string): boolean
	local fa, fb = Unlocks.features[a], Unlocks.features[b]
	local sa, sb = fa.menuSlot or 100, fb.menuSlot or 100
	if sa ~= sb then
		return sa < sb
	end
	return a < b
end

local function announce(ids: { string })
	table.sort(ids, announceOrder)
	local names = {}
	for _, id in ids do
		local key = Unlocks.features[id].textKey
		if key then
			table.insert(names, ClientState.t(key))
		end
		Ui.markNew(id)
	end
	FeatureRemotes.FeatureSeen:FireServer(ids)
	if #names > 0 then
		-- Не раньше, чем окно релиза покажет оценку (открыть могла эта игра)
		ClientState.afterReveal(function()
			UnlockNotice.toast(ClientState.t("unlock_opened", { list = table.concat(names, ", ") }))
			SoundController.play("unlock_feature")
		end)
	end
end

local function refresh()
	local seen = readSeen()
	local current = progress()
	local fresh: { string } = {}
	local any = false
	for id, feature in Unlocks.features do
		local meets = current ~= nil and Unlocks.meets(id, current)
		local now = meets or (seen ~= nil and seen[id] == true)
		if now ~= (open[id] == true) then
			open[id] = now
			Ui.setGateOpen(id, now)
			any = true
		end
		-- Объявляем то, что открылось по условиям и сервер ещё не помнит
		if meets and seen and not seen[id] and feature.toast and not announced[id] then
			announced[id] = true
			table.insert(fresh, id)
		end
	end
	if #fresh > 0 then
		announce(fresh)
	end
	-- Без тоста (toast = false), но тоже «видел»: после Rebirth/смены этапа не спрячется
	if seen and current then
		local silent: { string } = {}
		for id, feature in Unlocks.features do
			if not feature.toast and not seen[id] and not announced[id] and Unlocks.meets(id, current) then
				announced[id] = true
				table.insert(silent, id)
			end
		end
		if #silent > 0 then
			FeatureRemotes.FeatureSeen:FireServer(silent)
		end
	end
	if any then
		changedEvent:Fire()
	end
end

-- Пересчёт раз в кадр: данные, атрибуты гаража и «видел» приходят пачкой
local scheduled = false
local function schedule()
	if scheduled then
		return
	end
	scheduled = true
	task.defer(function()
		scheduled = false
		refresh()
	end)
end

function FeatureGate.start()
	if started then
		return
	end
	started = true
	ClientState.changed:Connect(schedule)
	player:GetAttributeChangedSignal("OwnsGarage"):Connect(schedule)
	player:GetAttributeChangedSignal(Unlocks.SEEN_ATTRIBUTE):Connect(schedule)
	refresh()
end

return FeatureGate
