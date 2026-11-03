--!strict
-- Remote'ы выбора языка (отдельно от Remotes.luau, чтобы не спорить с другими фичами).
-- Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "LanguageRemotes"

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	if not folder:FindFirstChild("SetLanguage") then
		local remote = Instance.new("RemoteEvent")
		remote.Name = "SetLanguage"
		remote.Parent = folder
	end
	if not folder:FindFirstChild("GetLanguage") then
		local remote = Instance.new("RemoteFunction")
		remote.Name = "GetLanguage"
		remote.Parent = folder
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

return {
	-- клиент -> сервер: код языка из Texts.languages
	SetLanguage = folder:WaitForChild("SetLanguage") :: RemoteEvent,
	-- клиент -> сервер, ответ: сохранённый код языка или nil
	GetLanguage = folder:WaitForChild("GetLanguage") :: RemoteFunction,
}
