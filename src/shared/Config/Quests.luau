--!strict
-- Задания (issue #9): 15 постоянных + пул ежедневных (3 в день, смена в 00:00 UTC).
-- Денежные награды — в «минутах дохода» (Config/Rewards): в #9 суммы даны для офиса,
-- где минута дохода ≈ $1 000, отсюда пересчёт ($300 -> 0.3 мин и т.д.).
--
-- kind — как считается прогресс (QuestService):
--   gamesReleased   — всего выпущено игр (profile.gamesReleased)
--   upgrades        — куплено апгрейдов
--   upgradeOwned    — куплен апгрейд upgradeId
--   bestScore       — лучшая оценка >= target
--   employees       — сотрудников в команде (TODO #7: QuestService.onEmployeesChanged)
--   sessionEarnings — заработано денег за сессию
-- События релиза (QuestService.onGameReleased):
--   greatCombo      — игр с «отличным» сочетанием (fit темы >= Quests.greatComboFit)
--   genreGames      — игр в жанре genreId
--   distinctGenres  — разных жанров
--   comboGames      — игр в жанре genreId с темой topicId
--   scoreStreak     — игр подряд с оценкой >= minScore

local Rewards = require(script.Parent.Rewards)

export type Reward = Rewards.Reward

export type Quest = {
	id: string,
	kind: string,
	target: number,
	genreId: string?,
	topicId: string?,
	upgradeId: string?,
	minScore: number?,
	name: string,
	nameEn: string,
	reward: Reward,
}

-- Ежедневное задание. Подстановки в названии: {target}, {genre}, {percent}, {score}.
-- dailyGenre = true — жанр дня выбирается из открытых жанров игрока.
export type DailyQuest = {
	id: string,
	kind: string, -- releaseGames | earnIncome | soundFocus | scoreInGenre | scoreAtLeast | greatCombo
	target: number, -- для earnIncome — минут дохода (сумма считается при выдаче)
	minScore: number?,
	minFocus: number?,
	dailyGenre: boolean?,
	name: string,
	nameEn: string,
}

local Quests = {}

Quests.greatComboFit = 1.2
Quests.dailyCount = 3
Quests.dailyReward = { incomeMinutes = 15 } :: Reward

Quests.list = {
	{
		id = "first_game",
		kind = "gamesReleased",
		target = 1,
		name = "Выпусти первую игру",
		nameEn = "Release your first game",
		reward = { incomeMinutes = 0.3 },
	},
	{
		id = "upgrades_3",
		kind = "upgrades",
		target = 3,
		name = "Купи 3 апгрейда",
		nameEn = "Buy 3 upgrades",
		reward = { incomeMinutes = 0.5 },
	},
	{
		id = "score_7",
		kind = "bestScore",
		target = 7,
		name = "Получи оценку 7+",
		nameEn = "Get a score of 7+",
		reward = { incomeMinutes = 0.8 },
	},
	{
		id = "great_combo",
		kind = "greatCombo",
		target = 1,
		name = "Выпусти игру с отличным сочетанием жанр + тема",
		nameEn = "Release a game with a great genre + topic combo",
		reward = { researchPoints = 10 },
	},
	{
		id = "rpg_3",
		kind = "genreGames",
		genreId = "rpg",
		target = 3,
		name = "Выпусти 3 игры в жанре RPG",
		nameEn = "Release 3 RPG games",
		reward = { incomeMinutes = 2 },
	},
	{
		id = "first_employee",
		kind = "employees",
		target = 1,
		name = "Найми первого сотрудника",
		nameEn = "Hire your first employee",
		reward = { incomeMinutes = 1.5 },
	},
	{
		id = "office",
		kind = "upgradeOwned",
		upgradeId = "office",
		target = 1,
		name = "Переедь в офис",
		nameEn = "Move to an office",
		reward = { researchPoints = 25 },
	},
	{
		id = "score_10",
		kind = "bestScore",
		target = 10,
		name = "Получи 10/10",
		nameEn = "Get a 10/10",
		reward = { incomeMinutes = 5, badge = "masterpiece" },
	},
	{
		id = "genres_5",
		kind = "distinctGenres",
		target = 5,
		name = "Выпусти игры в 5 разных жанрах",
		nameEn = "Release games in 5 different genres",
		reward = { researchPoints = 30 },
	},
	{
		id = "games_25",
		kind = "gamesReleased",
		target = 25,
		name = "Выпусти 25 игр",
		nameEn = "Release 25 games",
		reward = { incomeMinutes = 10 },
	},
	{
		id = "horror_ghosts",
		kind = "comboGames",
		genreId = "horror",
		topicId = "ghosts",
		target = 1,
		name = "Выпусти хоррор с темой «Призраки»",
		nameEn = "Release a horror game about ghosts",
		reward = { incomeMinutes = 8 },
	},
	{
		id = "full_team",
		kind = "employees",
		target = 4,
		name = "Собери полную команду офиса (4 сотрудника)",
		nameEn = "Build a full office team (4 employees)",
		reward = { researchPoints = 50 },
	},
	{
		id = "streak_8",
		kind = "scoreStreak",
		minScore = 8,
		target = 3,
		name = "Сделай 3 игры подряд с оценкой 8+",
		nameEn = "Make 3 games in a row scoring 8+",
		reward = { incomeMinutes = 15 },
	},
	{
		id = "session_100k",
		kind = "sessionEarnings",
		target = 100_000,
		name = "Заработай $100 000 за одну сессию",
		nameEn = "Earn $100,000 in one session",
		reward = { incomeBonus = 0.05 },
	},
	{
		id = "games_100",
		kind = "gamesReleased",
		target = 100,
		name = "Выпусти 100 игр",
		nameEn = "Release 100 games",
		reward = { employee = "ghost_coder" }, -- легендарный «Призрачный кодер» (#7)
	},
} :: { Quest }

Quests.dailyPool = {
	{
		id = "release_3",
		kind = "releaseGames",
		target = 3,
		name = "Выпусти {target} игры",
		nameEn = "Release {target} games",
	},
	{
		id = "release_5",
		kind = "releaseGames",
		target = 5,
		name = "Выпусти {target} игр",
		nameEn = "Release {target} games",
	},
	{
		id = "earn_10",
		kind = "earnIncome",
		target = 10,
		name = "Заработай {target}",
		nameEn = "Earn {target}",
	},
	{
		id = "sound_40",
		kind = "soundFocus",
		minFocus = 0.4,
		target = 1,
		name = "Сделай игру со звуком ≥ {percent}%",
		nameEn = "Make a game with sound ≥ {percent}%",
	},
	{
		id = "genre_day_8",
		kind = "scoreInGenre",
		minScore = 8,
		dailyGenre = true,
		target = 1,
		name = "Получи {score}+ в жанре дня: {genre}",
		nameEn = "Score {score}+ in the genre of the day: {genre}",
	},
	{
		id = "score_7_x2",
		kind = "scoreAtLeast",
		minScore = 7,
		target = 2,
		name = "Выпусти {target} игры с оценкой {score}+",
		nameEn = "Release {target} games scoring {score}+",
	},
	{
		id = "great_combo_day",
		kind = "greatCombo",
		target = 1,
		name = "Выпусти игру с отличным сочетанием",
		nameEn = "Release a game with a great combo",
	},
} :: { DailyQuest }

function Quests.find(id: string): Quest?
	for _, quest in Quests.list do
		if quest.id == id then
			return quest
		end
	end
	return nil
end

function Quests.findDaily(id: string): DailyQuest?
	for _, quest in Quests.dailyPool do
		if quest.id == id then
			return quest
		end
	end
	return nil
end

return Quests
