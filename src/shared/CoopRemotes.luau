--!strict
-- Remotes совместной разработки и холдингов (CoopService, HoldingService / CoopController,
-- HoldingPanel), в своей папке. Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "CoopRemotes"

local NAMES = {
	-- ===== Совместная разработка =====
	"CoopInvite", -- клиент -> сервер: userId, projectId — позвать в свою текущую игру
	"CoopInvited", -- сервер -> гостю: { inviteId, name, game, seconds } — тост «Принять / Отказаться»
	"CoopReply", -- клиент -> сервер: inviteId, accept (boolean)
	"CoopLeave", -- клиент -> сервер: без аргументов — выйти из совместной игры (гость или хозяин)
	-- сервер -> клиент: nil или { role = "host"|"guest", partner, game, projectId, progress, helping }
	"CoopState",
	-- сервер -> клиент: тост { kind, name?, money?, reason? }
	"CoopNotice",
	-- ===== Холдинги =====
	"HoldingRequest", -- клиент -> сервер: без аргументов — прислать состояние и топ
	"HoldingState", -- сервер -> клиент: { holding?, canCreate, cost, minLevel, board, weekLeft }
	"HoldingCreate", -- клиент -> сервер: name
	"HoldingInvite", -- клиент -> сервер: userId — позвать игрока с сервера в свой холдинг
	"HoldingInvited", -- сервер -> клиенту: { inviteId, name, holding, seconds }
	"HoldingReply", -- клиент -> сервер: inviteId, accept (boolean)
	"HoldingLeave", -- клиент -> сервер: без аргументов
	"HoldingKick", -- клиент -> сервер: userId — владелец убирает участника
	"HoldingNotice", -- сервер -> клиент: тост { kind, name?, money?, reason? }
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local CoopRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	CoopRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return CoopRemotes
