--!strict
-- График контента (Config/ContentDrops): окно «🆕 Что нового», когда игрок впервые заходит после
-- новой волны. Сам выход предметов проверяют сервисы магазинов, UnlockRules, DailyEvents и др. —
-- здесь только «видел ли игрок последнюю волну».
-- profile.contentDropSeen — номер последней увиденной волны. Новичок (ещё нет выпущенных игр) и
-- старое сохранение без поля получают текущий номер тихо: окно — только про то, что вышло потом.
-- Клиенту — атрибут игрока ContentDropNew (номер волны, 0 — показывать нечего).
-- Волна может выйти, пока игрок в игре (полночь UTC): проверяем раз в CHECK_SECONDS.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ContentDrops = require(ReplicatedStorage.Shared.Config.ContentDrops)
local ContentDropRemotes = require(ReplicatedStorage.Shared.ContentDropRemotes)
local DataService = require(script.Parent.DataService)

local CHECK_SECONDS = 60
local SEEN_COOLDOWN = 1

local ContentDropService = {}
local lastSeen: { [Player]: number } = {}

local function check(player: Player, profile: DataService.Profile)
	local current = ContentDrops.currentIndex(os.time())
	local seen = profile.contentDropSeen
	if type(seen) ~= "number" or seen ~= seen or profile.gamesReleased <= 0 then
		profile.contentDropSeen = current
		player:SetAttribute("ContentDropNew", 0)
		return
	end
	player:SetAttribute("ContentDropNew", if seen < current then current else 0)
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
	-- Не дальше вышедшей волны: клиент не может «увидеть» будущую
	local current = ContentDrops.currentIndex(os.time())
	local seen = math.clamp(math.floor(index), 1, current)
	profile.contentDropSeen = math.max(tonumber(profile.contentDropSeen) or 0, seen)
	check(player, profile)
end

function ContentDropService.start()
	DataService.onProfileLoaded(check)
	ContentDropRemotes.SeenDrop.OnServerEvent:Connect(onSeen)
	Players.PlayerRemoving:Connect(function(player)
		lastSeen[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile then
					check(player, profile)
				end
			end
		end
	end)
end

return ContentDropService
