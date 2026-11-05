--!strict
-- Remotes дерева перков Rebirth (RebirthPerkService, Config/RebirthPerks), по образцу ResearchRemotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "RebirthPerkRemotes"

local NAMES = {
	"BuyRebirthPerk", -- клиент -> сервер: branchId
	"RespecRebirthPerks", -- клиент -> сервер: бесплатный сброс дерева
	"RequestRebirthPerks", -- клиент -> сервер: прислать состояние
	"RebirthPerkState", -- сервер -> клиент: { stars, earned, levels, respecLeft }
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

local RebirthPerkRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	RebirthPerkRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return RebirthPerkRemotes
