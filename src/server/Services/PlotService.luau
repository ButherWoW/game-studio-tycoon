--!strict
-- Участки и тайкун-апгрейды.
-- В Workspace нужна папка Plots с частями Plot1..PlotN (точка привязки участка),
-- в ServerStorage — папка Upgrades с моделями (имена из Config/Upgrades).
-- Если их нет в плейсе, WorldService создаёт их сам при старте сервера.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local DataService = require(script.Parent.DataService)

local PlotService = {}
local owners: { [BasePart]: Player } = {}

local function getPlot(player: Player): BasePart?
	for plot, owner in owners do
		if owner == player then
			return plot
		end
	end
	return nil
end

local function placeUpgrade(plot: BasePart, upgrade: Upgrades.Upgrade)
	local folder = ServerStorage:FindFirstChild("Upgrades")
	local template = folder and folder:FindFirstChild(upgrade.model)
	if not template or not template:IsA("Model") then
		warn("[PlotService] Missing model", upgrade.model)
		return
	end
	local model = template:Clone()
	-- Модели в ServerStorage построены относительно точки (0,0,0)
	model:PivotTo(plot.CFrame * model:GetPivot())
	model.Parent = plot
end

local function assignPlot(player: Player)
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then
		warn("[PlotService] workspace.Plots not found")
		return
	end
	for _, plot in plotsFolder:GetChildren() do
		if plot:IsA("BasePart") and not owners[plot] then
			owners[plot] = player
			player:SetAttribute("PlotName", plot.Name)
			-- Восстанавливаем купленное
			task.spawn(function()
				local profile
				repeat
					profile = DataService.get(player)
					task.wait(0.2)
				until profile or not player.Parent
				if not profile then
					return
				end
				for _, upgrade in Upgrades do
					if profile.upgrades[upgrade.id] then
						placeUpgrade(plot, upgrade)
					end
				end
			end)
			return
		end
	end
	warn("[PlotService] No free plots")
end

local function onBuyUpgrade(player: Player, upgradeId: any)
	if type(upgradeId) ~= "string" then
		return
	end
	local profile = DataService.get(player)
	local plot = getPlot(player)
	if not profile or not plot then
		return
	end
	for _, upgrade in Upgrades do
		if upgrade.id == upgradeId then
			if profile.upgrades[upgrade.id] then
				return
			end
			if upgrade.requires and not profile.upgrades[upgrade.requires] then
				return
			end
			if DataService.trySpend(player, upgrade.cost) then
				profile.upgrades[upgrade.id] = true
				placeUpgrade(plot, upgrade)
				DataService.replicate(player)
			end
			return
		end
	end
end

function PlotService.start()
	Players.PlayerAdded:Connect(assignPlot)
	for _, player in Players:GetPlayers() do
		assignPlot(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local plot = getPlot(player)
		if plot then
			owners[plot] = nil
			for _, child in plot:GetChildren() do
				if child:IsA("Model") then
					child:Destroy()
				end
			end
		end
	end)
	Remotes.BuyUpgrade.OnServerEvent:Connect(onBuyUpgrade)
end

return PlotService
