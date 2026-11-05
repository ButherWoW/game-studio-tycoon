--!strict
-- Звуки и музыка (задача 5.6, ключи — issue #22). id = 0 — звука ещё нет, play() молчит.
-- Все ID — звуки от автора Roblox (user 1) из Creator Store, бесплатные, подходят для любой игры (05.11, Dev 1).

export type Sound = {
	id: number,
	volume: number,
	looped: boolean?,
}

local Sounds = {}

Sounds.list = {
	click = { id = 15675032796, volume = 0.4 }, -- любая кнопка UI
	card_select = { id = 10066968815, volume = 0.4 }, -- выбор жанра или темы
	unlock = { id = 17208327798, volume = 0.6 }, -- открыли жанр или тему
	buy = { id = 10066947742, volume = 0.6 }, -- купили апгрейд
	cant_afford = { id = 17208353912, volume = 0.5 }, -- не хватает денег
	dev_start = { id = 16480577565, volume = 0.6 }, -- старт разработки
	dev_tick = { id = 16480551554, volume = 0.15 }, -- раз в несколько секунд разработки (тихо)
	critic_reveal = { id = 15675028888, volume = 0.5 }, -- открылась оценка критика
	score_low = { id = 17208214688, volume = 0.6 }, -- итог 1–4
	score_mid = { id = 17208361335, volume = 0.6 }, -- итог 5–7
	score_high = { id = 12222253, volume = 0.7 }, -- итог 8–10
	money = { id = 127645268874265, volume = 0.6 }, -- начислен доход
	record = { id = 15675043410, volume = 0.7 }, -- новый рекорд студии
	move_office = { id = 16480578036, volume = 0.8 }, -- переезд в офис
	music_garage = { id = 15675069601, volume = 0.25, looped = true }, -- фон в гараже
} :: { [string]: Sound }

-- Тайминги звуков, привязанных к событиям
Sounds.devTickInterval = 4 -- пауза между dev_tick во время разработки, секунд
Sounds.criticRevealDelay = 0.6 -- совпадает с REVEAL_DELAY в ReleaseWindow
Sounds.scoreLowMax = 4 -- итог 1..4 — score_low
Sounds.scoreMidMax = 7 -- 5..7 — score_mid, выше — score_high
Sounds.moneyDelay = 0.4 -- пауза между итогом и звуком денег

return Sounds
