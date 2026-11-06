--!strict
-- Вступление для новичка (4 экрана при первом входе): помнит в профиле, что игрок его уже видел
-- (profile.introSeen), и включает клиенту атрибут игрока IntroActive (true — показать). Сам показ,
-- «Далее» и «Пропустить» — на клиенте (IntroController); туториал и окна входа ждут, пока
-- IntroActive = true. Старое сохранение: кто уже выпускал игры, вступление не видит.
-- Атрибут ставится всегда (true/false): клиент по nil понимает, что сервер ещё не ответил.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IntroRemotes = require(ReplicatedStorage.Shared.IntroRemotes)
local DataService = require(script.Parent.DataService)

local IntroService = {}

local function onLoaded(player: Player, profile: DataService.Profile)
	if profile.introSeen ~= true and (tonumber(profile.gamesReleased) or 0) > 0 then
		profile.introSeen = true
	end
	player:SetAttribute("IntroActive", profile.introSeen ~= true)
end

-- Повторное сообщение (или подделка у игрока, который уже видел вступление) — тихо игнорируем
local function onSeen(player: Player)
	local profile = DataService.get(player)
	if not profile or profile.introSeen == true then
		return
	end
	profile.introSeen = true
	player:SetAttribute("IntroActive", false)
end

function IntroService.start()
	IntroRemotes.IntroSeen.OnServerEvent:Connect(onSeen)
	DataService.onProfileLoaded(onLoaded)
end

return IntroService
