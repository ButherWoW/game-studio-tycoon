--!strict
-- Настройки игрока (Config/Settings): хранятся в profile.settings, клиент спрашивает их при входе
-- и присылает изменения по одному ключу. Сервер принимает только известные ключи и значения.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage.Shared.Config.Settings)
local SettingsRemotes = require(ReplicatedStorage.Shared.SettingsRemotes)
local DataService = require(script.Parent.DataService)

local PROFILE_WAIT_SECONDS = 15
local MAX_CHANGES_PER_MINUTE = 120 -- кнопки − / + жмут быстро, но не сотнями

local SettingsService = {}

-- Один ожидающий запрос на игрока: спам до загрузки профиля не плодит потоки
local waiting: { [Player]: boolean } = {}
local budget: { [Player]: { windowStart: number, count: number } } = {}

-- Настройки игрока (всегда полный набор; нет профиля — значения по умолчанию)
function SettingsService.get(player: Player): Settings.Values
	local profile = DataService.get(player)
	return Settings.sanitize(profile and profile.settings)
end

local function onGetSettings(player: Player): Settings.Values?
	if waiting[player] then
		return nil
	end
	waiting[player] = true
	local ok, values = pcall(function()
		local deadline = os.clock() + PROFILE_WAIT_SECONDS
		local profile = DataService.get(player)
		while not profile and os.clock() < deadline and player.Parent == Players do
			task.wait(0.25)
			profile = DataService.get(player)
		end
		return if profile then Settings.sanitize(profile.settings) else nil
	end)
	waiting[player] = nil
	return if ok then values else nil
end

local function allowed(player: Player): boolean
	local now = os.clock()
	local entry = budget[player]
	if not entry or now - entry.windowStart >= 60 then
		entry = { windowStart = now, count = 0 }
		budget[player] = entry
	end
	entry.count += 1
	return entry.count <= MAX_CHANGES_PER_MINUTE
end

local function onSetSetting(player: Player, key: any, value: any)
	local clean = Settings.clean(key, value)
	if clean == nil or not allowed(player) then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	-- Храним полный проверенный набор: мусор из старых версий не доживёт до сохранения
	local values = Settings.sanitize(profile.settings) :: any
	values[key] = clean
	profile.settings = values
end

function SettingsService.start()
	SettingsRemotes.GetSettings.OnServerInvoke = onGetSettings
	SettingsRemotes.SetSetting.OnServerEvent:Connect(onSetSetting)
	Players.PlayerRemoving:Connect(function(player)
		waiting[player] = nil
		budget[player] = nil
	end)
end

return SettingsService
