--!strict
-- Рекламные щиты у спавна (BillboardService). Купил рекламную кампанию (Config/AdCampaigns,
-- за Robux или за $) — последняя выпущенная игра попадает в очередь щитов сервера.
-- Места щитов — StartPark.billboards. Обложка — Images.covers[genreId] (V20), 0 — эмодзи жанра.

local Billboards = {
	rotateSeconds = 60, -- смена показа на щитах
	-- Сколько игра стоит в очереди: длительность кампании, но не меньше minSeconds
	minSeconds = 10 * 60,
	maxQueue = 24, -- больше записей не держим: вытесняются самые старые из купленных за $
	-- Щит: опора и панель. Низ панели выше крон деревьев парка (до ~20 studs, astra-park/layout.json)
	poleHeight = 24,
	poleSize = 1.4,
	panelSize = Vector2.new(16, 9),
	panelDepth = 0.6,
	pixelsPerStud = 40,
	-- Без обложки (Images.covers = 0) — эмодзи жанра
	genreIcons = {
		action = "💥",
		adventure = "🗺",
		casual = "🎈",
		rpg = "⚔",
		simulation = "🏙",
		puzzle = "🧩",
		racing = "🏎",
		strategy = "♟",
		sports = "⚽",
		horror = "👻",
	} :: { [string]: string },
}

return Billboards
