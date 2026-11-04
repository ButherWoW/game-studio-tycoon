--!strict
-- События во время разработки: всплывают с выбором, влияют на очки (а значит на оценку) и время.
-- work — секунды работы студии, добавленные в направление focus ("all" — по фокусу игры);
-- отрицательные — потеря. time — секунды к времени разработки. chance — шанс, что сработает
-- хорошо; при неудаче применяется failWork. Тексты: devevent_<id>_title / _a / _b в Texts и Locales.
-- Вариант b — «спокойный», он же применяется, если игрок не ответил вовремя.

export type Effect = {
	focus: string?,
	work: number?,
	time: number?,
	chance: number?,
	failWork: number?,
}
export type DevEvent = { id: string, a: Effect, b: Effect }

local DevEvents = {
	firstAt = 5, -- секунд разработки до первого события
	intervalMin = 7,
	intervalMax = 11,
	answerSeconds = 6,
	maxPerGame = 3,
	list = {
		{ id = "bug", a = { focus = "gameplay", work = 4, time = 2 }, b = { chance = 0.5, failWork = -4 } },
		{ id = "music", a = { focus = "sound", work = 5 }, b = {} },
		{ id = "art", a = { focus = "graphics", work = 5 }, b = {} },
		{ id = "story", a = { focus = "story", work = 5, time = 1 }, b = {} },
		{ id = "crunch", a = { time = -4, chance = 0.6, failWork = -5 }, b = {} },
		{ id = "playtest", a = { focus = "gameplay", work = 6, time = 3 }, b = {} },
		{ id = "streamer", a = { focus = "all", work = 3 }, b = {} },
	} :: { DevEvent },
}

return DevEvents
