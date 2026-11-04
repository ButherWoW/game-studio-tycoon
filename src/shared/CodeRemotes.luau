--!strict
-- Remotes промокодов (CodeService), в своей папке. Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "CodeRemotes"

local NAMES = {
	"RedeemCode", -- клиент -> сервер: text — введённый код
	-- сервер -> клиент: { reason: "ok" | "invalid" | "used" | "expired" | "limit", reward: CodeReward? }
	"CodeResult",
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

local CodeRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	CodeRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return CodeRemotes
