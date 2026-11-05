--!strict
-- Тост «🎉 Новый жанр доступен: …», когда выполнились условия открытия жанра или темы
-- (shared/UnlockRules) и её теперь можно купить. Сравниваем снимки данных до и после:
-- первый снимок — точка отсчёта (без тостов), каждый жанр/тема объявляется один раз за сессию.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local UnlockRules = require(ReplicatedStorage.Shared.UnlockRules)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local TOAST_SECONDS = 3.5

local player = Players.LocalPlayer

local UnlockNotice = {}

local queue: { string } = {}
local showing = false

local function showNext()
	local text = table.remove(queue, 1)
	if not text then
		showing = false
		return
	end
	showing = true
	local screen = Instance.new("ScreenGui")
	screen.Name = "UnlockToast"
	-- Под окнами (10+), над HUD — как другие тосты
	screen.DisplayOrder = 4
	screen.ResetOnSpawn = false
	screen.Parent = player:WaitForChild("PlayerGui")
	local label = Ui.label(screen, text, 36, Ui.titleFontFor(ClientState.lang), Ui.colors.good)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.3)
	label.Size = UDim2.new(0.9, 0, 0, 36)
	label.BackgroundColor3 = Ui.colors.panel
	label.BackgroundTransparency = 0.2
	Ui.corner(label, 10)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(560, 36)
	limit.Parent = label
	task.delay(TOAST_SECONDS, function()
		screen:Destroy()
		showNext()
	end)
end

-- Общая очередь тостов открытия: её же берёт FeatureGate («🆕 Открыто: …»), чтобы тосты
-- жанров и систем не ложились друг на друга
local function toast(text: string)
	table.insert(queue, text)
	if not showing then
		showNext()
	end
end
UnlockNotice.toast = toast

-- Закрытые жанры/темы с условиями, которые уже выполнены: "genre/rpg" -> true
local function readySet(data: any): { [string]: boolean }
	local result: { [string]: boolean } = {}
	local function scan(kind: string, source: { [string]: any }, unlocked: any)
		for id, item in source do
			local open = type(unlocked) == "table" and unlocked[id]
			if not open and item.requires and not item.seasonal and UnlockRules.check(item, data) then
				result[kind .. "/" .. id] = true
			end
		end
	end
	scan("genre", Genres, data.unlockedGenres)
	scan("topic", Topics, data.unlockedTopics)
	return result
end

function UnlockNotice.start()
	local known: { [string]: boolean }? = nil
	ClientState.changed:Connect(function()
		local data = ClientState.data
		if type(data) ~= "table" then
			return
		end
		local ready = readySet(data)
		if not known then
			known = ready
			return
		end
		local seen = known :: { [string]: boolean }
		for key in ready do
			if not seen[key] then
				seen[key] = true
				local kind, id = key:match("^(%a+)/(.+)$")
				local item = if kind == "genre" then (Genres :: any)[id] else (Topics :: any)[id]
				if item then
					local textKey = if kind == "genre" then "unlock_new_genre" else "unlock_new_topic"
					-- Не раньше, чем окно релиза покажет оценку (условие могла выполнить эта игра)
					ClientState.afterReveal(function()
						toast(ClientState.t(textKey, { name = ClientState.localName(item) }))
					end)
				end
			end
		end
	end)
end

return UnlockNotice
