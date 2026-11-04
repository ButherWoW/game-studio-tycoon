--!strict
-- Тосты своей консоли и стримера (ConsoleService, StreamerService): этап готов, консоль вышла,
-- хайп стрима добавил к доходу игры. Показываем после окна релиза (ClientState.afterReveal).
-- Снимок консоли сервер шлёт при входе; клиент просит заново, когда сменился этап студии.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConsoleRemotes = require(ReplicatedStorage.Shared.ConsoleRemotes)
local Console = require(ReplicatedStorage.Shared.Config.Console)
local ClientState = require(script.Parent.Parent.ClientState)
local ConsoleClient = require(script.Parent.Parent.ConsoleClient)
local DepthToast = require(script.Parent.Parent.DepthToast)
local Ui = require(script.Parent.Parent.Ui)

local ConsoleNotice = {}

local function onNotice(info: any)
	if type(info) ~= "table" then
		return
	end
	ClientState.afterReveal(function()
		if info.kind == "launched" then
			DepthToast.show(ClientState.t("console_notice_launched"), Ui.colors.good)
		elseif info.kind == "stageDone" then
			local stage = Console.stages[tonumber(info.stage) or 0]
			if stage then
				DepthToast.show(
					ClientState.t(
						"console_notice_stage",
						{ stage = ClientState.t("console_stage_" .. stage.id) }
					),
					Ui.colors.good
				)
			end
		elseif info.kind == "hype" then
			DepthToast.show(
				ClientState.t("streamer_notice_hype", { percent = tonumber(info.percent) or 0 }),
				Ui.colors.money
			)
		end
	end)
end

function ConsoleNotice.start()
	ConsoleRemotes.ConsoleNotice.OnClientEvent:Connect(onNotice)
	-- Этап студии поменялся (офис, 3-й этаж) — платформы и стример могли открыться
	local level = -1
	ClientState.changed:Connect(function()
		local data = ClientState.data
		local current = if data then data.studioLevel else -1
		if current ~= level then
			level = current
			ConsoleClient.request()
		end
	end)
end

return ConsoleNotice
