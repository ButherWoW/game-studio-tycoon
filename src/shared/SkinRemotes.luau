--!strict
-- Remotes скинов сотрудников (как PosterRemotes), в своей папке. Сервер создаёт, клиент ждёт.
-- Покупку за Robux клиент запускает сам (PromptProductPurchase), скин выдаёт ProcessReceipt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "SkinRemotes"

local NAMES = {
	"SkinStateRequest", -- клиент -> сервер: без аргументов, прислать SkinState
	-- сервер -> клиент: { owned = { [skinId]: true }, assigned = { [employeeId]: skinId } }
	"SkinState",
	"BuySkin", -- клиент -> сервер: skinId — купить обычный скин за $
	"AssignSkin", -- клиент -> сервер: employeeId, skinId? — надеть скин (nil — свой вид)
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

local SkinRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	SkinRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return SkinRemotes
