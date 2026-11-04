--!strict
-- Картинки интерфейса (docs/VISUAL.md, V3). id = 0 — картинки ещё нет, кнопка показывает эмодзи.
-- Dev 1: загрузить PNG из docs/visual/astra-2026-11-04/V3 в Creator Hub → Development Items →
-- Decals/Images и вставить сюда Image ID (не Decal ID!) напротив имени файла.

local Images = {}

Images.menu = {
	menu_research = 111519993777789, -- menu_research.png, 🔬
	menu_team = 77230608397075, -- menu_team.png, 👥
	menu_quests = 136993744510245, -- menu_quests.png, 📋
	menu_shop = 137630997422818, -- menu_shop.png, 🛒
	menu_rebirth = 93873527228508, -- menu_rebirth.png, ♻️
	menu_language = 126564198254913, -- menu_language.png, 🌐
	menu_hits = 113373317118331, -- menu_hits.png, 🔒
	menu_thieves = 92220236077266, -- menu_thieves.png, 😈
	menu_holiday = 108939585178579, -- menu_holiday.png, 🎉
	menu_camera = 113053777664719, -- menu_camera.png, 🎥
	menu_bank = 82427982778270, -- menu_bank.png, 🏦
	home = 0, -- 🏠, PNG в V3 нет
} :: { [string]: number }

return Images
