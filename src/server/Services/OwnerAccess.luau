--!strict
-- Кто владелец игры (сейф SafeService, админ-панель AdminService). Без start(): библиотека.
-- Владельцы: Config/Admin.ownerUserIds и Config/Safe.ownerUserIds (обе пустые в репозитории — UserId
-- задаются там, если нужен кто-то кроме создателя), создатель игры (game.CreatorId у игры
-- пользователя) или владелец группы-создателя (GroupService, один запрос на сервер).
-- Решает только сервер: атрибуты игрока (SafeAdmin, AdminPanel) — лишь подсказка клиенту, какие
-- кнопки рисовать; каждый remote заново зовёт OwnerAccess.isOwner.

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Admin = require(ReplicatedStorage.Shared.Config.Admin)
local Safe = require(ReplicatedStorage.Shared.Config.Safe)

local OwnerAccess = {}

local owners: { [number]: boolean } = {}
local resolved = false
local resolving = false
local callbacks: { (Player) -> () } = {}

local function addIds(list: { number })
	for _, id in list do
		if type(id) == "number" and id > 0 and id == math.floor(id) then
			owners[id] = true
		end
	end
end

local function notify(player: Player)
	for _, callback in callbacks do
		task.spawn(callback, player)
	end
end

-- Один раз на сервер: списки из Config сразу, владелец группы — запросом (уступает поток)
local function resolve()
	if resolved or resolving then
		return
	end
	resolving = true
	addIds(Admin.ownerUserIds)
	addIds(Safe.ownerUserIds)
	if game.CreatorType == Enum.CreatorType.User then
		if game.CreatorId > 0 then
			owners[game.CreatorId] = true
		end
	elseif game.CreatorId > 0 then
		local ok, info = pcall(function()
			return GroupService:GetGroupInfoAsync(game.CreatorId)
		end)
		local owner = ok and type(info) == "table" and (info :: any).Owner
		local ownerId = type(owner) == "table" and tonumber(owner.Id)
		if ownerId then
			owners[ownerId] = true
		elseif not ok then
			warn("[OwnerAccess] GetGroupInfoAsync failed:", info)
		end
	end
	resolved = true
	for _, player in Players:GetPlayers() do
		if owners[player.UserId] then
			notify(player)
		end
	end
end

-- Владелец ли игрок. До ответа GroupService владелец группы — ещё нет (кнопки появятся по onOwner)
function OwnerAccess.isOwner(player: Player): boolean
	return typeof(player) == "Instance" and player:IsA("Player") and owners[player.UserId] == true
end

function OwnerAccess.isOwnerId(userId: number): boolean
	return owners[userId] == true
end

-- callback(player) для каждого владельца на сервере: уже вошедших (когда список готов) и новых
function OwnerAccess.onOwner(callback: (Player) -> ())
	table.insert(callbacks, callback)
	if resolved then
		for _, player in Players:GetPlayers() do
			if owners[player.UserId] then
				task.spawn(callback, player)
			end
		end
	end
	if #callbacks == 1 then
		Players.PlayerAdded:Connect(function(player)
			if resolved and owners[player.UserId] then
				notify(player)
			end
		end)
	end
	task.spawn(resolve)
end

return OwnerAccess
