--!strict
-- RemoteEvent налоговой (TaxService). Состояние — атрибуты игрока: TaxBill (счёт, 0 — нет),
-- TaxDue (os.time срока оплаты), TaxAuditUntil (os.time конца проверки), TaxNextIn (сек до счёта), TaxRate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"PayTax", -- клиент -> сервер: без аргументов, оплатить счёт
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("TaxRemotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "TaxRemotes"
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
	folder = ReplicatedStorage:WaitForChild("TaxRemotes") :: Folder
end

local TaxRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	TaxRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return TaxRemotes
