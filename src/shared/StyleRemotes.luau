--!strict
-- Remotes стилей мебели (окно «Студия» → «Стиль», FurnitureStyleService) и отделки студии
-- (вкладка «Отделка», InteriorFinishService). Сервер создаёт, клиент ждёт.
-- Покупку за Robux клиент запускает сам (PromptProductPurchase), стиль/отделку выдаёт ProcessReceipt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "StyleRemotes"

local NAMES = {
	"StyleStateRequest", -- клиент -> сервер: без аргументов, прислать StyleState
	-- сервер -> клиент: { owned = { [styleId]: true }, selected = styleId }
	"StyleState",
	"BuyStyle", -- клиент -> сервер: styleId — купить стиль за $
	"SelectStyle", -- клиент -> сервер: styleId — поставить открытый стиль
	"FinishStateRequest", -- клиент -> сервер: без аргументов, прислать FinishState
	-- сервер -> клиент: { owned = { [finishId]: true }, selected = finishId }
	"FinishState",
	"SelectFinish", -- клиент -> сервер: finishId — поставить открытую отделку (купить — только за Robux)
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

local StyleRemotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	StyleRemotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return StyleRemotes
