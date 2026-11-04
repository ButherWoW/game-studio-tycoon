--!strict
-- Снимок окна «Студия» с сервера (DecorService): купленный декор, настроение команды с разбором,
-- интерьер этажей с причинами замков. Общий для окна «Студия», «Команды» и HUD.
-- Remotes ждём в своём потоке: HUD требует этот модуль и не должен зависнуть, если серверный
-- DecorService не поднялся.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local remotes: { [string]: RemoteEvent }? = nil
local Mood = require(Shared.Config.Mood)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

export type MoodPart = { key: string, value: number, vars: { [string]: any }? }
export type MoodInfo = {
	value: number,
	target: number,
	staff: number,
	active: boolean,
	speed: number,
	review: number,
	parts: { MoodPart },
}
export type Offer = {
	id: string,
	cost: number,
	floor: number,
	move: boolean?,
	stage: number?,
	lock: string?,
	lockVars: { [string]: any }?,
}
export type State = {
	owned: { [string]: boolean },
	floorsOpen: number,
	studioLevel: number,
	ownsGarage: boolean,
	mood: MoodInfo?,
	offers: { Offer },
}

local StudioState = {}
StudioState.state = { owned = {}, floorsOpen = 1, studioLevel = 1, ownsGarage = false, offers = {} } :: State
local changedEvent = Instance.new("BindableEvent")
StudioState.changed = changedEvent.Event

function StudioState.request()
	if remotes then
		remotes.StudioStateRequest:FireServer()
	end
end

-- Цвет настроения: красный / жёлтый / зелёный (Config/Mood)
function StudioState.moodColor(value: number): Color3
	if value < Mood.redBelow then
		return Ui.colors.bad
	elseif value < Mood.yellowBelow then
		return Ui.colors.money
	end
	return Ui.colors.good
end

local function signed(n: number): string
	local text = string.format("%.1f", math.abs(n)):gsub("%.0$", "")
	return (if n < 0 then "−" else "+") .. text
end
StudioState.signed = signed

-- Строки разбора: «+6 Удобства студии», «−9 Теснота (3 сотр.)» и эффекты
function StudioState.moodLines(info: MoodInfo): { string }
	local lines = {}
	for _, part in info.parts do
		local vars = table.clone(part.vars or {})
		table.insert(lines, signed(part.value) .. "  " .. ClientState.t(part.key, vars))
	end
	if info.active then
		table.insert(lines, ClientState.t("mood_effect_speed", { mult = string.format("%.2f", info.speed) }))
		if info.review ~= 0 then
			table.insert(lines, ClientState.t("mood_effect_review", { n = signed(info.review) }))
		end
	else
		table.insert(lines, ClientState.t("mood_no_staff"))
	end
	return lines
end

local function listen()
	local DecorRemotes = require(Shared.DecorRemotes)
	remotes = DecorRemotes
	DecorRemotes.StudioState.OnClientEvent:Connect(function(newState: any)
		if
			type(newState) ~= "table"
			or type(newState.owned) ~= "table"
			or type(newState.offers) ~= "table"
		then
			return
		end
		StudioState.state = newState
		changedEvent:Fire()
	end)
end

-- Подписка при первом require (модуль кэшируется — один раз)
task.spawn(listen)

return StudioState
