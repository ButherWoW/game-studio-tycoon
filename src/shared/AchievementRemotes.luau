--!strict
-- Remotes достижений (AchievementService). Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"RequestAchievements", -- клиент -> сервер: прислать состояние (при старте и открытии окна)
	"AchievementState", -- сервер -> клиент: { done = { [id]: os.time }, stats = { [stat]: number } }
	"AchievementUnlocked", -- сервер -> клиент: { id } — тост; { backfill = N } — за прошлый прогресс
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("AchievementRemotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "AchievementRemotes"
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
	folder = ReplicatedStorage:WaitForChild("AchievementRemotes") :: Folder
end

local AchievementRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	AchievementRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return AchievementRemotes
