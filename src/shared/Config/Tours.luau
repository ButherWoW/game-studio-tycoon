--!strict
-- Экскурсии по студиям, лайки и глобальные рейтинги (TourService на сервере, TourWindow на клиенте).
-- Неделя и день — по UTC: неделя с понедельника (Tours.weekId), день — os.time() // 86400.
-- Данные в профиле (лениво, defaultProfile не трогаем):
--   likes = { total, week = { weekId, count } } — лайки владельцу студии;
--   tours = { day, given = { [ownerUserId] = true }, rewardWeek, badgeWeeklyStar, hit = { weekId, value } }.

local Tours = {}

-- Кнопка «Посетить»: не чаще раза в visitCooldown секунд
Tours.visitCooldown = 5
-- Лайк из списка — после стольких секунд на участке владельца (на самом участке — сразу)
Tours.likeAfterSeconds = 10
-- Сколько последних посещённых студий (владелец уже вышел) помнить для лайка из списка
Tours.recentLimit = 5

-- Лайки владельцу, который вышел: копятся в памяти и раз в queueFlushSeconds уходят
-- одним UpdateAsync в DataStore Likes_v1 (ключ — userId); при следующем входе сливаются в профиль
Tours.queueFlushSeconds = 30

-- Глобальные рейтинги (OrderedDataStore): запись игрока не чаще writeSeconds и только если
-- значение изменилось; топ читается раз в readSeconds на сервер
Tours.writeSeconds = 5 * 60
Tours.readSeconds = 5 * 60
Tours.topSize = 50
-- Стоимость студии (апгрейды + этажи + деньги) — не больше этого (OrderedDataStore хранит целые)
Tours.valueCap = 1e15
-- Лучший хит недели: оценка × hitScoreFactor + очки игры (не больше hitScoreFactor − 1)
Tours.hitScoreFactor = 1000000

-- Награда недели: топ-weeklyTop по лайкам прошлой недели получает минуты дохода и значок ⭐
Tours.weeklyTop = 10
Tours.weeklyRewardMinutes = 30

-- Табличка «👍 N» справа от вывески студии (как SIGN_OFFSET в StartParkService)
Tours.signOffset = CFrame.new(10, 17, 29.5)
Tours.signSize = Vector2.new(3.6, 2.2)

-- Доска «👍 Студии недели» в парке: место относительно спавна (как точки в Config/StartPark).
-- nil — доску не ставим
Tours.parkBoard = { position = Vector3.new(-14, 0, 17), yaw = 180, rows = 10 } :: {
	position: Vector3,
	yaw: number,
	rows: number,
}?

local DAY = 86400
local WEEK = 7 * DAY
-- 1 января 1970 — четверг: сдвиг на 3 дня, чтобы неделя начиналась с понедельника
local WEEK_SHIFT = 3 * DAY

function Tours.weekId(now: number?): number
	return ((now or os.time()) + WEEK_SHIFT) // WEEK
end

function Tours.dayId(now: number?): number
	return (now or os.time()) // DAY
end

-- Секунд до начала следующей недели (для подписи «до конца недели»)
function Tours.weekLeft(now: number?): number
	local t = now or os.time()
	return (Tours.weekId(t) + 1) * WEEK - WEEK_SHIFT - t
end

return Tours
