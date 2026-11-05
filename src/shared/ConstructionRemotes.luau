--!strict
-- RemoteEvent стройки (ConstructionService, Config/Construction). Сервер создаёт, клиент ждёт.
-- Состояние стройки — поле construction в снимке DataChanged ({ stage, startedAt, endsAt }).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	-- сервер -> клиент: { kind = "done", stage } — построено (тост, дальше MoveCelebration);
	-- { kind = "speed", minutes } — ускорено; { kind = "fallback", amount } — стройки уже нет,
	-- ускорение за Robux превратилось в доход
	"BuildEvent",
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("ConstructionRemotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ConstructionRemotes"
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
	folder = ReplicatedStorage:WaitForChild("ConstructionRemotes") :: Folder
end

local ConstructionRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	ConstructionRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return ConstructionRemotes
