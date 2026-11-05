--!strict
-- Окно награды за вход (issue #10): 7 плиток, текущий день подсвечен, кнопка «День N — забрать».
-- Показывается сам, когда сервер сообщает, что награда доступна (при входе и после 00:00 UTC).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestRemotes = require(ReplicatedStorage.Shared.QuestRemotes)
local DailyRewards = require(ReplicatedStorage.Shared.Config.DailyRewards)
local Social = require(ReplicatedStorage.Shared.Config.Social)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local ArtIcon = require(script.Parent.Parent.ArtIcon)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local QuestWindow = require(script.Parent.QuestWindow)

local DailyRewardWindow = {}

-- Картинки V17 (Config/Images.daily). Рамки режутся 9-slice: углы и звезда сверху не тянутся,
-- растягивается середина. Прямоугольники — в пикселях PNG
local BOARD_SLICE = Rect.new(140, 140, 1060, 560) -- daily_board_bg 1200×700, деревянная рамка
local BOARD_SLICE_SCALE = 0.3
local CARD_SLICE = Rect.new(48, 56, 208, 280) -- daily_card_* 256×320
local CARD_SLICE_SCALE = 0.4
local REWARD_ICON = 44

local gui: ScreenGui? = nil
-- Автопоказ один раз, пока награда доступна: закрыл без получения — не всплывает снова
-- при каждом запросе, но остаётся кнопка в окне «Задания» (QuestWindow.setDailyReward).
-- Сбрасывается, когда сервер говорит «недоступна» (забрал) — часы клиента не нужны
local shownDay: number? = nil
-- День в открытом окне: перерисовать его, когда придёт сохранённый язык
local openDay = 1

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

local function show(day: number)
	close()
	openDay = day
	local screen = Instance.new("ScreenGui")
	screen.Name = "DailyRewardWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 15
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local window = Ui.window(screen, "Window", Vector2.new(760, 380))
	local board =
		ArtIcon.fill(window, Images.daily.boardBg, Enum.ScaleType.Slice, BOARD_SLICE, BOARD_SLICE_SCALE)
	if board then
		Ui.corner(board)
	end
	local title = Ui.label(window, ClientState.t("daily_reward_title"), 40, Ui.titleFontFor(ClientState.lang))
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 40)
	-- Огонёк серии слева от заголовка (номер дня серии — на плитке и кнопке)
	ArtIcon.prefix(title, "", Images.daily.streakFlame, 40)
	local closeButton = Ui.button(window, "×", Ui.colors.bad, close)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 10)
	closeButton.Size = UDim2.fromOffset(40, 40)

	local tiles = Instance.new("Frame")
	tiles.BackgroundTransparency = 1
	tiles.Position = UDim2.fromOffset(16, 62)
	tiles.Size = UDim2.new(1, -32, 0, 170)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tiles
	tiles.Parent = window

	local count = #DailyRewards
	for i, reward in DailyRewards do
		local tile = Instance.new("Frame")
		tile.LayoutOrder = i
		tile.Size = UDim2.new(1 / count, -6 * (count - 1) / count, 1, 0)
		tile.BackgroundColor3 = if i == day
			then Ui.colors.primary
			elseif i < day then Ui.colors.locked
			else Color3.fromRGB(44, 46, 66)
		Ui.corner(tile, 10)
		-- Рамка карточки по состоянию: сегодня, забрано, завтра, дальше
		local cardId = if i == day
			then Images.daily.cardToday
			elseif i < day then Images.daily.cardClaimed
			elseif i == day + 1 then Images.daily.cardNormal
			else Images.daily.cardLocked
		if ArtIcon.fill(tile, cardId, Enum.ScaleType.Slice, CARD_SLICE, CARD_SLICE_SCALE) then
			tile.BackgroundTransparency = 1
		end
		local dayLabel = Ui.label(
			tile,
			ClientState.t("daily_reward_day", { day = i }),
			26,
			Ui.titleFontFor(ClientState.lang)
		)
		dayLabel.TextXAlignment = Enum.TextXAlignment.Center
		dayLabel.Position = UDim2.fromOffset(4, 6)
		dayLabel.Size = UDim2.new(1, -8, 0, 26)
		local text = Ui.label(tile, QuestWindow.describeReward(reward), 120, Enum.Font.GothamMedium)
		text.TextXAlignment = Enum.TextXAlignment.Center
		text.TextYAlignment = Enum.TextYAlignment.Top
		text.TextWrapped = true
		text.Position = UDim2.fromOffset(4, 40)
		text.Size = UDim2.new(1, -8, 1, -46)
		-- Иконка награды по виду над подписью; подпись (суммы) остаётся ниже, чуть мельче
		local icon = ArtIcon.fill(tile, ArtIcon.rewardImage(reward))
		if icon then
			icon.ZIndex = 1
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.Position = UDim2.new(0.5, 0, 0, 36)
			icon.Size = UDim2.fromOffset(REWARD_ICON, REWARD_ICON)
			text.Position = UDim2.fromOffset(4, 40 + REWARD_ICON + 4)
			text.Size = UDim2.new(1, -8, 1, -(46 + REWARD_ICON + 4))
		end
		tile.Parent = tiles
	end

	local hint = Ui.label(window, ClientState.t("daily_reward_hint"), 22, nil, Ui.colors.muted)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.Position = UDim2.fromOffset(16, 242)
	hint.Size = UDim2.new(1, -32, 0, 22)

	-- Бонус Roblox Premium (Config/Social.premium): у премиум-игроков золотой, у остальных — серый
	local perks = {}
	local premium = Social.premium
	if premium.offlineBonus > 0 then
		table.insert(
			perks,
			ClientState.t("premium_offline", { percent = math.floor(premium.offlineBonus * 100 + 0.5) })
		)
	end
	if premium.dailyCoffeeMinutes > 0 then
		table.insert(perks, ClientState.t("premium_coffee", { minutes = premium.dailyCoffeeMinutes }))
	end
	if #perks > 0 then
		local active = Players.LocalPlayer.MembershipType == Enum.MembershipType.Premium
		local line = Ui.label(
			window,
			ClientState.t("premium_bonus", { perks = table.concat(perks, ", ") }),
			22,
			nil,
			if active then Ui.colors.money else Ui.colors.muted
		)
		line.TextXAlignment = Enum.TextXAlignment.Center
		line.Position = UDim2.fromOffset(16, 270)
		line.Size = UDim2.new(1, -32, 0, 22)
	end

	local claim = Ui.button(
		window,
		ClientState.t("daily_reward_claim", { day = day }),
		Ui.colors.good,
		function()
			QuestRemotes.ClaimDailyReward:FireServer()
			QuestWindow.setDailyReward(nil, nil)
			close()
		end
	)
	claim.AnchorPoint = Vector2.new(0.5, 1)
	claim.Position = UDim2.new(0.5, 0, 1, -16)
	claim.Size = UDim2.fromOffset(300, 56)
end

function DailyRewardWindow.start()
	QuestRemotes.DailyRewardState.OnClientEvent:Connect(function(state)
		if type(state) ~= "table" or type(state.day) ~= "number" then
			return
		end
		if not state.available then
			shownDay = nil
			QuestWindow.setDailyReward(nil, nil)
			close()
			return
		end
		local day = state.day
		QuestWindow.setDailyReward(day, function()
			QuestWindow.close()
			show(day)
		end)
		if shownDay == day then
			return
		end
		shownDay = day
		show(day)
	end)
	-- Окно всплывает при входе, сохранённый язык приходит позже (отчёт #2, п. 3)
	ClientState.langChanged:Connect(function()
		if gui then
			show(openDay)
		end
	end)
	-- QuestWindow при старте уже запросил данные; сервер ответит и сам при загрузке профиля
end

return DailyRewardWindow
