--!strict
-- Remotes платных эффектов и эффектов исследований (5.9, 3.8), по образцу Remotes.luau, в своей папке.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "PaidRemotes"

local NAMES = {
	"InstantFinish", -- клиент -> сервер: projectId — потратить заряд «Мгновенно закончить»
	"SetAutoRelease", -- клиент -> сервер: boolean — тумблер «Авто-релиз»
	"DevStateRequest", -- клиент -> сервер: прислать DevState
	-- сервер -> клиент: { slots, busy, projects = { { id, name, laptop } }, instantFinish,
	-- autoReleaseOwned, autoReleaseOn, reviewPreview, royaltyPerMinute }
	"DevState",
	"ReviewPreviewRequest", -- клиент -> сервер: { genreId, topicId, focus }
	"ReviewPreview", -- сервер -> клиент: { genreId, topicId, min, max }
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

local PaidRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	PaidRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return PaidRemotes
