--!strict
-- Рекламные щиты у спавна (Config/Billboards, места — StartPark.billboards).
-- Купил рекламную кампанию (MonetizationService.applyAd → onAdPurchased) — последняя выпущенная
-- игра (profile.lastGame) встаёт в очередь щитов этого сервера на время кампании.
-- Раз в Billboards.rotateSeconds показ меняется: купленные за Robux всегда на щитах (если их
-- больше, чем щитов, — по кругу), за $ — по кругу на оставшихся щитах.
-- Названия игры и студии — ввод игроков: перед показом BroadcastText (TextService для всех).
-- Подписи «Новинка от студии» и «Здесь может быть твоя игра» переводит клиент (SignText + TextKey).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local AdCampaigns = require(Shared.Config.AdCampaigns)
local Billboards = require(Shared.Config.Billboards)
local Images = require(Shared.Config.Images)
local StartPark = require(Shared.Config.StartPark)
local DataService = require(script.Parent.DataService)
local BroadcastText = require(script.Parent.BroadcastText)

type Ad = {
	userId: number,
	name: string,
	studio: string,
	genreId: string,
	score: number,
	paid: boolean,
	addedAt: number,
	expiresAt: number,
}
type Board = {
	empty: Frame,
	ad: Frame,
	cover: ImageLabel,
	icon: TextLabel,
	title: TextLabel,
	studio: TextLabel,
	score: TextLabel,
	shownUserId: number,
}

local BillboardService = {}

local queue: { [number]: Ad } = {} -- по userId: одна игра игрока на щитах
local boards: { Board } = {}
local rotation = 0
local filtering: { [number]: boolean } = {}

local function now(): number
	return os.time()
end

-- ===== Модель щита =====

local function label(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.4
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = parent
	return l
end

-- Опора на дорожке к участку (плейс без парка Астры, тропинки WorldService) — щит не ставим
local function onPlotPath(position: Vector3): boolean
	local paths = workspace:FindFirstChild("PlotPaths")
	for _, path in if paths then paths:GetChildren() else {} do
		if path:IsA("BasePart") then
			local here = path.CFrame:PointToObjectSpace(position)
			if
				math.abs(here.X) < path.Size.X / 2 + Billboards.poleSize
				and math.abs(here.Z) < path.Size.Z / 2 + Billboards.poleSize
			then
				return true
			end
		end
	end
	return false
end

local function buildBoard(folder: Instance, index: number, base: CFrame): Board
	local model = Instance.new("Model")
	model.Name = "Billboard" .. index
	local pole = Instance.new("Part")
	pole.Name = "Pole"
	pole.Anchored = true
	pole.Size = Vector3.new(Billboards.poleSize, Billboards.poleHeight, Billboards.poleSize)
	pole.CFrame = base * CFrame.new(0, Billboards.poleHeight / 2, 0)
	pole.Color = Color3.fromRGB(70, 72, 80)
	pole.Material = Enum.Material.Metal
	pole.Parent = model
	local size = Billboards.panelSize
	local panel = Instance.new("Part")
	panel.Name = "Panel"
	panel.Anchored = true
	panel.Size = Vector3.new(size.X, size.Y, Billboards.panelDepth)
	panel.CFrame = base * CFrame.new(0, Billboards.poleHeight + size.Y / 2, 0)
	panel.Color = Color3.fromRGB(24, 22, 34)
	panel.Material = Enum.Material.SmoothPlastic
	panel.Parent = model
	-- Рамка-подсветка снизу: щит видно издалека
	local strip = Instance.new("Part")
	strip.Name = "Strip"
	strip.Anchored = true
	strip.CanCollide = false
	strip.Size = Vector3.new(size.X, 0.3, Billboards.panelDepth + 0.1)
	strip.CFrame = base * CFrame.new(0, Billboards.poleHeight + 0.15, 0)
	strip.Color = Color3.fromRGB(255, 80, 200)
	strip.Material = Enum.Material.Neon
	strip.Parent = model

	-- Лицо модели — +Z (к спавну): грань Back
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = Billboards.pixelsPerStud
	gui.Parent = panel

	local empty = Instance.new("Frame")
	empty.Name = "Empty"
	empty.BackgroundTransparency = 1
	empty.Size = UDim2.fromScale(1, 1)
	empty.Parent = gui
	-- Перевод — StartParkController по TextKey (имя SignText)
	local emptyTitle = label(
		empty,
		"SignText",
		UDim2.fromScale(0.9, 0.4),
		UDim2.fromScale(0.05, 0.12),
		Color3.fromRGB(255, 201, 60)
	)
	emptyTitle.TextXAlignment = Enum.TextXAlignment.Center
	emptyTitle.Text = "📢 Здесь может быть твоя игра!"
	emptyTitle:SetAttribute("TextKey", "bill_empty")
	local emptyHint =
		label(empty, "SignText", UDim2.fromScale(0.9, 0.24), UDim2.fromScale(0.05, 0.6), Color3.new(1, 1, 1))
	emptyHint.TextXAlignment = Enum.TextXAlignment.Center
	emptyHint.Font = Enum.Font.GothamMedium
	emptyHint.Text = "Купи рекламу — и игру увидит весь сервер"
	emptyHint:SetAttribute("TextKey", "bill_empty_hint")

	local ad = Instance.new("Frame")
	ad.Name = "Ad"
	ad.BackgroundTransparency = 1
	ad.Size = UDim2.fromScale(1, 1)
	ad.Visible = false
	ad.Parent = gui
	local cover = Instance.new("ImageLabel")
	cover.Name = "Cover"
	cover.BackgroundColor3 = Color3.fromRGB(44, 46, 66)
	cover.Size = UDim2.fromScale(0.36, 0.84)
	cover.Position = UDim2.fromScale(0.03, 0.08)
	cover.ScaleType = Enum.ScaleType.Crop
	cover.Parent = ad
	local icon = label(cover, "Icon", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.new(1, 1, 1))
	icon.TextXAlignment = Enum.TextXAlignment.Center
	local tag = label(
		ad,
		"SignText",
		UDim2.fromScale(0.56, 0.16),
		UDim2.fromScale(0.42, 0.08),
		Color3.fromRGB(255, 80, 200)
	)
	tag.Text = "🆕 Новинка от студии"
	tag:SetAttribute("TextKey", "bill_new")
	local studio = label(
		ad,
		"Studio",
		UDim2.fromScale(0.56, 0.16),
		UDim2.fromScale(0.42, 0.25),
		Color3.fromRGB(255, 201, 60)
	)
	local title =
		label(ad, "Title", UDim2.fromScale(0.56, 0.3), UDim2.fromScale(0.42, 0.44), Color3.new(1, 1, 1))
	title.TextWrapped = true
	local score = label(
		ad,
		"Score",
		UDim2.fromScale(0.56, 0.16),
		UDim2.fromScale(0.42, 0.78),
		Color3.fromRGB(255, 201, 60)
	)

	model.Parent = folder
	return {
		empty = empty,
		ad = ad,
		cover = cover,
		icon = icon,
		title = title,
		studio = studio,
		score = score,
		shownUserId = -1,
	}
end

local function build()
	local folder = workspace:FindFirstChild("StartPark")
	if not folder or folder:FindFirstChild("Billboard1") then
		return
	end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local center = if spawn and spawn:IsA("BasePart")
		then Vector3.new(spawn.Position.X, 0, spawn.Position.Z)
		else Vector3.zero
	for _, spot in StartPark.billboards do
		local angle = math.rad(spot.angle)
		local pos = center + Vector3.new(math.cos(angle) * spot.radius, 0, math.sin(angle) * spot.radius)
		if onPlotPath(pos) then
			warn(
				"[BillboardService] Щит на дорожке к участку — пропущен:",
				spot.angle,
				spot.radius
			)
			continue
		end
		-- lookAt направляет −Z к спавну; разворот — лицо (+Z) к спавну
		local base = CFrame.lookAt(pos, center) * CFrame.Angles(0, math.pi, 0)
		table.insert(boards, buildBoard(folder, #boards + 1, base))
	end
end

-- ===== Показ =====

local function show(board: Board, ad: Ad?)
	local userId = if ad then ad.userId else 0
	if board.shownUserId == userId and not ad then
		return
	end
	board.shownUserId = userId
	board.empty.Visible = ad == nil
	board.ad.Visible = ad ~= nil
	if not ad then
		return
	end
	local image = Images.covers[ad.genreId] or 0
	board.cover.Image = if image > 0 then "rbxassetid://" .. image else ""
	board.icon.Text = if image > 0 then "" else (Billboards.genreIcons[ad.genreId] or "🎮")
	board.title.Text = ad.name
	board.studio.Text = ad.studio
	board.score.Text = "★ " .. ad.score
end

local function sortedAds(paid: boolean): { Ad }
	local list: { Ad } = {}
	for _, ad in queue do
		if ad.paid == paid then
			table.insert(list, ad)
		end
	end
	table.sort(list, function(a, b)
		if a.addedAt ~= b.addedAt then
			return a.addedAt < b.addedAt
		end
		return a.userId < b.userId
	end)
	return list
end

local function prune()
	local t = now()
	for userId, ad in queue do
		if ad.expiresAt <= t then
			queue[userId] = nil
		end
	end
end

local function render()
	local count = #boards
	if count == 0 then
		return
	end
	prune()
	local paid = sortedAds(true)
	local cash = sortedAds(false)
	local chosen: { Ad } = {}
	if #paid >= count then
		for i = 1, count do
			table.insert(chosen, paid[(rotation + i - 1) % #paid + 1])
		end
	else
		for _, ad in paid do
			table.insert(chosen, ad)
		end
		local free = count - #paid
		for j = 1, math.min(free, #cash) do
			table.insert(chosen, cash[(rotation + j - 1) % #cash + 1])
		end
	end
	-- Щиты тоже по кругу: одна и та же игра не висит всё время на одном месте
	for i, board in boards do
		show(board, chosen[(i - 1 + rotation) % count + 1])
	end
end

-- Очередь не растёт без конца: выкидываем самые старые за $, потом самые старые за Robux
local function trimQueue()
	local size = 0
	for _ in queue do
		size += 1
	end
	while size > Billboards.maxQueue do
		local victims = sortedAds(false)
		if #victims == 0 then
			victims = sortedAds(true)
		end
		local oldest = victims[1]
		if not oldest then
			return
		end
		queue[oldest.userId] = nil
		size -= 1
	end
end

-- ===== Вход из других сервисов =====

-- Последняя выпущенная игра (DevelopmentService); name уже отфильтрован при релизе
function BillboardService.onGameReleased(
	player: Player,
	info: { name: string, genreId: string, score: number }
)
	local profile = DataService.get(player)
	if not profile or type(info.name) ~= "string" or type(info.genreId) ~= "string" then
		return
	end
	profile.lastGame = {
		name = string.sub(info.name, 1, 200),
		genreId = string.sub(info.genreId, 1, 40),
		score = math.clamp(tonumber(info.score) or 0, 0, 10),
	}
end

-- Куплена рекламная кампания (MonetizationService): paid — за Robux. Не уступает поток
function BillboardService.onAdPurchased(player: Player, campaign: AdCampaigns.AdCampaign, paid: boolean)
	local profile = DataService.get(player)
	local latest = profile and profile.lastGame
	if not profile or not latest or player.UserId <= 0 or filtering[player.UserId] then
		return
	end
	local rawStudio = (profile :: any).studioName
	local studioText = if type(rawStudio) == "string" and rawStudio ~= ""
		then rawStudio
		else "Studio " .. player.DisplayName
	local userId = player.UserId
	local duration = math.max(campaign.durationSeconds, Billboards.minSeconds)
	local gameName, genreId, score = latest.name, latest.genreId, latest.score
	filtering[userId] = true
	task.spawn(function()
		-- Фильтр Roblox для всех (щит видят все игроки сервера); не прошёл — не показываем
		local name = BroadcastText.filter(gameName, userId)
		local studio = BroadcastText.filter(studioText, userId)
		filtering[userId] = nil
		if not name or not studio then
			return
		end
		local t = now()
		local old = queue[userId]
		local stillPaid = old ~= nil and old.paid and old.expiresAt > t
		queue[userId] = {
			userId = userId,
			name = name,
			studio = studio,
			genreId = genreId,
			score = score,
			paid = paid or stillPaid,
			addedAt = if old then old.addedAt else t,
			expiresAt = math.max(if old then old.expiresAt else 0, t + duration),
		}
		trimQueue()
		render()
	end)
end

function BillboardService.start()
	-- Сразу в start: StartParkService (стартует позже по алфавиту) учтёт щиты как препятствия
	local ok, err = pcall(build)
	if not ok then
		warn("[BillboardService] build failed:", err)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		-- Купленный показ остаётся до конца кампании; чистим только служебное
		filtering[player.UserId] = nil
	end)
	render()
	task.spawn(function()
		while true do
			task.wait(Billboards.rotateSeconds)
			rotation += 1
			local okRender, errRender = pcall(render)
			if not okRender then
				warn("[BillboardService] render failed:", errRender)
			end
		end
	end)
end

return BillboardService
