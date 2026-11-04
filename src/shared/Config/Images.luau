--!strict
-- Картинки интерфейса (docs/VISUAL.md, V3). id = 0 — картинки ещё нет, кнопка показывает эмодзи.
-- Dev 1: загрузить PNG из docs/visual/astra-2026-11-04/V3 в Creator Hub → Development Items →
-- Decals/Images и вставить сюда Image ID (не Decal ID!) напротив имени файла.

local Images = {}

Images.menu = {
	menu_research = 0, -- menu_research.png, 🔬
	menu_team = 0, -- menu_team.png, 👥
	menu_quests = 0, -- menu_quests.png, 📋
	menu_shop = 0, -- menu_shop.png, 🛒
	menu_rebirth = 0, -- menu_rebirth.png, ♻️
	menu_language = 0, -- menu_language.png, 🌐
	menu_hits = 0, -- menu_hits.png, 🔒
	menu_thieves = 0, -- menu_thieves.png, 😈
	menu_holiday = 0, -- menu_holiday.png, 🎉
	menu_camera = 0, -- menu_camera.png, 🎥
	menu_bank = 0, -- menu_bank.png, 🏦
	home = 0, -- 🏠, PNG в V3 нет
} :: { [string]: number }

return Images
