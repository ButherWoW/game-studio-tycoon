--!strict
-- Капитал игрока для таблички над головой (CapitalTags на клиентах): атрибут игрока "Capital"
-- (целые $), обновляется раз в 2 секунды и только при изменении. Деньги другим клиентам напрямую
-- не уходят — профиль на сервере, видна только эта сумма.

local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)

local ATTRIBUTE = "Capital"
local INTERVAL = 2

local CapitalService = {}

local function refresh(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local cash = profile.cash
	if type(cash) ~= "number" or cash ~= cash then
		return
	end
	local value = math.max(0, math.floor(cash))
	if player:GetAttribute(ATTRIBUTE) ~= value then
		player:SetAttribute(ATTRIBUTE, value)
	end
end

function CapitalService.start()
	task.spawn(function()
		while true do
			task.wait(INTERVAL)
			for _, player in Players:GetPlayers() do
				refresh(player)
			end
		end
	end)
end

return CapitalService
