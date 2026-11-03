--!strict
-- Remotes заданий, наград за вход и таблицы лидеров (шаг 4.5). Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"RequestQuestData", -- клиент -> сервер: прислать всё текущее (при старте клиента)
	"QuestState", -- сервер -> клиент: { quests = {...}, daily = {...}, day }
	"ClaimQuest", -- клиент -> сервер: kind ("quest" | "daily"), id
	"DailyRewardState", -- сервер -> клиент: { day 1..7, available }
	"ClaimDailyReward", -- клиент -> сервер: без аргументов
	"LeaderboardData", -- сервер -> клиент: { available, best = { {name, value} }, games = {...} }
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("QuestRemotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "QuestRemotes"
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
	folder = ReplicatedStorage:WaitForChild("QuestRemotes") :: Folder
end

local QuestRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	QuestRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return QuestRemotes
