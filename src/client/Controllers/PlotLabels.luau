--!strict
-- Надписи на кнопках покупки ставит сервер по-русски (он не знает язык игрока).
-- Здесь клиент переписывает их на свой язык: upgrade_<id> / stage_<id> из Locales + цена.
-- Так же — подписи этажей офиса (OfficeFloors): табличка 🔒, пульт и подсказки лифта.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)
local Construction = require(ReplicatedStorage.Shared.Config.Construction)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local StudioLayout = require(ReplicatedStorage.Shared.StudioLayout)
local Features = require(ReplicatedStorage.Shared.Config.Features)
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
	-- Серая кнопка на месте переезда, пока идёт стройка (PlotService, V29)
	if id == "building" then
		return ClientState.t("build_button")
	end
	-- Серая «🔒 Скоро» на месте переезда на этаж, который выходит обновлением по средам
	local soonId = id:match("^soon_(.+)$")
	if soonId then
		for _, stage in Stages do
			if stage.id == soonId then
				local days = Features.daysUntil(Features.stages[stage.level] or "")
				return "🔒 "
					.. ClientState.localName(stage)
					.. "\n"
					.. ClientState.t("upd_soon", { days = days })
			end
		end
		return nil
	end
	local stageId = id:match("^stage_(.+)$")
	if stageId then
		for _, stage in Stages do
			if stage.id == stageId then
				local name = ClientState.localName(stage)
				return ClientState.t("team_move")
					.. ": "
					.. name
					.. "\n"
					.. Texts.money(stage.cost)
					.. "\n"
					.. ClientState.t("move_hint", { minutes = Construction.duration(stage.level) // 60 })
			end
		end
		return nil
	end
	local upgrade = byId[id]
	if not upgrade then
		return nil
	end
	-- Нет перевода в Locales (новые апгрейды) — английское название из Texts.en, не русское
	local name =
		ClientState.localText("upgrade_" .. id, upgrade.name, Texts.en["upgrade_" .. id] or upgrade.name)
	local price = if upgrade.cost <= 0 then ClientState.t("price_free") else Texts.money(upgrade.cost)
	-- Что даёт предмет: очки в секунду (оценка), скорость, бонус к оценке
	local bonuses = {}
	if upgrade.pointsPerSecond then
		table.insert(bonuses, ClientState.t("bonus_pps", { value = upgrade.pointsPerSecond }))
	end
	local speed = (upgrade :: any).speed
	if type(speed) == "number" then
		table.insert(bonuses, ClientState.t("bonus_speed", { value = math.floor(speed * 100 + 0.5) }))
	end
	local review = (upgrade :: any).reviewBonus
	if type(review) == "number" then
		table.insert(bonuses, ClientState.t("bonus_review", { value = review }))
	end
	local line = (if upgrade.move then "🏢 " else "") .. name .. "\n" .. price
	if upgrade.move and upgrade.cost > 0 then
		for _, stage in Stages do
			if stage.requiresUpgrade == id then
				local minutes = Construction.duration(stage.level) // 60
				line ..= "\n" .. ClientState.t("move_hint", { minutes = minutes })
			end
		end
	end
	if #bonuses > 0 then
		line ..= "\n" .. table.concat(bonuses, " · ")
	end
	return line
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

-- Подписи этажей по атрибутам, которые ставит OfficeFloors
local function relabelFloor(item: Instance)
	local lang = ClientState.lang
	if item:IsA("TextLabel") then
		local sign = item:GetAttribute("FloorSign")
		local lift = item:GetAttribute("FloorLift")
		if type(sign) == "number" then
			item.Text = StudioLayout.floorSign(lang, sign)
			-- Этаж строится: цену и условия не показываем, как у обычного 🔒
			local floorStage = StudioLayout.floorStage(sign)
			local ancestor: Instance? = item.Parent
			while ancestor and ancestor:GetAttribute("BuildingStage") == nil do
				ancestor = ancestor.Parent
			end
			if floorStage and ancestor and ancestor:GetAttribute("BuildingStage") == floorStage.level then
				item.Text = "🏗️ "
					.. StudioLayout.floorName(lang, sign)
					.. "\n"
					.. ClientState.t("build_lock_building")
			end
		elseif type(lift) == "number" then
			item.Text = "🛗 " .. StudioLayout.floorName(lang, lift)
		end
	elseif item:IsA("ProximityPrompt") then
		local target = item:GetAttribute("FloorTarget")
		local arrow = item:GetAttribute("FloorArrow")
		if type(target) == "number" and type(arrow) == "string" then
			item.ActionText = arrow .. " " .. StudioLayout.floorName(lang, target)
			item.ObjectText = ClientState.t("floor_lift")
		end
		local cost = item:GetAttribute("MoveCost")
		local minutes = item:GetAttribute("MoveMinutes")
		if type(cost) == "number" and type(minutes) == "number" then
			item.ActionText = ClientState.t("move_prompt_action")
			item.ObjectText =
				ClientState.t("move_prompt_object", { price = Texts.money(cost), minutes = minutes })
		end
	end
end

local function isFloorText(item: Instance): boolean
	return item:GetAttribute("MoveCost") ~= nil
		or item:GetAttribute("FloorSign") ~= nil
		or item:GetAttribute("FloorLift") ~= nil
		or item:GetAttribute("FloorTarget") ~= nil
end

local function relabelAll()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return
	end
	for _, d in plots:GetDescendants() do
		if d.Name:sub(1, 4) == "Buy_" then
			relabel(d)
		elseif isFloorText(d) then
			relabelFloor(d)
		end
	end
end

function PlotLabels.start()
	-- Кнопки пересоздаются после каждой покупки — ловим новые
	workspace.DescendantAdded:Connect(function(d)
		if d.Name:sub(1, 4) == "Buy_" then
			-- BillboardGui прилетает чуть позже самой кнопки
			task.defer(relabel, d)
		elseif d:IsA("TextLabel") or d:IsA("ProximityPrompt") then
			task.defer(function()
				if isFloorText(d) then
					relabelFloor(d)
				end
			end)
		end
	end)
	ClientState.changed:Connect(relabelAll)
	relabelAll()
end

return PlotLabels
