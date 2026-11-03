--!strict
-- Вымышленные игровые издания и их фразы (задача B из docs/DEV2_NEXT.md).
-- 4 издания × 4 диапазона оценок × 3 фразы, RU + EN. Подстановки: {genre}, {topic}.
-- Диапазоны: low 1–3, mid 4–6, good 7–8, top 9–10.

export type Phrase = { ru: string, en: string }
export type Critic = {
	id: string,
	name: string,
	nameEn: string,
	mood: string, -- характер, для художника и озвучки
	phrases: { low: { Phrase }, mid: { Phrase }, good: { Phrase }, top: { Phrase } },
}

local Critics: { Critic } = {
	{
		id = "herald",
		name = "Пиксельный Вестник",
		nameEn = "Pixel Herald",
		mood = "строгий критик старой школы, скуп на похвалу",
		phrases = {
			low = {
				{
					ru = "Мы ждали {genre}, а получили недоразумение.",
					en = "We expected {genre}. We got a misunderstanding.",
				},
				{
					ru = "Тема «{topic}» заслуживала лучшего.",
					en = "The {topic} theme deserved better.",
				},
				{
					ru = "Удалили после пяти минут. Это были долгие минуты.",
					en = "Uninstalled after five minutes. Long minutes.",
				},
			},
			mid = {
				{
					ru = "Крепкий середнячок, но без души.",
					en = "Solid, average, soulless.",
				},
				{
					ru = "Видно старание, не видно идеи.",
					en = "We see the effort, not the idea.",
				},
				{
					ru = "Для {genre} маловато. Для первого раза — сойдёт.",
					en = "Thin for {genre}. Fine for a first try.",
				},
			},
			good = {
				{
					ru = "Редкий случай, когда {topic} и {genre} дружат.",
					en = "A rare case where {topic} and {genre} get along.",
				},
				{
					ru = "Добротная работа. Ставим на полку рядом с классикой.",
					en = "Good craft. It goes on the shelf next to the classics.",
				},
				{
					ru = "Есть шероховатости, но играть хочется.",
					en = "Rough edges, but we kept playing.",
				},
			},
			top = {
				{
					ru = "Мы не ставим высоких оценок. Сегодня исключение.",
					en = "We don't give high scores. Today is an exception.",
				},
				{
					ru = "Эталон жанра {genre}. Учебники перепишут.",
					en = "The new {genre} benchmark. Textbooks will be rewritten.",
				},
				{
					ru = "Безупречно. Даже придраться не к чему.",
					en = "Flawless. Nothing left to nitpick.",
				},
			},
		},
	},
	{
		id = "gamertime",
		name = "ГеймерТайм",
		nameEn = "GamerTime",
		mood = "восторженный молодёжный блог, много эмоций",
		phrases = {
			low = {
				{
					ru = "Ну такое… даже мемы не спасли.",
					en = "Meh… not even memes could save it.",
				},
				{
					ru = "Чат уснул на первой минуте стрима.",
					en = "Chat fell asleep in minute one of the stream.",
				},
				{ ru = "{topic}? Серьёзно? В {genre}?", en = "{topic}? Seriously? In {genre}?" },
			},
			mid = {
				{
					ru = "На вечерок пойдёт, но друзьям не советуем.",
					en = "Fine for an evening, but we won't tell our friends.",
				},
				{
					ru = "Есть пара крутых моментов, остальное — так себе.",
					en = "A couple of cool moments, the rest is so-so.",
				},
				{ ru = "Ставим лайк за старание!", en = "A like for the effort!" },
			},
			good = {
				{
					ru = "Залипли до трёх ночи. Это успех!",
					en = "Played till 3 AM. That's a win!",
				},
				{
					ru = "{topic} — это вайб! Ждём продолжение.",
					en = "{topic} is a vibe! Sequel when?",
				},
				{
					ru = "Чат требует ещё один стрим по этой игре.",
					en = "Chat demands another stream of this one.",
				},
			},
			top = {
				{
					ru = "ЭТО ШЕДЕВР!!! Капслок не выключаем.",
					en = "MASTERPIECE!!! Caps lock stays on.",
				},
				{
					ru = "Игра года? Игра десятилетия!",
					en = "Game of the year? Game of the decade!",
				},
				{
					ru = "Лучший {genre}, во что мы играли. Точка.",
					en = "The best {genre} we've ever played. Period.",
				},
			},
		},
	},
	{
		id = "cube",
		name = "Кубик Ревью",
		nameEn = "Cube Review",
		mood = "добрый семейный журнал, ищет хорошее даже в плохом",
		phrases = {
			low = {
				{
					ru = "Всё получится в следующий раз, мы верим!",
					en = "Next time it'll work out, we believe in you!",
				},
				{ ru = "Зато обложка милая.", en = "At least the cover is cute." },
				{
					ru = "Даже у великих студий бывают неудачи.",
					en = "Even great studios have bad days.",
				},
			},
			mid = {
				{
					ru = "Детям понравится, взрослым — может быть.",
					en = "Kids will like it. Adults — maybe.",
				},
				{
					ru = "Уютная игра про {topic}, но без сюрпризов.",
					en = "A cozy {topic} game, no surprises.",
				},
				{
					ru = "Хороший старт, видно, что авторы растут.",
					en = "A good start — the team is clearly growing.",
				},
			},
			good = {
				{
					ru = "Играли всей семьёй. Бабушка тоже!",
					en = "The whole family played. Grandma too!",
				},
				{
					ru = "Добрая и продуманная. Таких игр не хватает.",
					en = "Kind and thoughtful. We need more of these.",
				},
				{
					ru = "Отличный {genre} для любого возраста.",
					en = "A great {genre} for any age.",
				},
			},
			top = {
				{
					ru = "Игра, после которой хочется улыбаться.",
					en = "A game that leaves you smiling.",
				},
				{
					ru = "Подарок для всех, кто любит {topic}.",
					en = "A gift to everyone who loves {topic}.",
				},
				{
					ru = "Пять звёзд из пяти и ещё одна сверху.",
					en = "Five stars out of five, plus one more.",
				},
			},
		},
	},
	{
		id = "hardcore",
		name = "Хардкор Дайджест",
		nameEn = "Hardcore Digest",
		mood = "циничный и саркастичный, видел всё",
		phrases = {
			low = {
				{
					ru = "Купили. Пожалели. Пишем обзор, чтобы вы не повторили.",
					en = "Bought it. Regretted it. Writing this so you don't.",
				},
				{
					ru = "{genre} про {topic}. Звучало плохо — так и вышло.",
					en = "{topic} {genre}. Sounded bad, turned out exactly so.",
				},
				{
					ru = "Лучшая часть игры — кнопка «Выход».",
					en = "Best feature: the Quit button.",
				},
			},
			mid = {
				{
					ru = "Ничего нового. Но и ничего ужасного.",
					en = "Nothing new. Nothing terrible either.",
				},
				{
					ru = "Сойдёт, если всё остальное уже пройдено.",
					en = "Fine if you've already played everything else.",
				},
				{
					ru = "Проходняк с проблесками таланта.",
					en = "Filler with flashes of talent.",
				},
			},
			good = {
				{
					ru = "Ладно, признаём: зацепило.",
					en = "Fine, we admit it: it hooked us.",
				},
				{
					ru = "Неожиданно умно для {genre}.",
					en = "Surprisingly smart for {genre}.",
				},
				{
					ru = "Мы искали, к чему придраться. Почти не нашли.",
					en = "We looked for flaws. Barely found any.",
				},
			},
			top = {
				{
					ru = "Мы разучились ворчать. Спасибо, нам это не нравится.",
					en = "We forgot how to grumble. Thanks, we hate it.",
				},
				{
					ru = "Редкая игра, за которую не стыдно перед индустрией.",
					en = "A rare game the industry can be proud of.",
				},
				{
					ru = "Сарказм выключен. Это просто очень хорошо.",
					en = "Sarcasm off. This is just really good.",
				},
			},
		},
	},
}

return Critics
