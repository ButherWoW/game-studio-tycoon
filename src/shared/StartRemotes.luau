--!strict
-- Remotes начала игры «Инди в парке» (гараж, доска заказов, картриджи). Сервер создаёт, клиент ждёт.
-- Владеет ли игрок гаражом и сколько у него картриджей — атрибуты игрока OwnsGarage и Cartridges.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "StartRemotes"

local NAMES = {
	"GarageBought", -- сервер -> клиент: (без данных) гараж куплен
	"JobBoardOpen", -- сервер -> клиент: { [jobId]: секунд до готовности (0 — готов) }
	"JobStart", -- клиент -> сервер: jobId
	"JobStarted", -- сервер -> клиент: { id, duration }
	"JobFinish", -- клиент -> сервер: jobId, score
	"JobResult", -- сервер -> клиент: { id, ok, pay }
	"ParkNotice", -- сервер -> клиент: { kind = "cartridge" | "pawn" | "full", count, pay? }
	-- Название студии: окно открывает атрибут игрока NeedsStudioName = true
	"SetStudioName", -- клиент -> сервер: name
	"StudioNameResult", -- сервер -> клиент: { ok, name?, reason? ("length" | "filtered" | "error") }
	-- Кнопка 🏠 в меню: перенести персонажа к воротам своего гаража
	"GoHome", -- клиент -> сервер: (без данных)
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

local StartRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	StartRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return StartRemotes
