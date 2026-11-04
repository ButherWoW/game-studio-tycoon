--!strict
-- Remotes мини-аркады (Config/Arcade), в своей папке. Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "ArcadeRemotes"

local NAMES = {
	"ArcadeStart", -- клиент -> сервер: projectId
	-- сервер -> клиент: { projectId, token, kind, seed, duration, countdown }
	-- или { projectId, error = "expired" | "used" | "busy", minutes }
	"ArcadeSession",
	"ArcadeSubmit", -- клиент -> сервер: token, score
	"ArcadeResult", -- сервер -> клиент: { token, score, grade?, bonus }
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

local ArcadeRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	ArcadeRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return ArcadeRemotes
