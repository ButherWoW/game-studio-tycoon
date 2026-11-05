--!strict
-- Звуки игровых моментов (проход «звуки», docs/SOUNDS.md): слушаем remotes и атрибуты, которые
-- уже шлёт сервер, и зовём SoundController — без правки окон и сервисов. Каждый блок — в своём
-- потоке: если чьих-то remotes нет (упал серверный модуль), остальные звуки всё равно работают.
-- Ключи и id — Config/Sounds. Новые моменты других фич: SoundController.play(key) / playAt(key, part).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundController = require(script.Parent.SoundController)

local player = Players.LocalPlayer

local SoundEvents = {}

local function play(key: string)
	SoundController.play(key)
end

-- require remotes-модуля в отдельном потоке (их require ждёт папку с сервера)
local function withRemotes(name: string, connect: (remotes: any) -> ())
	task.spawn(function()
		local module = Shared:WaitForChild(name, 60)
		if not module or not module:IsA("ModuleScript") then
			return
		end
		local ok, err = pcall(function()
			connect(require(module) :: any)
		end)
		if not ok then
			warn("[SoundEvents] " .. name .. ":", err)
		end
	end)
end

-- Атрибут игрока или ReplicatedStorage сменился: (старое, новое)
local function onAttribute(target: Instance, attribute: string, callback: (any, any) -> ())
	local last = target:GetAttribute(attribute)
	target:GetAttributeChangedSignal(attribute):Connect(function()
		local value = target:GetAttribute(attribute)
		local before = last
		last = value
		callback(before, value)
	end)
end

local function parkSafe(): Instance?
	local park = workspace:FindFirstChild("StartPark")
	return park and park:FindFirstChild("ParkSafe")
end

-- Звук у сейфа (3D), если модели нет — обычный
local function playAtSafe(key: string)
	local safe = parkSafe()
	if safe then
		SoundController.playAt(key, safe)
	else
		play(key)
	end
end

local DAILY_TOASTS: { [string]: string } = {
	devent_bug_caught = "bug_catch",
	devent_investor_got = "investor_grant",
	devent_blitz_win = "blitz_win",
	devent_bug_limit = "error",
}

local STOCK_MESSAGES: { [string]: string } = {
	stock_bought = "stock_buy",
	stock_sold = "stock_sell",
	stock_ipo_done = "ipo_bell",
	stock_bankrupt_owner = "company_event_bad",
	stock_bankrupt_holder = "company_event_bad",
}

local SAFE_RESULTS: { [string]: string } = {
	ok = "safe_open",
	wrong = "safe_wrong",
	used = "safe_wrong",
	empty = "safe_wrong",
}

function SoundEvents.start()
	-- ===== Атрибуты: события дня, Золотой час, зарплата, налоги, приставы, IPO =====
	onAttribute(ReplicatedStorage, "DailyEventActive", function(before, value)
		if value == true and before ~= true then
			play("daily_event_start")
		end
	end)
	onAttribute(ReplicatedStorage, "DailyGoldenActive", function(before, value)
		if value == true and before ~= true then
			play("golden_hour")
		end
	end)
	onAttribute(player, "PaydayCount", function()
		if (tonumber(player:GetAttribute("PaydayPaid")) or 0) > 0 then
			play("payday")
		end
	end)
	onAttribute(player, "TaxBill", function(before, value)
		if (tonumber(before) or 0) > 0 and (tonumber(value) or 0) == 0 then
			play("tax_paid")
		end
	end)
	onAttribute(player, "BailiffsActive", function(before, value)
		if value == true and before ~= true then
			play("bailiff_knock")
		end
	end)

	-- Дверь: вошёл на свой участок или вышел с него (по смене музыки места)
	SoundController.onMusicChanged(function(before: string?, after: string)
		if not before or before == "music_golden" or after == "music_golden" then
			return
		end
		if (before == "music_park") ~= (after == "music_park") then
			play("door")
		end
	end)

	-- Лифт: пульт этажа (ProximityPrompt с атрибутом FloorTarget, не закрытый 🔒)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt:GetAttribute("FloorTarget") ~= nil and prompt:GetAttribute("FloorArrow") ~= "🔒" then
			local parent = prompt.Parent
			if parent then
				SoundController.playAt("elevator_ding", parent)
			end
		end
	end)

	-- Покупка за Robux прошла
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, _, purchased: boolean)
		if purchased and userId == player.UserId then
			play("purchase_robux_thanks")
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who: Player, _, purchased: boolean)
		if purchased and who == player then
			play("purchase_robux_thanks")
		end
	end)

	-- ===== Remotes =====
	withRemotes("DailyEventRemotes", function(remotes)
		remotes.DailyEventToast.OnClientEvent:Connect(function(payload: any)
			if type(payload) == "table" and type(payload.key) == "string" then
				local key = DAILY_TOASTS[payload.key]
				if key then
					play(key)
				end
			end
		end)
	end)

	withRemotes("StartRemotes", function(remotes)
		remotes.ParkNotice.OnClientEvent:Connect(function(payload: any)
			local kind = type(payload) == "table" and payload.kind
			if kind == "cartridge" then
				play("coin_pickup")
			elseif kind == "pawn" then
				play("pawn_sell")
			elseif kind == "full" then
				play("error")
			end
		end)
		remotes.JobResult.OnClientEvent:Connect(function(payload: any)
			if type(payload) == "table" then
				play(if payload.ok then "money" else "error")
			end
		end)
	end)

	withRemotes("HitRemotes", function(remotes)
		remotes.HitAlarm.OnClientEvent:Connect(function(payload: any)
			if type(payload) == "table" and payload.stop ~= true then
				play("theft_alarm")
			end
		end)
		remotes.HitToast.OnClientEvent:Connect(function(payload: any)
			local key = type(payload) == "table" and payload.key
			if type(key) == "string" then
				play(if string.find(key, "_err_", 1, true) then "error" else "toast")
			end
		end)
	end)

	withRemotes("BailiffRemotes", function(remotes)
		remotes.BailiffSeized.OnClientEvent:Connect(function(payload: any)
			if type(payload) == "table" and payload.left ~= true then
				play("bailiff_knock")
			end
		end)
	end)

	withRemotes("SocialRemotes", function(remotes)
		remotes.SocialNotice.OnClientEvent:Connect(function(payload: any)
			local kind = type(payload) == "table" and payload.kind
			if kind == "giftReceived" or kind == "groupReward" then
				play("gift_received")
			elseif kind == "giftUnavailable" or kind == "giftOwned" then
				play("error")
			elseif type(kind) == "string" then
				play("toast")
			end
		end)
	end)

	withRemotes("LiveOpsRemotes", function(remotes)
		remotes.LiveOpsToast.OnClientEvent:Connect(function()
			play("toast")
		end)
	end)

	withRemotes("CompanyEventRemotes", function(remotes)
		remotes.CompanyEvent.OnClientEvent:Connect(function(payload: any)
			local kind = type(payload) == "table" and payload.kind
			if kind == "good" then
				play("company_event_good")
			elseif kind == "bad" then
				play("company_event_bad")
			end
		end)
	end)

	withRemotes("QuickRemotes", function(remotes)
		remotes.QuickEventResult.OnClientEvent:Connect(function(payload: any)
			local grade = type(payload) == "table" and payload.grade
			if grade == "perfect" then
				play("qte_perfect")
			elseif grade == "good" then
				play("qte_hit")
			elseif grade == "miss" or grade == "ignored" then
				play("qte_miss")
			end
		end)
	end)

	withRemotes("SafeRemotes", function(remotes)
		remotes.SafeResult.OnClientEvent:Connect(function(payload: any)
			local reason = type(payload) == "table" and payload.reason
			if type(reason) == "string" then
				playAtSafe(SAFE_RESULTS[reason] or "error")
			end
		end)
	end)

	withRemotes("StockRemotes", function(remotes)
		remotes.StockState.OnClientEvent:Connect(function(payload: any)
			local message = type(payload) == "table" and payload.message
			if type(message) == "string" then
				play(
					STOCK_MESSAGES[message]
						or (if string.find(message, "_err_", 1, true) then "error" else "toast")
				)
			end
		end)
	end)

	withRemotes("RetentionRemotes", function(remotes)
		remotes.RebirthResult.OnClientEvent:Connect(function(payload: any)
			if type(payload) == "table" then
				play(if payload.ok then "rebirth_whoosh" else "error")
			end
		end)
	end)

	withRemotes("ConsoleRemotes", function(remotes)
		remotes.ConsoleNotice.OnClientEvent:Connect(function(payload: any)
			local kind = type(payload) == "table" and payload.kind
			if kind == "stageDone" then
				play("console_stage_done")
			elseif kind == "launched" then
				play("console_launched")
			end
		end)
	end)

	withRemotes("MascotRemotes", function(remotes)
		local equipped: any = nil
		local first = true
		remotes.MascotState.OnClientEvent:Connect(function(payload: any)
			if type(payload) ~= "table" then
				return
			end
			local now = payload.equipped
			if not first and now ~= nil and now ~= equipped then
				play("mascot_squeak")
			end
			first = false
			equipped = now
		end)
	end)
end

return SoundEvents
