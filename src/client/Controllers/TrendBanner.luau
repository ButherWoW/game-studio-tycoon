--!strict
-- Плашка «🔥 В тренде: Хоррор + Призраки, ещё 7:12» под HUD (шаг 4.3).
-- Тренд выбирает сервер (TrendService) и кладёт в атрибуты ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)
local Images = require(ReplicatedStorage.Shared.Config.Images)

local BANNER_HEIGHT = 26
-- Иконки жанра (слева) и темы (справа) из V21; 0 — плашка как раньше, только текст
local ICON_SIZE = 20
local BANNER_WIDTH = 340

local TrendBanner = {}

local function formatTime(seconds: number): string
	local s = math.max(math.floor(seconds), 0)
	return string.format("%d:%02d", s // 60, s % 60)
end

function TrendBanner.start()
	-- Первая плашка общего стека под HUD (Ui.bannerStack), под ней выставка
	local banner = Ui.label(
		Ui.bannerStack(),
		"",
		BANNER_HEIGHT,
		Ui.titleFontFor(ClientState.lang),
		Color3.fromRGB(255, 160, 70)
	)
	banner.Name = "TrendBanner"
	banner.LayoutOrder = 1
	banner.TextXAlignment = Enum.TextXAlignment.Center
	banner.Size = UDim2.fromOffset(BANNER_WIDTH, BANNER_HEIGHT)
	banner.BackgroundTransparency = 0.25
	banner.BackgroundColor3 = Ui.colors.panel
	banner.Visible = false
	Ui.corner(banner, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.Parent = banner
	-- Новичку — с гаража (Config/Unlocks.trends)
	Ui.gate(banner, "trends")

	-- Держатели иконок за пределами отступа текста: пустые и прозрачные, пока картинок нет
	local function iconHolder(name: string, x: number): Frame
		local holder = Instance.new("Frame")
		holder.Name = name
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(x, 0.5)
		-- Отступ текста растёт на ICON_SIZE, иконка встаёт в этот зазор (4 px от края плашки)
		holder.Position = UDim2.new(x, if x == 0 then -(ICON_SIZE + 4) else ICON_SIZE + 4, 0.5, 0)
		holder.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
		holder.Parent = banner
		return holder
	end
	local genreHolder = iconHolder("GenreIcon", 0)
	local topicHolder = iconHolder("TopicIcon", 1)
	local shownIcons = ""
	local function setIcons(genreId: string, topicId: string)
		local key = genreId .. "/" .. topicId
		if key == shownIcons then
			return
		end
		shownIcons = key
		genreHolder:ClearAllChildren()
		topicHolder:ClearAllChildren()
		local hasGenre = Ui.artImage(genreHolder, Images.genres[genreId]) ~= nil
		local hasTopic = Ui.artImage(topicHolder, Images.topics[topicId]) ~= nil
		padding.PaddingLeft = UDim.new(0, if hasGenre then 8 + ICON_SIZE else 10)
		padding.PaddingRight = UDim.new(0, if hasTopic then 8 + ICON_SIZE else 10)
	end

	local function refresh()
		local genre = Genres[ReplicatedStorage:GetAttribute("TrendGenre") :: any]
		local topic = Topics[ReplicatedStorage:GetAttribute("TrendTopic") :: any]
		local endsAt = ReplicatedStorage:GetAttribute("TrendEndsAt")
		if not genre or not topic or type(endsAt) ~= "number" then
			banner.Visible = false
			return
		end
		banner.Visible = true
		setIcons(genre.id, topic.id)
		banner.Font = Ui.titleFontFor(ClientState.lang)
		banner.Text = ClientState.t("trend_banner", {
			genre = ClientState.localName(genre),
			topic = ClientState.localName(topic),
			-- Серверное время: часы клиента могут спешить
			time = formatTime(endsAt - workspace:GetServerTimeNow()),
		})
	end

	ReplicatedStorage:GetAttributeChangedSignal("TrendGenre"):Connect(refresh)
	ReplicatedStorage:GetAttributeChangedSignal("TrendTopic"):Connect(refresh)
	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)
end

return TrendBanner
