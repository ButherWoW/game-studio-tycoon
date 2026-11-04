--!strict
-- Друзья на клиенте: кнопка «📨 Пригласить друга» (SocialService:PromptGameInvite с LaunchData
-- "ref:<userId>" — по ней ReferralService узнаёт, кто пригласил) и тосты FriendNotice
-- (награды за приглашение и ответы обмена). Входящий запрос обмена показывает TradeWindow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage.Shared
local Friends = require(Shared.Config.Friends)
local Skins = require(Shared.Config.Skins)
local Posters = require(Shared.Config.Posters)
local Mascots = require(Shared.Config.Mascots)
local Texts = require(Shared.Config.Texts)
local FriendRemotes = require(Shared.FriendRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local TOAST_SECONDS = 4

local player = Players.LocalPlayer

local FriendsController = {}

-- ===== Тосты =====

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
	screen.Name = "FriendsToast"
	screen.DisplayOrder = 4 -- под окнами (10+), над HUD — как другие тосты
	screen.ResetOnSpawn = false
	screen.Parent = player:WaitForChild("PlayerGui")
	local label = Ui.label(screen, item.text, 36, Ui.titleFontFor(ClientState.lang), item.color)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.18)
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

function FriendsController.toast(text: string, color: Color3?)
	table.insert(queue, { text = text, color = color or Ui.colors.text })
	if not showing then
		showNext()
	end
end

-- ===== Названия предметов =====

local ICONS = { skin = "👔", poster = "🖼", mascot = "🐾" }

function FriendsController.itemName(kind: any, id: any): string
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

-- «👔 Худи-кодер»
function FriendsController.itemLabel(kind: any, id: any): string
	return (ICONS[kind] or "") .. " " .. FriendsController.itemName(kind, id)
end

-- ===== Приглашение =====

local inviting = false

function FriendsController.invite()
	if inviting then
		return
	end
	inviting = true
	task.spawn(function()
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if not ok or can ~= true then
			FriendsController.toast(ClientState.t("friends_invite_unavailable"), Ui.colors.bad)
			inviting = false
			return
		end
		local shown = pcall(function()
			local options = Instance.new("ExperienceInviteOptions")
			options.PromptMessage = ClientState.t("friends_invite_message")
			options.LaunchData = "ref:" .. player.UserId
			SocialService:PromptGameInvite(player, options)
		end)
		if not shown then
			FriendsController.toast(ClientState.t("friends_invite_unavailable"), Ui.colors.bad)
		end
		inviting = false
	end)
end

-- ===== Уведомления сервера =====

local function money(value: any): string
	return Texts.money(if type(value) == "number" then value else 0)
end

local function name(value: any): string
	return if type(value) == "string" then value else "?"
end

-- Тосты обмена: ключ текста и цвет (tradeRequest и tradeState рисует TradeWindow)
local TRADE_TOASTS: { [string]: { key: string, good: boolean? } } = {
	tradeSent = { key = "trade_request_sent", good = true },
	tradeDeclined = { key = "trade_declined" },
	tradeExpired = { key = "trade_expired" },
	tradeCancelled = { key = "trade_cancelled" },
	tradeDone = { key = "trade_done", good = true },
	tradeBusy = { key = "trade_busy" },
	tradeUnavailable = { key = "trade_unavailable" },
	tradeCooldown = { key = "trade_cooldown" },
	tradeDebt = { key = "trade_debt" },
	tradeFailed = { key = "trade_failed" },
	tradeEmpty = { key = "trade_empty" },
}

local function onNotice(notice: any)
	if type(notice) ~= "table" or type(notice.kind) ~= "string" then
		return
	end
	local kind = notice.kind
	if kind == "referralPending" then
		FriendsController.toast(
			ClientState.t(
				"referral_pending",
				{ name = name(notice.name), minutes = notice.minutes or 5, money = money(notice.money) }
			),
			Ui.colors.money
		)
	elseif kind == "referralNew" then
		FriendsController.toast(
			ClientState.t("referral_new", { money = money(notice.money) }),
			Ui.colors.good
		)
	elseif kind == "referralInviter" then
		FriendsController.toast(
			ClientState.t("referral_inviter", { name = name(notice.name), money = money(notice.money) }),
			Ui.colors.good
		)
	elseif kind == "referralCap" then
		FriendsController.toast(ClientState.t("referral_cap", { name = name(notice.name) }), Ui.colors.muted)
	elseif kind == "tradeOwned" then
		FriendsController.toast(
			ClientState.t(
				"trade_owned",
				{ name = name(notice.name), item = FriendsController.itemName(notice.itemKind, notice.item) }
			),
			Ui.colors.bad
		)
	else
		local spec = TRADE_TOASTS[kind]
		if spec then
			-- Отмена партнёром — с его именем; своя отмена — без
			local text = if kind == "tradeCancelled" and type(notice.name) == "string"
				then ClientState.t("trade_cancelled_by", { name = notice.name })
				else ClientState.t(spec.key, { name = name(notice.name) })
			FriendsController.toast(text, if spec.good then Ui.colors.good else Ui.colors.muted)
		end
	end
end

function FriendsController.start()
	FriendRemotes.FriendNotice.OnClientEvent:Connect(onNotice)
	-- Сколько приглашений ушло: счётчик в профиле и тост
	SocialService.GameInvitePromptClosed:Connect(function(who: any, recipients: any)
		if who ~= player or type(recipients) ~= "table" or #recipients == 0 then
			return
		end
		FriendRemotes.InviteSent:FireServer(#recipients)
		FriendsController.toast(
			ClientState.t("friends_invite_sent", { money = money(Friends.referral.newPlayerCash) }),
			Ui.colors.good
		)
	end)
end

return FriendsController
