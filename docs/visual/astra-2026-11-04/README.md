# Game Studio Tycoon — комплект визуала V1–V6

38 PNG по заданию docs/VISUAL.md. Создано 4 ноября 2026 через встроенный OpenAI ImageGen; экспорт размеров — macOS sips. Цвета ниже — целевая палитра из задания, не замер каждого пикселя.

## Состав

| Раздел | Файлов | Формат |
| --- | ---: | --- |
| V1 — варианты иконки | 3 | 512×512 |
| V2 — рекламные превью | 5 | 1920×1080 |
| V3 — иконки меню | 11 | 256×256, прозрачность |
| V4 — макеты окон | 10 | 1920×1080 / 844×390 |
| V5 — концепты локаций | 5 | 1920×1080 |
| V6 — раскадровки | 4 | 1920×1080 |

## Передача разработчикам

V1–V2: выбрать иконку и загрузить изображения на страницу игры. V3: загрузить PNG в Roblox и передать ID разработчику интерфейса. V4: визуальные макеты для реализации; текст и шрифты нужно задавать настоящими элементами интерфейса, сохраняя локализацию. Начертания на картинках приблизительные, файлы шрифтов не входят. Внешние панели вокруг некоторых окон иллюстративные; функциональный состав брать из docs/VISUAL.md и текущего кода. V5: художественные концепты, размеры в studs нужно выдерживать при сборке в Studio. V6: четыре кадра на эффект, это раскадровки, а не готовые анимации.

Файлы локальные; в GitHub и Roblox не загружались.

## Каталог

- [V1/icon_v1.png](V1/icon_v1.png) — Крупный план разработчика за компьютером. Палитра: #FFC93C, #3D7BFF, #A0703C.
- [V1/icon_v2.png](V1/icon_v2.png) — Фронтальный персонаж со звёздами. Палитра: #FFC93C, #3D7BFF, #FFD9A0.
- [V1/icon_v3.png](V1/icon_v3.png) — Рабочее место в открытом гараже. Палитра: #FFC93C, #3D7BFF, #A0703C.
- [V2/thumb_1_garage.png](V2/thumb_1_garage.png) — Гараж и первый успешный релиз. Палитра: #3D7BFF, #FFC93C, #A0703C.
- [V2/thumb_2_grow.png](V2/thumb_2_grow.png) — Рост от гаража до небоскрёба. Палитра: #3D7BFF, #FFC93C, #A0703C.
- [V2/thumb_3_team.png](V2/thumb_3_team.png) — Команда разработчиков. Палитра: #3D7BFF, #FFC93C, #A0703C.
- [V2/thumb_4_steal.png](V2/thumb_4_steal.png) — Шуточная погоня за картриджем. Палитра: #3D7BFF, #FFC93C, #A0703C.
- [V2/thumb_5_expo.png](V2/thumb_5_expo.png) — Выставка и приз $15,000. Палитра: #3D7BFF, #FFC93C, #A0703C.
- [V3/menu_research.png](V3/menu_research.png) — Колба исследований. Палитра: #1E1E2E, #3D7BFF, #FFC93C, #3DDC84, #9650DC.
- [V3/menu_team.png](V3/menu_team.png) — Два сотрудника. Палитра: #1E1E2E, #3D7BFF, #FFC93C, #3DDC84, #9650DC.
- [V3/menu_quests.png](V3/menu_quests.png) — Планшет с галочкой. Палитра: #1E1E2E, #3D7BFF, #FFC93C, #3DDC84, #9650DC.
- [V3/menu_shop.png](V3/menu_shop.png) — Тележка магазина. Палитра: #1E1E2E, #3D7BFF, #FFC93C, #3DDC84, #9650DC.
- [V3/menu_rebirth.png](V3/menu_rebirth.png) — Круговые стрелки перезапуска. Палитра: #1E1E2E, #3D7BFF, #FFC93C, #3DDC84, #9650DC.
- [V3/menu_language.png](V3/menu_language.png) — Глобус выбора языка. Палитра: #1E1E2E, #3D7BFF, #FFC93C, #3DDC84, #9650DC.
- [V3/menu_hits.png](V3/menu_hits.png) — Картридж с замком. Палитра: #1E1E2E, #3D7BFF, #FFC93C, #3DDC84, #9650DC.
- [V3/menu_thieves.png](V3/menu_thieves.png) — Хитрая маска. Палитра: #1E1E2E, #3D7BFF, #FFC93C, #3DDC84, #9650DC.
- [V3/menu_holiday.png](V3/menu_holiday.png) — Праздничная хлопушка. Палитра: #1E1E2E, #3D7BFF, #FFC93C, #3DDC84, #9650DC.
- [V3/menu_camera.png](V3/menu_camera.png) — Кинокамера. Палитра: #1E1E2E, #3D7BFF, #FFC93C, #3DDC84, #9650DC.
- [V3/menu_bank.png](V3/menu_bank.png) — Банк с монетой. Палитра: #1E1E2E, #3D7BFF, #FFC93C, #3DDC84, #9650DC.
- [V4/hud_desktop.png](V4/hud_desktop.png) — Игровой HUD — компьютер. Палитра: #1E1E2E, #3E405A, #3D7BFF, #FFC93C, #FFFFFF, #B8BCD0.
- [V4/hud_mobile.png](V4/hud_mobile.png) — Игровой HUD — телефон. Палитра: #1E1E2E, #3E405A, #3D7BFF, #FFC93C, #FFFFFF, #B8BCD0.
- [V4/create_desktop.png](V4/create_desktop.png) — Окно создания игры — компьютер. Палитра: #1E1E2E, #3E405A, #3D7BFF, #FFC93C, #FFFFFF, #B8BCD0.
- [V4/create_mobile.png](V4/create_mobile.png) — Окно создания игры — телефон. Палитра: #1E1E2E, #3E405A, #3D7BFF, #FFC93C, #FFFFFF, #B8BCD0.
- [V4/release_desktop.png](V4/release_desktop.png) — Оценки критиков и доход — компьютер. Палитра: #1E1E2E, #3E405A, #3D7BFF, #FFC93C, #FFFFFF, #B8BCD0.
- [V4/release_mobile.png](V4/release_mobile.png) — Оценки критиков и доход — телефон. Палитра: #1E1E2E, #3E405A, #3D7BFF, #FFC93C, #FFFFFF, #B8BCD0.
- [V4/bank_desktop.png](V4/bank_desktop.png) — Предложение кредита — компьютер. Палитра: #1E1E2E, #3E405A, #3D7BFF, #FFC93C, #FFFFFF, #B8BCD0.
- [V4/bank_mobile.png](V4/bank_mobile.png) — Предложение кредита — телефон. Палитра: #1E1E2E, #3E405A, #3D7BFF, #FFC93C, #FFFFFF, #B8BCD0.
- [V4/team_desktop.png](V4/team_desktop.png) — Список найма сотрудников — компьютер. Палитра: #1E1E2E, #3E405A, #3D7BFF, #FFC93C, #FFFFFF, #B8BCD0.
- [V4/team_mobile.png](V4/team_mobile.png) — Список найма сотрудников — телефон. Палитра: #1E1E2E, #3E405A, #3D7BFF, #FFC93C, #FFFFFF, #B8BCD0.
- [V5/concept_park.png](V5/concept_park.png) — Стартовый парк: ноутбуки, фонтан, доска заданий, ломбард. Палитра: #6BBF59, #D9C9A3, #9C6B3F.
- [V5/concept_garage_empty.png](V5/concept_garage_empty.png) — Пустой гараж с одним рабочим местом. Палитра: #A0703C, #8C8C8C, #FFD9A0.
- [V5/concept_garage_full.png](V5/concept_garage_full.png) — Гараж с четырьмя рабочими местами, кофе и полкой хитов. Палитра: #A0703C, #8C8C8C, #FFD9A0, #3D7BFF.
- [V5/concept_office.png](V5/concept_office.png) — Офис на восемь рабочих мест со стеклянной переговоркой. Палитра: #F2F2F2, #C8A27A, #4CAF50.
- [V5/concept_skyscraper.png](V5/concept_skyscraper.png) — Ночной этаж небоскрёба на 12 рабочих мест. Палитра: #141A2E, #7C4DFF, #00E5FF.
- [V6/fx_release.png](V6/fx_release.png) — Релиз: появление оценки и конфетти. Палитра: #3D7BFF, #FFC93C, #1E1E2E, #3DDC84, #FF5A5F.
- [V6/fx_money.png](V6/fx_money.png) — Доход: частицы летят к счётчику. Палитра: #3D7BFF, #FFC93C, #1E1E2E, #3DDC84, #FF5A5F.
- [V6/fx_move.png](V6/fx_move.png) — Переезд: вспышка и новая студия. Палитра: #3D7BFF, #FFC93C, #1E1E2E, #3DDC84, #FF5A5F.
- [V6/fx_strike.png](V6/fx_strike.png) — Забастовка: сотрудники с табличками и уведомление. Палитра: #3D7BFF, #FFC93C, #1E1E2E, #3DDC84, #FF5A5F.

