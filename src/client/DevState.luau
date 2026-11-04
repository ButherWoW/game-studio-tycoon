--!strict
-- Снимок слотов разработки и платных эффектов с сервера (PaidRemotes.DevState).
-- Не контроллер: общий модуль для HUD и окна «Создать игру». Решения принимает сервер.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PaidRemotes = require(ReplicatedStorage.Shared.PaidRemotes)
local ShopRemotes = require(ReplicatedStorage.Shared.ShopRemotes)
local ResearchRemotes = require(ReplicatedStorage.Shared.ResearchRemotes)
local ClientState = require(script.Parent.ClientState)

export type ProjectInfo = { id: number, name: string, laptop: boolean }

local DevState = {}

DevState.slots = 1
DevState.busy = 0 -- занятые слоты, включая ждущие фильтр названия
DevState.projects = {} :: { ProjectInfo }
DevState.instantFinish = 0
DevState.autoReleaseOwned = false
DevState.autoReleaseOn = false
DevState.reviewPreview = false
DevState.royaltyPerMinute = 0

local changed = Instance.new("BindableEvent")
DevState.changed = changed.Event

-- Можно ли начать ещё одну игру (сервер всё равно проверит)
function DevState.hasFreeSlot(): boolean
	return DevState.busy < DevState.slots
end

local function num(value: any, default: number): number
	return if type(value) == "number" and value == value then value else default
end

PaidRemotes.DevState.OnClientEvent:Connect(function(state: any)
	if type(state) ~= "table" then
		return
	end
	DevState.slots = num(state.slots, 1)
	DevState.busy = num(state.busy, 0)
	local list: { ProjectInfo } = {}
	if type(state.projects) == "table" then
		for _, p in state.projects do
			if type(p) == "table" and type(p.id) == "number" then
				table.insert(list, { id = p.id, name = tostring(p.name or ""), laptop = p.laptop == true })
			end
		end
	end
	DevState.projects = list
	DevState.instantFinish = num(state.instantFinish, 0)
	DevState.autoReleaseOwned = state.autoReleaseOwned == true
	DevState.autoReleaseOn = state.autoReleaseOn == true
	DevState.reviewPreview = state.reviewPreview == true
	DevState.royaltyPerMinute = num(state.royaltyPerMinute, 0)
	-- Туториал и звуки смотрят на ClientState.developing: держим его по серверу
	ClientState.developing = DevState.busy > 0
	changed:Fire()
end)

-- Заряды покупают в магазине — ShopState приходит сразу после покупки
ShopRemotes.ShopState.OnClientEvent:Connect(function(state: any)
	local boosts = type(state) == "table" and state.boosts
	if type(boosts) == "table" and type(boosts.instantFinish) == "number" then
		DevState.instantFinish = boosts.instantFinish
		changed:Fire()
	end
end)

-- Слоты, тест-группа и издательство зависят от исследований и геймпассов: перезапросить снимок.
-- С задержкой — сервер отвечает не чаще раза в секунду
local requestQueued = false
function DevState.request()
	if requestQueued then
		return
	end
	requestQueued = true
	task.delay(1.1, function()
		requestQueued = false
		PaidRemotes.DevStateRequest:FireServer()
	end)
end
ResearchRemotes.ResearchChanged.OnClientEvent:Connect(DevState.request)
ShopRemotes.ShopState.OnClientEvent:Connect(DevState.request)
-- Первый снимок — когда профиль загружен (до этого сервер не отвечает)
local firstData: RBXScriptConnection? = nil
firstData = Remotes.DataChanged.OnClientEvent:Connect(function()
	if firstData then
		firstData:Disconnect()
		firstData = nil
	end
	DevState.request()
end)

return DevState
