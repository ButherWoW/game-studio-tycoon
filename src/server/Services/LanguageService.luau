--!strict
-- Язык интерфейса игрока: хранится в профиле (profile.lang), клиент спрашивает его при входе.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LanguageRemotes = require(ReplicatedStorage.Shared.LanguageRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local DataService = require(script.Parent.DataService)

local PROFILE_WAIT_SECONDS = 15

local LanguageService = {}

-- Один ожидающий запрос на игрока: спам запросами до загрузки профиля не плодит потоки
local waiting: { [Player]: boolean } = {}

local function onGetLanguage(player: Player): string?
	if waiting[player] then
		return nil
	end
	waiting[player] = true
	local ok, lang = pcall(function()
		-- Профиль грузится из DataStore асинхронно — ждём его, пока игрок в игре
		local deadline = os.clock() + PROFILE_WAIT_SECONDS
		local profile = DataService.get(player)
		while not profile and os.clock() < deadline and player.Parent == Players do
			task.wait(0.25)
			profile = DataService.get(player)
		end
		local saved = profile and (profile :: any).lang
		return if Texts.isLanguage(saved) then saved else nil
	end)
	waiting[player] = nil
	return if ok then lang else nil
end

local function onSetLanguage(player: Player, code: any)
	if not Texts.isLanguage(code) then
		return
	end
	local profile = DataService.get(player)
	if profile then
		(profile :: any).lang = code
	end
end

function LanguageService.start()
	LanguageRemotes.GetLanguage.OnServerInvoke = onGetLanguage
	LanguageRemotes.SetLanguage.OnServerEvent:Connect(onSetLanguage)
end

return LanguageService
