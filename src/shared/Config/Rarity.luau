--!strict
-- Цвета редкостей для карточек, чипов и плиток коллекции (UI в мультяшном стиле, issue #14).
-- Порядок = от обычного к редчайшему; id стабильные, цвета можно менять.

export type Tier = { id: string, color: Color3 }

local Rarity = {}

Rarity.tiers = {
	{ id = "common", color = Color3.fromRGB(150, 156, 170) },
	{ id = "uncommon", color = Color3.fromRGB(70, 200, 110) },
	{ id = "rare", color = Color3.fromRGB(60, 130, 255) },
	{ id = "epic", color = Color3.fromRGB(165, 95, 235) },
	{ id = "legendary", color = Color3.fromRGB(255, 160, 50) },
	{ id = "mythic", color = Color3.fromRGB(240, 90, 150) },
} :: { Tier }

local byId: { [string]: Tier } = {}
for _, tier in Rarity.tiers do
	byId[tier.id] = tier
end

-- Цвет редкости; неизвестный id — как у обычной
function Rarity.color(id: string): Color3
	local tier = byId[id] or Rarity.tiers[1]
	return tier.color
end

return Rarity
