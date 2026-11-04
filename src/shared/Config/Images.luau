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
	menu_achievements = 0, -- menu_achievements.png, 🏆 (V10)
	menu_studio = 0, -- menu_studio.png, 🛋️ (окно «Студия»: декор и настроение), PNG ещё нет
	home = 0, -- 🏠, PNG в V3 нет
} :: { [string]: number }

-- Постеры магазина (docs/VISUAL.md, V8; Config/Posters). 0 — картинки ещё нет: постер рисуется
-- цветом, эмодзи и названием. Dev 1: загрузить poster_<id>.png (768×1024) так же, как иконки
-- меню, и вставить Image ID напротив id постера
Images.posters = {
	pixelHero = 0, -- poster_pixelHero.png
	puzzleBlocks = 0, -- poster_puzzleBlocks.png
	turboRacer = 0, -- poster_turboRacer.png
	starBlaster = 0, -- poster_starBlaster.png
	ninjaCat = 0, -- poster_ninjaCat.png
	ghostManor = 0, -- poster_ghostManor.png
	robotArena = 0, -- poster_robotArena.png
	dragonValley = 0, -- poster_dragonValley.png
	neonCity = 0, -- poster_neonCity.png, премиум
	crystalKingdom = 0, -- poster_crystalKingdom.png, премиум
	mechTitan = 0, -- poster_mechTitan.png, премиум
	galaxyLegends = 0, -- poster_galaxyLegends.png, премиум
	goldenController = 0, -- poster_goldenController.png, премиум
} :: { [string]: number }

-- Медали достижений (V10, Астра #88): окно 🏆 вместо 🥉🥈🥇
Images.medals = {
	bronze = 71752753521866, -- medal_bronze.png
	silver = 95715963709982, -- medal_silver.png
	gold = 70516815676378, -- medal_gold.png
} :: { [string]: number }

-- Скины сотрудников (docs/VISUAL.md, V12; Config/Skins). 0 — картинки ещё нет: NPC красится
-- запасными цветами скина, в магазине — цветная карточка с эмодзи.
-- Dev 1: из docs/visual/astra-2026-11-05-skins/batch-1..3/V12 загрузить skin_<id>_shirt.png и
-- skin_<id>_pants.png (шаблоны 585×559) и skin_<id>_preview.png (512×512) как Images и вставить
-- Image ID (не Decal ID!) в shirt / pants / preview напротив id скина
Images.skins = {
	hoodie_coder = { shirt = 116925253396107, pants = 77040404351690, preview = 71584634617700 },
	pixel_artist = { shirt = 134341234705476, pants = 110913800554979, preview = 101781629414715 },
	sound_nerd = { shirt = 140584770538068, pants = 114882087803012, preview = 126279785622105 },
	writer = { shirt = 94386345570626, pants = 91319320361436, preview = 72542131784416 },
	intern = { shirt = 113270813059869, pants = 120755267901010, preview = 111233561221579 },
	bug_hunter = { shirt = 131441530857371, pants = 81481283222694, preview = 79545807894976 },
	speedrunner = { shirt = 103872155513441, pants = 109156030900915, preview = 96464281028661 },
	retro_gamer = { shirt = 119464023103825, pants = 138364891743589, preview = 82631326828501 },
	neon_streamer = { shirt = 73791546129249, pants = 74152800336888, preview = 120378517314886 }, -- премиум
	cyber_dev = { shirt = 82642398146223, pants = 130561786132954, preview = 137475696575517 }, -- премиум
	space_dev = { shirt = 88596041155611, pants = 121217414786209, preview = 87409951657588 }, -- премиум
	wizard_dev = { shirt = 133948528089059, pants = 84656926980640, preview = 128736905194190 }, -- премиум
} :: { [string]: { shirt: number, pants: number, preview: number } }

return Images
