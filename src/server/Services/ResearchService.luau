--!strict
-- Исследования (шаг 3.4, issue #8): ОИ за выпущенные игры и покупка узлов дерева.
-- Данные — profile.research (Config/Research.Data: points, owned, active, кредиты ускорений;
-- DataService.defaultProfile, проверка при загрузке — Research.sanitize).
-- Жанры открываем здесь; остальные эффекты отдаём через getModifiers.
--
-- Таймер лаборатории (Research.TIMING, просьба владельца 05.11): узел дерева и открытие жанра/темы
-- за $ (UnlockService → startCategory) — одно активное исследование. Цена списывается при старте,
-- эффект — когда os.time() >= active.endsAt (идёт офлайн и на других серверах; готовое закрывается
-- при входе, тост приходит, когда клиент попросил состояние). Отмена — полный возврат.
-- Ускорения: перк «Лаборатория» (RebirthPerks.researchTime) при старте и Robux-товары
-- Products.research (grantProduct из MonetizationService.ProcessReceipt, идемпотентно по квитанции).
-- Атрибуты игрока для HUD и окна «Создать игру»: ResearchKind, ResearchId, ResearchStartedAt,
-- ResearchEndsAt (os.time сервера; клиент сравнивает с workspace:GetServerTimeNow()).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Research = require(ReplicatedStorage.Shared.Config.Research)
local RebirthPerks = require(ReplicatedStorage.Shared.Config.RebirthPerks)
local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local Products = require(ReplicatedStorage.Shared.Config.Products)
local UnlockRules = require(ReplicatedStorage.Shared.UnlockRules)
local ResearchRemotes = require(ReplicatedStorage.Shared.ResearchRemotes)
local DataService = require(script.Parent.DataService)

local REQUEST_COOLDOWN = 0.5 -- секунд между запросами состояния от одного игрока
local CANCEL_COOLDOWN = 1
local TICK_SECONDS = 1 -- как часто проверяем, не закончилось ли исследование

local ResearchService = {}
local lastRequest: { [Player]: number } = {}
local lastCancel: { [Player]: number } = {}
-- Закончилось, пока игрока не было (при входе): тост, когда клиент попросит состояние
local pendingToasts: { [Player]: { { kind: string, id: string } } } = {}

-- Данные исследований игрока; nil, пока профиль не загружен
local function getData(player: Player): Research.Data?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	if type(profile.research) ~= "table" then
		profile.research = Research.defaultData()
	end
	return profile.research
end

-- Необязательный сервис (аналитика): без него ничего не ломается
local function logEvent(player: Player, field: string)
	local module = script.Parent:FindFirstChild("AnalyticsService")
	if module and module:IsA("ModuleScript") then
		local analytics = require(module) :: any
		if type(analytics.logDepth) == "function" then
			pcall(analytics.logDepth, player, "research", field)
		end
	end
end

local function setAttributes(player: Player, active: Research.Active?)
	player:SetAttribute("ResearchKind", if active then active.kind else nil)
	player:SetAttribute("ResearchId", if active then active.id else nil)
	player:SetAttribute("ResearchStartedAt", if active then active.startedAt else nil)
	player:SetAttribute("ResearchEndsAt", if active then active.endsAt else nil)
end

local function replicate(player: Player)
	local data = getData(player)
	if data then
		-- Окно «Команда» по атрибуту показывает, что РОБО-9000 можно нанять
		player:SetAttribute("RobotHire", Research.modifiers(data.owned).robotHire)
		setAttributes(player, data.active)
		local profile = DataService.get(player)
		local perks = RebirthPerks.forProfile(profile)
		-- Окно «Создать игру» показывает время открытия жанра/темы с перком «Лаборатория»
		player:SetAttribute("ResearchTimeReduction", perks.researchTime)
		ResearchRemotes.ResearchChanged:FireClient(player, {
			points = data.points,
			owned = data.owned,
			-- Скидка звёзд студии (ветка «Лаборатория»): окно показывает цены с ней
			discount = perks.researchDiscount,
			-- И сокращение времени той же ветки: окно показывает длительность с ним
			timeReduction = perks.researchTime,
			active = data.active,
			creditSeconds = data.creditSeconds,
			creditSkips = data.creditSkips,
		})
	end
end

-- Применить эффект и освободить лабораторию. Без yield
local function finish(player: Player, offline: boolean)
	local profile = DataService.get(player)
	local data = getData(player)
	local active = data and data.active
	if not profile or not data or not active then
		return
	end
	data.active = nil
	if active.kind == "node" then
		local node = Research.byId[active.id]
		data.owned[active.id] = true
		local genreId = node and node.effect.unlockGenre
		if genreId and Genres[genreId] then
			profile.unlockedGenres[genreId] = true
		end
	elseif active.kind == "genre" and Genres[active.id] then
		profile.unlockedGenres[active.id] = true
	elseif active.kind == "topic" and Topics[active.id] then
		profile.unlockedTopics[active.id] = true
	end
	DataService.replicate(player)
	replicate(player)
	logEvent(player, "finish_" .. active.kind .. "_" .. active.id)
	local toast = { kind = active.kind, id = active.id }
	if offline then
		local list = pendingToasts[player] or {}
		table.insert(list, toast)
		pendingToasts[player] = list
	else
		ResearchRemotes.ResearchFinished:FireClient(player, toast)
	end
end

-- Запустить таймер (цена уже списана). Кредиты ускорений за Robux применяются сразу
local function startTimer(
	player: Player,
	kind: Research.ActiveKind,
	id: string,
	minutes: number,
	paid: number
)
	local profile = DataService.get(player)
	local data = getData(player)
	if not profile or not data then
		return
	end
	local now = os.time()
	local seconds = Research.durationSeconds(minutes, RebirthPerks.forProfile(profile).researchTime)
	local active: Research.Active =
		{ kind = kind, id = id, startedAt = now, endsAt = now + seconds, paid = paid }
	-- «Завершить сейчас» из запаса — только на долгое (как в окне: короче skipHideSeconds не предлагаем)
	if data.creditSkips > 0 and seconds > Research.skipHideSeconds then
		data.creditSkips -= 1
		active.endsAt = now
	elseif data.creditSeconds > 0 then
		active.endsAt = math.max(active.endsAt - data.creditSeconds, now)
		data.creditSeconds = 0
	end
	data.active = active
	logEvent(player, "start_" .. kind .. "_" .. id)
	if active.endsAt <= now then
		finish(player, false)
	else
		replicate(player)
	end
end

-- Вызывать из DevelopmentService при релизе: ОИ = оценка игры
function ResearchService.onGameReleased(player: Player, score: number)
	if type(score) ~= "number" or score ~= score or score == math.huge then
		return
	end
	local data = getData(player)
	if not data then
		return
	end
	local gained = math.floor(math.clamp(score, 0, 10)) * Research.POINTS_PER_SCORE
	if gained <= 0 then
		return
	end
	data.points += gained
	replicate(player)
end

-- Очки исследований из наград (задания, вход, праздники) — в тот же счёт, что и за релизы
function ResearchService.addPoints(player: Player, points: number)
	local data = getData(player)
	if data and type(points) == "number" and points > 0 and points < math.huge then
		data.points += math.floor(points)
		replicate(player)
	end
end

-- Множители от изученных узлов (см. Research.Modifiers). Без профиля — нейтральные
function ResearchService.getModifiers(player: Player): Research.Modifiers
	local data = getData(player)
	return Research.modifiers(if data then data.owned else {})
end

function ResearchService.isResearched(player: Player, nodeId: string): boolean
	local data = getData(player)
	return data ~= nil and data.owned[nodeId] == true
end

-- Лаборатория занята (окно «Создать игру» не начнёт открытие жанра/темы)
function ResearchService.isBusy(player: Player): boolean
	local data = getData(player)
	return data ~= nil and data.active ~= nil
end

local function onBuy(player: Player, nodeId: any)
	if type(nodeId) ~= "string" then
		return
	end
	local node = Research.byId[nodeId]
	local profile = DataService.get(player)
	local data = getData(player)
	if not node or not profile or not data or data.active then
		return
	end
	local cost = RebirthPerks.researchCost(node.cost, RebirthPerks.forProfile(profile).researchDiscount)
	if data.owned[nodeId] or not Research.requirementsMet(node, data.owned) or data.points < cost then
		return
	end
	-- Узел жанра: пока не выполнены условия жанра (shared/UnlockRules), не изучается.
	-- Жанр уже открыт (куплен или старое сохранение) — узел можно изучить ради цепочки
	local lockedGenre = node.effect.unlockGenre
	if
		lockedGenre
		and Genres[lockedGenre]
		and not profile.unlockedGenres[lockedGenre]
		and not UnlockRules.check(Genres[lockedGenre], profile)
	then
		return
	end

	-- Без yield между проверкой и списанием: двойной клик не спишет дважды
	data.points -= cost
	startTimer(player, "node", nodeId, node.minutes, cost)
end

-- Открытие жанра/темы за $ (UnlockService): проверки условий — там, здесь лаборатория и деньги.
-- true — таймер запущен (или сразу готово по кредиту ускорения)
function ResearchService.startCategory(
	player: Player,
	kind: "genre" | "topic",
	id: string,
	cost: number
): boolean
	local data = getData(player)
	if not data or data.active then
		return false
	end
	if not DataService.trySpend(player, cost) then
		return false
	end
	startTimer(player, kind, id, Research.categoryMinutes(cost), cost)
	return true
end

local function onCancel(player: Player)
	local now = os.clock()
	if (lastCancel[player] or 0) + CANCEL_COOLDOWN > now then
		return
	end
	lastCancel[player] = now
	local data = getData(player)
	local active = data and data.active
	if not data or not active then
		return
	end
	-- Уже закончилось (тик ещё не дошёл): не возвращаем, а выдаём
	if os.time() >= active.endsAt then
		finish(player, false)
		return
	end
	data.active = nil
	if active.kind == "node" then
		data.points += active.paid
	else
		DataService.addCash(player, active.paid)
		-- Возврат — не заработок: иначе старт/отмена закрывали бы задания «заработай»
		local rewards = script.Parent:FindFirstChild("RewardService")
		if rewards and rewards:IsA("ModuleScript") then
			pcall((require(rewards) :: any).noteNonEarned, player, active.paid)
		end
	end
	logEvent(player, "cancel_" .. active.kind .. "_" .. active.id)
	replicate(player)
end

-- Продукт ускорения по productId (0 — ещё не создан в Dashboard, не совпадает ни с чем)
local function findProduct(productId: number): Products.ResearchProduct?
	for _, product in Products.research do
		if product.productId ~= 0 and product.productId == productId then
			return product
		end
	end
	return nil
end

-- Ускорение за Robux (MonetizationService.ProcessReceipt; квитанцию и сохранение ведёт он).
-- Нет активного исследования — кредит на следующее. false — не наш товар
function ResearchService.grantProduct(
	player: Player,
	profile: DataService.Profile,
	productId: number
): boolean
	local product = findProduct(productId)
	if not product then
		return false
	end
	if type(profile.research) ~= "table" then
		profile.research = Research.defaultData()
	end
	local data = profile.research
	local active = data.active
	logEvent(
		player,
		"skip_" .. product.id .. "_" .. (if active then active.kind .. "_" .. active.id else "credit")
	)
	if not active then
		if product.skip then
			data.creditSkips += 1
		else
			data.creditSeconds += product.seconds
		end
		replicate(player)
		return true
	end
	local now = os.time()
	active.endsAt = if product.skip then now else math.max(active.endsAt - product.seconds, now)
	if active.endsAt <= now then
		finish(player, false)
	else
		replicate(player)
	end
	return true
end

-- Rebirth (RebirthService): открытие жанра/темы за $ сгорает вместе со студией, как недоделанная
-- игра (деньги и так сбрасываются, а жанры/темы — снова закрыты). Узел дерева идёт дальше
function ResearchService.onRebirth(player: Player)
	local data = getData(player)
	local active = data and data.active
	if data and active and active.kind ~= "node" then
		data.active = nil
		logEvent(player, "rebirth_" .. active.kind .. "_" .. active.id)
	end
	replicate(player)
end

-- Перки Rebirth изменились (RebirthPerkService): прислать цены со скидкой
function ResearchService.sync(player: Player)
	replicate(player)
end

local function onRequest(player: Player)
	local now = os.clock()
	local last = lastRequest[player]
	if last and now - last < REQUEST_COOLDOWN then
		return
	end
	lastRequest[player] = now
	replicate(player)
	-- Клиент готов слушать: тосты исследований, закончившихся офлайн
	local toasts = pendingToasts[player]
	if toasts then
		pendingToasts[player] = nil
		for _, toast in toasts do
			ResearchRemotes.ResearchFinished:FireClient(
				player,
				{ kind = toast.kind, id = toast.id, offline = true }
			)
		end
	end
end

local function tick()
	local now = os.time()
	for _, player in Players:GetPlayers() do
		local profile = DataService.get(player)
		local research = profile and profile.research
		local active = if type(research) == "table" then research.active else nil
		if active and now >= active.endsAt then
			-- Ошибка одного игрока не должна останавливать цикл для всех
			local ok, err = pcall(finish, player, false)
			if not ok then
				warn("[ResearchService] finish failed:", player.UserId, err)
			end
		end
	end
end

function ResearchService.start()
	ResearchRemotes.BuyResearch.OnServerEvent:Connect(onBuy)
	ResearchRemotes.RequestResearch.OnServerEvent:Connect(onRequest)
	ResearchRemotes.CancelResearch.OnServerEvent:Connect(onCancel)
	-- Вход: закончившееся офлайн (или на другом сервере) закрываем сразу, тост — по запросу клиента
	DataService.onProfileLoaded(function(player, profile)
		local active = profile.research.active
		if active and os.time() >= active.endsAt then
			finish(player, true)
		else
			setAttributes(player, active)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		lastCancel[player] = nil
		pendingToasts[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			tick()
		end
	end)
end

return ResearchService
