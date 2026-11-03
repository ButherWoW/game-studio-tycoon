--!strict
-- Звуки и музыка (задача 5.6, ключи — issue #22). id = 0 — звука ещё нет, play() молчит.
-- Asset ID пришлёт Dev 1; брать только звуки от автора Roblox.

export type Sound = {
	id: number,
	volume: number,
	looped: boolean?,
}

local Sounds = {}

Sounds.list = {
	click = { id = 0, volume = 0.4 }, -- любая кнопка UI
	card_select = { id = 0, volume = 0.4 }, -- выбор жанра или темы
	unlock = { id = 0, volume = 0.6 }, -- открыли жанр или тему
	buy = { id = 0, volume = 0.6 }, -- купили апгрейд
	cant_afford = { id = 0, volume = 0.5 }, -- не хватает денег
	dev_start = { id = 0, volume = 0.6 }, -- старт разработки
	dev_tick = { id = 0, volume = 0.15 }, -- раз в несколько секунд разработки (тихо)
	critic_reveal = { id = 0, volume = 0.5 }, -- открылась оценка критика
	score_low = { id = 0, volume = 0.6 }, -- итог 1–4
	score_mid = { id = 0, volume = 0.6 }, -- итог 5–7
	score_high = { id = 0, volume = 0.7 }, -- итог 8–10
	money = { id = 0, volume = 0.6 }, -- начислен доход
	record = { id = 0, volume = 0.7 }, -- новый рекорд студии
	move_office = { id = 0, volume = 0.8 }, -- переезд в офис
	music_garage = { id = 0, volume = 0.25, looped = true }, -- фон в гараже
} :: { [string]: Sound }

-- Тайминги звуков, привязанных к событиям
Sounds.devTickInterval = 4 -- пауза между dev_tick во время разработки, секунд
Sounds.criticRevealDelay = 0.6 -- совпадает с REVEAL_DELAY в ReleaseWindow
Sounds.scoreLowMax = 4 -- итог 1..4 — score_low
Sounds.scoreMidMax = 7 -- 5..7 — score_mid, выше — score_high
Sounds.moneyDelay = 0.4 -- пауза между итогом и звуком денег

return Sounds
