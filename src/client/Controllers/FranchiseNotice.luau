--!strict
-- Тосты франшиз (FranchiseService): итог части франшизы (доход ×, фанаты, усталость)
-- и «хит можно сделать франшизой». Показываем после окна релиза (ClientState.afterReveal).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DepthRemotes = require(ReplicatedStorage.Shared.DepthRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local DepthToast = require(script.Parent.Parent.DepthToast)
local FranchiseClient = require(script.Parent.Parent.FranchiseClient)
local Ui = require(script.Parent.Parent.Ui)

local FranchiseNotice = {}

local function onNotice(info: any)
	if type(info) ~= "table" then
		return
	end
	ClientState.afterReveal(function()
		if type(info.candidate) == "string" then
			DepthToast.show(ClientState.t("fr_candidate", { name = info.candidate }), Ui.colors.money)
			return
		end
		if type(info.name) ~= "string" then
			return
		end
		local delta = tonumber(info.fansDelta) or 0
		DepthToast.show(
			ClientState.t("fr_notice", {
				name = info.name,
				mult = string.format("%.2f", tonumber(info.multiplier) or 1),
				fans = FranchiseClient.fansText(tonumber(info.fans) or 0),
				delta = (if delta >= 0 then "+" else "−") .. FranchiseClient.fansText(math.abs(delta)),
			}),
			if delta >= 0 then Ui.colors.good else Ui.colors.bad
		)
		if info.fatigue == true then
			DepthToast.show(ClientState.t("fr_notice_fatigue"), Ui.colors.bad)
		end
		if info.worse == true then
			DepthToast.show(ClientState.t("fr_notice_worse"), Ui.colors.bad)
		end
	end)
end

function FranchiseNotice.start()
	DepthRemotes.FranchiseNotice.OnClientEvent:Connect(onNotice)
end

return FranchiseNotice
