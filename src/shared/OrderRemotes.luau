--!strict
-- Remotes заказов дня (OrderService, доска на участке). Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"RequestOrders", -- клиент -> сервер: прислать текущие заказы (при старте клиента)
	"OrderState", -- сервер -> клиент: { day, endsAt, list = { { genreId, minScore, done, cash } }, completed = index? }
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("OrderRemotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "OrderRemotes"
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
	folder = ReplicatedStorage:WaitForChild("OrderRemotes") :: Folder
end

local OrderRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	OrderRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return OrderRemotes
