--!strict
-- Опт-ин уведомлений Roblox (Config/Friends.notify). Окно «Включить уведомления» показывает
-- только клиент (ExperienceNotificationService:PromptOptIn), сервер решает, когда пора:
-- один раз, после важного момента — гараж куплен в этой сессии или (гараж уже был) первый релиз
-- в сессии, не раньше minSessionSeconds после входа. Клиент отвечает NotifyResult:
-- "closed" — окно показали (больше не предлагаем), "unavailable" — Roblox не дал показать
-- (Studio, возраст, выключено в настройках): пробуем в следующих сессиях, всего maxTries раз.
-- Сами уведомления шлёт внешний сервис через Open Cloud (docs/NOTIFY_REFER_TRADE.md).
-- Данные: (profile :: any).notify = { prompted, at, tries } (лениво, defaultProfile не трогаем).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Friends = require(Shared.Config.Friends)
local FriendRemotes = require(Shared.FriendRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

type Session = {
	joinedAt: number,
	hadGarage: boolean, -- гараж был уже при входе
	games: number, -- выпущено игр при входе
	asked: boolean, -- в этой сессии уже предлагали
	answered: boolean, -- клиент ответил (второй ответ не считаем)
}

type NotifyData = { prompted: boolean, at: number, tries: number }

local NotifyService = {}
local sessions: { [Player]: Session } = {}

local function data(profile: DataService.Profile): NotifyData
	local p = profile :: any
	local raw = p.notify
	if type(raw) ~= "table" then
		raw = {}
	end
	local clean: NotifyData = {
		prompted = raw.prompted == true,
		at = tonumber(raw.at) or 0,
		tries = math.max(math.floor(tonumber(raw.tries) or 0), 0),
	}
	p.notify = clean
	return clean
end

local function logPrompt(player: Player, field: string)
	local analytics = script.Parent:FindFirstChild("AnalyticsService")
	if analytics and analytics:IsA("ModuleScript") then
		pcall((require(analytics) :: any).logDepth, player, "notifyPrompt", field)
	end
end

local function check(player: Player, session: Session)
	if session.asked then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local notify = data(profile)
	if notify.prompted or notify.tries >= Friends.notify.maxTries then
		session.asked = true
		return
	end
	if os.clock() - session.joinedAt < Friends.notify.minSessionSeconds then
		return
	end
	if not PlotService.ownsGarage(player) then
		return
	end
	-- Важный момент: гараж куплен в этой сессии или (гараж был) вышла игра
	if session.hadGarage and profile.gamesReleased <= session.games then
		return
	end
	session.asked = true
	FriendRemotes.NotifyPrompt:FireClient(player)
end

local function onResult(player: Player, result: any)
	local session = sessions[player]
	local profile = DataService.get(player)
	-- Ответ принимаем один раз и только если сервер сам предложил
	if not session or not session.asked or session.answered or not profile then
		return
	end
	session.answered = true
	local notify = data(profile)
	if notify.prompted then
		return
	end
	if result == "closed" then
		notify.prompted = true
		notify.at = os.time()
		logPrompt(player, "shown")
	elseif result == "unavailable" then
		notify.tries += 1
		-- Повтор в этой сессии не нужен: Roblox не передумает
		logPrompt(player, "unavailable")
	end
end

function NotifyService.start()
	DataService.onProfileLoaded(function(player: Player, profile: DataService.Profile)
		sessions[player] = {
			joinedAt = os.clock(),
			hadGarage = PlotService.ownsGarage(player),
			games = profile.gamesReleased,
			asked = false,
			answered = false,
		}
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
	FriendRemotes.NotifyResult.OnServerEvent:Connect(onResult)
	task.spawn(function()
		while true do
			task.wait(Friends.notify.checkSeconds)
			for player, session in sessions do
				if player.Parent then
					check(player, session)
				end
			end
		end
	end)
end

return NotifyService
