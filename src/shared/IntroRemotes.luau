--!strict
-- Remotes вступления для новичка (4 экрана при первом входе, IntroController). Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "IntroRemotes"

local NAMES = {
	-- клиент -> сервер: (без данных) игрок дошёл до конца вступления или нажал «Пропустить»
	-- (сервер запоминает profile.introSeen и снимает атрибут игрока IntroActive)
	"IntroSeen",
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

local IntroRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	IntroRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return IntroRemotes
