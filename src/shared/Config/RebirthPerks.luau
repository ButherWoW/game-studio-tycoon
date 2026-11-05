--!strict
-- Дерево перков Rebirth (роадмап 7.19): за каждый Rebirth — 1 «звезда студии».
-- Звёзд доступно = profile.rebirths − потрачено (сумма цен купленных уровней), поэтому старые
-- профили получают звёзды задним числом без миграции. Перки постоянные: Rebirth их не сбрасывает.
-- Данные — profile.rebirthPerks = { levels = { [branchId]: number }, respecUsed = boolean }
-- (RebirthPerkService). Эффекты считаются только по профилю (RebirthPerks.forProfile), поэтому
-- хуки в сервисах — одна строка, без зависимости от RebirthPerkService.
-- Тексты: rperk_<branch>, rperk_eff_<эффект> в Texts и Locales.
--
-- Баланс (почему такие числа):
--   * Цена уровней 1, 1, 2, 3, 4 = 11 звёзд на ветку, 55 на всё дерево. Rebirth стоит
--     baseCost × (n + 1) (Config/Rebirth), первые звёзды приходят каждые ~20–30 ч игры,
--     поздние — реже, поэтому весь набор — цель на десятки Rebirth, а 1–2 уровня — сразу.
--   * Скорость: −3% времени за уровень (до −15%). Множитель входит в durationFactor
--     DevelopmentService рядом с исследованиями и перками сотрудников и упирается в их же пол
--     0.25, а действует только на часть сверх Economy.devFloorSeconds — «короче нуля» не выйдет.
--   * Экономия: −4% аренды и зарплат за уровень (до −20%). Меньше, чем дают гранты событий;
--     расходы остаются заметными, забастовки и приставы работают как раньше.
--   * Стартовый капитал: денег после Rebirth вместо Config/Rebirth.cashAfter. Максимум $300k —
--     это гараж + переезд в офис, но ~1% цены второго Rebirth ($23M), этажи всё равно надо
--     зарабатывать играми (Stages.gamesRequired).
--   * Пассив: офлайн-доход +10% за уровень (до +50% к Offline.rate 0.3 → 0.45 — всё ещё меньше
--     половины обычного дохода) и +1 место на полке хитов на 3-м и 5-м уровне. Полка не больше
--     HitCartridges.maxSlots (10 мест на модели): на небоскрёбе бонус уже упирается в потолок.
--   * Лаборатория: исследования дешевле на 5% за уровень (до −25%), цена не меньше 1 ОИ.
-- tools/balance_sim.py --rebirth2 считает второй забег с 1 звездой (перебор веток): 1 уровень
-- даёт 0–2% времени до 2-го Rebirth, лучший — «Пассив» (docs/BALANCE.md, релизный проход 05.11).

export type BranchId = "speed" | "thrift" | "capital" | "passive" | "lab"

-- Сумма эффектов купленных уровней (нейтральные значения — без перков)
export type Effects = {
	devTime: number, -- доля сокращения времени разработки: 0.15 = на 15% быстрее
	expenses: number, -- доля скидки на аренду и зарплаты: 0.2 = −20%
	startCash: number, -- денег после Rebirth (0 — как в Config/Rebirth.cashAfter)
	offline: number, -- доля прибавки к офлайн-доходу: 0.5 = +50%
	hitSlots: number, -- дополнительных мест на полке хитов
	researchDiscount: number, -- доля скидки на исследования: 0.25 = −25%
}

export type Branch = {
	id: BranchId,
	icon: string,
	-- Цена каждого уровня в звёздах (длина = число уровней)
	costs: { number },
	-- Эффект ПОСЛЕ покупки уровня i (накопительный, не прибавка): levels[i]
	levels: { { [string]: number } },
}

local RebirthPerks = {}

-- Звёзд за один Rebirth
RebirthPerks.starsPerRebirth = 1
-- Бесплатный сброс дерева (звёзды возвращаются) — один раз за всё время
RebirthPerks.freeRespecs = 1

local COSTS = { 1, 1, 2, 3, 4 }

local branches: { Branch } = {
	{
		id = "speed",
		icon = "⚡",
		costs = COSTS,
		levels = {
			{ devTime = 0.03 },
			{ devTime = 0.06 },
			{ devTime = 0.09 },
			{ devTime = 0.12 },
			{ devTime = 0.15 },
		},
	},
	{
		id = "thrift",
		icon = "💸",
		costs = COSTS,
		levels = {
			{ expenses = 0.04 },
			{ expenses = 0.08 },
			{ expenses = 0.12 },
			{ expenses = 0.16 },
			{ expenses = 0.2 },
		},
	},
	{
		id = "capital",
		icon = "💰",
		costs = COSTS,
		levels = {
			{ startCash = 2_500 },
			{ startCash = 10_000 },
			{ startCash = 40_000 },
			{ startCash = 120_000 },
			{ startCash = 300_000 },
		},
	},
	{
		id = "passive",
		icon = "🌙",
		costs = COSTS,
		levels = {
			{ offline = 0.1 },
			{ offline = 0.2 },
			{ offline = 0.3, hitSlots = 1 },
			{ offline = 0.4, hitSlots = 1 },
			{ offline = 0.5, hitSlots = 2 },
		},
	},
	{
		id = "lab",
		icon = "🔬",
		costs = COSTS,
		levels = {
			{ researchDiscount = 0.05 },
			{ researchDiscount = 0.1 },
			{ researchDiscount = 0.15 },
			{ researchDiscount = 0.2 },
			{ researchDiscount = 0.25 },
		},
	},
}
RebirthPerks.branches = branches

-- Порядок эффектов в описаниях (ключи rperk_eff_<id>)
RebirthPerks.effectOrder = { "devTime", "expenses", "startCash", "offline", "hitSlots", "researchDiscount" }

local byId: { [string]: Branch } = {}
for _, branch in branches do
	byId[branch.id] = branch
end
RebirthPerks.byId = byId

local function num(value: any): number
	local n = tonumber(value)
	return if n and n == n and n > -math.huge and n < math.huge then n else 0
end

-- Уровень ветки из сохранённых данных: целое 0..число уровней (мусор — 0)
function RebirthPerks.levelOf(levels: any, branchId: string): number
	local branch = byId[branchId]
	if not branch or type(levels) ~= "table" then
		return 0
	end
	return math.clamp(math.floor(num(levels[branchId])), 0, #branch.costs)
end

-- Сколько звёзд стоит купленное (неизвестные ветки — бесплатно: их нет в конфиге)
function RebirthPerks.spent(levels: any): number
	local total = 0
	for _, branch in branches do
		for i = 1, RebirthPerks.levelOf(levels, branch.id) do
			total += branch.costs[i]
		end
	end
	return total
end

-- Свободные звёзды: никогда не меньше 0 (если цены в конфиге поднимут — купленное остаётся)
function RebirthPerks.available(rebirths: any, levels: any): number
	local earned = math.max(math.floor(num(rebirths)), 0) * RebirthPerks.starsPerRebirth
	return math.max(earned - RebirthPerks.spent(levels), 0)
end

-- Цена следующего уровня ветки (nil — ветка куплена целиком или её нет)
function RebirthPerks.nextCost(levels: any, branchId: string): number?
	local branch = byId[branchId]
	if not branch then
		return nil
	end
	return branch.costs[RebirthPerks.levelOf(levels, branchId) + 1]
end

local function neutral(): Effects
	return { devTime = 0, expenses = 0, startCash = 0, offline = 0, hitSlots = 0, researchDiscount = 0 }
end

-- Эффекты одного уровня ветки (0 — нейтральные)
function RebirthPerks.levelEffects(branchId: string, level: number): Effects
	local result = neutral()
	local branch = byId[branchId]
	local entry = branch and branch.levels[level]
	if entry then
		for key, value in entry do
			(result :: any)[key] = value
		end
	end
	return result
end

-- Сумма эффектов по уровням веток
function RebirthPerks.effects(levels: any): Effects
	local result = neutral()
	for _, branch in branches do
		local entry = branch.levels[RebirthPerks.levelOf(levels, branch.id)]
		if entry then
			for key, value in entry do
				local r = result :: any
				r[key] = (r[key] or 0) + value
			end
		end
	end
	-- Страховка от правок конфига: множители остаются в разумных рамках
	result.devTime = math.clamp(result.devTime, 0, 0.5)
	result.expenses = math.clamp(result.expenses, 0, 0.5)
	result.offline = math.clamp(result.offline, 0, 1)
	result.researchDiscount = math.clamp(result.researchDiscount, 0, 0.5)
	result.hitSlots = math.max(math.floor(result.hitSlots), 0)
	result.startCash = math.max(result.startCash, 0)
	return result
end

-- Эффекты по профилю (profile.rebirthPerks.levels); без данных — нейтральные
function RebirthPerks.forProfile(profile: any): Effects
	local data = if type(profile) == "table" then profile.rebirthPerks else nil
	return RebirthPerks.effects(if type(data) == "table" then data.levels else nil)
end

-- Цена исследования со скидкой «Лаборатории»: округление вверх, не меньше 1 ОИ
function RebirthPerks.researchCost(baseCost: number, discount: number): number
	if baseCost <= 0 then
		return baseCost
	end
	return math.max(math.ceil(baseCost * (1 - math.clamp(discount, 0, 0.5)) - 1e-6), 1)
end

return RebirthPerks
