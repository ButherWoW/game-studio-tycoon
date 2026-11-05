--!strict
-- «Зал славы» в парке: три пьедестала у спавна (StartPark.hallOfFame) с топ-3 студий прошлой недели.
-- Очки студии = лайки прошлой недели (OrderedDataStore LikesWeekly_<weekId>, пишет TourService)
-- + Gotw.hallGotwPoints за место в «Игре недели» (GotwService.lastWeekRows).
-- На пьедестале — аватар владельца (Players:CreateHumanoidModelFromUserId, уменьшенный и
-- закреплённый), табличка с названием студии и очками. Обновление — раз в Gotw.hallRefreshSeconds.
-- Название студии: из «Игры недели», иначе DataStore StudioCards_v1 (пишется при входе игрока
-- с названием студии), иначе «Studio <имя>». Текст на табличках — через BroadcastText.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage.Shared
local Gotw = require(Shared.Config.Gotw)
local StartPark = require(Shared.Config.StartPark)
local DataService = require(script.Parent.DataService)
local BroadcastText = require(script.Parent.BroadcastText)

type Winner = { userId: number, points: number, studio: string, player: string }
type Slot = {
	pedestal: BasePart,
	top: CFrame, -- точка на верхней грани пьедестала, лицом (+Z) к спавну
	studio: TextLabel,
	points: TextLabel,
	nameGui: BillboardGui,
	nameLabel: TextLabel,
	userId: number,
	avatar: Model?,
}

local PEDESTALS = {
	{ rank = 2, x = -4.3, height = 2.2, color = Color3.fromRGB(192, 192, 205) },
	{ rank = 1, x = 0, height = 3, color = Color3.fromRGB(255, 200, 50) },
	{ rank = 3, x = 4.3, height = 1.6, color = Color3.fromRGB(205, 127, 50) },
}
local PEDESTAL_SIZE = 3.4
local PLATFORM_HEIGHT = 0.4
local HEADER_Y = 9.4 -- низ вывески: выше аватаров и имён над ними
local MEDALS = { "🥇", "🥈", "🥉" }

local HallOfFameService = {}

local cardStore: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("StudioCards_v1")
	end)
	if ok then
		cardStore = result
	else
		warn("[HallOfFameService] DataStore StudioCards_v1 недоступен:", result)
	end
end

local slots: { [number]: Slot } = {} -- по месту 1..3
local cards: { [number]: string } = {} -- userId -> название студии (кэш на сервер)
local cardWritten: { [number]: string } = {}

local function num(value: any): number
	local n = tonumber(value)
	return if n and n == n and n >= 0 and n < math.huge then math.floor(n) else 0
end

-- ===== Модель =====

local function part(
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function surfaceLabel(p: BasePart, name: string, size: UDim2, position: UDim2, color: Color3): TextLabel
	local gui = p:FindFirstChildOfClass("SurfaceGui")
	if not gui then
		local newGui = Instance.new("SurfaceGui")
		-- Лицо модели — +Z: грань Back
		newGui.Face = Enum.NormalId.Back
		newGui.LightInfluence = 0
		newGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		newGui.PixelsPerStud = 50
		newGui.Parent = p
		gui = newGui
	end
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.5
	label.Text = ""
	label.Parent = gui
	return label
end

local function build()
	local spot = StartPark.hallOfFame
	local park = workspace:FindFirstChild("StartPark")
	if not spot or not park or park:FindFirstChild("HallOfFame") then
		return
	end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local center = if spawn and spawn:IsA("BasePart")
		then Vector3.new(spawn.Position.X, 0, spawn.Position.Z)
		else Vector3.zero
	local angle = math.rad(spot.angle)
	local pos = center + Vector3.new(math.cos(angle) * spot.radius, 0, math.sin(angle) * spot.radius)
	-- lookAt направляет −Z к спавну; разворот — лицо (+Z) к спавну
	local base = CFrame.lookAt(pos, center) * CFrame.Angles(0, math.pi, 0)

	local model = Instance.new("Model")
	model.Name = "HallOfFame"
	part(
		model,
		Vector3.new(spot.width, PLATFORM_HEIGHT, spot.depth),
		base * CFrame.new(0, PLATFORM_HEIGHT / 2, 0),
		Color3.fromRGB(70, 66, 80),
		Enum.Material.Slate
	)
	-- Вывеска «Зал славы» на двух стойках у задней кромки помоста
	local backZ = -spot.depth / 2 + 0.3
	for _, x in { -spot.width / 2 + 0.4, spot.width / 2 - 0.4 } do
		part(
			model,
			Vector3.new(0.3, HEADER_Y, 0.3),
			base * CFrame.new(x, HEADER_Y / 2, backZ),
			Color3.fromRGB(60, 60, 65),
			Enum.Material.Metal
		)
	end
	local header = part(
		model,
		Vector3.new(spot.width, 1.8, 0.3),
		base * CFrame.new(0, HEADER_Y + 0.9, backZ),
		Color3.fromRGB(28, 26, 40)
	)
	header.Name = "Header"
	-- Перевод — StartParkController по TextKey (имя SignText)
	local title = surfaceLabel(
		header,
		"SignText",
		UDim2.fromScale(1, 0.62),
		UDim2.fromScale(0, 0.02),
		Color3.fromRGB(255, 201, 60)
	)
	title.Text = "🏛 Зал славы"
	title:SetAttribute("TextKey", "hall_title")
	local subtitle = surfaceLabel(
		header,
		"SignText",
		UDim2.fromScale(1, 0.34),
		UDim2.fromScale(0, 0.64),
		Color3.new(1, 1, 1)
	)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.Text = "Лучшие студии прошлой недели"
	subtitle:SetAttribute("TextKey", "hall_subtitle")

	for _, info in PEDESTALS do
		local pedestal = part(
			model,
			Vector3.new(PEDESTAL_SIZE, info.height, PEDESTAL_SIZE),
			base * CFrame.new(info.x, PLATFORM_HEIGHT + info.height / 2, 0.2),
			info.color,
			Enum.Material.Marble
		)
		pedestal.Name = "Pedestal" .. info.rank
		local medal = surfaceLabel(
			pedestal,
			"Medal",
			UDim2.fromScale(1, 0.3),
			UDim2.fromScale(0, 0.02),
			Color3.new(1, 1, 1)
		)
		medal.Text = MEDALS[info.rank] .. " " .. info.rank
		local studio = surfaceLabel(
			pedestal,
			"Studio",
			UDim2.fromScale(0.96, 0.34),
			UDim2.fromScale(0.02, 0.34),
			Color3.new(1, 1, 1)
		)
		studio.Text = "—"
		local points = surfaceLabel(
			pedestal,
			"Points",
			UDim2.fromScale(1, 0.26),
			UDim2.fromScale(0, 0.7),
			Color3.fromRGB(255, 240, 200)
		)
		local nameGui = Instance.new("BillboardGui")
		nameGui.Name = "HallName"
		nameGui.Size = UDim2.fromScale(4, 0.8)
		-- Над головой уменьшенного аватара (≈ 3.6 studs), под вывеской
		nameGui.StudsOffsetWorldSpace = Vector3.new(0, info.height / 2 + 4.3, 0)
		nameGui.MaxDistance = 90
		nameGui.LightInfluence = 0
		nameGui.Enabled = false
		nameGui.Parent = pedestal
		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Size = UDim2.fromScale(1, 1)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.TextColor3 = info.color
		nameLabel.TextStrokeTransparency = 0.2
		nameLabel.Parent = nameGui
		slots[info.rank] = {
			pedestal = pedestal,
			top = base * CFrame.new(info.x, PLATFORM_HEIGHT + info.height, 0.2),
			studio = studio,
			points = points,
			nameGui = nameGui,
			nameLabel = nameLabel,
			userId = 0,
			avatar = nil,
		}
	end
	model.Parent = park
end

-- ===== Аватар =====

local function placeAvatar(slot: Slot, userId: number)
	if slot.avatar then
		slot.avatar:Destroy()
		slot.avatar = nil
	end
	if userId <= 0 then
		return
	end
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("Model") then
		warn("[HallOfFameService] Аватар не загрузился:", userId, result)
		return
	end
	-- Место могло смениться, пока грузился аватар
	if slot.userId ~= userId then
		result:Destroy()
		return
	end
	local avatar = result :: Model
	avatar.Name = "HallAvatar"
	for _, item in avatar:GetDescendants() do
		if item:IsA("BaseScript") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
		end
	end
	local humanoid = avatar:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	pcall(function()
		avatar:ScaleTo(Gotw.hallAvatarScale)
	end)
	-- Ступни на верх пьедестала, лицом к спавну (персонаж смотрит в −Z)
	local target = slot.top * CFrame.Angles(0, math.pi, 0)
	avatar:PivotTo(target)
	local box, size = avatar:GetBoundingBox()
	local bottom = box.Position.Y - size.Y / 2
	avatar:PivotTo(target + Vector3.new(0, slot.top.Position.Y - bottom, 0))
	avatar.Parent = slot.pedestal.Parent
	slot.avatar = avatar
end

-- ===== Данные =====

local function readLikes(weekId: number): { [number]: number }?
	local ok, page = pcall(function()
		local store = DataStoreService:GetOrderedDataStore("LikesWeekly_" .. weekId)
		return store:GetSortedAsync(false, Gotw.hallLikesTop):GetCurrentPage()
	end)
	if not ok then
		warn("[HallOfFameService] Лайки недели не прочитались:", page)
		return nil
	end
	local likes: { [number]: number } = {}
	for _, item in page :: any do
		local userId = tonumber(item.key)
		if userId then
			likes[userId] = num(item.value)
		end
	end
	return likes
end

local function readCard(userId: number): string?
	local cached = cards[userId]
	if cached then
		return cached
	end
	local store = cardStore
	if not store then
		return nil
	end
	local ok, result = pcall(function()
		return (store :: DataStore):GetAsync(tostring(userId))
	end)
	if ok and type(result) == "table" and type((result :: any).studio) == "string" then
		local studio = (result :: any).studio :: string
		if #studio <= 200 then
			cards[userId] = studio
			return studio
		end
	end
	return nil
end

local function displayNames(ids: { number }): { [number]: string }
	local names: { [number]: string } = {}
	local missing = {}
	for _, userId in ids do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			names[userId] = player.DisplayName
		else
			table.insert(missing, userId)
		end
	end
	if #missing > 0 then
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(missing)
		end)
		if ok and type(infos) == "table" then
			for _, info in infos do
				if type(info) == "table" and type(info.Id) == "number" then
					local display = info.DisplayName
					names[info.Id] = if type(display) == "string" and display ~= ""
						then display
						else info.Username
				end
			end
		end
	end
	for _, userId in ids do
		names[userId] = names[userId] or ("#" .. userId)
	end
	return names
end

local function winners(): { Winner }?
	local weekId = Gotw.weekId() - 1
	local likes = readLikes(weekId)
	local gotwModule = script.Parent:FindFirstChild("GotwService")
	local gotwRows: any = nil
	if gotwModule and gotwModule:IsA("ModuleScript") then
		local ok, rows = pcall(function()
			return (require(gotwModule) :: any).lastWeekRows()
		end)
		gotwRows = if ok then rows else nil
	end
	if not likes and not gotwRows then
		return nil
	end
	local points: { [number]: number } = {}
	local studios: { [number]: string } = {}
	for userId, count in likes or {} do
		points[userId] = (points[userId] or 0) + count
	end
	for _, row in gotwRows or {} do
		if type(row) == "table" and type(row.userId) == "number" and type(row.rank) == "number" then
			points[row.userId] = (points[row.userId] or 0) + (Gotw.hallGotwPoints[row.rank] or 0)
			if type(row.studio) == "string" and row.studio ~= "?" then
				studios[row.userId] = row.studio
			end
		end
	end
	local list: { Winner } = {}
	for userId, value in points do
		if value > 0 then
			table.insert(list, { userId = userId, points = value, studio = "", player = "" })
		end
	end
	table.sort(list, function(a, b)
		if a.points ~= b.points then
			return a.points > b.points
		end
		return a.userId < b.userId
	end)
	while #list > 3 do
		table.remove(list)
	end
	local ids = {}
	for _, w in list do
		table.insert(ids, w.userId)
	end
	local names = displayNames(ids)
	for _, w in list do
		w.player = names[w.userId]
		w.studio = studios[w.userId] or readCard(w.userId) or ("Studio " .. w.player)
	end
	return list
end

local function refresh()
	if not next(slots) then
		return
	end
	local list = winners()
	if not list then
		return -- DataStore не ответил: оставляем прошлый состав
	end
	for rank = 1, 3 do
		local slot = slots[rank]
		local w = list[rank]
		if slot then
			local userId = if w then w.userId else 0
			if w then
				-- Названия — ввод игроков: фильтр для всех; фильтр недоступен — не показываем
				-- ввод игрока (fail closed), а ставим «Studio <имя Roblox>»
				slot.studio.Text = BroadcastText.filter(w.studio, w.userId) or ("Studio " .. w.player)
				slot.points.Text = "★ " .. w.points
				slot.nameLabel.Text = w.player
				slot.nameGui.Enabled = true
			else
				slot.studio.Text = "—"
				slot.points.Text = ""
				slot.nameGui.Enabled = false
			end
			if slot.userId ~= userId then
				slot.userId = userId
				placeAvatar(slot, userId)
			end
		end
	end
end

-- Название студии для Зала славы — один раз за вход, если есть и изменилось
local function writeCard(player: Player, profile: DataService.Profile)
	local name = (profile :: any).studioName
	local store = cardStore
	if type(name) ~= "string" or name == "" or not store or player.UserId <= 0 then
		return
	end
	if cardWritten[player.UserId] == name then
		return
	end
	cardWritten[player.UserId] = name
	cards[player.UserId] = name
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(tostring(player.UserId), { studio = name })
	end)
	if not ok then
		warn(
			"[HallOfFameService] Карточка студии не записалась:",
			player.UserId,
			err
		)
		cardWritten[player.UserId] = nil
	end
end

function HallOfFameService.start()
	-- Сразу в start: StartParkService (стартует позже по алфавиту) учтёт помост как препятствие
	local ok, err = pcall(build)
	if not ok then
		warn("[HallOfFameService] build failed:", err)
	end
	DataService.onProfileLoaded(function(player: Player, profile: DataService.Profile)
		-- Не сразу: название студии могли ввести в первые секунды
		task.delay(30, function()
			if player.Parent and DataService.get(player) == profile then
				writeCard(player, profile)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		cardWritten[player.UserId] = nil
	end)
	task.spawn(function()
		-- GotwService читает прошлую неделю при старте — даём ему время
		task.wait(15)
		while true do
			local okRefresh, errRefresh = pcall(refresh)
			if not okRefresh then
				warn("[HallOfFameService] refresh failed:", errRefresh)
			end
			task.wait(Gotw.hallRefreshSeconds)
		end
	end)
end

return HallOfFameService
