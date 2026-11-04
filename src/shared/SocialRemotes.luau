--!strict
-- Remotes статуса и соцфич (VIP, подарки, группа), в своей папке. Сервер создаёт, клиент ждёт.
-- Подарок: клиент выбирает получателя (GiftSelect), сервер проверяет и сам открывает окно покупки.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "SocialRemotes"

local NAMES = {
	"GiftSelect", -- клиент -> сервер: giftId, userId получателя — выбрать, кому дарим
	-- сервер -> клиент: тост { kind, name?, itemKind?, itemId?, money? } (SocialController)
	"SocialNotice",
	"GroupCheck", -- клиент -> сервер: без аргументов — перепроверить группу (после «Вступить»)
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

local SocialRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	SocialRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return SocialRemotes
