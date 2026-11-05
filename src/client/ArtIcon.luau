--!strict
-- Картинки Астры (Config/Images.daily, Images.social) поверх старых эмодзи и цветных плашек.
-- Тот же приём, что у кнопок меню (Ui.menuButton): id > 0 — ImageLabel rbxassetid://id,
-- id 0 — ничего не создаём и не трогаем, окно выглядит как раньше.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Images = require(ReplicatedStorage.Shared.Config.Images)

local ArtIcon = {}

-- Картинка на всю площадь parent (под текстом: ZIndex 0). scaleType по умолчанию Fit;
-- для рамок — Slice с sliceCenter (в пикселях PNG) и sliceScale
function ArtIcon.fill(
	parent: GuiObject,
	id: number,
	scaleType: Enum.ScaleType?,
	sliceCenter: Rect?,
	sliceScale: number?
): ImageLabel?
	if id <= 0 then
		return nil
	end
	local image = Instance.new("ImageLabel")
	image.Name = "Art"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.ZIndex = 0
	image.ScaleType = scaleType or Enum.ScaleType.Fit
	if sliceCenter then
		image.SliceCenter = sliceCenter
		image.SliceScale = sliceScale or 1
	end
	image.Image = "rbxassetid://" .. id
	image.Parent = parent
	return image
end

-- Иконка вместо текста-эмодзи (кнопка «👍», медаль): текст прячем, картинка на всю кнопку
function ArtIcon.replace(target: TextLabel | TextButton, id: number): ImageLabel?
	local image = ArtIcon.fill(target, id)
	if image then
		target.Text = ""
		image.ZIndex = 1
	end
	return image
end

-- Текст без эмодзи-префикса, если вместо него рисуется картинка: «🎟 Коды» → «Коды».
-- Нет картинки или текст начинается не с этого эмодзи (другой язык) — текст как есть
function ArtIcon.strip(text: string, emoji: string, id: number): string
	if id <= 0 or emoji == "" or string.sub(text, 1, #emoji) ~= emoji then
		return text
	end
	local rest = string.sub(text, #emoji + 1)
	rest = string.gsub(rest, "^\u{FE0F}", "")
	rest = string.gsub(rest, "^%s+", "")
	return rest
end

-- Иконка size×size слева от текста кнопки или подписи; эмодзи-префикс убирается из текста.
-- Текст сдвигается вправо через UIPadding (у Ui.button он уже есть — расширяем его)
function ArtIcon.prefix(target: TextLabel | TextButton, emoji: string, id: number, size: number): ImageLabel?
	if id <= 0 then
		return nil
	end
	target.Text = ArtIcon.strip(target.Text, emoji, id)
	local padding = target:FindFirstChildOfClass("UIPadding")
	if not padding then
		local created = Instance.new("UIPadding")
		created.Parent = target
		padding = created
	end
	local pad = padding :: UIPadding
	local shift = size + 4
	pad.PaddingLeft = UDim.new(0, pad.PaddingLeft.Offset + shift)
	local image = Instance.new("ImageLabel")
	image.Name = "ArtIcon"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0, 0.5)
	-- Дети тоже сдвинуты UIPadding: возвращаем иконку на освободившееся место слева
	image.Position = UDim2.new(0, -shift, 0.5, 0)
	image.Size = UDim2.fromOffset(size, size)
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = "rbxassetid://" .. id
	image.Parent = target
	return image
end

-- Награда → ключ иконки в Images.daily и запасное эмодзи. Несколько видов сразу или предмет
-- (кубок, постер, маскот, звание) — «большая награда»
function ArtIcon.rewardKind(reward: any): (string, string)
	if type(reward) ~= "table" then
		return "rewardCash", "💰"
	end
	local kinds = 0
	for _, field in { "incomeMinutes", "researchPoints", "coffeeMinutes", "adBonus", "skin" } do
		if reward[field] ~= nil then
			kinds += 1
		end
	end
	if reward.trophy or reward.poster or reward.mascot or reward.title or kinds > 1 then
		return "rewardBig", "🎁"
	elseif reward.skin then
		return "rewardSkin", "👕"
	elseif reward.coffeeMinutes then
		return "rewardCoffee", "☕"
	elseif reward.researchPoints then
		return "rewardResearch", "🔬"
	end
	return "rewardCash", "💰"
end

-- id иконки награды (0 — картинки нет)
function ArtIcon.rewardImage(reward: any): number
	local key = ArtIcon.rewardKind(reward)
	return Images.daily[key] or 0
end

return ArtIcon
