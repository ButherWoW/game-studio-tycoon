--!strict
-- Опт-ин уведомлений Roblox: сервер (NotifyService) говорит «пора» после важного момента,
-- клиент ждёт, пока закроются окна игры, проверяет CanPromptOptInAsync и показывает окно
-- Roblox PromptOptIn. Ответ серверу: "closed" — окно показали, "unavailable" — Roblox не дал.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Friends = require(Shared.Config.Friends)
local FriendRemotes = require(Shared.FriendRemotes)
local Ui = require(script.Parent.Parent.Ui)

local NotifyPrompt = {}
local busy = false

local function prompt()
	if busy then
		return
	end
	busy = true
	-- Не поверх окна релиза или магазина: ждём, пока игрок их закроет
	local deadline = os.clock() + Friends.notify.windowWaitSeconds
	while Ui.anyWindowOpen() and os.clock() < deadline do
		task.wait(1)
	end
	if Ui.anyWindowOpen() then
		busy = false
		return -- ответа нет: сервер предложит в следующей сессии
	end
	local okService, service = pcall(function()
		return game:GetService("ExperienceNotificationService")
	end)
	local can = false
	if okService and service then
		local ok, result = pcall(function()
			return (service :: any):CanPromptOptInAsync()
		end)
		can = ok and result == true
	end
	if not can then
		FriendRemotes.NotifyResult:FireServer("unavailable")
		busy = false
		return
	end
	local shown = pcall(function()
		(service :: any):PromptOptIn()
	end)
	FriendRemotes.NotifyResult:FireServer(if shown then "closed" else "unavailable")
	busy = false
end

function NotifyPrompt.start()
	FriendRemotes.NotifyPrompt.OnClientEvent:Connect(function()
		task.spawn(prompt)
	end)
end

return NotifyPrompt
