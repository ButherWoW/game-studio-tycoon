--!strict
-- Remotes быстрых событий разработки (Config/QuickEvents). Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "QuickRemotes"

local NAMES = {
	-- сервер -> клиент: { id, kind, projectId, startedAt, leadIn, expiresAt, ...параметры вида }
	-- (время — workspace:GetServerTimeNow())
	"QuickEvent",
	-- клиент -> сервер: id, action ("press" | "release" | "up" | "down" | "left" | "right"),
	-- clientTime (workspace:GetServerTimeNow() в момент нажатия)
	"QuickEventInput",
	"QuickEventResult", -- сервер -> клиент: { id, grade, delta, total }
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

local QuickRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	QuickRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return QuickRemotes
