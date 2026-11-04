--!strict
-- RemoteEvent кредита банка (LoanService). Сервер создаёт, клиент ждёт (как в Remotes.luau).
-- Состояние — атрибуты игрока: LoanOffer (сколько банк готов дать, 0 — не предлагает)
-- и LoanDebt (сколько осталось вернуть).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"TakeLoan", -- клиент -> сервер: без аргументов, взять предложенный кредит
	"RepayLoan", -- клиент -> сервер: без аргументов, погасить сколько хватает денег
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("LoanRemotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LoanRemotes"
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
	folder = ReplicatedStorage:WaitForChild("LoanRemotes") :: Folder
end

local LoanRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	LoanRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return LoanRemotes
