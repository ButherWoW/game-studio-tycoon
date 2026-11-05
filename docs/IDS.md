# ID товаров, геймпассов и значков в двух вселенных

Developer Products, GamePasses и Badges принадлежат **вселенной**: ID из тестовой вселенной
не работают в основной игре, и наоборот. Поэтому в конфигах хранятся оба набора, а нужный
выбирается сам при запуске по `game.GameId` — один и тот же билд работает в обоих плейсах.

| Вселенная | Universe ID (`game.GameId`) | Place ID | `Universe.current()` |
|---|---|---|---|
| Тестовая «Game Studio Tycoon v2» | 10774624686 | 75334772365832 | `"test"` |
| Основная «Game Studio Tycoon» | 10774551088 | 91848575533083 | `"main"` |
| Неопубликованный плейс в Studio | 0 | — | `"studio-unpublished"` (берёт test) |
| Любая другая | … | … | `"test"` + предупреждение в Output |

## Как это устроено

- `src/shared/Config/Universe.luau` — определяет вселенную один раз при первом `require`.
- В конфигах ID записаны парой:

  ```lua
  productId = Universe.pick({ test = 3728447988, main = 0 }),
  ```

  `Universe.pick` возвращает `main` в основной игре и `test` во всех остальных случаях.
  Остальной код видит обычное число — как раньше.
- **`main = 0` — товар в основной игре ещё не создан**: кнопка «Скоро»/предложение скрыто,
  квитанции с этим ID не ищутся. Тестовый ID в основной игре **не подставляется никогда**.
- Подарки (`Config/Social.luau`, `giftProducts`) и значки (`Config/Achievements.luau`,
  `badgeIds`) — таблицы `ключ = { test = ..., main = ... }`. Значка нет в `badgeIds` — достижение без значка.
- Квитанции (`ProcessReceipt` → `findByProduct` и т. п.) сравнивают с уже выбранным числом,
  поэтому совпадают только ID текущей вселенной, а 0 пропускается.
- Группа Roblox (`Social.groupId`) — одна на обе вселенные, пары нет.

## Что делает Dev 1 (основная игра)

1. В Creator Dashboard открыть вселенную **10774551088** («Game Studio Tycoon»).
2. Создать Developer Products и GamePasses с теми же названиями и ценами, что в тестовой v2
   (цены — `robuxPrice` в конфиге рядом с ID). Для подарков — «Gift: <название>», цена как у предмета.
3. Вписать ID в `main = ...` нужной строки (порядок `test`, потом `main` не менять — его читает скрипт).
   Найти строку: поиск по тестовому ID из таблицы ниже.
4. Перегенерировать таблицу: `python3 tools/list_ids.py --write`.
5. `stylua src && selene src && rojo build`, коммит, проверить в Studio (ниже).

Значки: добавить в `badgeIds` в `Config/Achievements.luau` строку
`office_2 = { test = <ID v2>, main = <ID основной> },` (ключ — id достижения).

## Проверить в Studio

- В `Config/Debug.luau` поставить `forceUniverse = "main"` — в Studio включится набор основной игры:
  всё, где `main = 0`, станет «Скоро»; `"test"` — тестовый; `nil` — по `game.GameId`.
  На живых серверах `forceUniverse` не действует.
- Покупки в Studio проходят только для товаров той вселенной, в которой опубликован открытый плейс.

## Таблица ID

Генерируется `python3 tools/list_ids.py --write` из конфигов — руками не править.
Пустая ячейка main — ещё не создан в основной игре; «—» в test — не создан и в тестовой.
Ключи `offers.*` и `deals.*` — `Products.offers` и скидочные копии `Products.deals` («Сделка дня»).

<!-- ids:begin -->
| Конфиг | Ключ | Тип | test (v2, 10774624686) | main (10774551088) |
|---|---|---|---|---|
| AdCampaigns | `social` | Developer Product | 3728447783 |  |
| AdCampaigns | `streamers` | Developer Product | 3728447889 |  |
| AdCampaigns | `tv` | Developer Product | 3728447939 |  |
| AdCampaigns | `worldwide` | Developer Product | 3728447942 |  |
| FurnitureStyles | `neon` | Developer Product | 3728447945 |  |
| GamePasses | `doubleCash` | GamePass | 2071008855 |  |
| GamePasses | `autoRelease` | GamePass | 2072480376 |  |
| GamePasses | `fastDev` | GamePass | 2067092439 |  |
| GamePasses | `extraSlot` | GamePass | 2068496428 |  |
| GamePasses | `vipOffice` | GamePass | 2070720897 |  |
| GamePasses | `legendaryEmployee` | GamePass | 2070314109 |  |
| InteriorFinishes | `obsidianGold` | Developer Product | 3728485040 |  |
| InteriorFinishes | `sakura` | Developer Product | 3728485054 |  |
| InteriorFinishes | `aurora` | Developer Product | 3728485064 |  |
| Mascots | `neon_fox` | Developer Product | 3728447955 |  |
| Mascots | `dragon_byte` | Developer Product | 3728447957 |  |
| Mascots | `golden_trophy` | Developer Product | 3728447964 |  |
| Mascots | `cosmic_whale` | Developer Product | 3728447966 |  |
| Posters | `neonCity` | Developer Product | 3728447969 |  |
| Posters | `crystalKingdom` | Developer Product | 3728447971 |  |
| Posters | `mechTitan` | Developer Product | 3728447973 |  |
| Posters | `galaxyLegends` | Developer Product | 3728447981 |  |
| Posters | `goldenController` | Developer Product | 3728447985 |  |
| Products | `instantFinish` | Developer Product | 3728447988 |  |
| Products | `patch` | Developer Product | 3728447989 |  |
| Products | `coffee` | Developer Product | 3728447993 |  |
| Products | `income10` | Developer Product | 3728447996 |  |
| Products | `income30` | Developer Product | 3728447999 |  |
| Products | `income90` | Developer Product | 3728448002 |  |
| Products | `offers.doubleRelease` | Developer Product | 3728448015 |  |
| Products | `offers.starterPack` | Developer Product | 3728448017 |  |
| Products | `deals.instantFinish` | Developer Product | 3728448020 |  |
| Products | `deals.patch` | Developer Product | 3728448022 |  |
| Products | `deals.coffee` | Developer Product | 3728448025 |  |
| Products | `deals.income10` | Developer Product | 3728448031 |  |
| Products | `deals.income30` | Developer Product | 3728448038 |  |
| Products | `deals.income90` | Developer Product | 3728448040 |  |
| Products | `deals.poster_neonCity` | Developer Product | 3728448052 |  |
| Products | `deals.poster_crystalKingdom` | Developer Product | 3728448055 |  |
| Products | `deals.poster_mechTitan` | Developer Product | 3728448058 |  |
| Products | `deals.poster_galaxyLegends` | Developer Product | 3728448061 |  |
| Products | `deals.poster_goldenController` | Developer Product | 3728448065 |  |
| Products | `deals.skin_neon_streamer` | Developer Product | 3728448066 |  |
| Products | `deals.skin_cyber_dev` | Developer Product | 3728448069 |  |
| Products | `deals.skin_space_dev` | Developer Product | 3728448070 |  |
| Products | `deals.skin_wizard_dev` | Developer Product | 3728448090 |  |
| Season | `seasonPass` | Developer Product | 3728448106 |  |
| Season | `seasonSkip` | Developer Product | 3728448111 |  |
| Skins | `neon_streamer` | Developer Product | 3728448093 |  |
| Skins | `cyber_dev` | Developer Product | 3728448098 |  |
| Skins | `space_dev` | Developer Product | 3728448101 |  |
| Skins | `wizard_dev` | Developer Product | 3728448105 |  |
| Social | `gift_neon_streamer` | Developer Product | — |  |
| Social | `gift_cyber_dev` | Developer Product | — |  |
| Social | `gift_space_dev` | Developer Product | — |  |
| Social | `gift_wizard_dev` | Developer Product | — |  |
| Social | `gift_neonCity` | Developer Product | — |  |
| Social | `gift_crystalKingdom` | Developer Product | — |  |
| Social | `gift_mechTitan` | Developer Product | — |  |
| Social | `gift_galaxyLegends` | Developer Product | — |  |
| Social | `gift_goldenController` | Developer Product | — |  |
| Social | `gift_neon_fox` | Developer Product | — |  |
| Social | `gift_dragon_byte` | Developer Product | — |  |
| Social | `gift_golden_trophy` | Developer Product | — |  |
| Social | `gift_cosmic_whale` | Developer Product | — |  |

Всего записей: 65; создано в test: 52; заполнено в main: 0.
<!-- ids:end -->
