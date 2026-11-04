--!strict
-- Надписи на кнопках покупки ставит сервер по-русски (он не знает язык игрока).
-- Здесь клиент переписывает их на свой язык: upgrade_<id> / stage_<id> из Locales + цена.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)

local PlotLabels = {}

local byId: { [string]: Upgrades.Upgrade } = {}
for _, upgrade in Upgrades do
	byId[upgrade.id] = upgrade
end

local function labelFor(buttonName: string): string?
	local id = buttonName:match("^Buy_(.+)$")
	if not id then
		return nil
	end
	local stageId = id:match("^stage_(.+)$")
	if stageId then
		for _, stage in Stages do
			if stage.id == stageId then
				local name = ClientState.localName(stage)
				return ClientState.t("team_move") .. ": " .. name .. "\n" .. Texts.money(stage.cost)
			end
		end
		return nil
	end
	local upgrade = byId[id]
	if not upgrade then
		return nil
	end
	local name = ClientState.localText("upgrade_" .. id, upgrade.name, upgrade.name)
	local price = if upgrade.cost <= 0 then ClientState.t("price_free") else Texts.money(upgrade.cost)
	return (if upgrade.move then "🏢 " else "") .. name .. "\n" .. price
end

local function relabel(button: Instance)
	if not button:IsA("BasePart") then
		return
	end
	local text = labelFor(button.Name)
	local label = button:FindFirstChildWhichIsA("BillboardGui")
	local textLabel = label and label:FindFirstChildWhichIsA("TextLabel")
	if text and textLabel then
		textLabel.Text = text
	end
end

local function relabelAll()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return
	end
	for _, d in plots:GetDescendants() do
		if d.Name:sub(1, 4) == "Buy_" then
			relabel(d)
		end
	end
end

function PlotLabels.start()
	-- Кнопки пересоздаются после каждой покупки — ловим новые
	workspace.DescendantAdded:Connect(function(d)
		if d.Name:sub(1, 4) == "Buy_" then
			-- BillboardGui прилетает чуть позже самой кнопки
			task.defer(relabel, d)
		end
	end)
	ClientState.changed:Connect(relabelAll)
	relabelAll()
end

return PlotLabels
