--!strict
-- «📊 Топ-10 индустрии» (кнопка меню — слот 18): место студии игрока среди конкурентов
-- (RivalService, Config/Rivals) по стоимости студии. Плашка под HUD, пока идёт хит конкурента
-- (атрибуты ReplicatedStorage RivalHit*), тосты «обогнал студию» и «конкурент выпустил хит».
-- Логотипы студий — Config/Images.rivals (V19); 0 — эмодзи студии, как раньше.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local DepthRemotes = require(Shared.DepthRemotes)
local Genres = require(Shared.Config.Genres)
local Images = require(Shared.Config.Images)
local Rivals = require(Shared.Config.Rivals)
local Texts = require(Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local DepthToast = require(script.Parent.Parent.DepthToast)
local Ui = require(script.Parent.Parent.Ui)

local MENU_SLOT = 17
local ROW_HEIGHT = 40
local BANNER_HEIGHT = 26
local BANNER_WIDTH = 400
local REFRESH_SECONDS = 5

local player = Players.LocalPlayer

local RivalWindow = {}

local gui: ScreenGui? = nil
local content: ScrollingFrame? = nil
local footer: TextLabel? = nil
local state: any = nil

local function genreName(id: any): string
	local genre = if type(id) == "string" then Genres[id] else nil
	return if genre then ClientState.localName(genre) else tostring(id)
end

-- Логотип студии по id или по названию (в тостах и плашке хита сервер шлёт только название); 0 — нет
local function logoOf(id: any, name: any): number
	if type(id) ~= "string" then
		id = nil
		for _, rival in Rivals.list do
			if rival.name == name then
				id = rival.id
				break
			end
		end
	end
	return if type(id) == "string" then Images.rivals[id] or 0 else 0
end

local function hitPercent(): number
	return math.floor((1 - Rivals.hitRevenueMultiplier) * 100 + 0.5)
end

local function render()
	local frame = content
	if not frame then
		return
	end
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	if type(state) ~= "table" or type(state.top) ~= "table" then
		Ui.label(frame, ClientState.t("quests_loading"), 28, nil, Ui.colors.muted)
		return
	end
	for i, entry in state.top do
		local you = entry.you == true
		local row = Instance.new("Frame")
		row.BackgroundColor3 = if you then Color3.fromRGB(40, 62, 52) else Color3.fromRGB(44, 46, 66)
		row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		row.LayoutOrder = i
		Ui.corner(row, 10)
		local name = if you then ClientState.t("rivals_you", { name = entry.name }) else entry.name
		local logo = if you then 0 else logoOf(entry.id, entry.name)
		local left = Ui.label(
			row,
			if logo > 0
				then string.format("%d. %s", i, tostring(name))
				else string.format("%d. %s %s", i, tostring(entry.icon), tostring(name)),
			26,
			nil,
			if you then Ui.colors.good else Ui.colors.text
		)
		left.Position = UDim2.fromOffset(10, 7)
		left.Size = UDim2.new(0.62, -10, 0, 26)
		if logo > 0 then
			-- Логотип слева от места, текст сдвигается на ширину логотипа
			local art = Ui.artImage(row, logo, "left")
			if art then
				art.Size = UDim2.fromOffset(ROW_HEIGHT - 6, ROW_HEIGHT - 6)
				art.Position = UDim2.new(0, 6, 0.5, 0)
			end
			left.Position = UDim2.fromOffset(ROW_HEIGHT + 6, 7)
			left.Size = UDim2.new(0.62, -(ROW_HEIGHT + 6), 0, 26)
		end
		local right = Ui.label(row, Texts.money(tonumber(entry.value) or 0), 26, nil, Ui.colors.money)
		right.TextXAlignment = Enum.TextXAlignment.Right
		right.Position = UDim2.new(0.62, 0, 0, 7)
		right.Size = UDim2.new(0.38, -10, 0, 26)
		row.Parent = frame
	end
	local label = footer
	if label then
		local parts = { ClientState.t("rivals_rank", { rank = state.rank }) }
		if type(state.nextName) == "string" then
			table.insert(
				parts,
				ClientState.t(
					"rivals_next",
					{ name = state.nextName, gap = Texts.money(tonumber(state.nextGap) or 0) }
				)
			)
		else
			table.insert(parts, ClientState.t("rivals_first"))
		end
		label.Text = table.concat(parts, " · ")
	end
end

function RivalWindow.close()
	if gui then
		gui:Destroy()
		gui = nil
		content = nil
		footer = nil
		Ui.windowClosed()
	end
end

function RivalWindow.open()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "RivalWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened(RivalWindow.close) -- окно меню: закрывает другое открытое окно меню

	local window = Ui.window(screen, "Window", Vector2.new(600, 600))
	local title = Ui.label(window, ClientState.t("rivals_title"), 40, Ui.titleFontFor(ClientState.lang))
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 40)
	local close = Ui.button(window, ClientState.t("create_close"), Ui.colors.bad, RivalWindow.close)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Size = UDim2.fromOffset(40, 40)

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(16, 60)
	scroll.Size = UDim2.new(1, -32, 1, -116)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	Ui.list(scroll, 6)
	scroll.Parent = window
	content = scroll

	local foot = Ui.label(window, "", 24, Enum.Font.GothamMedium, Ui.colors.money)
	foot.TextXAlignment = Enum.TextXAlignment.Center
	foot.Position = UDim2.new(0, 16, 1, -44)
	foot.Size = UDim2.new(1, -32, 0, 28)
	footer = foot

	render()
	DepthRemotes.RivalRequest:FireServer()
end

local function buildHitBanner()
	local banner =
		Ui.label(Ui.bannerStack(), "", BANNER_HEIGHT, Ui.titleFontFor(ClientState.lang), Ui.colors.bad)
	banner.Name = "RivalHitBanner"
	banner.LayoutOrder = 6
	banner.TextXAlignment = Enum.TextXAlignment.Center
	banner.Size = UDim2.fromOffset(BANNER_WIDTH, BANNER_HEIGHT)
	banner.BackgroundTransparency = 0.25
	banner.BackgroundColor3 = Ui.colors.panel
	banner.Visible = false
	Ui.corner(banner, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.Parent = banner

	-- Логотип студии слева (Images.rivals); меняется вместе с хитом
	local art: ImageLabel? = nil
	local artId = 0
	local function setLogo(id: number)
		if id == artId then
			return
		end
		artId = id
		if art then
			art:Destroy()
		end
		art = Ui.artImage(banner, id, "left")
		padding.PaddingLeft = UDim.new(0, if art then 10 + BANNER_HEIGHT else 10)
		padding.PaddingRight = padding.PaddingLeft
		if art then
			art.Position = UDim2.new(0, -BANNER_HEIGHT, 0.5, 0)
		end
	end

	local function refresh()
		local endsAt = ReplicatedStorage:GetAttribute("RivalHitEndsAt")
		local left = if type(endsAt) == "number" then endsAt - workspace:GetServerTimeNow() else 0
		if left <= 0 then
			banner.Visible = false
			return
		end
		local s = math.floor(left)
		local studio = ReplicatedStorage:GetAttribute("RivalHitStudio")
		local logo = logoOf(nil, studio)
		setLogo(logo)
		banner.Visible = true
		banner.Font = Ui.titleFontFor(ClientState.lang)
		local text = ClientState.t("rivals_hit_banner", {
			icon = if logo > 0
				then ""
				else tostring(ReplicatedStorage:GetAttribute("RivalHitIcon") or "🏢"),
			name = tostring(studio or ""),
			genre = genreName(ReplicatedStorage:GetAttribute("RivalHitGenre")),
			percent = hitPercent(),
			time = string.format("%d:%02d", s // 60, s % 60),
		})
		banner.Text = (string.gsub(text, "^%s+", ""))
	end
	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)
end

function RivalWindow.start()
	Ui.menuButton(MENU_SLOT, "📊", function()
		if gui then
			RivalWindow.close()
		else
			RivalWindow.open()
		end
	end)
	buildHitBanner()
	DepthRemotes.RivalState.OnClientEvent:Connect(function(newState: any)
		if type(newState) == "table" then
			state = newState
			render()
		end
	end)
	DepthRemotes.RivalNotice.OnClientEvent:Connect(function(info: any)
		if type(info) ~= "table" then
			return
		end
		-- Есть логотип — эмодзи из текста убираем, логотип рисует тост слева
		local passed = info.passed
		if type(passed) == "table" then
			local logo = logoOf(passed.id, passed.name)
			local text = ClientState.t("rivals_passed", {
				icon = if logo > 0 then "" else tostring(passed.icon),
				name = tostring(passed.name),
				reward = Texts.money(tonumber(passed.reward) or 0),
			})
			DepthToast.show((string.gsub(text, "^%s+", "")), Ui.colors.good, logo)
		end
		local hit = info.hit
		if type(hit) == "table" then
			local logo = logoOf(hit.id, hit.name)
			local text = ClientState.t("rivals_hit", {
				icon = if logo > 0 then "" else tostring(hit.icon),
				name = tostring(hit.name),
				genre = genreName(hit.genreId),
				percent = hitPercent(),
			})
			DepthToast.show((string.gsub(text, "^%s+", "")), Ui.colors.bad, logo)
		end
	end)
	-- Пока окно открыто — обновлять (деньги и конкуренты растут)
	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			if gui then
				DepthRemotes.RivalRequest:FireServer()
			end
		end
	end)
end

return RivalWindow
