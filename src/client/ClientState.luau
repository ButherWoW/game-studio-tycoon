--!strict
-- Последние данные игрока с сервера и язык интерфейса — общие для всех контроллеров.

local LocalizationService = game:GetService("LocalizationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)

local ClientState = {}

-- Снимок из DataService.replicate (nil, пока сервер не прислал)
ClientState.data = nil :: any
ClientState.developing = false
ClientState.lang = (if LocalizationService.RobloxLocaleId:sub(1, 2) == "ru" then "ru" else "en") :: Texts.Lang
-- Сочетания, которые игрок уже выпускал в этой сессии: "genre/topic" -> лучшая оценка
ClientState.knownCombos = {} :: { [string]: number }

local changed = Instance.new("BindableEvent")
ClientState.changed = changed.Event

function ClientState.t(key: string, vars: { [string]: any }?): string
	return Texts.format(ClientState.lang, key, vars)
end

-- Имя жанра или темы на языке игрока
function ClientState.localName(item: { name: string, nameEn: string }): string
	return if ClientState.lang == "en" then item.nameEn else item.name
end

Remotes.DataChanged.OnClientEvent:Connect(function(data)
	ClientState.data = data
	changed:Fire()
end)

Remotes.DevelopmentProgress.OnClientEvent:Connect(function()
	if not ClientState.developing then
		ClientState.developing = true
		changed:Fire()
	end
end)

Remotes.GameReleased.OnClientEvent:Connect(function(info)
	ClientState.developing = false
	if type(info.genreId) == "string" and type(info.topicId) == "string" then
		local key = info.genreId .. "/" .. info.topicId
		ClientState.knownCombos[key] = math.max(ClientState.knownCombos[key] or 0, info.score)
	end
	changed:Fire()
end)

return ClientState
