--!strict
-- Окно релиза (шаг 2.5): 4 критика по очереди открывают оценки, потом итог и доход.
-- Оценки критиков — оформление вокруг итоговой оценки сервера (в среднем дают её же).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local Critics = require(ReplicatedStorage.Shared.Config.Critics)
local AdCampaigns = require(ReplicatedStorage.Shared.Config.AdCampaigns)
local HitCartridges = require(ReplicatedStorage.Shared.Config.HitCartridges)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local ArtIcon = require(script.Parent.Parent.ArtIcon)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local CreateGameWindow = require(script.Parent.CreateGameWindow)
local OfferClient = require(script.Parent.Parent.OfferClient)
local ArcadeWindow = require(script.Parent.ArcadeWindow)

local REVEAL_DELAY = 0.6
local CRITIC_SPREAD = { -1, 0, 0, 1 } -- сумма 0: среднее равно итоговой оценке

local ReleaseWindow = {}
local gui: ScreenGui? = nil
-- Токен ClientState.beginReveal текущего окна: HUD и тост хита ждут раскрытия оценки
local revealToken: number? = nil
local rng = Random.new()

local function band(score: number): string
	if score <= 3 then
		return "low"
	elseif score <= 6 then
		return "mid"
	elseif score <= 8 then
		return "good"
	end
	return "top"
end

local function shuffled<T>(list: { T }): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function criticLine(critic: Critics.Critic, score: number, genreName: string, topicName: string): string
	local scoreBand = band(score)
	local options = (critic.phrases :: any)[scoreBand] :: { Critics.Phrase }
	local index = rng:NextInteger(1, #options)
	local phrase = options[index]
	-- Перевод из Locales (critic_<id>_<band>_<n>), иначе поля ru/en из Config/Critics
	local text = Texts.lookup(ClientState.lang, `critic_{critic.id}_{scoreBand}_{index}`)
		or if ClientState.lang == "ru" then phrase.ru else phrase.en
	return (text:gsub("{genre}", genreName):gsub("{topic}", topicName))
end

local function socialAd(): AdCampaigns.AdCampaign?
	for _, campaign in AdCampaigns do
		if campaign.id == "social" then
			return campaign
		end
	end
	return nil
end

local function revealed()
	local token = revealToken
	if token then
		revealToken = nil
		ClientState.markRevealed(token)
	end
end

local function close()
	revealed()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

local function show(info: any)
	close()
	if type(info) ~= "table" or type(info.score) ~= "number" then
		return
	end
	local revenue = tonumber(info.revenue) or 0
	local loanRepaid = math.max(tonumber(info.loanRepaid) or 0, 0)
	-- Деньги уже начислены сервером: HUD покажет их вместе с итогом, а не до оценок
	revealToken = ClientState.beginReveal(revenue - loanRepaid)
	local genre = Genres[info.genreId]
	local topic = Topics[info.topicId]
	local genreName = if genre then ClientState.localName(genre) else ""
	local topicName = if topic then ClientState.localName(topic) else ""

	local screen = Instance.new("ScreenGui")
	screen.Name = "ReleaseWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	-- Предложение под итогом (×2 к доходу этой игры / геймпасс ×2): окно выше на строку
	local offer = OfferClient.releaseOffer(info)
	-- Плейтест «Сыграй в свою игру» (ArcadeWindow): ещё строка под итогом
	local arcade = ArcadeWindow.available(info)
	local window = Ui.window(
		screen,
		"Window",
		Vector2.new(620, (if offer then 692 else 636) + (if arcade then 50 else 0))
	)
	-- Тело прокручивается: на низком экране (телефон) Ui.window делает окно ниже, а не мельче,
	-- и итог с кнопками уходит в прокрутку, а не за край экрана
	local body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 6
	Ui.list(body, 8)
	body.Parent = window

	local title = Ui.label(
		body,
		ClientState.t("release_title", { name = info.name }),
		40,
		Ui.titleFontFor(ClientState.lang)
	)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 1
	local sub = Ui.label(body, ClientState.t("release_critics"), 22, nil, Ui.colors.muted)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.LayoutOrder = 2

	-- Карточки критиков: сначала «?», потом по очереди открываются
	local cards: { { score: TextLabel, quote: TextLabel, value: number, critic: Critics.Critic } } = {}
	local spread = shuffled(CRITIC_SPREAD)
	for i, critic in Critics do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
		row.Size = UDim2.new(1, 0, 0, 58)
		row.LayoutOrder = 2 + i
		Ui.corner(row, 10)

		local scoreLabel = Ui.label(row, "?", 58, Ui.titleFontFor(ClientState.lang), Ui.colors.muted)
		scoreLabel.Size = UDim2.new(0, 58, 1, 0)
		scoreLabel.TextXAlignment = Enum.TextXAlignment.Center

		local criticName = Texts.lookup(ClientState.lang, "critic_name_" .. critic.id)
			or if ClientState.lang == "ru" then critic.name else critic.nameEn
		local nameLabel = Ui.label(row, criticName, 20, nil, Ui.colors.muted)
		nameLabel.Position = UDim2.fromOffset(64, 4)
		nameLabel.Size = UDim2.new(1, -72, 0, 20)
		-- Логотип издания (Images.critics, V25) слева от названия; 0 — только название
		ArtIcon.prefix(nameLabel, "", Images.critics[critic.id] or 0, 20)

		local quote = Ui.label(row, "", 26, Enum.Font.GothamMedium)
		quote.Position = UDim2.fromOffset(64, 26)
		quote.Size = UDim2.new(1, -72, 0, 26)
		row.Parent = body

		local value = math.clamp(info.score + (spread[i] or 0), 1, 10)
		table.insert(cards, { score = scoreLabel, quote = quote, value = value, critic = critic })
	end

	-- Штраф за повтор жанра+темы (сервер присылает уже с учётом сиквела)
	local repeatPenalty = math.max(tonumber(info.repeatPenalty) or 0, 0)
	local repeatLine = Ui.label(body, "", 24, nil, Ui.colors.bad)
	repeatLine.TextXAlignment = Enum.TextXAlignment.Center
	repeatLine.LayoutOrder = 19
	repeatLine.Visible = false

	-- Сумма быстрых событий разработки (QuickEventService); nil — событий не было
	local quickBonus = tonumber(info.quickBonus)
	local quickLine = Ui.label(body, "", 24, nil, Ui.colors.muted)
	quickLine.TextXAlignment = Enum.TextXAlignment.Center
	quickLine.LayoutOrder = 18
	quickLine.Visible = false

	-- Настроение команды (MoodService): ±0.2 к оценке; 0 — строки нет
	local moodBonus = tonumber(info.moodBonus) or 0
	local moodLine = Ui.label(body, "", 24, nil, Ui.colors.muted)
	moodLine.TextXAlignment = Enum.TextXAlignment.Center
	moodLine.LayoutOrder = 17
	moodLine.Visible = false

	-- Команда (навыки, перки, легендарные — StaffService.reviewBonus); 0 — строки нет
	local teamBonus = tonumber(info.teamBonus) or 0
	local teamLine = Ui.label(body, "", 24, nil, Ui.colors.good)
	teamLine.TextXAlignment = Enum.TextXAlignment.Center
	teamLine.LayoutOrder = 16
	teamLine.Visible = false

	local total = Ui.label(body, "", 44, Ui.titleFontFor(ClientState.lang))
	total.TextXAlignment = Enum.TextXAlignment.Center
	total.LayoutOrder = 20
	local money = Ui.label(body, "", 32, Ui.titleFontFor(ClientState.lang), Ui.colors.money)
	money.TextXAlignment = Enum.TextXAlignment.Center
	money.LayoutOrder = 21
	local loan = Ui.label(body, "", 24, nil, Ui.colors.bad)
	loan.TextXAlignment = Enum.TextXAlignment.Center
	loan.LayoutOrder = 22
	loan.Visible = false

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 48)
	buttons.LayoutOrder = 23
	local buttonsLayout = Instance.new("UIListLayout")
	buttonsLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonsLayout.Padding = UDim.new(0, 8)
	buttonsLayout.Parent = buttons
	buttons.Visible = false
	buttons.Parent = body

	Ui.button(buttons, ClientState.t("release_again"), Ui.colors.primary, function()
		close()
		CreateGameWindow.open()
	end).Size =
		UDim2.new(0.32, 0, 1, 0)

	local ad = socialAd()
	local data = ClientState.data
	local adActive = data and data.activeAd and data.activeAd.expiresAt > os.time()
	if ad and ad.cashCost and not adActive then
		local cost = ad.cashCost
		local canPay = data and data.cash >= cost
		Ui.button(
			buttons,
			ClientState.t("release_ad", { price = Texts.money(cost) }),
			if canPay then Ui.colors.money else Ui.colors.locked,
			function()
				if canPay then
					Remotes.BuyAdCampaignWithCash:FireServer(ad.id)
					close()
				end
			end
		).Size =
			UDim2.new(0.36, 0, 1, 0)
	end

	Ui.button(buttons, ClientState.t("release_close"), Ui.colors.locked, close).Size =
		UDim2.new(0.26, 0, 1, 0)

	-- Анимация открытия; если окно закрыли раньше — просто выходим
	task.spawn(function()
		for _, card in cards do
			task.wait(REVEAL_DELAY)
			if gui ~= screen then
				return
			end
			card.score.Text = tostring(card.value)
			card.score.TextColor3 = Ui.scoreColor(card.value)
			-- «Критики в городе» (события дня): реплика на ступень восторженнее оценки
			local mood = if info.criticsHype == true then math.min(card.value + 2, 10) else card.value
			card.quote.Text = criticLine(card.critic, mood, genreName, topicName)
		end
		task.wait(REVEAL_DELAY)
		if gui ~= screen then
			return
		end
		if repeatPenalty > 0 then
			local n = (string.format("%.1f", repeatPenalty):gsub("%.0$", ""))
			repeatLine.Text = ClientState.t("critic_repeat", { n = n })
			repeatLine.Visible = true
		end
		if quickBonus then
			local n = string.format("%.2f", math.abs(quickBonus)):gsub("0+$", ""):gsub("%.$", "")
			quickLine.Text =
				ClientState.t("qte_release_line", { n = (if quickBonus < 0 then "−" else "+") .. n })
			quickLine.TextColor3 = if quickBonus > 0
				then Ui.colors.good
				elseif quickBonus < 0 then Ui.colors.bad
				else Ui.colors.muted
			quickLine.Visible = true
		end
		if moodBonus ~= 0 then
			local n = string.format("%.1f", math.abs(moodBonus)):gsub("%.0$", "")
			moodLine.Text =
				ClientState.t("mood_release_line", { n = (if moodBonus < 0 then "−" else "+") .. n })
			moodLine.TextColor3 = if moodBonus > 0 then Ui.colors.good else Ui.colors.bad
			moodLine.Visible = true
		end
		if math.abs(teamBonus) >= 0.005 then
			local n = string.format("%.2f", math.abs(teamBonus)):gsub("0+$", ""):gsub("%.$", "")
			teamLine.Text =
				ClientState.t("release_team_line", { n = (if teamBonus < 0 then "−" else "+") .. n })
			teamLine.TextColor3 = if teamBonus > 0 then Ui.colors.good else Ui.colors.bad
			teamLine.Visible = true
		end
		total.Text = ClientState.t("release_score", { score = info.score })
		total.TextColor3 = Ui.scoreColor(info.score)
		local scale = Instance.new("UIScale")
		scale.Scale = 1.4
		scale.Parent = total
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		-- Частицы Астры над игроком (Images.fx, V24): релиз — монеты, хит — ещё звёзды, 10 — конфетти.
		-- Текстур нет (0) — ничего, как раньше
		local score = tonumber(info.score) or 0
		ArtIcon.burst({ Images.fx.coin, if score >= HitCartridges.minScore then Images.fx.star else 0 }, 24)
		if score >= 10 then
			ArtIcon.burst({ Images.fx.confetti1, Images.fx.confetti2 }, 40)
		end

		local moneyText = ClientState.t("release_revenue", { money = Texts.money(revenue) })
		if type(info.adBonus) == "number" and info.adBonus > 0 then
			moneyText ..= "  (" .. ClientState.t(
				"release_ad_bonus",
				{ percent = math.floor(info.adBonus * 100) }
			) .. ")"
		end
		if info.isRecord then
			moneyText ..= "\n" .. ClientState.t("release_best")
		end
		money.Text = moneyText
		-- Часть дохода ушла банку (LoanService): показываем, сколько, чтобы сумма сходилась с HUD
		if loanRepaid > 0 then
			loan.Text = ClientState.t("release_loan_repaid", { money = Texts.money(loanRepaid) })
			loan.Visible = true
		end
		buttons.Visible = true
		if offer then
			offer(body, 24)
		end
		if arcade then
			local play = Ui.button(
				body,
				ClientState.t("arcade_play"),
				Color3.fromRGB(150, 90, 230),
				function()
					close()
					ArcadeWindow.open(info)
				end
			)
			play.Size = UDim2.new(1, 0, 0, 40)
			play.LayoutOrder = 25
		end
		revealed()
	end)
end

function ReleaseWindow.start()
	Remotes.GameReleased.OnClientEvent:Connect(show)
end

return ReleaseWindow
