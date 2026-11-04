--!strict
-- Remotes франшиз, контрактов издателей и конкурентов (FranchiseService, ContractService,
-- RivalService), в своей папке. Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "DepthRemotes"

local NAMES = {
	"FranchiseRequest", -- клиент -> сервер: прислать FranchiseState
	-- сервер -> клиент: { list = { { id, name, genreId, topicId, fans, entries, lastAt, lastScore,
	-- lastName } }, candidates = { { key, name, genreId, topicId, score } }, serverTime }
	"FranchiseState",
	"FranchiseCreate", -- клиент -> сервер: key кандидата
	-- сервер -> клиент: после релиза части { name, multiplier, fans, fansDelta, fatigue, worse }
	-- или { candidate = name } — игру можно сделать франшизой
	"FranchiseNotice",
	"ContractRequest", -- клиент -> сервер: прислать ContractState
	-- сервер -> клиент: { offer = Contract?, active = Contract?, serverTime }
	"ContractState",
	"ContractRespond", -- клиент -> сервер: offerId, accept (boolean)
	-- сервер -> клиент: { result = "accepted" | "done" | "failed", publisher, amount, debt? }
	"ContractResult",
	"RivalRequest", -- клиент -> сервер: прислать RivalState
	-- сервер -> клиент: { top = { { id?, name, icon, value, you? } }, rank, nextName?, nextGap? }
	"RivalState",
	-- сервер -> клиент: { passed = { name, icon, reward } } или { hit = { name, icon, genreId } }
	"RivalNotice",
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

local DepthRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	DepthRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return DepthRemotes
