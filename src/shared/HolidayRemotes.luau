--!strict
-- Remotes праздничных ивентов. Сервер создаёт, клиент ждёт.
-- Активный ивент — атрибуты ReplicatedStorage: HolidayId, HolidayEndsAt (os.time, UTC).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "HolidayRemotes"

local NAMES = {
	"RequestHolidayState", -- клиент -> сервер: без аргументов
	-- сервер -> клиент: { id: string?, endsAt, quest = { progress, target, claimed }?,
	--   calendar = { count, total, available, nextDayAt }?, cosmetics = { [id]: true } }
	"HolidayState",
	"ClaimHolidayQuest", -- клиент -> сервер: без аргументов
	"ClaimHolidayGift", -- клиент -> сервер: без аргументов (подарок календаря на сегодня)
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

local HolidayRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	HolidayRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return HolidayRemotes
