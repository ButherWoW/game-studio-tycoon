--!strict
-- Обновления по средам (Config/Features) на сервере:
--   • whenReleased(id, fn) — сервисы невышедших систем откладывают свой start() сюда: циклы, NPC,
--     модели, баннеры и обработчики remotes включаются в момент выхода (проверка раз в
--     CHECK_SECONDS, без перезапуска сервера). Вышла — fn сразу;
--   • mute(remotes) — пока система не вышла, её RemoteEvent «глушится» пустым обработчиком: запросы
--     клиента не копятся в очереди Roblox и не выполнятся пачкой в момент выхода;
--   • окно «🆕 Новое обновление» (WhatsNewWindow): атрибуты игрока FeatureUpdateNew (номер
--     последнего вышедшего обновления в Features.updates, 0 — показывать нечего) и
--     FeatureUpdateSeen (что уже видел — окно перечисляет всё после него).
-- profile.featureUpdateSeen — номер последнего увиденного обновления. Новичок (ещё нет выпущенных
-- игр) и старое сохранение без поля получают текущий номер тихо, как в ContentDropService.
-- Хуки DevelopmentService невышедших систем отключает он сам (Features.serviceReleased).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Features = require(ReplicatedStorage.Shared.Config.Features)
local ContentDropRemotes = require(ReplicatedStorage.Shared.ContentDropRemotes)
local DataService = require(script.Parent.DataService)

local CHECK_SECONDS = 60
local SEEN_COOLDOWN = 1

type Waiting = { id: string, name: string, fn: () -> () }

local FeatureReleaseService = {}

local waiting: { Waiting } = {}
local lastSeen: { [Player]: number } = {}

local function run(entry: Waiting)
	local ok, err = pcall(entry.fn)
	if not ok then
		warn("[FeatureReleaseService] " .. entry.name .. " failed to start:", err)
	end
end

-- Запустить fn, когда система id выйдет (сразу, если уже вышла). name — для лога
function FeatureReleaseService.whenReleased(id: string, name: string, fn: () -> ())
	local entry = { id = id, name = name, fn = fn }
	if Features.isReleased(id) then
		run(entry)
		return
	end
	table.insert(waiting, entry)
end

-- Пока система id не вышла, запросы к remotes молча отбрасываются (после выхода — обычные
-- обработчики сервиса, этот остаётся пустым и ничего не делает)
function FeatureReleaseService.mute(id: string, remotes: { RemoteEvent })
	if Features.isReleased(id) then
		return
	end
	for _, remote in remotes do
		remote.OnServerEvent:Connect(function() end)
	end
end

-- Вышла ли система (для сервисов, которые сами проверяют на каждом шаге)
function FeatureReleaseService.isReleased(id: string): boolean
	return Features.isReleased(id)
end

-- Модели в парке, поставленные после старта сервера (щиты, Зал славы): StartParkService не
-- кладёт в них картриджи. Лениво: StartParkService стартует позже по алфавиту и сам соберёт
-- препятствия, если система вышла уже к старту сервера
function FeatureReleaseService.parkObstacles(names: { string })
	local park = workspace:FindFirstChild("StartPark")
	local module = script.Parent:FindFirstChild("StartParkService")
	if not park or not module or not module:IsA("ModuleScript") then
		return
	end
	local ok, service = pcall(require, module)
	local add = ok and type(service) == "table" and (service :: any).addObstacle
	if type(add) ~= "function" then
		return
	end
	for _, name in names do
		local model = park:FindFirstChild(name)
		if model then
			pcall(add, model)
		end
	end
end

local function seenOf(profile: DataService.Profile): number?
	local raw = (profile :: any).featureUpdateSeen
	if type(raw) ~= "number" or raw ~= raw then
		return nil
	end
	return math.floor(raw)
end

local function check(player: Player, profile: DataService.Profile)
	local current = Features.currentIndex()
	local seen = seenOf(profile)
	if seen == nil or profile.gamesReleased <= 0 then
		(profile :: any).featureUpdateSeen = current
		seen = current
	end
	player:SetAttribute("FeatureUpdateSeen", seen)
	player:SetAttribute("FeatureUpdateNew", if (seen :: number) < current then current else 0)
end

local function onSeen(player: Player, index: any)
	local now = os.clock()
	if (lastSeen[player] or 0) + SEEN_COOLDOWN > now then
		return
	end
	lastSeen[player] = now
	local profile = DataService.get(player)
	if not profile or type(index) ~= "number" or index ~= index then
		return
	end
	-- Не дальше вышедшего: клиент не может «увидеть» будущее обновление
	local seen = math.clamp(math.floor(index), 0, Features.currentIndex());
	(profile :: any).featureUpdateSeen = math.max(seenOf(profile) or 0, seen)
	check(player, profile)
end

local function tick()
	local i = 1
	while i <= #waiting do
		local entry = waiting[i]
		if Features.isReleased(entry.id) then
			table.remove(waiting, i)
			print("[FeatureReleaseService] released:", entry.id, entry.name)
			run(entry)
		else
			i += 1
		end
	end
	for _, player in Players:GetPlayers() do
		local profile = DataService.get(player)
		if profile then
			check(player, profile)
		end
	end
end

function FeatureReleaseService.start()
	DataService.onProfileLoaded(check)
	ContentDropRemotes.SeenUpdate.OnServerEvent:Connect(onSeen)
	Players.PlayerRemoving:Connect(function(player)
		lastSeen[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			local ok, err = pcall(tick)
			if not ok then
				warn("[FeatureReleaseService] tick failed:", err)
			end
		end
	end)
end

return FeatureReleaseService
