--!strict
-- Картриджи-хиты: игра с оценкой >= 7 становится картриджем на полке участка и приносит
-- деньги раз в минуту. Чужой картридж можно украсть (ProximityPrompt), донести до своей полки
-- и забрать себе; хозяин, коснувшись вора, возвращает картридж и получает штраф.
-- Вход — HitService.onGameReleased из DevelopmentService.release (через optional).
--
-- Против дюпа: пока картридж несут, он остаётся в profile.hits хозяина (просто не стоит
-- на полке). Переход к вору — одним действием при доставке, после проверки, что он ещё
-- у хозяина. Любой сбой (вор умер/вышел/убежал, хозяин вышел) — картридж просто снова на полке.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DailyEvents = require(ReplicatedStorage.Shared.Config.DailyEvents)
local Gotw = require(ReplicatedStorage.Shared.Config.Gotw)
local HitCartridges = require(ReplicatedStorage.Shared.Config.HitCartridges)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local RebirthPerks = require(ReplicatedStorage.Shared.Config.RebirthPerks)
local Tours = require(ReplicatedStorage.Shared.Config.Tours)
local HitRemotes = require(ReplicatedStorage.Shared.HitRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local ModelFactory = require(script.Parent.ModelFactory)
local StyleModels = require(script.Parent.StyleModels)
local ThiefBoardService = require(script.Parent.ThiefBoardService)

export type Hit = {
	id: string,
	name: string,
	genreId: string,
	topicId: string,
	score: number,
	creatorId: number,
	creatorName: string,
	stolenFrom: string?, -- у кого украден последним (имя для «украдено у …»)
	-- «Обновление / DLC»: UTC-день последнего обновления (Tours.dayId) и конец буста дохода (os.time).
	-- Едут с картриджем при краже: вор не обновит его второй раз в тот же день
	updatedDay: number?,
	boostUntil: number?,
}

type Shelf = { model: Model, parts: { [string]: BasePart } }

type Carry = {
	thief: Player,
	victim: Player,
	hit: Hit,
	part: BasePart,
	highlight: Highlight,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	speedBefore: number,
	startedAt: number,
	lastPosition: Vector3,
	lastCheck: number,
}

local DELIVER_SPEED_SLACK = 2 -- studs запаса на лаги при проверке пути перед доставкой
local CARRY_TICK = 0.1
local REQUEST_COOLDOWN = 1
local CARTRIDGE_SIZE = Vector3.new(1.4, 1.6, 0.35)

local HitService = {}

local shelves: { [Player]: Shelf } = {}
local carries: { [Player]: Carry } = {} -- по вору
local carriedIds: { [string]: Carry } = {}
local leaving: { [Player]: boolean } = {}
-- Таймеры на os.clock(); клиенту отправляем остаток в секундах
local lockedUntil: { [number]: number } = {}
local lockReadyAt: { [number]: number } = {}
local immuneUntil: { [number]: number } = {}
local stealReadyAt: { [number]: number } = {}
-- Таймеры выше — по UserId и не чистятся при выходе: перезаход их не сбрасывает
-- Пара «вор → жертва» (ключ "thief:victim") и начало удержания prompt у каждого вора
local pairReadyAt: { [string]: number } = {}
local holdStarted: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
local lastUpdate: { [Player]: number } = {}
local cachedTemplate: Model? = nil
local cachedTrophy: Model? = nil

local function toast(player: Player, key: string, vars: { [string]: any }?)
	if player.Parent then
		HitRemotes.HitToast:FireClient(player, { key = key, vars = vars })
	end
end

-- Картриджи в профиле: ленивая инициализация и отсев мусора из сохранения
local function hitsOf(profile: DataService.Profile): { Hit }
	local p = profile :: any
	if type(p.hits) ~= "table" then
		p.hits = {}
		return p.hits
	end
	local clean = true
	for _, hit in p.hits do
		if type(hit) ~= "table" or type(hit.id) ~= "string" or type(hit.score) ~= "number" then
			clean = false
			break
		end
		-- Поля обновления из сохранения: не число (или NaN/inf) — как будто обновления не было
		for _, field in { "updatedDay", "boostUntil" } do
			local value = hit[field]
			if
				value ~= nil and (type(value) ~= "number" or value ~= value or math.abs(value) == math.huge)
			then
				hit[field] = nil
			end
		end
	end
	if not clean then
		local list: { Hit } = {}
		for _, hit in p.hits do
			if type(hit) == "table" and type(hit.id) == "string" and type(hit.score) == "number" then
				hit.name = if type(hit.name) == "string" then hit.name else "?"
				hit.creatorName = if type(hit.creatorName) == "string" then hit.creatorName else "?"
				table.insert(list, hit :: Hit)
			end
		end
		p.hits = list
	end
	return p.hits
end

local function capacity(profile: DataService.Profile): number
	-- + места за звёзды студии (Config/RebirthPerks, ветка «Пассив»), не больше мест на модели
	local bonus = RebirthPerks.forProfile(profile).hitSlots
	return math.min(HitCartridges.slots(profile.studioLevel) + bonus, HitCartridges.maxSlots)
end

-- На полке стоят сильнейшие capacity штук (после Rebirth слотов меньше — лишние «в коробке»).
-- Порядок: по оценке, при равенстве — кто раньше попал в профиль
local function activeHits(profile: DataService.Profile): { Hit }
	local hits = hitsOf(profile)
	local order: { number } = {}
	for i in hits do
		table.insert(order, i)
	end
	table.sort(order, function(a, b)
		if hits[a].score ~= hits[b].score then
			return hits[a].score > hits[b].score
		end
		return a < b
	end)
	local result: { Hit } = {}
	for i = 1, math.min(#order, capacity(profile)) do
		table.insert(result, hits[order[i]])
	end
	return result
end

local function findIndex(hits: { Hit }, id: string): number?
	for i, hit in hits do
		if hit.id == id then
			return i
		end
	end
	return nil
end

-- Сколько картриджей хранится всего: на полке — сильнейшие capacity(profile), остальные
-- «в коробке» до следующих переездов (после Rebirth слотов меньше, но хиты не пропадают)
local BOX_LIMIT = HitCartridges.maxSlots

-- Самый слабый не уносимый сейчас картридж (при равенстве — самый старый)
local function weakestIndex(hits: { Hit }): (number?, number)
	local weakest: number? = nil
	local weakestScore = math.huge
	for i, candidate in hits do
		if not carriedIds[candidate.id] and candidate.score < weakestScore then
			weakest = i
			weakestScore = candidate.score
		end
	end
	return weakest, weakestScore
end

-- Поместится ли хит: коробка не полна или он сильнее самого слабого
local function fits(profile: DataService.Profile, hit: Hit): boolean
	local hits = hitsOf(profile)
	if #hits < BOX_LIMIT then
		return true
	end
	local _, weakestScore = weakestIndex(hits)
	return hit.score > weakestScore
end

-- Добавить картридж; при полной коробке выкинуть самый слабый (при равенстве — самый старый).
-- Новый тоже участвует: если он слабее всех, он и вылетает. Уносимые сейчас не трогаем.
-- Возвращает true, если новый остался.
local function addHit(profile: DataService.Profile, hit: Hit): boolean
	local hits = hitsOf(profile)
	table.insert(hits, hit)
	while #hits > BOX_LIMIT do
		local weakest = #hits
		local weakestScore = math.huge
		for i, candidate in hits do
			if not carriedIds[candidate.id] and candidate.score < weakestScore then
				weakest = i
				weakestScore = candidate.score
			end
		end
		table.remove(hits, weakest)
	end
	return findIndex(hits, hit.id) ~= nil
end

-- Доход картриджа в минуту с учётом буста обновления
local function hitIncome(hit: Hit, now: number): number
	local income = HitCartridges.income(hit.score)
	if (hit.boostUntil or 0) > now then
		income = math.floor(income * HitCartridges.updateBoost)
	end
	return income
end

-- Доход полки в минуту: картриджи × множитель фанатов студии (Config/Fans, ×1 при 0 фанатах)
local function incomeOf(profile: DataService.Profile): number
	local total = 0
	local now = os.time()
	for _, hit in activeHits(profile) do
		if not carriedIds[hit.id] then
			total += hitIncome(hit, now)
		end
	end
	return math.floor(total * Formulas.fanMultiplier(tonumber(profile.fans) or 0))
end

-- Модуль другой фичи без жёсткой зависимости (ShopService тянет много сервисов)
local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

-- Цена обновления хита: минуты дохода студии (ShopService.incomePerMinute)
local function updatePrice(player: Player, profile: DataService.Profile): number
	local shop = optional("ShopService")
	local income = 0
	if shop and type(shop.incomePerMinute) == "function" then
		local ok, value = pcall(shop.incomePerMinute, player, profile)
		income = if ok and type(value) == "number" then value else 0
	end
	return HitCartridges.updatePrice(income)
end

local function isNewbie(profile: DataService.Profile): boolean
	return profile.gamesReleased < HitCartridges.newbieGames
end

local function promptsOpen(player: Player, profile: DataService.Profile): boolean
	return (lockedUntil[player.UserId] or 0) <= os.clock() and not isNewbie(profile)
end

local function sendState(player: Player)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	local now = os.clock()
	local stats = ThiefBoardService.stats(profile)
	-- Картриджи на полке для кнопок «Обновить»: можно ли сегодня и сколько ещё идёт буст
	local today = Tours.dayId()
	local nowTime = os.time()
	local list = {}
	for _, hit in activeHits(profile) do
		table.insert(list, {
			id = hit.id,
			name = hit.name,
			genreId = hit.genreId, -- обложка жанра (V20) в строке окна хитов
			score = hit.score,
			income = hitIncome(hit, nowTime),
			boostLeft = math.max((hit.boostUntil or 0) - nowTime, 0),
			updatedToday = hit.updatedDay == today,
			carried = carriedIds[hit.id] ~= nil,
		})
	end
	HitRemotes.HitState:FireClient(player, {
		hits = list,
		updatePrice = updatePrice(player, profile),
		updateBoost = HitCartridges.updateBoost,
		updateMinutes = HitCartridges.updateBoostMinutes,
		updateScore = HitCartridges.updateScore,
		updateMaxScore = HitCartridges.updateMaxScore,
		nextDayIn = (today + 1) * 86400 - nowTime,
		count = #activeHits(profile),
		slots = capacity(profile),
		income = incomeOf(profile),
		lockLeft = math.max((lockedUntil[player.UserId] or 0) - now, 0),
		lockReadyIn = math.max((lockReadyAt[player.UserId] or 0) - now, 0),
		lockSeconds = HitCartridges.lockSeconds,
		newbieGames = HitCartridges.newbieGames,
		steals = stats.steals,
		stolenIncome = stats.stolenIncome,
		caught = stats.caught,
		catches = stats.catches,
	})
end

-- ===== Полка =====

local function shelfTemplate(profile: DataService.Profile): Model?
	-- Модель, импортированная в Studio (в стиле мебели игрока, StyleModels), важнее собранной из деталей
	local folder = ServerStorage:FindFirstChild("Upgrades")
	local imported = StyleModels.find(folder, "HitShelf", profile)
	if imported and imported:IsA("Model") then
		return imported
	end
	if not cachedTemplate then
		cachedTemplate = ModelFactory.build("HitShelf")
	end
	return cachedTemplate
end

-- Статуэтка «Игра недели» (GotwService): модель Trophy_GOTW из ServerStorage.Upgrades, иначе из деталей
local function trophyTemplate(): Model
	local folder = ServerStorage:FindFirstChild("Upgrades")
	local imported = folder and folder:FindFirstChild(Gotw.trophyModel)
	if imported and imported:IsA("Model") then
		return imported
	end
	if cachedTrophy then
		return cachedTrophy
	end
	local model = Instance.new("Model")
	model.Name = Gotw.trophyModel
	local gold = Color3.fromRGB(255, 200, 50)
	local function piece(size: Vector3, offset: Vector3, color: Color3, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Size = size
		p.CFrame = CFrame.new(offset)
		p.Color = color
		p.Material = Enum.Material.Metal
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	local base = piece(Vector3.new(1, 0.3, 1), Vector3.new(0, 0.15, 0), Color3.fromRGB(40, 32, 28))
	piece(Vector3.new(0.25, 0.6, 0.25), Vector3.new(0, 0.6, 0), gold)
	piece(Vector3.new(0.8, 0.8, 0.8), Vector3.new(0, 1.25, 0), gold, Enum.PartType.Ball)
	local star = piece(Vector3.new(0.45, 0.45, 0.45), Vector3.new(0, 1.85, 0), gold, Enum.PartType.Ball)
	star.Material = Enum.Material.Neon
	model.PrimaryPart = base
	model.WorldPivot = CFrame.new()
	cachedTrophy = model
	return model
end

local function renderTrophy(profile: DataService.Profile, shelf: Shelf)
	local old = shelf.model:FindFirstChild("GotwTrophy")
	local gotw = (profile :: any).gotw
	local show = type(gotw) == "table" and (tonumber(gotw.trophyUntil) or 0) > os.time()
	if not show then
		if old then
			old:Destroy()
		end
		return
	end
	if old then
		return
	end
	local trophy = trophyTemplate():Clone()
	trophy.Name = "GotwTrophy"
	for _, item in trophy:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
		end
	end
	trophy:PivotTo(shelf.model:GetPivot() * Gotw.trophyOffset)
	trophy.Parent = shelf.model
end

-- Кубок блиц-джема (DailyEventService → rewards.trophies.blitzJam): только модель Астры
-- Trophy_Blitz из ServerStorage.Upgrades (или ServerStorage); нет модели — ничего не ставим
local function renderBlitzTrophy(profile: DataService.Profile, shelf: Shelf)
	local cfg = DailyEvents.blitzJam
	if shelf.model:FindFirstChild("BlitzTrophy") then
		return
	end
	local rewards = (profile :: any).rewards
	local trophies = type(rewards) == "table" and rewards.trophies
	local wins = if type(trophies) == "table" then tonumber(trophies[cfg.trophy]) or 0 else 0
	if wins <= 0 then
		return
	end
	local folder = ServerStorage:FindFirstChild("Upgrades")
	local source = (folder and folder:FindFirstChild(cfg.trophyModel))
		or ServerStorage:FindFirstChild(cfg.trophyModel)
	if not (source and source:IsA("Model")) then
		return
	end
	local trophy = source:Clone()
	trophy.Name = "BlitzTrophy"
	for _, item in trophy:GetDescendants() do
		if item:IsA("BaseScript") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
		end
	end
	trophy:PivotTo(shelf.model:GetPivot() * cfg.trophyOffset)
	trophy.Parent = shelf.model
end

local function makeCartridge(hit: Hit): Part
	local rarity = HitCartridges.rarity(hit.score)
	local p = Instance.new("Part")
	p.Name = "Hit_" .. hit.id
	p.Size = CARTRIDGE_SIZE
	p.Color = rarity.color
	p.Material = if rarity.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	if rarity.glow then
		local glow = Instance.new("PointLight")
		glow.Color = rarity.color
		glow.Range = 6
		glow.Brightness = 1.5
		glow.Parent = p
	end
	-- Размер в studs: подписи соседних картриджей (шаг 2) не налезают друг на друга
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(2, 0.55)
	billboard.StudsOffset = Vector3.new(0, 1.15, 0)
	billboard.MaxDistance = 40
	billboard.LightInfluence = 0
	billboard.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = rarity.color
	label.TextStrokeTransparency = 0.3
	label.Text = "★" .. hit.score .. " " .. hit.name
	label.Parent = billboard
	return p
end

local tryStartSteal: (thief: Player, owner: Player, hitId: string, source: BasePart) -> ()

local function addPrompt(owner: Player, profile: DataService.Profile, part: BasePart, hit: Hit)
	local prompt = Instance.new("ProximityPrompt")
	-- Текст на языке игрока ставит клиент (HitController); здесь — запасной
	prompt.ActionText = Texts.ru.hit_prompt
	prompt.ObjectText = "★" .. hit.score .. " " .. hit.name
	prompt.HoldDuration = HitCartridges.holdDuration
	prompt.MaxActivationDistance = HitCartridges.promptDistance
	prompt.RequiresLineOfSight = false
	local open = promptsOpen(owner, profile)
	prompt.Enabled = open
	-- Клиент прячет prompt у хозяина локально; «Open» — серверное состояние для пересчёта
	prompt:SetAttribute("Open", open)
	prompt:SetAttribute("HitOwner", owner.UserId)
	prompt.PromptButtonHoldBegan:Connect(function(thief: Player)
		holdStarted[thief] = os.clock()
	end)
	prompt.Triggered:Connect(function(thief: Player)
		tryStartSteal(thief, owner, hit.id, part)
	end)
	prompt.Parent = part
end

local function refreshPrompts(player: Player)
	local shelf = shelves[player]
	local profile = DataService.get(player)
	if not shelf or not profile then
		return
	end
	local open = promptsOpen(player, profile)
	for _, part in shelf.parts do
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = open
			prompt:SetAttribute("Open", open)
		end
	end
end

-- Поставить полку (если её снёс PlotService.rebuild) и заново расставить картриджи
local function renderShelf(player: Player)
	local plot = PlotService.getPlot(player)
	local profile = DataService.get(player)
	if not plot or not profile or leaving[player] then
		return
	end
	local shelf = shelves[player]
	if not shelf or not shelf.model:IsDescendantOf(plot) then
		if shelf then
			shelf.model:Destroy()
		end
		local template = shelfTemplate(profile)
		if not template then
			return
		end
		local model = template:Clone()
		model.Name = "HitShelf"
		model:PivotTo(
			plot.CFrame
				* CFrame.new(HitCartridges.shelfPosition)
				* CFrame.Angles(0, math.rad(HitCartridges.shelfRotation), 0)
		)
		model.Parent = plot
		shelf = { model = model, parts = {} }
		shelves[player] = shelf
	end
	local current = shelf :: Shelf
	for _, part in current.parts do
		part:Destroy()
	end
	current.parts = {}
	local pivot = current.model:GetPivot()
	-- Слот уносимого картриджа остаётся пустым: видно, что именно украли
	for index, hit in activeHits(profile) do
		if not carriedIds[hit.id] then
			local part = makeCartridge(hit)
			part.Anchored = true
			part.CFrame = pivot * ModelFactory.hitShelfSlot(index)
			addPrompt(player, profile, part, hit)
			part.Parent = current.model
			current.parts[hit.id] = part
		end
	end
	renderTrophy(profile, current)
	renderBlitzTrophy(profile, current)
end

-- ===== Кража =====

local function getRoot(character: Model?): (Humanoid?, BasePart?)
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, root
end

-- Снять картридж с вора. Сам картридж всё это время в профиле хозяина
local function cleanup(carry: Carry)
	if carries[carry.thief] == carry then
		carries[carry.thief] = nil
	end
	if carriedIds[carry.hit.id] == carry then
		carriedIds[carry.hit.id] = nil
	end
	carry.part:Destroy()
	carry.highlight:Destroy()
	if carry.humanoid.Parent and carry.humanoid.Health > 0 then
		carry.humanoid.WalkSpeed = carry.speedBefore
	end
	if carry.victim.Parent then
		HitRemotes.HitAlarm:FireClient(carry.victim, { stop = true })
	end
	renderShelf(carry.victim)
	sendState(carry.victim)
end

local function cancelCarry(carry: Carry)
	cleanup(carry)
	toast(carry.thief, "hit_carry_failed")
	toast(carry.victim, "hit_returned", { name = carry.hit.name })
end

local function caught(carry: Carry)
	local thiefProfile = DataService.get(carry.thief)
	local victimProfile = DataService.get(carry.victim)
	cleanup(carry)
	if not thiefProfile or not victimProfile then
		return
	end
	local penalty = math.max(HitCartridges.penaltyMin, HitCartridges.penaltyMinutes * incomeOf(thiefProfile))
	-- В минус не уводим: забираем сколько есть
	local amount = math.floor(math.min(penalty, thiefProfile.cash))
	if amount > 0 and DataService.trySpend(carry.thief, amount) then
		DataService.addCash(carry.victim, amount)
	else
		amount = 0
	end
	local thiefStats = ThiefBoardService.stats(thiefProfile)
	thiefStats.caught += 1
	local victimStats = ThiefBoardService.stats(victimProfile)
	victimStats.catches += 1
	ThiefBoardService.changed(carry.thief)
	toast(carry.victim, "hit_caught_thief", { amount = Texts.money(amount) })
	toast(
		carry.thief,
		"hit_you_were_caught",
		{ player = carry.victim.DisplayName, amount = Texts.money(amount) }
	)
	sendState(carry.thief)
	sendState(carry.victim)
end

local function deliver(carry: Carry)
	local thiefProfile = DataService.get(carry.thief)
	local victimProfile = DataService.get(carry.victim)
	if not thiefProfile or not victimProfile then
		cancelCarry(carry)
		return
	end
	local victimHits = hitsOf(victimProfile)
	local index = findIndex(victimHits, carry.hit.id)
	if not index then
		cancelCarry(carry)
		return
	end
	-- Без yield между проверкой и переносом: картридж не может оказаться у двоих
	-- Коробка вора полна более сильными: картридж не поместится — не уничтожаем чужой хит
	if not fits(thiefProfile, carry.hit) then
		cancelCarry(carry)
		return
	end
	cleanup(carry)
	local hit = table.remove(victimHits, index) :: Hit
	hit.stolenFrom = carry.victim.DisplayName
	local record = hit :: any
	record.stolenFromId = carry.victim.UserId
	record.stolenAt = os.time()
	-- В статистику «Главных воров» картридж идёт один раз на вора: перекладывание туда-сюда не накручивает
	record.thieves = if type(record.thieves) == "table" then record.thieves else {}
	local firstTime = record.thieves[tostring(carry.thief.UserId)] == nil
	record.thieves[tostring(carry.thief.UserId)] = true
	addHit(thiefProfile, hit)
	immuneUntil[carry.victim.UserId] = os.clock() + HitCartridges.victimImmunity
	local stats = ThiefBoardService.stats(thiefProfile)
	if firstTime then
		stats.steals += 1
		stats.stolenIncome += HitCartridges.income(hit.score)
	end
	ThiefBoardService.changed(carry.thief)
	toast(carry.thief, "hit_stolen_by_you", { name = hit.name, player = carry.victim.DisplayName })
	toast(carry.victim, "hit_lost", { name = hit.name, player = carry.thief.DisplayName })
	renderShelf(carry.thief)
	renderShelf(carry.victim)
	sendState(carry.thief)
	sendState(carry.victim)
	-- Сохраняем обоих сразу: окно, когда картридж есть у двоих в DataStore, — секунды, а не минута
	task.spawn(DataService.save, carry.victim)
	task.spawn(DataService.save, carry.thief)
end

tryStartSteal = function(thief: Player, owner: Player, hitId: string, source: BasePart)
	if thief == owner or leaving[thief] or leaving[owner] or not owner.Parent or carries[thief] then
		return
	end
	local thiefProfile = DataService.get(thief)
	local ownerProfile = DataService.get(owner)
	if not thiefProfile or not ownerProfile then
		return
	end
	local now = os.clock()
	if isNewbie(thiefProfile) then
		toast(thief, "hit_err_newbie", { count = HitCartridges.newbieGames })
		return
	elseif isNewbie(ownerProfile) then
		toast(thief, "hit_err_victim_newbie")
		return
	elseif (lockedUntil[owner.UserId] or 0) > now then
		toast(thief, "hit_err_locked")
		return
	elseif (immuneUntil[owner.UserId] or 0) > now then
		toast(thief, "hit_err_immune", { seconds = math.ceil(immuneUntil[owner.UserId] - now) })
		return
	elseif (stealReadyAt[thief.UserId] or 0) > now then
		toast(thief, "hit_err_cooldown", { seconds = math.ceil(stealReadyAt[thief.UserId] - now) })
		return
	elseif carriedIds[hitId] then
		toast(thief, "hit_err_busy")
		return
	elseif (pairReadyAt[thief.UserId .. ":" .. owner.UserId] or 0) > now then
		toast(thief, "hit_err_pair", {
			minutes = math.ceil((pairReadyAt[thief.UserId .. ":" .. owner.UserId] - now) / 60),
		})
		return
	end
	-- Prompt держат HoldDuration секунд; fireproximityprompt без удержания не проходит
	local began = holdStarted[thief]
	holdStarted[thief] = nil
	if not began or now - began < HitCartridges.holdDuration - 0.3 then
		return
	end
	-- Картридж должен стоять на полке хозяина прямо сейчас
	local hit: Hit? = nil
	for _, candidate in activeHits(ownerProfile) do
		if candidate.id == hitId then
			hit = candidate
		end
	end
	-- Нести некуда — у вора нет своей полки (участок не выдан)
	if not hit or not shelves[thief] then
		return
	end
	-- Свой же картридж, отобранный недавно, обратно не утащить: пинг-понг на альтах
	local taken = hit :: any
	if
		taken.stolenFromId == thief.UserId
		and (tonumber(taken.stolenAt) or 0) + HitCartridges.stealBackCooldown > os.time()
	then
		toast(thief, "hit_err_steal_back")
		return
	end
	local character = thief.Character
	local humanoid, root = getRoot(character)
	if not humanoid or not root or not character then
		return
	end
	-- Prompt проверяет дистанцию на клиенте; повторяем на сервере с запасом на пинг
	if (root.Position - source.Position).Magnitude > HitCartridges.promptDistance + 4 then
		return
	end

	stealReadyAt[thief.UserId] = now + HitCartridges.thiefCooldown
	pairReadyAt[thief.UserId .. ":" .. owner.UserId] = now + HitCartridges.pairCooldown
	local part = makeCartridge(hit)
	part.Name = "CarriedHit"
	part.Anchored = false
	part.Massless = true
	part.CanQuery = false
	-- В руках перед грудью; WeldConstraint держит текущее взаимное положение
	part.CFrame = root.CFrame * CFrame.new(0, 0.3, -1.1)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	part.Parent = character

	local highlight = Instance.new("Highlight")
	highlight.Name = "ThiefHighlight"
	highlight.FillColor = Color3.fromRGB(255, 60, 60)
	highlight.OutlineColor = Color3.fromRGB(255, 220, 220)
	highlight.FillTransparency = 0.6
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = character
	highlight.Parent = character

	local carry: Carry = {
		thief = thief,
		victim = owner,
		hit = hit,
		part = part,
		highlight = highlight,
		character = character,
		humanoid = humanoid,
		root = root,
		speedBefore = humanoid.WalkSpeed,
		startedAt = now,
		lastPosition = root.Position,
		lastCheck = now,
	}
	humanoid.WalkSpeed = HitCartridges.carrySpeed
	carries[thief] = carry
	carriedIds[hit.id] = carry
	renderShelf(owner)
	sendState(owner)
	HitRemotes.HitAlarm:FireClient(
		owner,
		{ thiefId = thief.UserId, thiefName = thief.DisplayName, name = hit.name }
	)
	toast(thief, "hit_carry_hint", { name = hit.name })
end

-- Одна проверка уносимого картриджа: вернуть, поймали, донёс или несёт дальше
local function checkCarry(carry: Carry)
	local thief, victim = carry.thief, carry.victim
	if leaving[victim] or not victim.Parent or not DataService.get(victim) then
		cancelCarry(carry)
		return
	end
	local _, root = getRoot(thief.Character)
	if
		leaving[thief]
		or not thief.Parent
		or thief.Character ~= carry.character
		or root ~= carry.root
		or not root
		or not carry.part:IsDescendantOf(carry.character)
	then
		cancelCarry(carry)
		return
	end
	local now = os.clock()
	local position = root.Position
	local flat = Vector3.new(position.X, 0, position.Z)
	if
		now - carry.startedAt > HitCartridges.carryTimeout
		or position.Y < HitCartridges.fallY
		or flat.Magnitude > HitCartridges.maxMapDistance
	then
		cancelCarry(carry)
		return
	end
	-- Скорость по горизонтали между проверками: спидхак и телепорт возвращают картридж
	local dt = now - carry.lastCheck
	if dt >= 0.25 then
		local moved = Vector3.new(position.X - carry.lastPosition.X, 0, position.Z - carry.lastPosition.Z)
		if moved.Magnitude / dt > HitCartridges.maxCarrySpeed then
			cancelCarry(carry)
			return
		end
		carry.lastPosition = position
		carry.lastCheck = now
	end
	-- Полёт: под вором нет пола ближе maxCarryHeight — кража отменяется
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance }
	if not workspace:Raycast(position, Vector3.new(0, -HitCartridges.maxCarryHeight, 0), params) then
		cancelCarry(carry)
		return
	end
	local _, victimRoot = getRoot(victim.Character)
	local gap = if victimRoot then victimRoot.Position - position else nil
	if
		gap
		and Vector3.new(gap.X, 0, gap.Z).Magnitude <= HitCartridges.catchDistance
		and math.abs(gap.Y) <= HitCartridges.catchHeight
	then
		caught(carry)
		return
	end
	local shelf = shelves[thief]
	if shelf and shelf.model.Parent then
		local target = shelf.model:GetPivot().Position
		local offset = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
		if offset.Magnitude <= HitCartridges.deliverDistance and math.abs(target.Y - position.Y) < 8 then
			-- Скорость проверяется раз в 0.25 с, а доставка — каждый тик: телепорт к полке между
			-- проверками не должен засчитаться. Путь от последней точки проверки — не быстрее бега
			local sinceCheck = now - carry.lastCheck
			local moved = Vector3.new(position.X - carry.lastPosition.X, 0, position.Z - carry.lastPosition.Z)
			if moved.Magnitude > HitCartridges.maxCarrySpeed * sinceCheck + DELIVER_SPEED_SLACK then
				cancelCarry(carry)
				return
			end
			deliver(carry)
		end
	end
end

-- Игрок сейчас уносит чужой картридж или его картридж уносят (для PlotService: кнопка 🏠)
function HitService.inChase(player: Player): boolean
	for _, carry in carries do
		if carry.thief == player or carry.victim == player then
			return true
		end
	end
	return false
end

-- ===== Защита и вход =====

local function onRequestLock(player: Player)
	local profile = DataService.get(player)
	if not profile or leaving[player] then
		return
	end
	local now = os.clock()
	if (lockReadyAt[player.UserId] or 0) > now then
		sendState(player)
		return
	end
	lockedUntil[player.UserId] = now + HitCartridges.lockSeconds
	lockReadyAt[player.UserId] = now + HitCartridges.lockCooldown
	refreshPrompts(player)
	sendState(player)
	task.delay(HitCartridges.lockSeconds + 0.1, function()
		if player.Parent and not leaving[player] then
			refreshPrompts(player)
			sendState(player)
		end
	end)
end

-- «Обновление / DLC» хита на своей полке: раз в UTC-день на картридж, цена — минуты дохода
local function onRequestUpdate(player: Player, hitId: any)
	if type(hitId) ~= "string" or #hitId > 64 or leaving[player] then
		return
	end
	local now = os.clock()
	if (lastUpdate[player] or 0) + HitCartridges.updateCooldown > now then
		return
	end
	lastUpdate[player] = now
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local hit: Hit? = nil
	for _, candidate in activeHits(profile) do
		if candidate.id == hitId then
			hit = candidate
		end
	end
	if not hit then
		toast(player, "hitupd_err_missing")
		sendState(player)
		return
	end
	local target = hit :: Hit
	local today = Tours.dayId()
	if carriedIds[target.id] then
		toast(player, "hitupd_err_carried")
		return
	elseif target.updatedDay == today then
		toast(player, "hitupd_err_today")
		sendState(player)
		return
	end
	local price = updatePrice(player, profile)
	if not DataService.trySpend(player, price) then
		toast(player, "hitupd_err_cash", { price = Texts.money(price) })
		return
	end
	local nowTime = os.time()
	target.updatedDay = today
	target.boostUntil = math.max(target.boostUntil or 0, nowTime) + HitCartridges.updateBoostMinutes * 60
	target.score = math.min(target.score + HitCartridges.updateScore, HitCartridges.updateMaxScore)
	toast(player, "hitupd_done", {
		name = target.name,
		score = target.score,
		boost = HitCartridges.updateBoost,
		minutes = HitCartridges.updateBoostMinutes,
	})
	renderShelf(player)
	sendState(player)
end

-- Перерисовать полку и окно (статуэтка «Игры недели» появилась или пропала)
function HitService.refreshShelf(player: Player)
	renderShelf(player)
	sendState(player)
end

local function onRequestState(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	sendState(player)
end

-- name уже отфильтрован TextService в DevelopmentService (его видят все игроки)
function HitService.onGameReleased(
	player: Player,
	info: { name: string, genreId: string, topicId: string, score: number }
)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if info.score >= HitCartridges.minScore then
		local hit: Hit = {
			id = HttpService:GenerateGUID(false),
			name = info.name,
			genreId = info.genreId,
			topicId = info.topicId,
			score = math.clamp(math.floor(info.score), 1, 10),
			creatorId = player.UserId,
			creatorName = player.DisplayName,
		}
		if addHit(profile, hit) then
			toast(
				player,
				"hit_new",
				{ name = hit.name, score = hit.score, income = Texts.money(HitCartridges.income(hit.score)) }
			)
		else
			toast(player, "hit_shelf_full", { name = hit.name })
		end
		renderShelf(player)
	else
		-- Мог перестать быть новичком: открыть prompts
		refreshPrompts(player)
	end
	sendState(player)
end

local function onPlayerRemoving(player: Player)
	leaving[player] = true
	for _, carry in carries do
		if carry.thief == player or carry.victim == player then
			cancelCarry(carry)
		end
	end
	local shelf = shelves[player]
	if shelf then
		shelf.model:Destroy()
	end
	shelves[player] = nil
	lastRequest[player] = nil
	lastUpdate[player] = nil
	holdStarted[player] = nil
	-- Обработчики, начатые до выхода, ещё могут спросить leaving
	task.delay(30, function()
		leaving[player] = nil
	end)
end

function HitService.start()
	HitRemotes.RequestLock.OnServerEvent:Connect(onRequestLock)
	HitRemotes.RequestHitState.OnServerEvent:Connect(onRequestState)
	HitRemotes.RequestHitUpdate.OnServerEvent:Connect(onRequestUpdate)
	-- Участок собран (вход, переезд, Rebirth): поставить полку и картриджи, обновить слоты
	PlotService.plotChanged:Connect(function(player: Player)
		renderShelf(player)
		sendState(player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Один общий цикл: проверки уносимых картриджей
	task.spawn(function()
		while true do
			task.wait(CARRY_TICK)
			local list: { Carry } = {}
			for _, carry in carries do
				table.insert(list, carry)
			end
			for _, carry in list do
				-- Мог уже завершиться в этом же проходе (вор поймал вора и т.п.)
				if carries[carry.thief] == carry then
					-- Ошибка в одной краже не должна останавливать цикл для всех
					local ok, err = pcall(checkCarry, carry)
					if not ok then
						warn("[HitService] checkCarry failed:", err)
						pcall(cancelCarry, carry)
					end
				end
			end
		end
	end)

	-- Один общий цикл пассивного дохода
	task.spawn(function()
		while true do
			task.wait(HitCartridges.incomeInterval)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(function()
					local profile = DataService.get(player)
					if profile and not leaving[player] then
						local amount = incomeOf(profile)
						if amount > 0 then
							DataService.addCash(player, amount)
							toast(player, "hit_income", { amount = Texts.money(amount) })
						end
					end
				end)
				if not ok then
					warn("[HitService] income failed:", err)
				end
			end
		end
	end)
end

return HitService
