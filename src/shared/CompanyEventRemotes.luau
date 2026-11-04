--!strict
-- Remotes событий компании (Config/CompanyEvents, CompanyEventService), в своей папке.
-- Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "CompanyEventRemotes"

local NAMES = {
	-- сервер -> клиент: { token, id, kind, emoji, lines?, options? = { a = vars, b = vars }, insured, repair? }
	"CompanyEvent",
	"CompanyEventSeen", -- клиент -> сервер: token — карточку показали (с этого момента идёт время на ответ)
	"CompanyEventChoice", -- клиент -> сервер: token, "a" | "b"
	"CompanyEventResult", -- сервер -> клиент: { token, id, choice, lines, insured }
	-- сервер -> клиент: { effects = { { kind, value, endsAt, item? } }, insuranceEndsAt?, insurancePrice,
	-- nextScore, nextRevenue, repairCost }
	"CompanyEventState",
	"CompanyEventStateRequest", -- клиент -> сервер: без аргументов
	"BuyInsurance", -- клиент -> сервер: без аргументов
	"RepairItem", -- клиент -> сервер: без аргументов — починить сломанный предмет
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

local CompanyEventRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	CompanyEventRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return CompanyEventRemotes
