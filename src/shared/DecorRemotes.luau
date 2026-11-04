--!strict
-- Remotes окна «Студия» (декор, настроение, покупка интерьера). Сервер создаёт, клиент ждёт.
-- Интерьер из окна покупается старым Remotes.BuyUpgrade: те же проверки, что у кнопок на полу.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "DecorRemotes"

local NAMES = {
	"StudioStateRequest", -- клиент -> сервер: без аргументов, прислать StudioState
	-- сервер -> клиент: { owned = { ["<id>@<этаж>"]: true }, floorsOpen, studioLevel, ownsGarage,
	-- mood = { value, target, staff, active, parts = { { key, value, vars? } } },
	-- offers = { { id, cost, floor, move?, stage?, lock?, lockVars? } } — интерьер этажей }
	"StudioState",
	"BuyDecor", -- клиент -> сервер: itemId, floor — купить декор на этаж
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

local DecorRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	DecorRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return DecorRemotes
