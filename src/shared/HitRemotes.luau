--!strict
-- Remotes картриджей-хитов и таблицы воров. Сервер создаёт, клиент ждёт.
-- Лидер воров сервера — атрибут ReplicatedStorage «TopThiefUserId» (титул рисует клиент).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "HitRemotes"

local NAMES = {
	-- сервер -> клиент: { count, income, slots, lockedUntil, lockReadyAt, stealReadyAt }
	"HitState",
	-- сервер -> клиент: { key: string, vars: { [string]: any }? } — тост, ключ из Texts
	"HitToast",
	-- сервер -> хозяину: { thiefId: number, thiefName: string, name: string } или { stop = true }
	"HitAlarm",
	"RequestHitState", -- клиент -> сервер
	"RequestLock", -- клиент -> сервер: «Закрыть студию»
	-- сервер -> клиент: { server: { Row }, global: { available: boolean, rows: { Row } } }
	-- Row = { userId, name, steals, catches }
	"ThiefBoard",
	"RequestThiefBoard", -- клиент -> сервер
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

local HitRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	HitRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return HitRemotes
