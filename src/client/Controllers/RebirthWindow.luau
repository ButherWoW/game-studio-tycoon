--!strict
-- Окно Rebirth (шаг 4.4): слот меню 5. Две вкладки:
--   «♻️ Перерождение» — условия, что сбросится/останется, подтверждение в два клика;
--   «⭐ Звёзды» — дерево перков (роадмап 7.19, Config/RebirthPerks): 1 звезда за Rebirth.
-- Решение, сброс и покупка перков — на сервере (RebirthService, RebirthPerkService).
-- Обе вкладки — прокручиваемые тела на всю высоту: на телефоне 844×390 окно ниже, текст читается.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rebirth = require(ReplicatedStorage.Shared.Config.Rebirth)
local RebirthPerks = require(ReplicatedStorage.Shared.Config.RebirthPerks)
local RetentionRemotes = require(ReplicatedStorage.Shared.RetentionRemotes)
local RebirthPerkRemotes = require(ReplicatedStorage.Shared.RebirthPerkRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local ArtIcon = require(script.Parent.Parent.ArtIcon)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local CONFIRM_SECONDS = 3 -- сколько ждём второй клик
local CARD_HEIGHT = 100
local PERCENT_EFFECTS: { [string]: boolean } =
	{ devTime = true, expenses = true, offline = true, researchDiscount = true }

local RebirthWindow = {}
local gui: ScreenGui? = nil
local refresh: (() -> ())? = nil
local renderStars: (() -> ())? = nil
local tab: "rebirth" | "stars" = "rebirth"
-- Последнее состояние перков с сервера: { stars, earned, levels, respecLeft }
local perkState: any = nil

local function multText(rebirths: number): string
	-- 1.5 -> "1.5", 2 -> "2"
	return (string.format("%.1f", Rebirth.multiplier(rebirths)):gsub("%.0$", ""))
end

local function starCount(): number
	return if perkState and type(perkState.stars) == "number" then perkState.stars else 0
end

local function levelOf(branchId: string): number
	local levels = if perkState then perkState.levels else nil
	return RebirthPerks.levelOf(levels, branchId)
end

-- «разработка −9% времени, …» по эффектам уровня; пусто — «нет»
local function describe(effects: RebirthPerks.Effects): string
	local parts = {}
	for _, key in RebirthPerks.effectOrder do
		local value = (effects :: any)[key] :: number
		if value and value > 0 then
			local shown = if PERCENT_EFFECTS[key]
				then tostring(math.round(value * 100))
				elseif key == "startCash" then Texts.money(value)
				else tostring(value)
			table.insert(parts, ClientState.t("rperk_eff_" .. key, { value = shown }))
		end
	end
	return if #parts > 0 then table.concat(parts, ", ") else ClientState.t("rperk_none")
end

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		refresh = nil
		renderStars = nil
		Ui.windowClosed()
	end
end

local function makePage(window: Frame, top: number): ScrollingFrame
	local page = Instance.new("ScrollingFrame")
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Position = UDim2.fromOffset(16, top)
	page.Size = UDim2.new(1, -32, 1, -top - 12)
	page.CanvasSize = UDim2.new()
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.ScrollBarThickness = 6
	Ui.list(page, 8)
	page.Parent = window
	return page
end

local function buildRebirthPage(page: ScrollingFrame): () -> ()
	local count = Ui.label(page, "", 24, nil, Ui.colors.muted)
	count.TextXAlignment = Enum.TextXAlignment.Center
	count.LayoutOrder = 2
	local nextLine = Ui.label(page, "", 26, nil, Ui.colors.money)
	nextLine.TextXAlignment = Enum.TextXAlignment.Center
	nextLine.LayoutOrder = 3
	local office = Ui.label(page, "", 24)
	office.LayoutOrder = 4
	local cash = Ui.label(page, "", 24)
	cash.LayoutOrder = 5
	local resets =
		Ui.label(page, ClientState.t("rebirth_resets"), 36, Enum.Font.GothamMedium, Ui.colors.muted)
	resets.TextWrapped = true
	resets.LayoutOrder = 6
	local keeps = Ui.label(page, ClientState.t("rebirth_keeps"), 20, Enum.Font.GothamMedium, Ui.colors.muted)
	keeps.LayoutOrder = 7
	-- Сколько денег будет после Rebirth с перком «Стартовый капитал»
	local startCash = Ui.label(page, "", 20, Enum.Font.GothamMedium, Ui.colors.money)
	startCash.LayoutOrder = 8

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, -8, 0, 52)
	buttons.LayoutOrder = 9
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = buttons
	buttons.Parent = page

	local armedAt: number? = nil
	local canRebirth = false
	local action: TextButton

	local function update()
		local data = ClientState.data
		if not data then
			return
		end
		local rebirths = data.rebirths or 0
		-- Долг банка гасится вместе с ребёрзом (LoanService)
		local cost = Rebirth.cost(rebirths) + (tonumber(Players.LocalPlayer:GetAttribute("LoanDebt")) or 0)
		local hasOffice = data.upgrades and data.upgrades[Rebirth.requiredUpgrade] == true
		local hasCash = data.cash >= cost
		canRebirth = hasOffice and hasCash

		count.Text = ClientState.t("rebirth_count", { count = rebirths, mult = multText(rebirths) })
		nextLine.Text = ClientState.t("rebirth_next", { mult = multText(rebirths + 1) })
		office.Text = (if hasOffice then "✅ " else "❌ ") .. ClientState.t("rebirth_need_office")
		office.TextColor3 = if hasOffice then Ui.colors.good else Ui.colors.bad
		cash.Text = (if hasCash then "✅ " else "❌ ")
			.. ClientState.t("rebirth_need_cash", { price = Texts.money(cost) })
		cash.TextColor3 = if hasCash then Ui.colors.good else Ui.colors.bad
		local after = RebirthPerks.levelEffects("capital", levelOf("capital")).startCash
		startCash.Visible = after > Rebirth.cashAfter
		startCash.Text = "💰 " .. ClientState.t("rperk_eff_startCash", { value = Texts.money(after) })

		if not canRebirth then
			armedAt = nil
			action.Text = ClientState.t("rebirth_locked")
			action.BackgroundColor3 = Ui.colors.locked
		elseif armedAt then
			action.Text = ClientState.t("rebirth_confirm")
			action.BackgroundColor3 = Ui.colors.bad
		else
			action.Text = ClientState.t("rebirth_button")
			action.BackgroundColor3 = Ui.colors.primary
		end
	end

	action = Ui.button(buttons, "", Ui.colors.locked, function()
		if not canRebirth then
			return
		end
		local now = os.clock()
		if armedAt and now - armedAt <= CONFIRM_SECONDS then
			armedAt = nil
			RetentionRemotes.RequestRebirth:FireServer()
			action.Text = "…"
			return
		end
		-- Первый клик: просим подтвердить; через CONFIRM_SECONDS кнопка остывает
		local stamp = now
		armedAt = stamp
		update()
		task.delay(CONFIRM_SECONDS, function()
			if gui and armedAt == stamp then
				armedAt = nil
				update()
			end
		end)
	end)
	action.Size = UDim2.new(0.6, 0, 1, 0)
	Ui.button(buttons, ClientState.t("rebirth_close"), Ui.colors.locked, close).Size =
		UDim2.new(0.35, 0, 1, 0)
	return update
end

-- Ветка перков → ключ иконки Астры в Images.rebirthPerks (V28: rperk_<ключ>.png); у lab иконки нет
local BRANCH_ART: { [string]: string } =
	{ speed = "speed", thrift = "costs", capital = "start", passive = "offline" }

local function branchCard(parent: Instance, order: number, branch: RebirthPerks.Branch)
	local level = levelOf(branch.id)
	local maxLevel = #branch.costs
	local cost = branch.costs[level + 1]
	local stars = starCount()

	local card = Instance.new("Frame")
	card.Name = branch.id
	card.BackgroundColor3 = if level >= maxLevel
		then Color3.fromRGB(40, 62, 52)
		else Color3.fromRGB(44, 46, 66)
	card.Size = UDim2.new(1, -8, 0, CARD_HEIGHT)
	card.LayoutOrder = order
	Ui.corner(card, 10)

	local name = Ui.label(
		card,
		branch.icon .. " " .. ClientState.t("rperk_" .. branch.id),
		28,
		Ui.titleFontFor(ClientState.lang)
	)
	name.Position = UDim2.fromOffset(10, 6)
	name.Size = UDim2.new(1, -170, 0, 28)
	local artKey = BRANCH_ART[branch.id]
	ArtIcon.prefix(name, branch.icon, if artKey then Images.rebirthPerks[artKey] or 0 else 0, 26)
	local levelLabel = Ui.label(
		card,
		ClientState.t("rperk_level", { level = level, max = maxLevel }),
		20,
		nil,
		Ui.colors.money
	)
	levelLabel.Position = UDim2.new(1, -160, 0, 10)
	levelLabel.Size = UDim2.fromOffset(150, 20)
	levelLabel.TextXAlignment = Enum.TextXAlignment.Right

	local now = Ui.label(
		card,
		ClientState.t("rperk_now", { effect = describe(RebirthPerks.levelEffects(branch.id, level)) }),
		24,
		Enum.Font.GothamMedium,
		if level > 0 then Ui.colors.good else Ui.colors.muted
	)
	now.Position = UDim2.fromOffset(10, 40)
	now.Size = UDim2.new(1, -170, 0, 24)
	if cost then
		local nextLabel = Ui.label(
			card,
			ClientState.t(
				"rperk_next",
				{ effect = describe(RebirthPerks.levelEffects(branch.id, level + 1)) }
			),
			24,
			Enum.Font.GothamMedium,
			Ui.colors.muted
		)
		nextLabel.Position = UDim2.fromOffset(10, 68)
		nextLabel.Size = UDim2.new(1, -170, 0, 24)
	end

	local affordable = cost ~= nil and stars >= cost
	local text = if not cost
		then ClientState.t("rperk_maxed")
		elseif affordable then ClientState.t("rperk_buy", { cost = cost })
		else ClientState.t("rperk_need", { cost = cost })
	local button = Ui.button(
		card,
		text,
		if affordable then Ui.colors.primary else Ui.colors.locked,
		function()
			if affordable then
				RebirthPerkRemotes.BuyRebirthPerk:FireServer(branch.id)
			end
		end
	)
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -10, 1, -10)
	button.Size = UDim2.fromOffset(150, 48)
	card.Parent = parent
end

local function buildStarsPage(page: ScrollingFrame): () -> ()
	local respecArmedAt: number? = nil

	local function render()
		local scroll = page.CanvasPosition
		for _, child in page:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		if not perkState then
			Ui.label(page, ClientState.t("quests_loading"), 28, nil, Ui.colors.muted)
			return
		end
		local header =
			Ui.label(page, ClientState.t("rperk_stars", { count = starCount() }), 32, nil, Ui.colors.money)
		header.TextXAlignment = Enum.TextXAlignment.Center
		header.LayoutOrder = 1
		ArtIcon.prefix(header, "⭐", Images.misc.rebirthStar, 30)
		local hint = Ui.label(page, ClientState.t("rperk_hint"), 22, Enum.Font.GothamMedium, Ui.colors.muted)
		hint.TextXAlignment = Enum.TextXAlignment.Center
		hint.TextWrapped = true
		hint.LayoutOrder = 2
		for i, branch in RebirthPerks.branches do
			branchCard(page, 2 + i, branch)
		end

		local left = tonumber(perkState.respecLeft) or 0
		local spent = RebirthPerks.spent(perkState.levels)
		local canRespec = left > 0 and spent > 0
		local respecText = if left <= 0
			then ClientState.t("rperk_respec_used")
			elseif respecArmedAt then ClientState.t("rperk_respec_confirm")
			else ClientState.t("rperk_respec")
		local respec = Ui.button(
			page,
			respecText,
			if not canRespec
				then Ui.colors.locked
				elseif respecArmedAt then Ui.colors.bad
				else Ui.colors.primary,
			function()
				if not canRespec then
					return
				end
				local now = os.clock()
				if respecArmedAt and now - respecArmedAt <= CONFIRM_SECONDS then
					respecArmedAt = nil
					RebirthPerkRemotes.RespecRebirthPerks:FireServer()
					return
				end
				local stamp = now
				respecArmedAt = stamp
				local current = renderStars
				if current then
					current()
				end
				task.delay(CONFIRM_SECONDS, function()
					if respecArmedAt == stamp then
						respecArmedAt = nil
						local again = renderStars
						if again then
							again()
						end
					end
				end)
			end
		)
		respec.Size = UDim2.new(1, -8, 0, 44)
		respec.LayoutOrder = 100
		page.CanvasPosition = scroll
	end
	return render
end

function RebirthWindow.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "RebirthWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 15
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened(close) -- окно меню: закрывает другое открытое окно меню

	local window = Ui.window(screen, "Window", Vector2.new(560, 470))

	local title = Ui.label(window, ClientState.t("rebirth_title"), 40, Ui.titleFontFor(ClientState.lang))
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Position = UDim2.fromOffset(60, 10)
	title.Size = UDim2.new(1, -120, 0, 40)
	local closeButton = Ui.button(window, "×", Ui.colors.bad, close)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 10)
	closeButton.Size = UDim2.fromOffset(40, 40)

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(16, 58)
	tabs.Size = UDim2.new(1, -32, 0, 42)
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabs
	tabs.Parent = window

	local rebirthPage = makePage(window, 110)
	local starsPage = makePage(window, 110)
	local update = buildRebirthPage(rebirthPage)
	local drawStars = buildStarsPage(starsPage)

	local rebirthTab: TextButton
	local starsTab: TextButton
	local function showTab()
		rebirthPage.Visible = tab == "rebirth"
		starsPage.Visible = tab == "stars"
		rebirthTab.BackgroundColor3 = if tab == "rebirth" then Ui.colors.primary else Ui.colors.locked
		starsTab.BackgroundColor3 = if tab == "stars" then Ui.colors.primary else Ui.colors.locked
		starsTab.Text = ArtIcon.strip(
			ClientState.t("rperk_tab_stars", { count = starCount() }),
			"⭐",
			Images.misc.rebirthStar
		)
	end
	rebirthTab = Ui.button(tabs, ClientState.t("rperk_tab_rebirth"), Ui.colors.locked, function()
		tab = "rebirth"
		showTab()
	end)
	rebirthTab.Size = UDim2.new(0.5, -4, 1, 0)
	starsTab = Ui.button(tabs, "", Ui.colors.locked, function()
		tab = "stars"
		showTab()
	end)
	starsTab.Size = UDim2.new(0.5, -4, 1, 0)
	-- Звезда Rebirth Астры (Images.misc.rebirthStar, V28) вместо ⭐ в названии вкладки
	ArtIcon.prefix(starsTab, "⭐", Images.misc.rebirthStar, 24)

	refresh = function()
		update()
		showTab()
	end
	renderStars = function()
		drawStars()
		update()
		showTab()
	end
	drawStars()
	refresh()
	RebirthPerkRemotes.RequestRebirthPerks:FireServer()
end

function RebirthWindow.start()
	Ui.menuButton(5, "♻️", function()
		if gui then
			close()
		else
			RebirthWindow.open()
		end
	end, "menu_rebirth")

	ClientState.changed:Connect(function()
		if refresh then
			refresh()
		end
	end)
	-- Заголовок и статичные строки не обновляет refresh: при смене языка собираем окно заново
	ClientState.langChanged:Connect(function()
		if gui then
			close()
			RebirthWindow.open()
		end
	end)
	RebirthPerkRemotes.RebirthPerkState.OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then
			return
		end
		perkState = state
		if renderStars then
			renderStars()
		end
	end)
	RebirthPerkRemotes.RequestRebirthPerks:FireServer()

	RetentionRemotes.RebirthResult.OnClientEvent:Connect(function(result)
		if type(result) ~= "table" then
			return
		end
		if result.ok then
			close()
			-- Короткое уведомление в центре экрана
			local screen = Instance.new("ScreenGui")
			screen.Name = "RebirthDone"
			screen.ResetOnSpawn = false
			screen.DisplayOrder = 15
			screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
			local toast = Ui.label(
				screen,
				ClientState.t("rebirth_done", { mult = multText(tonumber(result.rebirths) or 0) }),
				48,
				Ui.titleFont,
				Ui.colors.money
			)
			toast.TextXAlignment = Enum.TextXAlignment.Center
			toast.AnchorPoint = Vector2.new(0.5, 0.5)
			toast.Position = UDim2.fromScale(0.5, 0.35)
			toast.Size = UDim2.fromOffset(520, 48)
			-- Конфетти Астры над игроком (Images.fx, V24); нет текстур — без частиц, как раньше
			ArtIcon.burst({ Images.fx.confetti1, Images.fx.confetti2 }, 40)
			task.delay(4, function()
				screen:Destroy()
			end)
		elseif refresh then
			refresh()
		end
	end)
end

return RebirthWindow
