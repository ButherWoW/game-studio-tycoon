--!strict
-- Remotes сезона и гейм-джема. Сервер создаёт, клиент ждёт.
-- Хакатон — без remotes: атрибуты ReplicatedStorage HackathonStartsAt / HackathonEndsAt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "LiveOpsRemotes"

local NAMES = {
	"RequestSeason", -- клиент -> сервер: прислать состояние сезона и джема
	"SeasonState", -- сервер -> клиент: { id, startsAt, endsAt, xp, premium, claimedFree, claimedPremium, ... }
	"ClaimSeason", -- клиент -> сервер: track ("free" | "premium" | "all"), tier (1..30; для "all" — 0)
	"JamState", -- сервер -> клиент: { weekId, genreId, topicId, endsAt, best, top = {...}, last = {...} }
	"LiveOpsToast", -- сервер -> клиент: { key, vars } — короткое уведомление
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

local LiveOpsRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	LiveOpsRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return LiveOpsRemotes
