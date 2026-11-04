--!strict
-- Постеры на стенах студии (Config/Posters): покупка, места на стенах, детали на участке.
-- Обычные — за $ (BuyPoster), премиум — за Robux: квитанцию принимает MonetizationService
-- и зовёт grantProduct (эффект в профиле, сохраняет MonetizationService до PurchaseGranted).
-- PlotService.rebuild сносит все модели участка — постеры ставим заново по plotChanged.
-- Косметика: бонусов к доходу и оценкам нет.
-- Данные: profile.posters = { owned = { [posterId]: true }, equipped = { [slotId]: posterId } }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Posters = require(Shared.Config.Posters)
local Images = require(Shared.Config.Images)
local PosterRemotes = require(Shared.PosterRemotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local MODEL_NAME = "PlayerPosters"
local ACTION_COOLDOWN = 0.25 -- покупка/перевешивание не чаще
local STATE_REQUEST_COOLDOWN = 1
local FRAME_BORDER = 0.3 -- рамка вокруг постера, studs
local PIXELS_PER_STUD = 60
local CASH_FRAME_COLOR = Color3.fromRGB(35, 32, 40)

local PosterService = {}
local lastAction: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}

type PosterData = { owned: { [string]: boolean }, equipped: { [string]: string } }

-- Поле профиля в порядке: старые сохранения без него, мусор, проданные/удалённые из Config постеры
local function data(profile: DataService.Profile): PosterData
	local raw = (profile :: any).posters
	if type(raw) ~= "table" then
		raw = {}
	end
	local owned: { [string]: boolean } = {}
	if type(raw.owned) == "table" then
		for id, value in raw.owned do
			if value == true and Posters.get(id) then
				owned[id] = true
			end
		end
	end
	local equipped: { [string]: string } = {}
	local used: { [string]: boolean } = {}
	if type(raw.equipped) == "table" then
		for slotId, posterId in raw.equipped do
			if
				Posters.getSlot(slotId)
				and type(posterId) == "string"
				and owned[posterId]
				and not used[posterId]
			then
				equipped[slotId] = posterId
				used[posterId] = true
			end
		end
	end
	local clean = { owned = owned, equipped = equipped }
	profile.posters = clean
	return clean
end

local function visibleSlots(profile: DataService.Profile): { Posters.Slot }
	local result = {}
	for _, slot in Posters.slots do
		if Posters.slotVisible(slot, profile.studioLevel) then
			table.insert(result, slot)
		end
	end
	return result
end

local function pushState(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local posters = data(profile)
	local slotIds = {}
	if PlotService.ownsGarage(player) then
		for _, slot in visibleSlots(profile) do
			table.insert(slotIds, slot.id)
		end
	end
	PosterRemotes.PosterState:FireClient(player, {
		owned = posters.owned,
		equipped = posters.equipped,
		slots = slotIds,
	})
end

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Лицевая сторона постера: картинка, если загружена, иначе цвет + эмодзи + название
local function decorate(board: BasePart, poster: Posters.Poster)
	local gui = Instance.new("SurfaceGui")
	-- Постер смотрит на +Z своей детали: это грань Back
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = if poster.premium then 0 else 0.4
	gui.Parent = board

	local imageId = Images.posters[poster.id] or 0
	if imageId > 0 then
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundColor3 = poster.background
		image.BorderSizePixel = 0
		image.ScaleType = Enum.ScaleType.Crop
		image.Image = "rbxassetid://" .. imageId
		image.Parent = gui
		return
	end

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = poster.background
	back.BorderSizePixel = 0
	back.Parent = gui
	if poster.premium then
		-- Глянец: сверху светлее, снизу темнее
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(poster.background:Lerp(poster.accent, 0.35), poster.background)
		gradient.Parent = back
	end

	local emoji = Instance.new("TextLabel")
	emoji.BackgroundTransparency = 1
	emoji.Position = UDim2.fromScale(0.1, 0.08)
	emoji.Size = UDim2.fromScale(0.8, 0.55)
	emoji.TextScaled = true
	emoji.Font = Enum.Font.GothamBold
	emoji.Text = poster.emoji
	emoji.Parent = back

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.06, 0.68)
	title.Size = UDim2.fromScale(0.88, 0.26)
	title.TextScaled = true
	title.TextWrapped = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = poster.accent
	title.TextStrokeTransparency = 0.5
	title.Text = poster.title
	title.Parent = back
end

-- Снести и заново поставить постеры игрока на его участке
local function place(player: Player)
	local plot = PlotService.getPlot(player)
	local profile = DataService.get(player)
	if not plot then
		return
	end
	local old = plot:FindFirstChild(MODEL_NAME)
	if old then
		old:Destroy()
	end
	if not profile or not PlotService.ownsGarage(player) then
		return
	end
	local posters = data(profile)
	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	local size = Posters.size
	for _, slot in visibleSlots(profile) do
		local poster = Posters.get(posters.equipped[slot.id])
		if not poster then
			continue
		end
		local position = slot.position + Vector3.new(0, Posters.stageY(slot.stage), 0)
		local cframe = plot.CFrame * CFrame.new(position) * CFrame.Angles(0, math.rad(slot.rotation), 0)
		-- Рамка чуть позади постера; у премиум — неоновая и светится
		local frame = makePart(
			model,
			"Frame_" .. slot.id,
			Vector3.new(size.X + FRAME_BORDER * 2, size.Y + FRAME_BORDER * 2, size.Z),
			cframe * CFrame.new(0, 0, -size.Z / 2),
			if poster.premium then poster.accent else CASH_FRAME_COLOR
		)
		if poster.premium then
			frame.Material = Enum.Material.Neon
			local glow = Instance.new("PointLight")
			glow.Color = poster.accent
			glow.Range = 8
			glow.Brightness = 0.8
			glow.Parent = frame
		end
		local board = makePart(
			model,
			"Poster_" .. slot.id,
			Vector3.new(size.X, size.Y, size.Z / 2),
			cframe * CFrame.new(0, 0, size.Z / 4),
			poster.background
		)
		board:SetAttribute("PosterId", poster.id)
		decorate(board, poster)
	end
	model.Parent = plot
end

-- Повесить постер на первое свободное место (сразу после покупки)
local function autoEquip(profile: DataService.Profile, posterId: string)
	local posters = data(profile)
	for _, id in posters.equipped do
		if id == posterId then
			return
		end
	end
	for _, slot in visibleSlots(profile) do
		if not posters.equipped[slot.id] then
			posters.equipped[slot.id] = posterId
			return
		end
	end
end

local function grant(player: Player, profile: DataService.Profile, poster: Posters.Poster)
	local posters = data(profile)
	posters.owned[poster.id] = true
	autoEquip(profile, poster.id)
	place(player)
	pushState(player)
end

-- Премиум-постер за Robux (зовёт MonetizationService.ProcessReceipt). false — это не постер.
-- Повторная выдача безопасна: постер просто остаётся купленным
function PosterService.grantProduct(player: Player, profile: DataService.Profile, productId: number): boolean
	local poster = Posters.findByProduct(productId)
	if not poster then
		return false
	end
	grant(player, profile, poster)
	return true
end

-- Выдать постер по id (сделка дня). false — уже куплен или такого нет
function PosterService.grantPoster(player: Player, profile: DataService.Profile, posterId: string): boolean
	local poster = Posters.get(posterId)
	if not poster or data(profile).owned[poster.id] then
		return false
	end
	grant(player, profile, poster)
	return true
end

function PosterService.owns(player: Player, posterId: string): boolean
	local profile = DataService.get(player)
	return profile ~= nil and data(profile).owned[posterId] == true
end

local function throttled(player: Player): boolean
	local now = os.clock()
	if (lastAction[player] or 0) + ACTION_COOLDOWN > now then
		return true
	end
	lastAction[player] = now
	return false
end

local function onBuy(player: Player, posterId: any)
	if throttled(player) then
		return
	end
	local poster = Posters.get(posterId)
	local profile = DataService.get(player)
	-- Премиум за $ не продаётся; купленный второй раз не продаём
	if not poster or poster.premium or not profile then
		return
	end
	local cost = poster.cost
	if type(cost) ~= "number" or cost < 0 or data(profile).owned[poster.id] then
		return
	end
	if DataService.trySpend(player, cost) then
		grant(player, profile, poster)
	end
end

local function onEquip(player: Player, slotId: any, posterId: any)
	if throttled(player) then
		return
	end
	local profile = DataService.get(player)
	local slot = Posters.getSlot(slotId)
	if not profile or not slot or not PlotService.ownsGarage(player) then
		return
	end
	-- Перевешивать можно только на места, которые сейчас на участке
	if not Posters.slotVisible(slot, profile.studioLevel) then
		return
	end
	local posters = data(profile)
	if posterId == nil then
		posters.equipped[slot.id] = nil
	else
		local poster = Posters.get(posterId)
		if not poster or not posters.owned[poster.id] then
			return
		end
		-- Один постер — одно место: снимаем его с прежнего
		for otherSlot, id in posters.equipped do
			if id == poster.id then
				posters.equipped[otherSlot] = nil
			end
		end
		posters.equipped[slot.id] = poster.id
	end
	place(player)
	pushState(player)
end

local function onStateRequest(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + STATE_REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	pushState(player)
end

function PosterService.start()
	PosterRemotes.BuyPoster.OnServerEvent:Connect(onBuy)
	PosterRemotes.EquipPoster.OnServerEvent:Connect(onEquip)
	PosterRemotes.PosterStateRequest.OnServerEvent:Connect(onStateRequest)
	-- Участок собран заново (вход, переезд, Rebirth, покупка гаража) — постеры и места этапа
	PlotService.plotChanged:Connect(function(player: Player)
		place(player)
		pushState(player)
	end)
	DataService.onProfileLoaded(function(player: Player, profile: DataService.Profile)
		data(profile)
		pushState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		lastRequest[player] = nil
	end)
end

return PosterService
