--!strict
-- Rebirth (шаг 4.4): с этапа «офис» за Config/Rebirth.cost(rebirths) игрок начинает заново.
-- Сбрасываем деньги, апгрейды, открытые жанры/темы и runBestScore (по нему считаются награды
-- «N минут дохода»); сохраняем rebirths (+1), bestScore, gamesReleased. Фанаты студии —
-- остаётся Config/Fans.rebirthKeep (FansService.onRebirth).
-- Множитель дохода (1 + 0.5 × rebirths) применяет DevelopmentService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local Research = require(ReplicatedStorage.Shared.Config.Research)
local Rebirth = require(ReplicatedStorage.Shared.Config.Rebirth)
local RebirthPerks = require(ReplicatedStorage.Shared.Config.RebirthPerks)
local RetentionRemotes = require(ReplicatedStorage.Shared.RetentionRemotes)
local DataService = require(script.Parent.DataService)
local FansService = require(script.Parent.FansService)
local PlotService = require(script.Parent.PlotService) :: any

local REQUEST_COOLDOWN = 2 -- секунд между запросами одного игрока

local RebirthService = {}
local lastRequest: { [Player]: number } = {}

-- Стартовые жанры/темы — бесплатные (unlockCost = 0), как в defaultProfile
local function freeSet(map: { [string]: any }): { [string]: boolean }
	local result = {}
	for id, item in map do
		-- Сезонные темы (Хэллоуин, Новый год) открывает только HolidayService во время ивента
		if item.unlockCost <= 0 and not item.seasonal then
			result[id] = true
		end
	end
	return result
end

-- Причина, почему нельзя (nil — можно)
function RebirthService.check(profile: DataService.Profile): string?
	if not profile.upgrades[Rebirth.requiredUpgrade] then
		return "no_office"
	end
	if (tonumber(profile.studioLevel) or 1) < Rebirth.requiredStudioLevel then
		return "no_floor3"
	end
	-- Акции других студий — деньги вне баланса: проданные после Rebirth обошли бы сброс денег.
	-- Сначала продать всё (окно биржи), потом Rebirth
	local stocks = (profile :: any).stocks
	if type(stocks) == "table" and type(stocks.holdings) == "table" and next(stocks.holdings) ~= nil then
		return "has_stocks"
	end
	-- Кредит банка гасится вместе с ребёрзом: денег нужно на ребёрз + долг
	local debt = math.max(math.floor(tonumber((profile :: any).loanDebt) or 0), 0)
	if profile.cash < Rebirth.cost(profile.rebirths) + debt then
		return "no_money"
	end
	return nil
end

-- Пересобрать участок после сброса апгрейдов.
-- Нужна PlotService.rebuild(player): убрать модели и кнопки участка, поставить купленное,
-- создать кнопки заново. Пока её нет — только предупреждение (участок обновится при перезаходе).
local function rebuildPlot(player: Player)
	if type(PlotService.rebuild) == "function" then
		PlotService.rebuild(player)
	else
		warn(
			"[RebirthService] PlotService.rebuild не найден: участок пересоберётся при перезаходе"
		)
	end
end

local function onRequestRebirth(player: Player)
	local now = os.clock()
	if (lastRequest[player] or 0) + REQUEST_COOLDOWN > now then
		return
	end
	lastRequest[player] = now

	local profile = DataService.get(player)
	if not profile then
		return
	end
	local reason = RebirthService.check(profile)
	if reason then
		RetentionRemotes.RebirthResult:FireClient(player, { ok = false, reason = reason })
		return
	end

	-- Всё синхронно, без yield: между проверкой и сбросом никто не вклинится
	profile.rebirths += 1
	-- Перк «Стартовый капитал» (Config/RebirthPerks) заменяет cashAfter, если больше
	profile.cash = math.max(Rebirth.cashAfter, RebirthPerks.forProfile(profile).startCash)
	profile.upgrades = {}
	-- Набежавшая зарплата прошлой команды (ExpensesService) после Rebirth не переносится:
	-- и в профиле, и в памяти сервиса (иначе её списали бы на ближайшей выплате)
	local stored: any = profile
	stored.payday = nil
	for _, name in { "ExpensesService", "TaxService" } do
		local module = script.Parent:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			(require(module) :: any).reset(player)
		end
	end
	profile.unlockedGenres = freeSet(Genres)
	profile.unlockedTopics = freeSet(Topics)
	-- Награды «N минут дохода» — по новой студии, а не по рекорду до Rebirth (отчёт #2)
	profile.runBestScore = 0
	-- Жанры, открытые исследованиями, остаются: исследования Rebirth не сбрасывает
	local research = (profile :: any).research
	if type(research) == "table" and type(research.owned) == "table" then
		for _, node in Research.list do
			if research.owned[node.id] and node.effect.unlockGenre then
				profile.unlockedGenres[node.effect.unlockGenre] = true
			end
		end
	end
	-- Несобранный офлайн-доход и недоделанная игра сгорают вместе со студией
	-- (иначе их забирали бы после сброса, уже с новым множителем Rebirth)
	local data = profile :: any
	data.offlinePending = 0
	-- Роялти «Издательства» от игр до Rebirth сгорают вместе со студией
	if type(data.perks) == "table" then
		data.perks.royalties = {}
	end
	player:SetAttribute("OfflinePending", 0)
	local loanModule = script.Parent:FindFirstChild("LoanService")
	if loanModule and loanModule:IsA("ModuleScript") then
		(require(loanModule) :: any).clear(player, profile)
	end
	local devModule = script.Parent:FindFirstChild("DevelopmentService")
	if devModule and devModule:IsA("ModuleScript") then
		(require(devModule) :: any).cancel(player)
	end
	-- Открытие жанра/темы за $ в лаборатории сгорает (узел дерева исследований идёт дальше)
	local researchModule = script.Parent:FindFirstChild("ResearchService")
	if researchModule and researchModule:IsA("ModuleScript") then
		(require(researchModule) :: any).onRebirth(player)
	end
	-- Этап сбрасываем здесь: PlotService.rebuild делает это только при наличии участка,
	-- а игрок в очереди на участок иначе сохранял бы офис/небоскрёб после Rebirth
	profile.studioLevel = 1
	-- Фанаты студии: остаётся часть (Config/Fans.rebirthKeep), бонус к продажам начинается не с нуля
	FansService.onRebirth(player)
	-- Стройка этажа (Config/Construction) сгорает вместе со студией. Без возврата денег: Rebirth и так
	-- обнуляет деньги, возврат стал бы лишь цифрой перед сбросом. PlotService.rebuild снимает её сам,
	-- здесь — для игрока без участка (в очереди)
	profile.construction = nil
	DataService.replicate(player)

	rebuildPlot(player)
	-- Задания «Заработай N минут дохода» — под новый доход (после rebuild: там studioLevel = 1)
	local questModule = script.Parent:FindFirstChild("QuestService")
	if questModule and questModule:IsA("ModuleScript") then
		(require(questModule) :: any).onRebirth(player)
	end
	RetentionRemotes.RebirthResult:FireClient(player, { ok = true, rebirths = profile.rebirths })
	-- Новая звезда студии и титулы за число Rebirth
	for _, name in { "RebirthPerkService", "TitleService" } do
		local module = script.Parent:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local service = require(module) :: any
			pcall(if name == "TitleService" then service.refresh else service.sync, player, true)
		end
	end

	-- Возвращаем персонажа на точку появления — к пустому гаражу
	task.spawn(function()
		if player.Parent then
			player:LoadCharacter()
		end
	end)
	-- Сразу сохраняем: ребёрз — крупное событие, не ждём автосейва
	task.spawn(DataService.save, player)
end

function RebirthService.start()
	RetentionRemotes.RequestRebirth.OnServerEvent:Connect(onRequestRebirth)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return RebirthService
