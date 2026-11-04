--!strict
-- Холдинги — объединения студий (HoldingService на сервере, HoldingPanel во вкладке «🏘 Студии»).
-- Запись холдинга — DataStore Holdings_v1 (ключ — id холдинга), очки недели — OrderedDataStore
-- HoldingsWeekly_<weekId>. Неделя — как у рейтингов (Tours.weekId, UTC, с понедельника).

local Holdings = {}

-- Создать холдинг: столько денег и этап студии не ниже офиса
Holdings.createCost = 1_000_000
Holdings.minStudioLevel = 2
Holdings.maxMembers = 10
Holdings.nameMin = 3
Holdings.nameMax = 20

-- Очки недели: за каждую игру участника и ещё за совместную игру двух участников
Holdings.pointsPerGame = 1
Holdings.pointsPerCoopGame = 3

-- Цели недели: points очков холдинга — каждому участнику minutes минут его дохода
Holdings.goals = {
	{ points = 20, minutes = 10 },
	{ points = 60, minutes = 20 },
	{ points = 150, minutes = 40 },
} :: { { points: number, minutes: number } }

-- Накопленные очки уходят в DataStore раз в flushSeconds; запись холдинга перечитывается
-- раз в refreshSeconds; топ холдингов — раз в boardSeconds
Holdings.flushSeconds = 60
Holdings.refreshSeconds = 180
Holdings.boardSeconds = 300
Holdings.boardSize = 20

-- Приглашение в холдинг висит столько секунд
Holdings.inviteSeconds = 30
Holdings.actionCooldown = 2

-- Табличка над головой: выше, если там уже VIP-табличка (VipService, StudsOffset 3)
Holdings.tagOffset = 3
Holdings.tagOffsetVip = 4
Holdings.tagMaxDistance = 60
Holdings.tagColor = Color3.fromRGB(140, 200, 255)

return Holdings
