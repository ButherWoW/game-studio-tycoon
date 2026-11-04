--!strict
-- Remotes маскотов (MascotService), в своей папке. Сервер создаёт, клиент ждёт.
-- Покупку за Robux клиент запускает сам (PromptProductPurchase), маскота выдаёт ProcessReceipt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "MascotRemotes"

local NAMES = {
	"MascotStateRequest", -- клиент -> сервер: без аргументов, прислать MascotState
	"MascotState", -- сервер -> клиент: { owned = { [mascotId]: true }, equipped = mascotId? }
	"BuyMascot", -- клиент -> сервер: mascotId — купить за $
	"EquipMascot", -- клиент -> сервер: mascotId? — взять с собой (nil — убрать)
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

local MascotRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	MascotRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return MascotRemotes
