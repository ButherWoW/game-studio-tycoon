--!strict
-- RemoteEvent биржи (StockService). Атрибуты игрока: StockListed (студия на бирже),
-- StockIpoReady (все условия IPO выполнены).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"StockRequest", -- клиент -> сервер: (companyId: number?) — прислать состояние биржи (и свечи компании)
	"StockBuy", -- клиент -> сервер: (companyId: number, shares: number)
	"StockSell", -- клиент -> сервер: (companyId: number, shares: number)
	"StockIpo", -- клиент -> сервер: без аргументов, выйти на биржу
	"StockState", -- сервер -> клиент: { companies, portfolio, ipo, selected?, candles?, message? }
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("StockRemotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "StockRemotes"
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
	folder = ReplicatedStorage:WaitForChild("StockRemotes") :: Folder
end

local StockRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	StockRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return StockRemotes
