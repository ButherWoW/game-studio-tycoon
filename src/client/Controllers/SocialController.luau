--!strict
-- Статус и соцфичи на клиенте:
--   * чат-тег «[👑 VIP]» перед именем VIP-игроков (атрибут IsVip ставит VipService);
--   * тосты подарков и награды за группу (SocialNotice от GiftService / SocialService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage.Shared
local Skins = require(Shared.Config.Skins)
local Posters = require(Shared.Config.Posters)
local Mascots = require(Shared.Config.Mascots)
local Texts = require(Shared.Config.Texts)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local TOAST_SECONDS = 4
local VIP_PREFIX = '<font color="#FFC93C">[👑 VIP]</font> '

local player = Players.LocalPlayer

local SocialController = {}

local queue: { { text: string, color: Color3 } } = {}
local showing = false

local function showNext()
	local item = table.remove(queue, 1)
	if not item then
		showing = false
		return
	end
	showing = true
	local screen = Instance.new("ScreenGui")
	screen.Name = "SocialToast"
	screen.DisplayOrder = 4 -- под окнами (10+), над HUD — как другие тосты
	screen.ResetOnSpawn = false
	screen.Parent = player:WaitForChild("PlayerGui")
	local label = Ui.label(screen, item.text, 36, Ui.titleFontFor(ClientState.lang), item.color)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.24)
	label.Size = UDim2.new(0.9, 0, 0, 36)
	label.BackgroundColor3 = Ui.colors.panel
	label.BackgroundTransparency = 0.15
	Ui.corner(label, 10)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 36)
	limit.Parent = label
	task.delay(TOAST_SECONDS, function()
		screen:Destroy()
		showNext()
	end)
end

local function toast(text: string, color: Color3)
	table.insert(queue, { text = text, color = color })
	if not showing then
		showNext()
	end
end

-- Название подарка на языке игрока
local function itemName(kind: any, id: any): string
	if kind == "skin" then
		local skin = Skins.get(id)
		return if skin then ClientState.localText("skin_" .. skin.id, skin.name, skin.nameEn) else "?"
	elseif kind == "mascot" then
		local mascot = Mascots.get(id)
		return if mascot
			then ClientState.localText("mascot_" .. mascot.id, mascot.name, mascot.nameEn)
			else "?"
	end
	local poster = Posters.get(id)
	return if poster then ClientState.localText("poster_" .. poster.id, poster.name, poster.nameEn) else "?"
end

local function onNotice(notice: any)
	if type(notice) ~= "table" or type(notice.kind) ~= "string" then
		return
	end
	local vars = {
		name = if type(notice.name) == "string" then notice.name else "?",
		item = itemName(notice.itemKind, notice.itemId),
	}
	local kind = notice.kind
	if kind == "giftReceived" then
		toast(ClientState.t("gift_received", vars), Ui.colors.money)
	elseif kind == "giftSent" then
		toast(ClientState.t("gift_sent", vars), Ui.colors.good)
	elseif kind == "giftFallback" then
		toast(ClientState.t("gift_fallback", vars), Ui.colors.money)
	elseif kind == "giftOwned" then
		toast(ClientState.t("gift_owned", vars), Ui.colors.bad)
	elseif kind == "giftUnavailable" then
		toast(ClientState.t("gift_unavailable"), Ui.colors.bad)
	elseif kind == "giftSoon" then
		toast(ClientState.t("gift_soon"), Ui.colors.muted)
	elseif kind == "groupReward" then
		local money = if type(notice.money) == "number" then Texts.money(notice.money) else ""
		toast(
			ClientState.t("group_reward", { skin = itemName("skin", notice.itemId), money = money }),
			Ui.colors.good
		)
	end
end

-- Тег холдинга «[Название]» (атрибут HoldingName ставит HoldingService). Название прошло фильтр,
-- но в RichText спецсимволы экранируем
local function holdingPrefix(speaker: Player): string
	local name = speaker:GetAttribute("HoldingName")
	if type(name) ~= "string" or name == "" then
		return ""
	end
	local safe = name:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
	return '<font color="#8CC8FF">[' .. safe .. "]</font> "
end

-- Чат: префиксы VIP и холдинга. Колбэк один на игру — больше никто его не ставит,
-- новые теги добавлять сюда
local function onIncomingMessage(message: TextChatMessage): TextChatMessageProperties?
	local source = message.TextSource
	local speaker = source and Players:GetPlayerByUserId(source.UserId)
	if not speaker then
		return nil
	end
	local prefix = (if speaker:GetAttribute("IsVip") == true then VIP_PREFIX else "")
		.. holdingPrefix(speaker)
	if prefix == "" then
		return nil
	end
	local properties = Instance.new("TextChatMessageProperties")
	properties.PrefixText = prefix .. message.PrefixText
	return properties
end

function SocialController.start()
	TextChatService.OnIncomingMessage = onIncomingMessage :: any
	local SocialRemotes = require(Shared.SocialRemotes)
	SocialRemotes.SocialNotice.OnClientEvent:Connect(onNotice)
end

return SocialController
