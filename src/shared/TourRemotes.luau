--!strict
-- Remotes экскурсий, лайков и рейтингов (TourService / TourWindow), в своей папке.
-- Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "TourRemotes"

local NAMES = {
	"TourRequest", -- клиент -> сервер: без аргументов — прислать список студий и рейтинги
	"TourList", -- сервер -> клиент: { studios, recent } — студии на сервере и недавно посещённые
	"TourBoards", -- сервер -> клиент: { available, likes, value, hit, weekId } — глобальные топы
	"TourVisit", -- клиент -> сервер: userId — перенести к воротам чужой студии
	"TourLike", -- клиент -> сервер: userId — «👍 Нравится»
	-- сервер -> клиент: { kind = "visit"|"like"|"liked"|"weeklyStar", ok?, reason?, name?, money?, rank? }
	"TourNotice",
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

local TourRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	TourRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return TourRemotes
