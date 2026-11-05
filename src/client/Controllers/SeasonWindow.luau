--!strict
-- Окно «🎫 Сезон»: вкладки «Сезон» (уровни, бесплатная и премиум-дорожка, покупки) и
-- «Гейм-джем» (тема недели, свой результат, топ-100). Кнопка меню — слот 15.
-- Клиент только показывает присланное сервером и просит «Забрать»; проверку делает сервер.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LiveOpsRemotes = require(ReplicatedStorage.Shared.LiveOpsRemotes)
local Season = require(ReplicatedStorage.Shared.Config.Season)
local GameJam = require(ReplicatedStorage.Shared.Config.GameJam)
local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local Posters = require(ReplicatedStorage.Shared.Config.Posters)
local ArtIcon = require(script.Parent.Parent.ArtIcon)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local QuestWindow = require(script.Parent.QuestWindow)
local ContentDropClient = require(script.Parent.Parent.ContentDropClient)

type Tab = "season" | "jam"

local MENU_SLOT = 16
local ROW_HEIGHT = 64
local ROW_COLOR = Color3.fromRGB(44, 46, 66)
local PREMIUM_COLOR = Color3.fromRGB(255, 170, 60)
-- Картинки V18 (Config/Images.social): шапки вкладок 4:1 и рамка иконки награды уровня
local BANNER_HEIGHT = 150
local TIER_ICON = 48

local SeasonWindow = {}

local gui: ScreenGui? = nil
local content: ScrollingFrame? = nil
local tabButtons: { [string]: TextButton } = {}
local tab: Tab = "season"
local seasonState: any = nil
local jamState: any = nil

local t = ClientState.t

local function duration(seconds: number): string
	seconds = math.max(seconds, 0)
	local days = seconds // 86400
	local hours = (seconds % 86400) // 3600
	if days > 0 then
		return t("season_time_days", { days = days, hours = hours })
	end
	return string.format("%d:%02d:%02d", hours, (seconds % 3600) // 60, seconds % 60)
end

-- Тема джема на языке игрока: «Хоррор + Космос»
function SeasonWindow.themeText(genreId: string, topicId: string): string
	local genre = Genres[genreId]
	local topic = Topics[topicId]
	local g = if genre then ClientState.localName(genre) else genreId
	local tp = if topic then ClientState.localName(topic) else topicId
	return g .. " + " .. tp
end

local function describe(reward: Season.Reward): string
	local parts = {}
	-- График контента: награды сезона выдаются сразу, даже до выхода волны (бонус пропуска —
	-- «раньше всех»); иначе сезон кончился бы раньше волны и предмет пропал
	local function soon(_kind: "poster" | "skin" | "mascot", _id: string, text: string): string
		return text
	end
	local base = QuestWindow.describeReward({
		incomeMinutes = reward.incomeMinutes,
		coffeeMinutes = reward.coffeeMinutes,
		researchPoints = reward.researchPoints,
	})
	if base ~= "" then
		table.insert(parts, base)
	end
	if reward.poster then
		-- Как в PosterShop: перевод poster_<id>, иначе name/nameEn из Config/Posters (не сырой ключ)
		local poster = Posters.get(reward.poster)
		local name = if poster
			then ClientState.localText("poster_" .. poster.id, poster.name, poster.nameEn)
			else reward.poster
		table.insert(parts, soon("poster", reward.poster, t("season_reward_poster", { name = name })))
	end
	if reward.skin then
		local skin = reward.skin
		table.insert(parts, soon("skin", skin, t("season_reward_skin", { name = t("skin_" .. skin) })))
	end
	if reward.mascot then
		local mascot = reward.mascot
		table.insert(
			parts,
			soon("mascot", mascot, t("season_reward_mascot", { name = t("season_mascot_" .. mascot) }))
		)
	end
	if reward.title then
		table.insert(parts, t("season_reward_title"))
	end
	return table.concat(parts, " + ")
end

local function clearContent(): ScrollingFrame?
	local frame = content
	if not frame then
		return nil
	end
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	return frame
end

local function buyButton(parent: Instance, text: string, productId: number, price: number): TextButton
	local soon = productId == 0
	local label = text .. " — " .. (if soon then t("shop_soon") else t("shop_robux", { price = price }))
	return Ui.button(parent, label, if soon then Ui.colors.locked else PREMIUM_COLOR, function()
		if not soon then
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
		end
	end)
end

local function claimedSet(list: any): { [number]: boolean }
	local set = {}
	if type(list) == "table" then
		for _, n in list do
			set[n] = true
		end
	end
	return set
end

-- Шапка вкладки (season_banner / gamejam_banner) первой строкой; id 0 — шапки нет
local function banner(frame: ScrollingFrame, id: number, order: number)
	if id <= 0 then
		return
	end
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, -8, 0, BANNER_HEIGHT)
	holder.LayoutOrder = order
	local image = ArtIcon.fill(holder, id)
	if image then
		image.ZIndex = 1
	end
	holder.Parent = frame
end

-- Рамка уровня (season_tier_free / premium) с иконкой награды внутри; без иконки — эмодзи вида
local function tierIcon(cell: Frame, reward: Season.Reward, frameId: number, dim: boolean)
	local slot = Instance.new("Frame")
	slot.BackgroundTransparency = 1
	slot.AnchorPoint = Vector2.new(0, 0.5)
	slot.Position = UDim2.fromScale(0, 0.5)
	slot.Size = UDim2.fromOffset(TIER_ICON, TIER_ICON)
	slot.Parent = cell
	local _, emoji = ArtIcon.rewardKind(reward)
	local rewardId = ArtIcon.rewardImage(reward)
	local inner = Instance.new("Frame")
	inner.BackgroundTransparency = 1
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(0.62, 0.62)
	inner.Parent = slot
	local icon = ArtIcon.fill(inner, rewardId)
	if icon then
		icon.ZIndex = 1
		icon.ImageTransparency = if dim then 0.45 else 0
	else
		local label = Ui.label(inner, emoji, TIER_ICON)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Size = UDim2.fromScale(1, 1)
		label.TextTransparency = if dim then 0.45 else 0
	end
	local frame = ArtIcon.fill(slot, frameId)
	if frame then
		frame.ZIndex = 2 -- рамка поверх иконки: центр у PNG прозрачный
	end
end

-- Половина строки уровня: награда и кнопка
local function rewardCell(
	row: Frame,
	x: number,
	reward: Season.Reward,
	state: string,
	frameId: number,
	onClaim: () -> ()
)
	local cell = Instance.new("Frame")
	cell.BackgroundTransparency = 1
	cell.Position = UDim2.new(x, 4, 0, 4)
	cell.Size = UDim2.new(0.42, -8, 1, -8)
	cell.Parent = row
	local color = if state == "claimed" then Ui.colors.muted else Ui.colors.text
	local text = Ui.label(cell, describe(reward), 18, Enum.Font.GothamMedium, color)
	text.TextWrapped = true
	text.Size = UDim2.new(0.62, 0, 1, 0)
	if frameId > 0 then
		tierIcon(cell, reward, frameId, state == "claimed")
		text.Position = UDim2.fromOffset(TIER_ICON + 4, 0)
		text.Size = UDim2.new(0.62, -(TIER_ICON + 4), 1, 0)
	end
	local buttonText = if state == "claimed"
		then t("quests_claimed")
		elseif state == "ready" then t("quests_claim")
		elseif state == "premium" then "🔒 " .. t("season_premium_short")
		else "🔒"
	local button = Ui.button(
		cell,
		buttonText,
		if state == "ready" then Ui.colors.good else Ui.colors.locked,
		function()
			if state == "ready" then
				onClaim()
			end
		end
	)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, 0, 0.5, 0)
	button.Size = UDim2.new(0.36, 0, 0, 36)
end

local function renderSeason(frame: ScrollingFrame)
	local s = seasonState
	if type(s) ~= "table" then
		Ui.label(frame, t("quests_loading"), 28, nil, Ui.colors.muted)
		return
	end
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local tier = tonumber(s.tier) or 0
	local xp = tonumber(s.xp) or 0
	local maxTier = #Season.tiers
	banner(frame, Images.social.seasonBanner, nextOrder())
	local header = Ui.label(
		frame,
		t(
			"season_header",
			{ n = (tonumber(s.index) or 0) + 1, time = duration((tonumber(s.endsAt) or 0) - os.time()) }
		),
		26,
		Ui.titleFontFor(ClientState.lang),
		Ui.colors.money
	)
	header.LayoutOrder = nextOrder()
	ContentDropClient.nextLine(frame, nextOrder())

	-- Уровень и полоса опыта до следующего
	local into = if tier >= maxTier then Season.xpPerTier else xp - tier * Season.xpPerTier
	local level = Ui.label(
		frame,
		if tier >= maxTier
			then t("season_level_max", { tier = tier })
			else t("season_level", { tier = tier, max = maxTier, xp = into, need = Season.xpPerTier }),
		22
	)
	level.LayoutOrder = nextOrder()
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Ui.colors.locked
	bar.Size = UDim2.new(1, -8, 0, 14)
	bar.LayoutOrder = nextOrder()
	Ui.corner(bar, 7)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Ui.colors.good
	fill.Size = UDim2.fromScale(math.clamp(into / Season.xpPerTier, 0, 1), 1)
	Ui.corner(fill, 7)
	fill.Parent = bar
	bar.Parent = frame
	Ui.label(frame, t("season_xp_hint"), 18, Enum.Font.GothamMedium, Ui.colors.muted).LayoutOrder =
		nextOrder()
	if s.title then
		Ui.label(frame, t("season_title_owned"), 22, nil, Ui.colors.money).LayoutOrder = nextOrder()
	end

	-- Покупки: премиум и +1 уровень
	local buyRow = Instance.new("Frame")
	buyRow.BackgroundTransparency = 1
	buyRow.Size = UDim2.new(1, -8, 0, 42)
	buyRow.LayoutOrder = nextOrder()
	local products = Season.products
	if s.premium then
		local owned = Ui.label(buyRow, t("season_premium_active"), 42, nil, PREMIUM_COLOR)
		owned.Size = UDim2.new(0.5, -4, 1, 0)
		ArtIcon.prefix(owned, "⭐", Images.social.seasonPremiumBadge, 36)
	else
		local pass = buyButton(
			buyRow,
			t("season_buy_premium"),
			products.seasonPass.productId,
			products.seasonPass.robuxPrice
		)
		pass.Size = UDim2.new(0.5, -4, 1, 0)
	end
	if tier < maxTier then
		local skip = buyButton(
			buyRow,
			t("season_buy_skip"),
			products.seasonSkip.productId,
			products.seasonSkip.robuxPrice
		)
		skip.Position = UDim2.new(0.5, 4, 0, 0)
		skip.Size = UDim2.new(0.5, -4, 1, 0)
	end
	buyRow.Parent = frame

	-- Есть что забрать — кнопка «Забрать всё»
	local claimedFree = claimedSet(s.claimedFree)
	local claimedPremium = claimedSet(s.claimedPremium)
	local anyReady = false
	for n = 1, tier do
		if not claimedFree[n] or (s.premium and not claimedPremium[n]) then
			anyReady = true
			break
		end
	end
	if anyReady then
		local all = Ui.button(frame, "🎁 " .. t("season_claim_all"), Ui.colors.good, function()
			LiveOpsRemotes.ClaimSeason:FireServer("all", 0)
		end)
		all.Size = UDim2.new(1, -8, 0, 40)
		all.LayoutOrder = nextOrder()
	end

	local heads = Instance.new("Frame")
	heads.BackgroundTransparency = 1
	heads.Size = UDim2.new(1, -8, 0, 22)
	heads.LayoutOrder = nextOrder()
	local freeHead = Ui.label(heads, t("season_track_free"), 22, nil, Ui.colors.muted)
	freeHead.Position = UDim2.new(0.16, 4, 0, 0)
	freeHead.Size = UDim2.new(0.42, -8, 1, 0)
	local premiumHead = Ui.label(heads, t("season_track_premium"), 22, nil, PREMIUM_COLOR)
	premiumHead.Position = UDim2.new(0.58, 4, 0, 0)
	premiumHead.Size = UDim2.new(0.42, -8, 1, 0)
	ArtIcon.prefix(premiumHead, "⭐", Images.social.seasonPremiumBadge, 22)
	heads.Parent = frame

	for n, entry in Season.tiers do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = ROW_COLOR
		row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		row.LayoutOrder = nextOrder()
		Ui.corner(row, 10)
		local reached = n <= tier
		local num = Ui.label(
			row,
			t("season_tier_n", { n = n }),
			24,
			Ui.titleFontFor(ClientState.lang),
			if reached then Ui.colors.good else Ui.colors.muted
		)
		num.TextXAlignment = Enum.TextXAlignment.Center
		num.Position = UDim2.new(0, 4, 0.5, -12)
		num.Size = UDim2.new(0.16, -8, 0, 24)
		local freeState = if claimedFree[n] then "claimed" elseif reached then "ready" else "locked"
		rewardCell(row, 0.16, entry.free, freeState, Images.social.seasonTierFree, function()
			LiveOpsRemotes.ClaimSeason:FireServer("free", n)
		end)
		local premiumState = if claimedPremium[n]
			then "claimed"
			elseif not s.premium then "premium"
			elseif reached then "ready"
			else "locked"
		rewardCell(row, 0.58, entry.premium, premiumState, Images.social.seasonTierPremium, function()
			LiveOpsRemotes.ClaimSeason:FireServer("premium", n)
		end)
		row.Parent = frame
	end
end

local function renderJam(frame: ScrollingFrame)
	local j = jamState
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	-- Тема известна и без сервера (Config/GameJam), остальное — из JamState
	banner(frame, Images.social.gamejamBanner, nextOrder())
	local week = GameJam.weekIndex()
	local genreId, topicId = GameJam.theme(week)
	local theme = Ui.label(
		frame,
		t("jam_theme", { theme = SeasonWindow.themeText(genreId, topicId) }),
		30,
		Ui.titleFontFor(ClientState.lang),
		Ui.colors.money
	)
	theme.LayoutOrder = nextOrder()
	Ui.label(
		frame,
		t("jam_ends", { time = duration(GameJam.weekEndsAt(week) - os.time()) }),
		22,
		nil,
		Ui.colors.muted
	).LayoutOrder =
		nextOrder()
	local how = Ui.label(frame, t("jam_how"), 36, Enum.Font.GothamMedium, Ui.colors.text)
	how.TextWrapped = true
	how.LayoutOrder = nextOrder()
	local r = GameJam.rewards
	local rewards = Ui.label(
		frame,
		t("jam_rewards", {
			top10 = r.top10.incomeMinutes,
			top100 = r.top100.incomeMinutes,
			all = r.participated.incomeMinutes,
		}),
		36,
		Enum.Font.GothamMedium,
		Ui.colors.muted
	)
	rewards.TextWrapped = true
	rewards.LayoutOrder = nextOrder()
	if type(j) ~= "table" then
		Ui.label(frame, t("quests_loading"), 28, nil, Ui.colors.muted).LayoutOrder = nextOrder()
		return
	end
	local best = j.best
	local mine = if type(best) == "table"
		then t(if j.rank then "jam_best_rank" else "jam_best", {
			score = best.score,
			money = Texts.money(tonumber(best.revenue) or 0),
			rank = j.rank,
		})
		else t("jam_no_entry")
	Ui.label(frame, mine, 24, nil, if type(best) == "table" then Ui.colors.good else Ui.colors.muted).LayoutOrder =
		nextOrder()
	local last = j.last
	if type(last) == "table" and type(last.tier) == "string" then
		local text = if last.tier == "participated"
			then t("jam_last_participated")
			else t("jam_last_rank", { rank = last.rank })
		Ui.label(frame, text, 22, nil, Ui.colors.muted).LayoutOrder = nextOrder()
	end
	local flags = j.flags
	if type(flags) == "table" and (flags.jamTop10 or flags.jamTop100) then
		local flag = Ui.label(
			frame,
			t(if flags.jamTop10 then "jam_flag_top10" else "jam_flag_top100"),
			22,
			nil,
			Ui.colors.money
		)
		flag.LayoutOrder = nextOrder()
		if flags.jamTop10 then
			ArtIcon.prefix(flag, "🏆", Images.social.gamejamMedalTop10, 22)
		else
			ArtIcon.prefix(flag, "🥇", Images.social.gamejamMedalTop100, 22)
		end
	end

	Ui.label(frame, t("jam_top_title"), 28, Ui.titleFontFor(ClientState.lang), Ui.colors.money).LayoutOrder =
		nextOrder()
	if not j.available then
		Ui.label(frame, t("leaders_unavailable"), 24, nil, Ui.colors.muted).LayoutOrder = nextOrder()
		return
	end
	local top = j.top
	if type(top) ~= "table" or #top == 0 then
		Ui.label(frame, t("jam_top_empty"), 24, nil, Ui.colors.muted).LayoutOrder = nextOrder()
		return
	end
	local me = Players.LocalPlayer
	for i, e in top do
		local isMe = e.name == me.DisplayName or e.name == me.Name
		local line = string.format("%d. %s — ⭐ %s", i, tostring(e.name), tostring(e.score))
		local color = if isMe then Ui.colors.good elseif i <= 10 then Ui.colors.money else Ui.colors.text
		Ui.label(frame, line, 22, Enum.Font.GothamMedium, color).LayoutOrder = nextOrder()
	end
end

local function render()
	local frame = clearContent()
	if not frame then
		return
	end
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == tab then Ui.colors.primary else Ui.colors.locked
	end
	if tab == "season" then
		renderSeason(frame)
	else
		renderJam(frame)
	end
end

function SeasonWindow.close()
	if gui then
		gui:Destroy()
		gui = nil
		content = nil
		tabButtons = {}
		Ui.windowClosed()
	end
end

function SeasonWindow.open(startTab: Tab?)
	if startTab then
		tab = startTab
	end
	if gui then
		render()
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "SeasonWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened(SeasonWindow.close) -- окно меню: закрывает другое открытое окно меню

	local window = Ui.window(screen, "Window", Vector2.new(720, 600))
	local title = Ui.label(window, t("season_title"), 40, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 40)
	local close = Ui.button(window, "×", Ui.colors.bad, SeasonWindow.close)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Size = UDim2.fromOffset(40, 40)

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(16, 58)
	tabs.Size = UDim2.new(1, -32, 0, 40)
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 8)
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Parent = tabs
	tabs.Parent = window
	for i, name in { "season", "jam" } do
		local button = Ui.button(tabs, t("season_tab_" .. name), Ui.colors.locked, function()
			tab = name :: any
			render()
		end)
		button.LayoutOrder = i
		button.Size = UDim2.new(0.5, -4, 1, 0)
		if name == "season" then
			ArtIcon.prefix(button, "🎫", Images.menu.menu_season or 0, 28)
		else
			ArtIcon.prefix(button, "🎮", Images.social.menuGamejam, 28)
		end
		tabButtons[name] = button
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(16, 108)
	scroll.Size = UDim2.new(1, -32, 1, -120)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	Ui.list(scroll, 8)
	scroll.Parent = window
	content = scroll

	render()
	LiveOpsRemotes.RequestSeason:FireServer()

	-- Таймеры сезона и джема: перерисовка раз в 30 с, пока окно открыто
	task.spawn(function()
		while gui == screen do
			task.wait(30)
			if gui == screen then
				render()
			end
		end
	end)
end

function SeasonWindow.start()
	Ui.menuButton(MENU_SLOT, "🎫", function()
		if gui then
			SeasonWindow.close()
		else
			SeasonWindow.open()
		end
	end, "menu_season")
	LiveOpsRemotes.SeasonState.OnClientEvent:Connect(function(state)
		if type(state) == "table" then
			seasonState = state
			if gui and tab == "season" then
				render()
			end
		end
	end)
	LiveOpsRemotes.JamState.OnClientEvent:Connect(function(state)
		if type(state) == "table" then
			jamState = state
			if gui and tab == "jam" then
				render()
			end
		end
	end)
	-- Сменили язык: заголовок и вкладки строятся в open — открытое окно собираем заново
	ClientState.langChanged:Connect(function()
		if gui then
			SeasonWindow.close()
			SeasonWindow.open()
		end
	end)
	LiveOpsRemotes.RequestSeason:FireServer()
end

return SeasonWindow
