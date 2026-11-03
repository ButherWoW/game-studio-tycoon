--!strict
-- Все RemoteEvent/RemoteFunction в одном месте. Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"StartDevelopment", -- клиент -> сервер: { genreId, topicId, name, focus }
	"DevelopmentProgress", -- сервер -> клиент: { progress 0..1, points }
	"GameReleased", -- сервер -> клиент: { name, score, revenue }
	"BuyUpgrade", -- клиент -> сервер: upgradeId
	"BuyAdCampaignWithCash", -- клиент -> сервер: campaignId
	"DataChanged", -- сервер -> клиент: снимок публичных данных игрока
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
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
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local Remotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	Remotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
