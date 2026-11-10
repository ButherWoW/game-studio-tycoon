--!strict
-- Обмен между игроками на сервере (Config/Friends.trade): косметика за $ (скины, постеры,
-- маскоты — Friends.tradeable) и деньги. Купленное за Robux не меняется.
-- Ход: запрос (TradeRequest) -> принять (TradeRespond) -> оба собирают предложение (TradeOffer,
-- каждый раз целиком) -> оба подтверждают (TradeConfirm). Любое изменение снимает оба
-- подтверждения и запирает кнопку на lockSeconds. Когда подтвердили оба — сервер заново
-- проверяет всё (оба на сервере, владение, долг, деньги) и меняет одним куском без yield.
-- Игрок в долгу (cash < 0) не меняется: иначе уводил бы предметы от приставов.
-- Состояние живёт только в памяти сервера; в профиле — только итог (предметы и деньги)
-- и сколько денег игрок получил обменами за текущие сутки UTC:
--   (profile :: any).tradeCash = { day = os.time() // 86400, received = number }.
-- Потолок полученного за сутки — Friends.trade.dailyCashMinutes минут СВОЕГО дохода получателя
-- (защита от перекачки с альтов повторными обменами по 50%).
-- Сохранение после обмена: сначала тот, кто отдаёт, потом получатель, по очереди — если вторая
-- запись не пройдёт, предмет пропадёт, но не раздвоится. Каждый обмен пишет в лог свой id.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Friends = require(Shared.Config.Friends)
local Skins = require(Shared.Config.Skins)
local Posters = require(Shared.Config.Posters)
local Mascots = require(Shared.Config.Mascots)
local FriendRemotes = require(Shared.FriendRemotes)
local PriceLevels = require(script.Parent.PriceLevels)
local DataService = require(script.Parent.DataService)
local FeatureUnlockService = require(script.Parent.FeatureUnlockService)
local SkinService = require(script.Parent.SkinService)
local PosterService = require(script.Parent.PosterService)
local MascotService = require(script.Parent.MascotService)
local RewardService = require(script.Parent.RewardService)
local FeatureReleaseService = require(script.Parent.FeatureReleaseService)

local DAY_SECONDS = 86400
local STATE_REQUEST_COOLDOWN = 1
local TIMEOUT_CHECK = 5

type Item = { kind: string, id: string }
type Offer = { items: { Item }, cash: number }
type Trade = {
	a: Player,
	b: Player,
	offers: { [Player]: Offer },
	confirmed: { [Player]: boolean },
	lockUntil: number,
	startedAt: number,
	id: string,
}

local TradeService = {}
local trades: { [Player]: Trade } = {}
-- Входящие запросы: incoming[кому][от кого] = os.clock()
local incoming: { [Player]: { [Player]: number } } = {}
local lastRequest: { [Player]: number } = {}
local lastOffer: { [Player]: number } = {}
local lastStateRequest: { [Player]: number } = {}
local declined: { [Player]: { [number]: number } } = {} -- кто кому отказал: [запросивший][userId]
local cooldownUntil: { [Player]: number } = {}
local tradeCounter = 0

local function notice(player: Player, payload: { [string]: any })
	FriendRemotes.FriendNotice:FireClient(player, payload)
end

local function log(player: Player, value: number, field: string)
	local analytics = script.Parent:FindFirstChild("AnalyticsService")
	if analytics and analytics:IsA("ModuleScript") then
		pcall((require(analytics) :: any).logLiveOps, player, "trade", value, field)
	end
end

local function owns(profile: DataService.Profile, item: Item): boolean
	if item.kind == "skin" then
		return SkinService.owns(profile, item.id)
	elseif item.kind == "poster" then
		return PosterService.ownsIn(profile, item.id)
	elseif item.kind == "mascot" then
		return MascotService.owns(profile, item.id)
	end
	return false
end

-- Что игрок может отдать: открытая косметика за $
local function inventory(profile: DataService.Profile): { Item }
	local result: { Item } = {}
	for _, skin in Skins.list do
		if Friends.tradeable("skin", skin.id) and SkinService.owns(profile, skin.id) then
			table.insert(result, { kind = "skin", id = skin.id })
		end
	end
	for _, poster in Posters.list do
		if Friends.tradeable("poster", poster.id) and PosterService.ownsIn(profile, poster.id) then
			table.insert(result, { kind = "poster", id = poster.id })
		end
	end
	for _, mascot in Mascots.list do
		if Friends.tradeable("mascot", mascot.id) and MascotService.owns(profile, mascot.id) then
			table.insert(result, { kind = "mascot", id = mascot.id })
		end
	end
	return result
end

-- Сколько денег игрок может положить в обмен
local function maxCash(profile: DataService.Profile): number
	if not Friends.trade.cashEnabled then
		return 0
	end
	return math.max(math.floor(profile.cash * Friends.trade.maxCashShare), 0)
end

-- Полученные обменами деньги за сегодня (UTC); вчерашнее обнуляется, мусор из сохранения чинится
local function cashLog(profile: DataService.Profile): { day: number, received: number }
	local today = os.time() // DAY_SECONDS
	local raw = (profile :: any).tradeCash
	local received = if type(raw) == "table" then raw.received else nil
	if
		type(raw) ~= "table"
		or raw.day ~= today
		or type(received) ~= "number"
		or received ~= received
		or received < 0
		or received == math.huge
	then
		raw = { day = today, received = 0 };
		(profile :: any).tradeCash = raw
	end
	return raw
end

-- Сколько ещё денег игрок может получить обменами сегодня
local function receiveLeft(player: Player, profile: DataService.Profile): number
	local cap = RewardService.incomeForMinutes(player, profile, Friends.trade.dailyCashMinutes)
	if type(cap) ~= "number" or cap ~= cap then
		return 0
	end
	return math.max(math.floor(cap - cashLog(profile).received), 0)
end

-- Сколько денег giver может положить в обмен с receiver: доля своего баланса и остаток суточного
-- потолка получателя
local function maxCashFor(
	profile: DataService.Profile,
	receiver: Player,
	receiverProfile: DataService.Profile
): number
	return math.min(maxCash(profile), receiveLeft(receiver, receiverProfile))
end

local function partnerOf(trade: Trade, player: Player): Player
	return if trade.a == player then trade.b else trade.a
end

local function pushState(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local trade = trades[player]
	local payload: { [string]: any } = { inventory = inventory(profile), maxCash = maxCash(profile) }
	if trade then
		local partner = partnerOf(trade, player)
		local partnerProfile = DataService.get(partner)
		if partnerProfile then
			payload.maxCash = maxCashFor(profile, partner, partnerProfile)
		end
		payload.trade = {
			partnerName = partner.DisplayName,
			partnerUserId = partner.UserId,
			mine = trade.offers[player],
			theirs = trade.offers[partner],
			myConfirm = trade.confirmed[player] == true,
			theirConfirm = trade.confirmed[partner] == true,
			lockLeft = math.max(trade.lockUntil - os.clock(), 0),
		}
	end
	FriendRemotes.TradeState:FireClient(player, payload)
end

local function pushBoth(trade: Trade)
	pushState(trade.a)
	pushState(trade.b)
end

local function endTrade(trade: Trade)
	if trades[trade.a] == trade then
		trades[trade.a] = nil
	end
	if trades[trade.b] == trade then
		trades[trade.b] = nil
	end
end

local function cancel(trade: Trade, by: Player?)
	endTrade(trade)
	for _, player in { trade.a, trade.b } do
		if player.Parent then
			notice(
				player,
				{ kind = "tradeCancelled", name = if by and by ~= player then by.DisplayName else nil }
			)
			pushState(player)
		end
	end
	log(by or trade.a, 0, "cancelled")
end

-- Может ли игрок сейчас начать обмен (nil — может, иначе причина для тоста)
local function blocker(player: Player): string?
	local profile = DataService.get(player)
	if not player.Parent or not profile then
		return "tradeUnavailable"
	elseif trades[player] then
		return "tradeBusy"
	elseif not FeatureUnlockService.isOpen(player, "trade") then
		-- Обмен открывается со 2-го этажа (Config/Unlocks): новичку запросы не приходят
		return "tradeUnavailable"
	elseif profile.cash < 0 then
		return "tradeDebt"
	elseif (cooldownUntil[player] or 0) > os.clock() then
		return "tradeCooldown"
	end
	return nil
end

local function startTrade(a: Player, b: Player)
	tradeCounter += 1
	local trade: Trade = {
		id = string.sub(game.JobId, 1, 8) .. "-" .. tradeCounter .. "-" .. os.time(),
		a = a,
		b = b,
		offers = { [a] = { items = {}, cash = 0 }, [b] = { items = {}, cash = 0 } },
		confirmed = {},
		lockUntil = os.clock() + Friends.trade.lockSeconds,
		startedAt = os.clock(),
	}
	trades[a] = trade
	trades[b] = trade
	incoming[a] = nil
	incoming[b] = nil
	pushBoth(trade)
	log(a, 1, "started")
end

local function onRequest(player: Player, userId: any)
	local now = os.clock()
	if (lastRequest[player] or 0) + Friends.trade.requestCooldown > now then
		notice(player, { kind = "tradeCooldown" })
		return
	end
	lastRequest[player] = now
	if type(userId) ~= "number" then
		return
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target or target == player then
		notice(player, { kind = "tradeUnavailable" })
		return
	end
	local mine = blocker(player)
	if mine then
		notice(player, { kind = mine })
		return
	end
	local theirs = blocker(target)
	if theirs then
		notice(player, { kind = if theirs == "tradeBusy" then "tradeBusy" else "tradeUnavailable" })
		return
	end
	-- Региональные цены: меняться могут только игроки с одним уровнем цены (проверка ждёт Roblox)
	if not PriceLevels.canTrade(player, target) then
		notice(player, { kind = "tradeUnavailable" })
		return
	end
	-- Пока ждали Roblox, кто-то мог начать другой обмен или выйти: проверяем заново
	if not player.Parent or not target.Parent or blocker(player) or blocker(target) then
		notice(player, { kind = "tradeBusy" })
		return
	end
	local refusedAt = declined[player] and declined[player][target.UserId]
	if refusedAt and refusedAt + Friends.trade.declineCooldown > now then
		notice(player, { kind = "tradeCooldown" })
		return
	end
	-- Встречный запрос уже ждёт — сразу начинаем
	local back = incoming[player] and incoming[player][target]
	if back and back + Friends.trade.requestSeconds > now then
		startTrade(target, player)
		return
	end
	incoming[target] = incoming[target] or {}
	incoming[target][player] = now
	notice(target, { kind = "tradeRequest", name = player.DisplayName, userId = player.UserId })
	notice(player, { kind = "tradeSent", name = target.DisplayName })
	task.delay(Friends.trade.requestSeconds, function()
		local list = incoming[target]
		if list and list[player] == now then
			list[player] = nil
			if player.Parent then
				notice(player, { kind = "tradeExpired", name = target.DisplayName })
			end
		end
	end)
end

local function onRespond(player: Player, userId: any, accept: any)
	if type(userId) ~= "number" then
		return
	end
	local requester = Players:GetPlayerByUserId(userId)
	local list = incoming[player]
	local at = requester and list and list[requester]
	if not requester or not list or not at or at + Friends.trade.requestSeconds < os.clock() then
		notice(player, { kind = "tradeExpired" })
		return
	end
	list[requester] = nil
	if accept ~= true then
		declined[requester] = declined[requester] or {}
		declined[requester][player.UserId] = os.clock()
		notice(requester, { kind = "tradeDeclined", name = player.DisplayName })
		return
	end
	local reason = blocker(player) or blocker(requester)
	if reason then
		notice(player, { kind = reason })
		return
	end
	startTrade(requester, player)
end

-- Предложение от клиента -> проверенное (чужое и непонятное выкидываем)
local function cleanOffer(
	player: Player,
	profile: DataService.Profile,
	partnerProfile: DataService.Profile,
	partner: Player,
	items: any,
	cash: any
): Offer
	local result: Offer = { items = {}, cash = 0 }
	local seen: { [string]: boolean } = {}
	if type(items) == "table" then
		for i = 1, Friends.trade.maxItems do
			local raw = items[i]
			if type(raw) ~= "table" then
				break
			end
			local item: Item = { kind = raw.kind, id = raw.id }
			local key = tostring(item.kind) .. ":" .. tostring(item.id)
			if seen[key] or not Friends.tradeable(item.kind, item.id) or not owns(profile, item) then
				continue
			end
			seen[key] = true
			-- Такой у партнёра уже есть: второй ему не нужен, предупреждаем отдающего
			if owns(partnerProfile, item) then
				notice(
					player,
					{ kind = "tradeOwned", name = partner.DisplayName, itemKind = item.kind, item = item.id }
				)
				continue
			end
			table.insert(result.items, item)
		end
	end
	if Friends.trade.cashEnabled and type(cash) == "number" and cash == cash and cash > 0 then
		result.cash = math.clamp(math.floor(cash), 0, maxCashFor(profile, partner, partnerProfile))
	end
	return result
end

local function onOffer(player: Player, items: any, cash: any)
	local trade = trades[player]
	if not trade then
		return
	end
	local now = os.clock()
	if (lastOffer[player] or 0) + Friends.trade.offerCooldown > now then
		pushState(player) -- клиент мог уже перерисовать — вернём правду
		return
	end
	lastOffer[player] = now
	local partner = partnerOf(trade, player)
	local profile = DataService.get(player)
	local partnerProfile = DataService.get(partner)
	if not profile or not partnerProfile then
		return
	end
	trade.offers[player] = cleanOffer(player, profile, partnerProfile, partner, items, cash)
	trade.confirmed = {}
	trade.lockUntil = now + Friends.trade.lockSeconds
	pushBoth(trade)
end

local function isEmpty(trade: Trade): boolean
	for _, offer in trade.offers do
		if #offer.items > 0 or offer.cash > 0 then
			return false
		end
	end
	return true
end

-- Всё ещё в силе: оба на сервере, без долга, предметы у отдающих, у получателей таких нет
local function valid(trade: Trade): boolean
	if trades[trade.a] ~= trade or trades[trade.b] ~= trade then
		return false
	end
	for _, giver in { trade.a, trade.b } do
		local receiver = partnerOf(trade, giver)
		local gp = DataService.get(giver)
		local rp = DataService.get(receiver)
		if
			not giver.Parent
			or not gp
			or not rp
			or gp.cash < 0
			or DataService.isClosing(giver)
			or DataService.isClosing(receiver)
		then
			return false
		end
		local offer = trade.offers[giver]
		if offer.cash < 0 or offer.cash > maxCashFor(gp, receiver, rp) then
			return false
		end
		for _, item in offer.items do
			if not Friends.tradeable(item.kind, item.id) or not owns(gp, item) or owns(rp, item) then
				return false
			end
		end
	end
	return true
end

local function grant(player: Player, profile: DataService.Profile, item: Item)
	if item.kind == "skin" then
		SkinService.grantSkin(player, profile, item.id)
	elseif item.kind == "poster" then
		PosterService.grantPoster(player, profile, item.id)
	else
		MascotService.grantMascot(player, profile, item.id)
	end
end

local function revoke(player: Player, profile: DataService.Profile, item: Item)
	if item.kind == "skin" then
		SkinService.revokeSkin(player, profile, item.id)
	elseif item.kind == "poster" then
		PosterService.revokePoster(player, profile, item.id)
	else
		MascotService.revokeMascot(player, profile, item.id)
	end
end

local function execute(trade: Trade)
	-- Сервер закрывается или профиль уже пишется в последний раз: обмен не проводим
	if DataService.isClosing(trade.a) or DataService.isClosing(trade.b) then
		cancel(trade, nil)
		return
	end
	if not valid(trade) then
		-- Что-то поменялось (вещь ушла приставам, деньги потрачены): подтвердить заново
		trade.confirmed = {}
		trade.lockUntil = os.clock() + Friends.trade.lockSeconds
		notice(trade.a, { kind = "tradeFailed" })
		notice(trade.b, { kind = "tradeFailed" })
		pushBoth(trade)
		return
	end
	local a, b = trade.a, trade.b
	local pa = DataService.get(a) :: DataService.Profile
	local pb = DataService.get(b) :: DataService.Profile
	local offerA, offerB = trade.offers[a], trade.offers[b]
	-- Сначала забираем у обоих, потом выдаём: без yield между проверкой и записью
	for _, item in offerA.items do
		revoke(a, pa, item)
	end
	for _, item in offerB.items do
		revoke(b, pb, item)
	end
	for _, item in offerA.items do
		grant(b, pb, item)
	end
	for _, item in offerB.items do
		grant(a, pa, item)
	end
	-- Деньги — перевод между игроками, а не доход: мимо addCash/trySpend (аналитика экономики)
	pa.cash += offerB.cash - offerA.cash
	pb.cash += offerA.cash - offerB.cash
	-- Суточный потолок полученного (valid уже проверил остаток)
	cashLog(pa).received += offerB.cash
	cashLog(pb).received += offerA.cash
	-- Полученное в обмене — не заработок: иначе пересылка туда-обратно закрывает задания «заработай»
	local netA = offerB.cash - offerA.cash
	if netA > 0 then
		RewardService.noteNonEarned(a, netA)
	elseif netA < 0 then
		RewardService.noteNonEarned(b, -netA)
	end
	endTrade(trade)
	local readyAt = os.clock() + Friends.trade.afterTradeCooldown
	cooldownUntil[a] = readyAt
	cooldownUntil[b] = readyAt
	for _, player in { a, b } do
		DataService.replicate(player)
		pushState(player)
		notice(player, { kind = "tradeDone", name = partnerOf(trade, player).DisplayName })
	end
	log(a, #offerA.items + #offerB.items, "done")
	print(
		string.format(
			"[TradeService] trade %s done: %d -> %d (%d items, $%d), %d -> %d (%d items, $%d)",
			trade.id,
			a.UserId,
			b.UserId,
			#offerA.items,
			offerA.cash,
			b.UserId,
			a.UserId,
			#offerB.items,
			offerB.cash
		)
	)
	-- Сохраняем по очереди: сначала отдающий (у кого забрали больше предметов, при равенстве —
	-- больше денег), потом получатель. Получателя не пишем, пока отдающий не записан (повторы):
	-- иначе при сбое вещь окажется в DataStore у обоих. Сбой второй записи теряет вещь, но не дублирует
	local giveA = #offerA.items * 1e12 + offerA.cash
	local giveB = #offerB.items * 1e12 + offerB.cash
	local first, second = if giveB > giveA then b else a, if giveB > giveA then a else b
	task.spawn(function()
		local saved = false
		for attempt = 1, Friends.trade.saveRetries do
			if DataService.save(first) then
				saved = true
				break
			end
			-- Отдающий выходит: его профиль пишет closeProfile (со своими повторами). Ждём конца записи
			if not first.Parent or DataService.isClosing(first) then
				while DataService.get(first) ~= nil do
					task.wait(0.5)
				end
				saved = true
				break
			end
			if attempt < Friends.trade.saveRetries then
				task.wait(Friends.trade.saveRetryPause)
			end
		end
		if not saved then
			warn("[TradeService] trade", trade.id, "giver save failed", first.UserId, "- receiver skipped")
			return
		end
		if not DataService.save(second) and second.Parent then
			warn("[TradeService] trade", trade.id, "save failed for", second.UserId)
		end
	end)
end

local function onConfirm(player: Player)
	local trade = trades[player]
	if not trade then
		return
	end
	if os.clock() < trade.lockUntil then
		pushState(player)
		return
	end
	if isEmpty(trade) then
		notice(player, { kind = "tradeEmpty" })
		return
	end
	trade.confirmed[player] = true
	if trade.confirmed[trade.a] and trade.confirmed[trade.b] then
		execute(trade)
	else
		pushBoth(trade)
	end
end

local function onCancel(player: Player)
	local trade = trades[player]
	if trade then
		cancel(trade, player)
	end
end

local function onStateRequest(player: Player)
	local now = os.clock()
	if (lastStateRequest[player] or 0) + STATE_REQUEST_COOLDOWN > now then
		return
	end
	lastStateRequest[player] = now
	pushState(player)
end

-- Идёт ли у игрока обмен (для других систем)
function TradeService.isTrading(player: Player): boolean
	return trades[player] ~= nil
end

local function startNow()
	FriendRemotes.TradeRequest.OnServerEvent:Connect(onRequest)
	FriendRemotes.TradeRespond.OnServerEvent:Connect(onRespond)
	FriendRemotes.TradeOffer.OnServerEvent:Connect(onOffer)
	FriendRemotes.TradeConfirm.OnServerEvent:Connect(onConfirm)
	FriendRemotes.TradeCancel.OnServerEvent:Connect(onCancel)
	FriendRemotes.TradeStateRequest.OnServerEvent:Connect(onStateRequest)
	Players.PlayerRemoving:Connect(function(player)
		local trade = trades[player]
		if trade then
			cancel(trade, player)
		end
		incoming[player] = nil
		for _, list in incoming do
			list[player] = nil
		end
		lastRequest[player] = nil
		lastOffer[player] = nil
		lastStateRequest[player] = nil
		declined[player] = nil
		cooldownUntil[player] = nil
	end)
	-- Сервер закрывается: профили пишутся по очереди, обмен посередине раздвоил бы предмет
	game:BindToClose(function()
		local seen: { [Trade]: boolean } = {}
		for _, trade in trades do
			if not seen[trade] then
				seen[trade] = true
				cancel(trade, nil)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(TIMEOUT_CHECK)
			local seen: { [Trade]: boolean } = {}
			for _, trade in trades do
				if not seen[trade] then
					seen[trade] = true
					if os.clock() - trade.startedAt > Friends.trade.tradeSeconds then
						cancel(trade, nil)
					end
				end
			end
		end
	end)
end

-- Обновления по средам (Config/Features): до выхода системы «trade» сервис спит — remotes
-- заглушены, циклы и обработчики не запущены; вышла (в т. ч. пока сервер работает) — startNow()
function TradeService.start()
	FeatureReleaseService.mute("trade", {
		FriendRemotes.TradeRequest,
		FriendRemotes.TradeRespond,
		FriendRemotes.TradeOffer,
		FriendRemotes.TradeConfirm,
		FriendRemotes.TradeCancel,
		FriendRemotes.TradeStateRequest,
	})
	FeatureReleaseService.whenReleased("trade", "TradeService", startNow)
end

return TradeService
