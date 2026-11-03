--!strict
-- Remotes магазина (по образцу Remotes.luau). Сервер создаёт, клиент ждёт.
-- Покупки за Robux клиент запускает сам (Prompt*Purchase), сервер узнаёт о них
-- из ProcessReceipt / PromptGamePassPurchaseFinished — доверять клиенту не нужно.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"ShopStateRequest", -- клиент -> сервер: без аргументов, прислать ShopState
	"ShopState", -- сервер -> клиент: { passes = { [passId]: true }, boosts = { instantFinish, patch, coffeeUntil }, incomePerMinute }
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("ShopRemotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ShopRemotes"
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
	folder = ReplicatedStorage:WaitForChild("ShopRemotes") :: Folder
end

local ShopRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	ShopRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return ShopRemotes
