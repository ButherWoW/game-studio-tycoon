--!strict
-- Последние данные игрока с сервера и язык интерфейса — общие для всех контроллеров.

local LocalizationService = game:GetService("LocalizationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local LanguageRemotes = require(ReplicatedStorage.Shared.LanguageRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)

local ClientState = {}

-- Снимок из DataService.replicate (nil, пока сервер не прислал)
ClientState.data = nil :: any
ClientState.developing = false

-- Код языка Roblox ("pt-br", "nb-no", "zh-cn"…) -> код из Texts.languages; нет такого -> en
local LOCALE_ALIASES: { [string]: string } = {
	nb = "no",
	nn = "no",
	zh = "zh-cn",
	ua = "uk",
	sh = "sr",
}

local function languageFromLocale(locale: string): Texts.Lang
	local id: string = (locale:lower():gsub("_", "-"))
	if Texts.isLanguage(id) then
		return id
	end
	local base = id:match("^(%a+)") or ""
	base = LOCALE_ALIASES[base] or base
	return if Texts.isLanguage(base) then base else "en"
end

ClientState.lang = languageFromLocale(LocalizationService.RobloxLocaleId) :: Texts.Lang
-- Сочетания, которые игрок уже выпускал в этой сессии: "genre/topic" -> лучшая оценка
ClientState.knownCombos = {} :: { [string]: number }

local changed = Instance.new("BindableEvent")
ClientState.changed = changed.Event

function ClientState.t(key: string, vars: { [string]: any }?): string
	return Texts.format(ClientState.lang, key, vars)
end

-- Сменить язык: перерисовать интерфейс и (если save ~= false) запомнить выбор на сервере
function ClientState.setLang(code: string, save: boolean?)
	if not Texts.isLanguage(code) then
		return
	end
	if save ~= false then
		LanguageRemotes.SetLanguage:FireServer(code)
	end
	if code ~= ClientState.lang then
		ClientState.lang = code
		changed:Fire()
	end
end

-- Текст из конфига на языке игрока: перевод по ключу из Locales, иначе поля ru/en конфига
function ClientState.localText(key: string, ru: string, en: string): string
	return Texts.lookup(ClientState.lang, key) or (if ClientState.lang == "ru" then ru else en)
end

-- Имя жанра или темы на языке игрока: перевод genre_<id>/topic_<id>, иначе name/nameEn
function ClientState.localName(item: { name: string, nameEn: string }): string
	local id = (item :: any).id
	local prefix = if type(id) ~= "string"
		then nil
		elseif (Genres :: any)[id] == item then "genre_"
		elseif (Topics :: any)[id] == item then "topic_"
		elseif (Stages :: any)[(item :: any).level] == item then "stage_"
		else nil
	if prefix then
		local translated = Texts.lookup(ClientState.lang, prefix .. id)
		if translated then
			return translated
		end
	end
	return if ClientState.lang == "ru" then item.name else item.nameEn
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
