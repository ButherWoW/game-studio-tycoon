--!strict
-- Remotes игровой выставки. Сервер создаёт, клиент ждёт.
-- Текущее состояние — атрибуты ReplicatedStorage (ExpoEndsAt, ExpoLeaderPlayer,
-- ExpoLeaderGame, ExpoLeaderScore): реплицируются сами, новый игрок сразу видит лидера.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "ExpoRemotes"

local NAMES = {
	"ExpoResult", -- сервер -> все клиенты: { winner: string?, game: string?, score: number?, prize: number }
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

local ExpoRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	ExpoRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return ExpoRemotes
