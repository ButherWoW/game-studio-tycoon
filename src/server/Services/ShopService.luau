--!strict
-- Магазин: владение геймпассами и эффекты разовых покупок (Config/GamePasses, Config/Products).
-- Квитанции принимает MonetizationService.ProcessReceipt и зовёт сюда grantProduct —
-- эффект попадает в профиль, а MonetizationService сохраняет его ДО PurchaseGranted.
--
-- Для других сервисов:
--   ShopService.getModifiers(player) -> { cashMultiplier, devSpeed, autoRelease, extraSlot }
--   ShopService.consumeCharge(player, "instantFinish" | "patch") -> boolean (списать заряд)
--   ShopService.ownsPass(player, passId) -> boolean (VIP-офис, легендарный сотрудник)

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ShopRemotes = require(Shared.ShopRemotes)
local Formulas = require(Shared.Formulas)
local GamePasses = require(Shared.Config.GamePasses)
local Products = require(Shared.Config.Products)
local DataService = require(script.Parent.DataService)

export type Modifiers = {
	cashMultiplier: number, -- множитель дохода релиза (×2 деньги)
	devSpeed: number, -- множитель скорости разработки (быстрая разработка, кофе)
	autoRelease: boolean,
	extraSlot: boolean,
}

export type ChargeKind = "instantFinish" | "patch"

local STATE_REQUEST_COOLDOWN = 1

local ShopService = {}
local owned: { [Player]: { [string]: boolean } } = {}
local lastRequest: { [Player]: number } = {}

local function pushState(player: Player)
	local profile = DataService.get(player)
	ShopRemotes.ShopState:FireClient(player, {
		passes = owned[player] or {},
		boosts = if profile then profile.boosts else nil,
		-- Для подписи «сейчас ≈ $…» у пакетов дохода; считает сервер
		incomePerMinute = if profile then ShopService.incomePerMinute(player, profile) else nil,
	})
end

function ShopService.ownsPass(player: Player, passId: GamePasses.PassId): boolean
	local passes = owned[player]
	return passes ~= nil and passes[passId] == true
end

function ShopService.getModifiers(player: Player): Modifiers
	local effects = GamePasses.effects
	local speed = 1
	if ShopService.ownsPass(player, "fastDev") then
		speed /= effects.fastDevTimeFactor
	end
	local profile = DataService.get(player)
	if profile and profile.boosts.coffeeUntil > os.time() then
		speed *= Products.effects.coffeeSpeed
	end
	return {
		cashMultiplier = if ShopService.ownsPass(player, "doubleCash")
			then effects.doubleCashMultiplier
			else 1,
		devSpeed = speed,
		autoRelease = ShopService.ownsPass(player, "autoRelease"),
		extraSlot = ShopService.ownsPass(player, "extraSlot"),
	}
end

-- Списать один заряд «мгновенно закончить» / «патч». false — зарядов нет
function ShopService.consumeCharge(player: Player, kind: ChargeKind): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	local boosts = profile.boosts
	if kind == "instantFinish" and boosts.instantFinish > 0 then
		boosts.instantFinish -= 1
	elseif kind == "patch" and boosts.patch > 0 then
		boosts.patch -= 1
	else
		return false
	end
	pushState(player)
	return true
end

-- Вернуть заряд, если действие сорвалось после списания (например, релиз упал с ошибкой)
function ShopService.refundCharge(player: Player, kind: ChargeKind)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if kind == "instantFinish" then
		profile.boosts.instantFinish += 1
	elseif kind == "patch" then
		profile.boosts.patch += 1
	end
	pushState(player)
end

-- Сколько $ студия зарабатывает за минуту (для пакетов «N минут дохода»)
function ShopService.incomePerMinute(player: Player, profile: DataService.Profile): number
	local income = Products.income
	local score = math.max(profile.bestScore, income.minScore)
	-- Множитель rebirth — как в DevelopmentService.release
	local rebirthMultiplier = 1 + 0.5 * profile.rebirths
	local perRelease = Formulas.revenue(score, profile.studioLevel, 0, rebirthMultiplier)
		* ShopService.getModifiers(player).cashMultiplier
	return math.max(math.floor(perRelease * income.releasesPerMinute), income.minPerMinute)
end

function ShopService.findProduct(productId: number): Products.Product?
	if productId == 0 then
		return nil
	end
	for _, product in Products.list do
		if product.productId == productId then
			return product
		end
	end
	return nil
end

-- Применить купленный продукт к профилю (без сохранения — его делает MonetizationService).
-- false — такого продукта нет
function ShopService.grantProduct(player: Player, profile: DataService.Profile, productId: number): boolean
	local product = ShopService.findProduct(productId)
	if not product then
		return false
	end
	local boosts = profile.boosts
	if product.kind == "instantFinish" then
		boosts.instantFinish += 1
	elseif product.kind == "patch" then
		boosts.patch += 1
	elseif product.kind == "coffee" then
		-- Кофе продлевает: новые 10 минут считаются от конца текущих
		boosts.coffeeUntil = math.max(boosts.coffeeUntil, os.time()) + Products.effects.coffeeSeconds
	elseif product.kind == "incomePack" then
		local amount = ShopService.incomePerMinute(player, profile) * (product.incomeMinutes or 0)
		DataService.addCash(player, amount);
		(require(script.Parent.RewardService) :: any).noteNonEarned(player, amount)
	end
	DataService.replicate(player)
	pushState(player)
	return true
end

local function findPass(gamePassId: number): GamePasses.GamePass?
	if gamePassId == 0 then
		return nil
	end
	for _, pass in GamePasses.list do
		if pass.gamePassId == gamePassId then
			return pass
		end
	end
	return nil
end

-- Проверяем все геймпассы параллельно; ошибка API = «не куплен», до следующего захода
local function loadPasses(player: Player)
	local passes: { [string]: boolean } = {}
	owned[player] = passes
	local pending = 0
	for _, pass in GamePasses.list do
		if pass.gamePassId == 0 then
			continue
		end
		pending += 1
		task.spawn(function()
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.gamePassId)
			end)
			if ok and result == true then
				passes[pass.id] = true
			elseif not ok then
				warn("[ShopService] UserOwnsGamePassAsync failed:", pass.id, result)
			end
			pending -= 1
		end)
	end
	while pending > 0 and player.Parent do
		task.wait(0.1)
	end
	if player.Parent and owned[player] == passes then
		pushState(player)
	end
end

-- Событие покупки можно подделать и заспамить: перепроверка у Roblox не чаще раза в 2 с на игрока
local PASS_EVENT_COOLDOWN = 2
local lastPassEvent: { [Player]: number } = {}

local function onPassPurchaseFinished(player: Player, gamePassId: number, wasPurchased: boolean)
	if not wasPurchased then
		return
	end
	local now = os.clock()
	if (lastPassEvent[player] or 0) + PASS_EVENT_COOLDOWN > now then
		return
	end
	lastPassEvent[player] = now
	local pass = findPass(gamePassId)
	local passes = owned[player]
	if not pass or not passes then
		return
	end
	-- Событие покупки не доказывает владение: перепроверяем у Roblox
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
	end)
	if ok and owns and owned[player] == passes then
		passes[pass.id] = true
		pushState(player)
	end
end

local function onStateRequest(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + STATE_REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now
	pushState(player)
end

function ShopService.start()
	Players.PlayerAdded:Connect(loadPasses)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPasses, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		lastRequest[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchaseFinished)
	ShopRemotes.ShopStateRequest.OnServerEvent:Connect(onStateRequest)
end

return ShopService
