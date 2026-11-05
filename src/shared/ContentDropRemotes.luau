--!strict
-- Remotes графика контента (ContentDropService, Config/ContentDrops), по образцу TitleRemotes.
-- Новая волна для окна «Что нового» — атрибут игрока ContentDropNew (номер волны, 0 — нет).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "ContentDropRemotes"

local NAMES = {
	"SeenDrop", -- клиент -> сервер: номер волны, окно «Что нового» закрыто
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

local ContentDropRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	ContentDropRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return ContentDropRemotes
