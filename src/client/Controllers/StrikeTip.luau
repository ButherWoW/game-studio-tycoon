--!strict
-- Разовая подсказка при первой забастовке команды: почему встали и что делать.
-- Забастовку ставит ExpensesService (атрибут игрока StaffStrike), «видел ли» — StaffService
-- (атрибут StrikeTipSeen: false — ещё не видел, nil — профиль не загружен, ждём).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StaffRemotes = require(ReplicatedStorage.Shared.StaffRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local PopupQueue = require(script.Parent.Parent.PopupQueue)
local OfferClient = require(script.Parent.Parent.OfferClient)

local StrikeTip = {}
local gui: ScreenGui? = nil
local dismissed = false -- закрыли в этой сессии (сервер ещё мог не ответить)

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

local function show()
	close()
	local screen = Instance.new("ScreenGui")
	screen.Name = "StrikeTip"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 25
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	-- Пакет дохода, который покрывает зарплату (Config/Offers.strike): ещё одна кнопка
	local pack = OfferClient.strikePack()
	local window = Ui.window(screen, "Window", Vector2.new(480, if pack then 392 else 330))
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	local layout = Ui.list(body, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	body.Parent = window

	local title = Ui.label(
		body,
		ClientState.t("strike_tip_title"),
		36,
		Ui.titleFontFor(ClientState.lang),
		Ui.colors.bad
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 1
	local text = Ui.label(body, ClientState.t("strike_tip_text"), 170, Enum.Font.GothamMedium)
	text.TextScaled = false
	text.TextSize = 20
	text.TextWrapped = true
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.LayoutOrder = 2

	local ok = Ui.button(body, ClientState.t("strike_tip_ok"), Ui.colors.primary, function()
		dismissed = true
		StaffRemotes.StrikeTipSeen:FireServer()
		close()
	end)
	ok.Size = UDim2.new(0.6, 0, 0, 52)
	ok.LayoutOrder = 3

	if pack then
		local product = pack.product
		OfferClient.track("strike", "shown")
		local pay = Ui.button(
			body,
			ClientState.t("offer_strike_pay", { price = product.robuxPrice }),
			Ui.colors.good,
			function()
				dismissed = true
				StaffRemotes.StrikeTipSeen:FireServer()
				close()
				OfferClient.buyProduct("strike", product.productId)
			end
		)
		pay.Size = UDim2.new(0.8, 0, 0, 52)
		pay.LayoutOrder = 4
	end
end

function StrikeTip.start()
	local player = Players.LocalPlayer
	local function wanted(): boolean
		return not dismissed
			and player:GetAttribute("StaffStrike") == true
			and player:GetAttribute("StrikeTipSeen") == false
	end
	local function check()
		if gui then
			return
		end
		-- По очереди с другими окнами входа и не во время туториала (PopupQueue)
		if wanted() then
			PopupQueue.push("strike", function()
				if not gui and wanted() then
					show()
				end
			end)
		else
			PopupQueue.remove("strike")
		end
	end
	player:GetAttributeChangedSignal("StaffStrike"):Connect(check)
	player:GetAttributeChangedSignal("StrikeTipSeen"):Connect(check)
	-- Язык приходит после входа — перерисовать открытую подсказку
	ClientState.langChanged:Connect(function()
		if gui then
			show()
		end
	end)
	check()
end

return StrikeTip
