--!strict
-- Всплывающие предложения доната (Config/Offers, общий модуль OfferClient):
--   • этаж: стоит у лифта рядом с 🔒 этажом, игр хватает, а денег нет — пакет дохода под разницу;
--   • забастовка: не хватает на зарплату — пакет, который её покрывает (первую забастовку
--     объясняет StrikeTip, в нём та же кнопка);
--   • стартовый набор: один раз после покупки гаража, не раньше showAfterSeconds сессии.
-- Окна в кулдауне и лимите сессии (OfferClient.canPopup). Выдаёт купленное сервер.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Offers = require(Shared.Config.Offers)
local Texts = require(Shared.Config.Texts)
local Features = require(Shared.Config.Features)
local StudioLayout = require(Shared.StudioLayout)
local ClientState = require(script.Parent.Parent.ClientState)
local RobuxPrice = require(script.Parent.Parent.RobuxPrice)
local OfferClient = require(script.Parent.Parent.OfferClient)

local CHECK_SECONDS = 5
local STRIKE_DELAY = 3 -- дать StrikeTip открыться первой

local player = Players.LocalPlayer
local OfferController = {}

local function onOwnPlot(instance: Instance): boolean
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild(tostring(player:GetAttribute("PlotName")))
	return plot ~= nil and instance:IsDescendantOf(plot)
end

-- Подсказка лифта на закрытый этаж (OfficeFloors: атрибуты FloorArrow/FloorTarget)
local function onPromptShown(prompt: ProximityPrompt)
	if prompt:GetAttribute("FloorArrow") ~= "🔒" or not onOwnPlot(prompt) then
		return
	end
	if not OfferClient.canPopup("floorLock") then
		return
	end
	local floor = tonumber(prompt:GetAttribute("FloorTarget"))
	local stage = floor and StudioLayout.floorStage(floor)
	local data = ClientState.data
	if not stage or not data then
		return
	end
	-- Этаж ещё не вышел (обновление по средам, Config/Features): деньги не помогут
	if not Features.stageReleased(stage.level) then
		return
	end
	-- Не хватает выпущенных игр — деньги не помогут, не предлагаем
	if (tonumber(data.gamesReleased) or 0) < stage.gamesRequired then
		return
	end
	local gap = stage.cost - (tonumber(data.cash) or 0)
	if gap <= 0 then
		return
	end
	local pack = OfferClient.packFor(gap, Offers.floorLock.packs)
	if not pack then
		return
	end
	local product = pack.product
	local floorName = StudioLayout.floorName(ClientState.lang, floor :: number)
	local textKey = if pack.amount >= gap then "offer_floor_text" else "offer_floor_text_partial"
	OfferClient.popup({
		kind = "floorLock",
		title = ClientState.t("offer_floor_title", { money = Texts.money(gap) }),
		lines = {
			ClientState.t(textKey, {
				pack = OfferClient.productName(product),
				amount = Texts.money(pack.amount),
				floor = floorName,
			}),
		},
		buyText = OfferClient.priceText(product.productId, product.robuxPrice),
		onBuy = function()
			OfferClient.buyProduct("floorLock", product.productId)
		end,
	})
end

local function checkStrike()
	-- Первую забастовку объясняет StrikeTip (там та же кнопка)
	if player:GetAttribute("StrikeTipSeen") == false or not OfferClient.canPopup("strike") then
		return
	end
	local pack, gap = OfferClient.strikePack()
	if not pack then
		return
	end
	local product = pack.product
	OfferClient.popup({
		kind = "strike",
		title = ClientState.t("offer_strike_title"),
		lines = {
			ClientState.t("offer_strike_text", {
				money = Texts.money(gap),
				pack = OfferClient.productName(product),
				amount = Texts.money(pack.amount),
			}),
		},
		buyText = ClientState.t(
			"offer_strike_pay",
			{ price = RobuxPrice.of(product.productId, product.robuxPrice) }
		),
		onBuy = function()
			OfferClient.buyProduct("strike", product.productId)
		end,
	})
end

local function checkStarter()
	local state = OfferClient.state
	if state.starterShown or not OfferClient.starterActive() then
		return
	end
	-- Онбординг: только после покупки гаража (в парке — ни одного предложения, canPopup),
	-- не раньше showAfterSeconds сессии, после туториала и окон входа (PopupQueue)
	local ready = player:GetAttribute("OwnsGarage") == true
		and OfferClient.sessionSeconds() >= Offers.starterPack.showAfterSeconds
	if ready and OfferClient.canPopup("starterPack") then
		state.starterShown = true -- сервер запомнит по событию «shown»
		OfferClient.showStarter()
	end
end

function OfferController.start()
	OfferClient.request()
	ProximityPromptService.PromptShown:Connect(onPromptShown)
	player:GetAttributeChangedSignal("StaffStrike"):Connect(function()
		if player:GetAttribute("StaffStrike") == true then
			task.delay(STRIKE_DELAY, checkStrike)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			pcall(checkStarter)
			-- Забастовка затянулась, а окно тогда не показали (было открыто другое) — ещё раз
			if player:GetAttribute("StaffStrike") == true then
				pcall(checkStrike)
			end
		end
	end)
end

return OfferController
