--!strict
-- Remotes сейфа в парке (SafeService), в своей папке. Сервер создаёт, клиент ждёт.
-- Состояние сейфа (есть ли код, приз, пуст ли) — атрибуты модели workspace.StartPark.ParkSafe:
-- SafeState ("off" | "on" | "empty"), SafeCash. Самого кода у клиента нет.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "SafeRemotes"

local NAMES = {
	"SafeOpen", -- сервер -> клиент: открыть клавиатуру (игрок нажал на сейф)
	"SafeTry", -- клиент -> сервер: digits — 6 цифр строкой
	-- сервер -> клиент: { reason: "ok" | "wrong" | "used" | "empty" | "off" | "slow" | "far" | "error",
	-- cash: number?, wait: number? (секунд до следующей попытки при "slow") }
	"SafeResult",
	-- сервер -> клиент: { kind: "new", cash } — баннер всем; { kind: "admin", text } — ответ владельцу
	"SafeNotice",
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

local SafeRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	SafeRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return SafeRemotes
