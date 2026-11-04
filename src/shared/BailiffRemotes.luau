--!strict
-- RemoteEvent приставов (BailiffService). Сервер создаёт, клиент ждёт (как в Remotes.luau).
-- Состояние — атрибуты игрока: BailiffDebt (долг = минус баланса, 0 — нет), BailiffLimit (лимит
-- овердрафта этапа), BailiffsActive (приставы забирают вещи).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	-- сервер -> клиент: { kind = "upgrade" | "decor", id, amount } — забрали предмет за amount;
	-- { left = true } — долг закрыт, приставы ушли
	"BailiffSeized",
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("BailiffRemotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "BailiffRemotes"
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
	folder = ReplicatedStorage:WaitForChild("BailiffRemotes") :: Folder
end

local BailiffRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	BailiffRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return BailiffRemotes
