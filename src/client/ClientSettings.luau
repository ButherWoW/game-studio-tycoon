--!strict
-- Настройки игрока на клиенте (Config/Settings): текущие значения, сигнал changed и сохранение
-- на сервере. Флаги эффектов дублируются атрибутами LocalPlayer — контроллеры проверяют их
-- без require этого модуля: "LowGraphics", "HideTitles", "HideMascots".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage.Shared.Config.Settings)
local SettingsRemotes = require(ReplicatedStorage.Shared.SettingsRemotes)

local ClientSettings = {}

local ATTRIBUTES: { [string]: string } = {
	lowGraphics = "LowGraphics",
	hideTitles = "HideTitles",
	hideMascots = "HideMascots",
}

ClientSettings.values = table.clone(Settings.defaults) :: Settings.Values

local changedEvent = Instance.new("BindableEvent")
-- (key) — поменялась одна настройка; при загрузке с сервера приходит по разу на каждый ключ
ClientSettings.changed = changedEvent.Event

-- Игрок уже менял настройку в этой сессии — ответ сервера с сохранённым её не перебивает
local touched: { [string]: boolean } = {}

local function apply(key: string, value: any)
	local values = ClientSettings.values :: any
	values[key] = value
	local attribute = ATTRIBUTES[key]
	if attribute then
		Players.LocalPlayer:SetAttribute(attribute, value == true)
	end
	changedEvent:Fire(key)
end

function ClientSettings.get(key: string): any
	return (ClientSettings.values :: any)[key]
end

-- Поменять настройку: применить сразу и отправить серверу (он проверит сам)
function ClientSettings.set(key: string, value: any)
	local clean = Settings.clean(key, value)
	if clean == nil then
		return
	end
	touched[key] = true
	if (ClientSettings.values :: any)[key] ~= clean then
		apply(key, clean)
	end
	SettingsRemotes.SetSetting:FireServer(key, clean)
end

-- «Меньше эффектов» включено (для контроллеров, которые уже требуют этот модуль)
function ClientSettings.lowGraphics(): boolean
	return ClientSettings.values.lowGraphics
end

local loaded = false

-- Загрузить сохранённые настройки (зовёт SettingsController при старте, повторный вызов — ничего)
function ClientSettings.load()
	if loaded then
		return
	end
	loaded = true
	for key, attribute in ATTRIBUTES do
		Players.LocalPlayer:SetAttribute(attribute, (ClientSettings.values :: any)[key] == true)
	end
	task.spawn(function()
		local ok, saved = pcall(function()
			return SettingsRemotes.GetSettings:InvokeServer()
		end)
		if not ok or type(saved) ~= "table" then
			return
		end
		local values = Settings.sanitize(saved) :: any
		for _, item in Settings.list do
			if not touched[item.key] and values[item.key] ~= (ClientSettings.values :: any)[item.key] then
				apply(item.key, values[item.key])
			end
		end
	end)
end

return ClientSettings
