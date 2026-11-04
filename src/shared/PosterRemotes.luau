--!strict
-- Remotes постеров (по образцу ShopRemotes.luau), в своей папке. Сервер создаёт, клиент ждёт.
-- Покупку за Robux клиент запускает сам (PromptProductPurchase), постер выдаёт ProcessReceipt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "PosterRemotes"

local NAMES = {
	"PosterStateRequest", -- клиент -> сервер: без аргументов, прислать PosterState
	-- сервер -> клиент: { owned = { [posterId]: true }, equipped = { [slotId]: posterId },
	-- slots = { slotId } — места, которые сейчас висят на участке }
	"PosterState",
	"BuyPoster", -- клиент -> сервер: posterId — купить обычный постер за $
	"EquipPoster", -- клиент -> сервер: slotId, posterId? — повесить постер на место (nil — снять)
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

local PosterRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	PosterRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return PosterRemotes
