--!strict
-- Remotes титулов над головой (TitleService, Config/Titles), по образцу ResearchRemotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "TitleRemotes"

local NAMES = {
	"SelectTitle", -- клиент -> сервер: titleId или "" (снять)
	"RequestTitles", -- клиент -> сервер: прислать состояние
	"TitleState", -- сервер -> клиент: { owned = { [id]: true }, selected, new = { id }? }
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

local TitleRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	TitleRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return TitleRemotes
