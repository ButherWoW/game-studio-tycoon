--!strict
-- Remotes предложений доната (Config/Offers), в своей папке. Сервер создаёт, клиент ждёт.
-- Покупку за Robux клиент запускает сам (Prompt*Purchase), выдаёт ProcessReceipt (OfferService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "OfferRemotes"

local NAMES = {
	"OfferStateRequest", -- клиент -> сервер: без аргументов, прислать OfferState
	-- сервер -> клиент: { firstJoin, starterBought, starterEndsAt, starterCash, incomePerMinute,
	-- dealOwned, doubleRelease = { id, revenue, endsAt }? }
	"OfferState",
	"OfferEvent", -- клиент -> сервер: kind, stage ("shown" | "clicked" | "purchased") — для аналитики
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

local OfferRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	OfferRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return OfferRemotes
