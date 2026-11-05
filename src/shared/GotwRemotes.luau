--!strict
-- Remotes «Игры недели» (GotwService / вкладка в окне 📊). Сервер создаёт, клиент ждёт.
-- Титул победителя — временный титул gotw_winner (TitleService); место — атрибут игрока GotwRank
-- (1..10, нет — nil), табличку рисует TitleTags.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "GotwRemotes"

local NAMES = {
	"GotwRequest", -- клиент -> сервер: без аргументов — прислать таблицу
	-- сервер -> клиент: { available, weekKey, endsAt, rows = { Row }, last = { Row }, mine = { name, genreId, score, revenue }? }
	-- Row = { rank, userId, player, studio, name, genreId, score, revenue }
	"GotwBoard",
	-- сервер -> клиент: { kind = "winner", rank, money } — награда за прошлую неделю
	"GotwNotice",
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

local GotwRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	GotwRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return GotwRemotes
