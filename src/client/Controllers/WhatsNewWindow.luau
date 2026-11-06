--!strict
-- Окно «🆕 Что нового»: первый вход после новой волны предметов (Config/ContentDrops) и/или
-- нового обновления систем по средам (Config/Features). Волна и обновление выходят в одну среду —
-- окно одно: сверху «🆕 Новое обновление: …» (все обновления после увиденного, с описанием),
-- ниже — предметы волны.
-- Атрибуты игрока: ContentDropNew (номер волны, ContentDropService) и FeatureUpdateNew /
-- FeatureUpdateSeen (номер последнего вышедшего и увиденного обновления, FeatureReleaseService);
-- 0 — нечего показывать. «Круто!» говорит серверу, что окно увидено.
-- Обновление вышло, пока игрок в игре, — ещё и тост «🆕 Новое обновление: …».
-- Всплывает само, по очереди с другими окнами входа (PopupQueue).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ContentDrops = require(ReplicatedStorage.Shared.Config.ContentDrops)
local Features = require(ReplicatedStorage.Shared.Config.Features)
local ContentDropRemotes = require(ReplicatedStorage.Shared.ContentDropRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local ContentDropClient = require(script.Parent.Parent.ContentDropClient)
local Ui = require(script.Parent.Parent.Ui)
local PopupQueue = require(script.Parent.Parent.PopupQueue)
local UnlockNotice = require(script.Parent.UnlockNotice)

local MAX_LINES = 8 -- больше не влезает на телефон: остальное — одной строкой «и ещё N»
local MAX_LINES_WITH_UPDATE = 4 -- вместе с обновлением систем предметов волны меньше
local LINE_HEIGHT = 24
local DESC_HEIGHT = 40

local WhatsNewWindow = {}
local gui: ScreenGui? = nil
local shownKey = ""
local player = Players.LocalPlayer

local function pendingDrop(): number
	local index = player:GetAttribute("ContentDropNew")
	return if type(index) == "number" and ContentDrops.drops[index] then index else 0
end

-- Номер последнего вышедшего обновления (0 — нечего показывать) и что игрок уже видел
local function pendingUpdate(): (number, number)
	local index = player:GetAttribute("FeatureUpdateNew")
	if type(index) ~= "number" or not Features.updates[index] then
		return 0, 0
	end
	local seen = tonumber(player:GetAttribute("FeatureUpdateSeen")) or 0
	return index, math.clamp(math.floor(seen), 0, index)
end

local function pendingKey(): string
	local update, seen = pendingUpdate()
	return pendingDrop() .. ":" .. update .. ":" .. seen
end

-- Название обновления на языке игрока: «🏆 Соревнование»
local function updateTitle(update: Features.Update): string
	return update.icon .. " " .. ClientState.t("upd_" .. update.id)
end

local function newUpdates(): { Features.Update }
	local index, seen = pendingUpdate()
	local list = {}
	for i = seen + 1, index do
		local update = Features.updates[i]
		if update and update.week > 0 then
			table.insert(list, update)
		end
	end
	return list
end

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		Ui.windowClosed()
	end
end

local function centered(label: TextLabel, order: number)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.LayoutOrder = order
end

local function show()
	close()
	local dropIndex = pendingDrop()
	local updateIndex = pendingUpdate()
	local updates = newUpdates()
	local drop = ContentDrops.drops[dropIndex]
	if not drop and #updates == 0 then
		return
	end
	shownKey = pendingKey()
	local items = if drop then ContentDrops.items(drop) else {}
	local maxLines = if #updates > 0 then MAX_LINES_WITH_UPDATE else MAX_LINES
	local lines = math.min(#items, maxLines) + (if #items > maxLines then 1 else 0)
	local hasNext = ContentDropClient.nextText() ~= nil

	local screen = Instance.new("ScreenGui")
	screen.Name = "WhatsNewWindow"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 25
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	Ui.windowOpened()

	local height = 210
		+ lines * (LINE_HEIGHT + 6)
		+ (if hasNext then 30 else 0)
		+ #updates * (36 + DESC_HEIGHT + 12)
		+ (if drop and #updates > 0 then 42 else 0)
	local window = Ui.window(screen, "Window", Vector2.new(480, height))
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 12)
	body.Size = UDim2.new(1, -32, 1, -24)
	local layout = Ui.list(body, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	body.Parent = window

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local headKey = if #updates > 0 then "upd_title" else "drop_whats_new"
	centered(Ui.label(body, ClientState.t(headKey), 24, Enum.Font.GothamBold, Ui.colors.muted), nextOrder())

	-- Обновления систем по средам: название и что вошло
	for _, update in updates do
		centered(
			Ui.label(body, updateTitle(update), 36, Ui.titleFontFor(ClientState.lang), Ui.colors.money),
			nextOrder()
		)
		local desc =
			Ui.label(body, ClientState.t("upd_" .. update.id .. "_desc"), DESC_HEIGHT, Enum.Font.GothamMedium)
		desc.TextWrapped = true
		centered(desc, nextOrder())
	end

	-- Волна предметов
	if drop then
		local title = Ui.label(
			body,
			ContentDropClient.title(drop),
			if #updates > 0 then 30 else 36,
			Ui.titleFontFor(ClientState.lang),
			Ui.colors.money
		)
		centered(title, nextOrder())
		for i, item in items do
			if i > maxLines then
				local more = Ui.label(
					body,
					ClientState.t("drop_more", { count = #items - maxLines }),
					LINE_HEIGHT - 4,
					Enum.Font.GothamMedium,
					Ui.colors.muted
				)
				centered(more, nextOrder())
				break
			end
			local line = Ui.label(
				body,
				ClientState.t("drop_kind_" .. item.kind)
					.. ": "
					.. ContentDropClient.itemName(item.kind, item.id),
				LINE_HEIGHT,
				Enum.Font.GothamMedium
			)
			centered(line, nextOrder())
		end
	end
	local hint = Ui.label(
		body,
		ClientState.t(if #updates > 0 then "upd_hint" else "drop_hint"),
		20,
		Enum.Font.GothamMedium,
		Ui.colors.muted
	)
	hint.TextWrapped = true
	centered(hint, nextOrder())
	local nextLabel = ContentDropClient.nextLine(body, nextOrder())
	if nextLabel then
		nextLabel.TextXAlignment = Enum.TextXAlignment.Center
	end

	local ok = Ui.button(body, ClientState.t("drop_ok"), Ui.colors.good, function()
		if drop then
			ContentDropRemotes.SeenDrop:FireServer(dropIndex)
		end
		if #updates > 0 then
			ContentDropRemotes.SeenUpdate:FireServer(updateIndex)
		end
		close()
	end)
	ok.Size = UDim2.new(0.6, 0, 0, 52)
	ok.LayoutOrder = nextOrder()
end

-- Тост для тех, кто в игре в момент выхода: «🆕 Новое обновление: 🏆 Соревнование, 🏢 Третий этаж»
local lastToasted = 0
local function toastNew(from: number, to: number)
	local names = {}
	for i = math.max(from, 0) + 1, to do
		local update = Features.updates[i]
		if update and update.week > 0 then
			table.insert(names, updateTitle(update))
		end
	end
	if #names > 0 then
		UnlockNotice.toast(ClientState.t("upd_toast", { name = table.concat(names, ", ") }))
	end
end

function WhatsNewWindow.start()
	local function check()
		local any = pendingDrop() > 0 or pendingUpdate() > 0
		if any then
			if not gui or shownKey ~= pendingKey() then
				PopupQueue.push("whatsNew", function()
					local still = pendingDrop() > 0 or pendingUpdate() > 0
					if still and (not gui or shownKey ~= pendingKey()) then
						show()
					end
				end)
			end
		else
			PopupQueue.remove("whatsNew")
			close()
		end
	end
	player:GetAttributeChangedSignal("ContentDropNew"):Connect(check)
	player:GetAttributeChangedSignal("FeatureUpdateSeen"):Connect(check)
	-- Первое значение приходит при входе (без тоста — для этого окно); дальше рост — вышло в игре
	local known = tonumber(player:GetAttribute("FeatureUpdateNew"))
	lastToasted = known or 0
	player:GetAttributeChangedSignal("FeatureUpdateNew"):Connect(function()
		local index = tonumber(player:GetAttribute("FeatureUpdateNew")) or 0
		if known == nil then
			known = index
			lastToasted = index
		elseif index > lastToasted then
			local seen = tonumber(player:GetAttribute("FeatureUpdateSeen")) or 0
			toastNew(math.max(lastToasted, seen), index)
			lastToasted = index
		end
		check()
	end)
	-- Сохранённый язык приходит после входа — перерисовать открытое окно
	ClientState.langChanged:Connect(function()
		if gui then
			show()
		end
	end)
	check()
end

return WhatsNewWindow
