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
| AdCampaigns | `social` | Developer Product | 3728447783 | 3728498032 |
| AdCampaigns | `streamers` | Developer Product | 3728447889 | 3728498043 |
| AdCampaigns | `tv` | Developer Product | 3728447939 | 3728498063 |
| AdCampaigns | `worldwide` | Developer Product | 3728447942 | 3728498075 |
| Console | `consoleSpeed5` | Developer Product | 3728502848 | 3728503139 |
| Console | `consoleSpeed30` | Developer Product | 3728502968 | 3728503201 |
| Console | `consoleSkip` | Developer Product | 3728503072 | 3728503265 |
| Construction | `buildSpeed5` | Developer Product | 3728500645 | 3728500862 |
| Construction | `buildSpeed30` | Developer Product | 3728500661 | 3728500873 |
| Construction | `buildSkip` | Developer Product | 3728500681 | 3728500885 |
| FurnitureStyles | `neon` | Developer Product | 3728447945 | 3728498090 |
| GamePasses | `doubleCash` | GamePass | 2071008855 | 2070540998 |
| GamePasses | `autoRelease` | GamePass | 2072480376 | 2071816553 |
| GamePasses | `fastDev` | GamePass | 2067092439 | 2070314173 |
| GamePasses | `extraSlot` | GamePass | 2068496428 | 2072234478 |
| GamePasses | `vipOffice` | GamePass | 2070720897 | 2071640568 |
| GamePasses | `legendaryEmployee` | GamePass | 2070314109 | 2068652542 |
| InteriorFinishes | `obsidianGold` | Developer Product | 3728485040 | 3728498631 |
| InteriorFinishes | `sakura` | Developer Product | 3728485054 | 3728498643 |
| InteriorFinishes | `aurora` | Developer Product | 3728485064 | 3728498658 |
| Mascots | `neon_fox` | Developer Product | 3728447955 | 3728498102 |
| Mascots | `dragon_byte` | Developer Product | 3728447957 | 3728498122 |
| Mascots | `golden_trophy` | Developer Product | 3728447964 | 3728498132 |
| Mascots | `cosmic_whale` | Developer Product | 3728447966 | 3728498151 |
| Posters | `neonCity` | Developer Product | 3728447969 | 3728498871 |
| Posters | `crystalKingdom` | Developer Product | 3728447971 | 3728498165 |
| Posters | `mechTitan` | Developer Product | 3728447973 | 3728498888 |
| Posters | `galaxyLegends` | Developer Product | 3728447981 | 3728498244 |
| Posters | `goldenController` | Developer Product | 3728447985 | 3728498256 |
| Products | `instantFinish` | Developer Product | 3728447988 | 3728498272 |
| Products | `patch` | Developer Product | 3728447989 | 3728498290 |
| Products | `coffee` | Developer Product | 3728447993 | 3728498309 |
| Products | `income10` | Developer Product | 3728447996 | 3728498324 |
| Products | `income30` | Developer Product | 3728447999 | 3728498349 |
| Products | `income90` | Developer Product | 3728448002 | 3728498365 |
| Products | `offers.doubleRelease` | Developer Product | 3728448015 | 3728498380 |
| Products | `offers.starterPack` | Developer Product | 3728448017 | 3728498901 |
| Products | `deals.instantFinish` | Developer Product | 3728448020 | 3728498397 |
| Products | `deals.patch` | Developer Product | 3728448022 | 3728498414 |
| Products | `deals.coffee` | Developer Product | 3728448025 | 3728498434 |
| Products | `deals.income10` | Developer Product | 3728448031 | 3728498444 |
| Products | `deals.income30` | Developer Product | 3728448038 | 3728498458 |
| Products | `deals.income90` | Developer Product | 3728448040 | 3728498477 |
| Products | `deals.poster_neonCity` | Developer Product | 3728448052 | 3728498495 |
| Products | `deals.poster_crystalKingdom` | Developer Product | 3728448055 | 3728498515 |
| Products | `deals.poster_mechTitan` | Developer Product | 3728448058 | 3728498524 |
| Products | `deals.poster_galaxyLegends` | Developer Product | 3728448061 | 3728498540 |
| Products | `deals.poster_goldenController` | Developer Product | 3728448065 | 3728498556 |
| Products | `deals.skin_neon_streamer` | Developer Product | 3728448066 | 3728498572 |
| Products | `deals.skin_cyber_dev` | Developer Product | 3728448069 | 3728498585 |
| Products | `deals.skin_space_dev` | Developer Product | 3728448070 | 3728498600 |
| Products | `deals.skin_wizard_dev` | Developer Product | 3728448090 | 3728498619 |
| Products | `researchSpeed5` | Developer Product | 3728500562 | 3728500791 |
| Products | `researchSpeed30` | Developer Product | 3728500582 | 3728500806 |
| Products | `researchSkip` | Developer Product | 3728500600 | 3728500828 |
| Season | `seasonPass` | Developer Product | 3728448106 | 3728498962 |
| Season | `seasonSkip` | Developer Product | 3728448111 | 3728498976 |
| Skins | `neon_streamer` | Developer Product | 3728448093 | 3728498913 |
| Skins | `cyber_dev` | Developer Product | 3728448098 | 3728498923 |
| Skins | `space_dev` | Developer Product | 3728448101 | 3728498933 |
| Skins | `wizard_dev` | Developer Product | 3728448105 | 3728498948 |
| Social | `gift_neon_streamer` | Developer Product | 3728497737 | 3728498672 |
| Social | `gift_cyber_dev` | Developer Product | 3728497750 | 3728498688 |
| Social | `gift_space_dev` | Developer Product | 3728497769 | 3728498698 |
| Social | `gift_wizard_dev` | Developer Product | 3728497787 | 3728498712 |
| Social | `gift_neonCity` | Developer Product | 3728497804 | 3728498731 |
| Social | `gift_crystalKingdom` | Developer Product | 3728497819 | 3728498751 |
| Social | `gift_mechTitan` | Developer Product | 3728497831 | 3728498769 |
| Social | `gift_galaxyLegends` | Developer Product | 3728497863 | 3728498785 |
| Social | `gift_goldenController` | Developer Product | 3728497878 | 3728498804 |
| Social | `gift_neon_fox` | Developer Product | 3728497891 | 3728498815 |
| Social | `gift_dragon_byte` | Developer Product | 3728497896 | 3728498830 |
| Social | `gift_golden_trophy` | Developer Product | 3728497908 | 3728498845 |
| Social | `gift_cosmic_whale` | Developer Product | 3728497923 | 3728498858 |
| Training | `skillSkip` | Developer Product | 3728500528 | 3728500763 |
| Training | `skillSkipAll` | Developer Product | 3728500547 | 3728500777 |

Всего записей: 76; создано в test: 76; заполнено в main: 76.
<!-- ids:end -->
