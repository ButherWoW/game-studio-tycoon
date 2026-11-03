--!strict
-- Remotes исследований (шаг 3.4), по образцу Remotes.luau, но в своей папке.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "ResearchRemotes"

local NAMES = {
	"BuyResearch", -- клиент -> сервер: nodeId
	"RequestResearch", -- клиент -> сервер: прислать текущее состояние
	"ResearchChanged", -- сервер -> клиент: { points, owned }
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

local ResearchRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	ResearchRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return ResearchRemotes
