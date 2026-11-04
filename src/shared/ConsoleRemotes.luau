--!strict
-- Remotes своей консоли, платформ и стримера (ConsoleService, StreamerService), в своей папке.
-- Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "ConsoleRemotes"

local NAMES = {
	"ConsoleRequest", -- клиент -> сервер: прислать ConsoleState
	-- сервер -> клиент: { platforms = { [id]: true }, console = { unlocked, stage, started, progress,
	-- need, launched, share, royaltyPerMinute, licensePerMinute, earned }, streamer = { allowed,
	-- employeeId?, hype, perMinute, earned, hypeBonus } }
	"ConsoleState",
	"ConsoleStage", -- клиент -> сервер: начать следующий этап консоли (оплата)
	"StreamerAssign", -- клиент -> сервер: employeeId (string) — назначить стримером, false — снять
	-- сервер -> клиент: { kind = "stageDone" | "launched" | "hype", stage?, percent? }
	"ConsoleNotice",
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

local ConsoleRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	ConsoleRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return ConsoleRemotes
