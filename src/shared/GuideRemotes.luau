--!strict
-- Remotes обучения по ходу игры (Config/Guides). Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "GuideRemotes"

local NAMES = {
	-- клиент -> сервер: id — игрок прочитал карточку обучения (нажал «Понятно»)
	-- (сервер запоминает в profile.guides.seen)
	"GuideSeen",
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

local GuideRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	GuideRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return GuideRemotes
