--!strict
-- RemoteEvent сотрудников и переезда студии. Сервер создаёт, клиент ждёт (как в Remotes.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"HireEmployee", -- клиент -> сервер: employeeId
	"FireEmployee", -- клиент -> сервер: employeeId (уволить, вернуть Employees.fireRefund цены)
	"StrikeTipSeen", -- клиент -> сервер: без аргументов, подсказку о забастовке закрыли
	"MoveStudio", -- клиент -> сервер: без аргументов, переезд на следующий этап
	"StaffChanged", -- сервер -> клиент: { [employeeId]: deskUpgradeId ("" — ждёт стол) }, { info, unlocked, now }
	"UpgradeSkill", -- клиент -> сервер: employeeId, skillKey
	"SetPerk", -- клиент -> сервер: employeeId, slot, perkId
	"SetLook", -- клиент -> сервер: employeeId, field ("shirt" | "skin" | "hat" | "item"), index
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("StaffRemotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "StaffRemotes"
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
	folder = ReplicatedStorage:WaitForChild("StaffRemotes") :: Folder
end

local StaffRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	StaffRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return StaffRemotes
