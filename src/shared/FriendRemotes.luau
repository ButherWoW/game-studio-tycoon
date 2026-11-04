--!strict
-- Remotes уведомлений, приглашений и обмена (NotifyService, ReferralService, TradeService),
-- в своей папке. Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "FriendRemotes"

local NAMES = {
	"NotifyPrompt", -- сервер -> клиент: без аргументов — пора предложить включить уведомления
	"NotifyResult", -- клиент -> сервер: "closed" (окно показали) | "unavailable" (Roblox не дал)
	"InviteSent", -- клиент -> сервер: число — скольким друзьям ушло приглашение
	-- сервер -> клиент: тост { kind, name?, money?, minutes?, item?, itemKind? } (FriendsController)
	"FriendNotice",
	"TradeRequest", -- клиент -> сервер: userId — предложить обмен
	"TradeRespond", -- клиент -> сервер: userId, accept — ответ на входящий запрос
	"TradeOffer", -- клиент -> сервер: { { kind, id } }, cash — своё предложение целиком
	"TradeConfirm", -- клиент -> сервер: без аргументов — подтвердить обмен
	"TradeCancel", -- клиент -> сервер: без аргументов — отменить обмен
	"TradeStateRequest", -- клиент -> сервер: без аргументов — прислать состояние заново
	-- сервер -> клиент: состояние обмена (nil — обмена нет) и свой инвентарь (TradeService.pushState)
	"TradeState",
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

local FriendRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	FriendRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return FriendRemotes
