--!strict
-- RemoteEvent туториала (по образцу Remotes.luau). Сервер создаёт, клиент ждёт.
-- Активен ли туториал, сервер сообщает атрибутом игрока TutorialActive.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"TutorialFinish", -- клиент -> сервер: completed (true — прошёл до конца, false — пропустил)
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

local TutorialRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	TutorialRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return TutorialRemotes
