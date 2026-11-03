--!strict
-- Remotes модных жанров, Rebirth и офлайн-дохода. Сервер создаёт, клиент ждёт.
-- Текущий тренд — атрибуты ReplicatedStorage (TrendGenre, TrendTopic, TrendEndsAt):
-- они реплицируются сами, и клиент, зашедший позже, сразу видит тренд.
-- Офлайн-доход к выдаче — атрибут игрока OfflinePending.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "RetentionRemotes"

local NAMES = {
	"RequestRebirth", -- клиент -> сервер: без аргументов
	"RebirthResult", -- сервер -> клиент: { ok: boolean, reason: string? }
	"ClaimOffline", -- клиент -> сервер: без аргументов
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

local RetentionRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	RetentionRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return RetentionRemotes
