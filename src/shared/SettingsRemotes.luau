--!strict
-- Remote'ы настроек игрока (Config/Settings, SettingsService). Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "SettingsRemotes"

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	if not folder:FindFirstChild("SetSetting") then
		local remote = Instance.new("RemoteEvent")
		remote.Name = "SetSetting"
		remote.Parent = folder
	end
	if not folder:FindFirstChild("GetSettings") then
		local remote = Instance.new("RemoteFunction")
		remote.Name = "GetSettings"
		remote.Parent = folder
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

return {
	-- клиент -> сервер: (key, value) из Config/Settings.list
	SetSetting = folder:WaitForChild("SetSetting") :: RemoteEvent,
	-- клиент -> сервер, ответ: таблица Settings.Values или nil (профиль не загрузился)
	GetSettings = folder:WaitForChild("GetSettings") :: RemoteFunction,
}
