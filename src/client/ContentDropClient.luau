--!strict
-- График контента на клиенте (Config/ContentDrops): подписи «🔒 Скоро: через N дн.» для карточек
-- магазинов, строка «Следующее обновление через N дн.» и имена предметов волны на языке игрока.
-- Только показ: что продаётся и выдаётся, проверяет сервер. Не контроллер — общий модуль
-- (SkinShop, MascotShop, PosterShop, StudioWindow, SeasonWindow, WhatsNewWindow).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ContentDrops = require(Shared.Config.ContentDrops)
local DailyEvents = require(Shared.Config.DailyEvents)
local Decor = require(Shared.Config.Decor)
local FurnitureStyles = require(Shared.Config.FurnitureStyles)
local Genres = require(Shared.Config.Genres)
local InteriorFinishes = require(Shared.Config.InteriorFinishes)
local Mascots = require(Shared.Config.Mascots)
local Posters = require(Shared.Config.Posters)
local Skins = require(Shared.Config.Skins)
local Topics = require(Shared.Config.Topics)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local ContentDropClient = {}

-- Вышел ли предмет (по серверному времени)
function ContentDropClient.isReleased(kind: ContentDrops.Kind, id: string): boolean
	return ContentDrops.isReleased(kind, id)
end

-- «🔒 Скоро: через N дн.», если предмет ещё не вышел и его у игрока нет; иначе nil
function ContentDropClient.teaser(kind: ContentDrops.Kind, id: string, owned: boolean?): string?
	if owned then
		return nil
	end
	local days = ContentDrops.daysUntil(kind, id)
	if days <= 0 then
		return nil
	end
	return ClientState.t("drop_soon_days", { days = days })
end

-- Название волны на языке игрока: «🤖 Неделя роботов»
function ContentDropClient.title(drop: ContentDrops.Drop): string
	return drop.icon .. " " .. ClientState.t("drop_" .. drop.id)
end

-- «🆕 Следующее обновление через N дн.: 🤖 Неделя роботов»; nil — все волны вышли
function ContentDropClient.nextText(): string?
	local drop, days = ContentDrops.nextDrop()
	if not drop then
		return nil
	end
	return ClientState.t("drop_next", { days = days, name = ContentDropClient.title(drop) })
end

-- Строка про следующее обновление в списке body (UIListLayout); ничего, если волн больше нет
function ContentDropClient.nextLine(body: Instance, order: number): TextLabel?
	local text = ContentDropClient.nextText()
	if not text then
		return nil
	end
	local label = Ui.label(body, text, 22, Enum.Font.GothamMedium, Ui.colors.money)
	label.LayoutOrder = order
	return label
end

local function named(item: { name: string, nameEn: string }?, key: string, fallback: string): string
	if not item then
		return fallback
	end
	return ClientState.localText(key, item.name, item.nameEn)
end

-- Имя предмета на языке игрока (для окна «Что нового»)
function ContentDropClient.itemName(kind: ContentDrops.Kind, id: string): string
	if kind == "genre" then
		local genre = Genres[id]
		return if genre then ClientState.localName(genre) else id
	elseif kind == "topic" then
		local topic = Topics[id]
		return if topic then ClientState.localName(topic) else id
	elseif kind == "skin" then
		return named(Skins.get(id), "skin_" .. id, id)
	elseif kind == "mascot" then
		return named(Mascots.get(id), "mascot_" .. id, id)
	elseif kind == "poster" then
		return named(Posters.get(id), "poster_" .. id, id)
	elseif kind == "decor" then
		return named(Decor.get(id), "decor_" .. id, id)
	elseif kind == "style" then
		return if FurnitureStyles.get(id) then ClientState.t("fstyle_" .. id) else id
	elseif kind == "finish" then
		return if InteriorFinishes.get(id) then ClientState.t("ifinish_" .. id) else id
	end
	local event = DailyEvents.get(id)
	return if event then event.icon .. " " .. ClientState.t("devent_name_" .. id) else id
end

return ContentDropClient
