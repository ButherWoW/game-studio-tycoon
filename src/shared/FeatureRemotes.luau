--!strict
-- Remotes постепенного открытия систем (Config/Unlocks). Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "FeatureRemotes"

local NAMES = {
	-- клиент -> сервер: { id, ... } — игрок увидел тост «Открыто» этих систем
	-- (сервер проверяет условия Config/Unlocks и запоминает в profile.features.seen)
	"FeatureSeen",
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

local FeatureRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	FeatureRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return FeatureRemotes
