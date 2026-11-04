--!strict
-- Контракты издателей (ContractService): окно предложения «Принять / Отказаться» по правилам
-- всплывающих окон (OfferClient.canPopup: кулдаун, лимит сессии, не поверх окон), плашка под HUD
-- (предложение — нажми, чтобы открыть; активный — прогресс и срок) и тосты итога.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local DepthRemotes = require(Shared.DepthRemotes)
local Genres = require(Shared.Config.Genres)
local Topics = require(Shared.Config.Topics)
local Texts = require(Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local OfferClient = require(script.Parent.Parent.OfferClient)
local DepthToast = require(script.Parent.Parent.DepthToast)
local Ui = require(script.Parent.Parent.Ui)

local BANNER_HEIGHT = 26
local BANNER_WIDTH = 400
local CHECK_SECONDS = 2

local ContractController = {}

local state: any = nil
local receivedAt = 0 -- os.clock() прихода состояния: срок активного тикает от него
local poppedId: number? = nil -- предложение, окно которого уже показали само

local function formatTime(seconds: number): string
	local s = math.max(math.floor(seconds), 0)
	return string.format("%d:%02d", s // 60, s % 60)
end

local function localName(map: { [string]: any }, id: any): string
	local item = if type(id) == "string" then map[id] else nil
	return if item then ClientState.localName(item) else tostring(id)
end

local function requirement(c: any): string
	local vars = {
		count = c.count,
		score = c.minScore,
		genre = localName(Genres, c.genreId),
		topic = localName(Topics, c.topicId),
	}
	return ClientState.t("contract_req_" .. tostring(c.kind), vars)
end

local function goal(c: any): string
	return ClientState.t("contract_goal_" .. tostring(c.kind), {
		score = c.minScore,
		genre = localName(Genres, c.genreId),
		topic = localName(Topics, c.topicId),
	})
end

local function respond(offer: any, accept: boolean)
	DepthRemotes.ContractRespond:FireServer(offer.id, accept)
end

local function showPopup(offer: any)
	poppedId = offer.id
	local factor = tonumber(state and state.repayFactor) or 1.25
	OfferClient.popup({
		kind = "contract",
		title = ClientState.t(
			"contract_title",
			{ publisher = offer.publisherIcon .. " " .. offer.publisherName }
		),
		lines = {
			requirement(offer),
			ClientState.t("contract_terms", {
				minutes = math.floor((tonumber(offer.seconds) or 0) / 60),
				advance = Texts.money(tonumber(offer.advance) or 0),
			}),
			ClientState.t("contract_reward", {
				bonus = Texts.money(tonumber(offer.bonus) or 0),
				penalty = Texts.money(math.ceil((tonumber(offer.advance) or 0) * factor)),
			}),
		},
		buyText = ClientState.t("contract_accept"),
		onBuy = function()
			respond(offer, true)
		end,
		laterText = ClientState.t("contract_decline"),
		onLater = function()
			respond(offer, false)
		end,
		countdown = function(left: number): string
			return ClientState.t("contract_expires", { time = formatTime(left) })
		end,
		endsAt = tonumber(offer.expiresAt),
	})
end

local function buildBanner(): TextButton
	local banner = Instance.new("TextButton")
	banner.Name = "ContractBanner"
	banner.LayoutOrder = 5
	banner.Size = UDim2.fromOffset(BANNER_WIDTH, BANNER_HEIGHT)
	banner.BackgroundTransparency = 0.25
	banner.BackgroundColor3 = Ui.colors.panel
	banner.TextColor3 = Ui.colors.money
	banner.TextScaled = true
	banner.AutoButtonColor = false
	banner.Text = ""
	banner.Visible = false
	Ui.corner(banner, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.Parent = banner
	banner.Parent = Ui.bannerStack()
	return banner
end

function ContractController.start()
	local banner = buildBanner()
	banner.Activated:Connect(function()
		local offer = state and state.offer
		if type(offer) == "table" and not Ui.anyWindowOpen() then
			showPopup(offer)
		end
	end)

	local function refresh()
		banner.Font = Ui.titleFontFor(ClientState.lang)
		local active = state and state.active
		local offer = state and state.offer
		if type(active) == "table" then
			local left = (tonumber(active.remaining) or 0) - (os.clock() - receivedAt)
			banner.Visible = true
			banner.TextColor3 = if left < 60 then Ui.colors.bad else Ui.colors.money
			banner.Text = ClientState.t("contract_banner_active", {
				publisher = active.publisherName,
				progress = active.progress,
				count = active.count,
				goal = goal(active),
				time = formatTime(left),
			})
		elseif type(offer) == "table" then
			local left = (tonumber(offer.expiresAt) or 0) - workspace:GetServerTimeNow()
			banner.Visible = left > 0
			banner.TextColor3 = Ui.colors.good
			banner.Text = ClientState.t("contract_banner_offer", {
				publisher = offer.publisherName,
				time = formatTime(left),
			})
		else
			banner.Visible = false
		end
	end

	DepthRemotes.ContractState.OnClientEvent:Connect(function(newState: any)
		if type(newState) ~= "table" then
			return
		end
		state = newState
		receivedAt = os.clock()
		refresh()
	end)
	DepthRemotes.ContractResult.OnClientEvent:Connect(function(info: any)
		if type(info) ~= "table" then
			return
		end
		local amount = Texts.money(tonumber(info.amount) or 0)
		if info.result == "accepted" then
			DepthToast.show(ClientState.t("contract_accepted", { amount = amount }), Ui.colors.money)
		elseif info.result == "done" then
			ClientState.afterReveal(function()
				DepthToast.show(
					ClientState.t("contract_done", { publisher = info.publisher, amount = amount }),
					Ui.colors.good
				)
			end)
		elseif info.result == "failed" then
			DepthToast.show(
				ClientState.t("contract_failed", { publisher = info.publisher, amount = amount }),
				Ui.colors.bad
			)
		end
	end)
	DepthRemotes.ContractRequest:FireServer()

	task.spawn(function()
		local sinceCheck = 0
		while true do
			task.wait(1)
			refresh()
			sinceCheck += 1
			if sinceCheck >= CHECK_SECONDS then
				sinceCheck = 0
				-- Новое предложение: окно само — только когда правила всплывающих окон разрешают
				local offer = state and state.offer
				if type(offer) == "table" and offer.id ~= poppedId and OfferClient.canPopup("contract") then
					local left = (tonumber(offer.expiresAt) or 0) - workspace:GetServerTimeNow()
					if left > 5 then
						showPopup(offer)
					end
				end
			end
		end
	end)
end

return ContractController
