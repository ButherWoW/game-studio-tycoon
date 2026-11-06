--!strict
-- Remotes админ-панели владельца (AdminService, клиент AdminPanel). Сервер создаёт, клиент ждёт.
-- Remotes видят все, но сервер отвечает только владельцам (OwnerAccess, проверка на каждый вызов);
-- остальным — nil без объяснений.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "AdminRemotes"

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	if not folder:FindFirstChild("AdminRequest") then
		local remote = Instance.new("RemoteFunction")
		remote.Name = "AdminRequest"
		remote.Parent = folder
	end
	if not folder:FindFirstChild("AdminAnnounce") then
		local remote = Instance.new("RemoteEvent")
		remote.Name = "AdminAnnounce"
		remote.Parent = folder
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

return {
	-- клиент -> сервер (только владелец): (action: string, args: table?) -> ответ
	-- { ok: boolean, text: string, confirm: string?, data: any? }. confirm — токен: повторить тот же
	-- запрос с args.confirm = токен в течение Config/Admin.confirmSeconds (кик, бан, сброс профиля)
	AdminRequest = folder:WaitForChild("AdminRequest") :: RemoteFunction,
	-- сервер -> все клиенты: { text: string (уже отфильтрован для всех), seconds: number }
	AdminAnnounce = folder:WaitForChild("AdminAnnounce") :: RemoteEvent,
}
