# Аналитика к запуску

Что игра пишет в **Creator Dashboard → Analytics** (Roblox AnalyticsService), где это в коде и что смотреть в первую неделю.

- Код: `src/server/Services/AnalyticsService.luau` (единственный, кто зовёт `AnalyticsService:Log*`).
- Настройки, шаги, категории: `src/shared/Config/Analytics.luau`.
- События уходят только с опубликованного сервера. В Studio при `debugPrint = true` они печатаются в Output строками `[Analytics] …` и никуда не отправляются.
- Свой бюджет: не больше `60 + 10 × игроков` событий в минуту на сервер (лимит Roblox ≈ 120 + 20 × игроков). Экономика копится и уходит сводкой раз в 60 с и при выходе игрока. `endingBalance` в сводке один на все строки (баланс игрока на момент сводки, а не после конкретной транзакции) — осознанный компромисс: для разрезов по типу и SKU не мешает, метрики «по балансу» из этих строк строить нельзя.
- Старые профили (играли до аналитики) воронку не пишут, иначе она начнётся с середины.

## 1. Воронка новичка (Funnels → Onboarding)

`LogOnboardingFunnelStepEvent`. Шаги — строго по порядку и **один раз за жизнь игрока**: в профиле хранится номер последнего отправленного шага (`profile.analytics.funnel`). Достигнут шаг N — до него дошлются все пропущенные (например, наняли сотрудника раньше, чем ввели название, — «Studio Named» уйдёт перед «First Hire»). После Rebirth этап сбрасывается, но воронка уже не повторяется.

| № | Шаг (имя в дашборде) | Когда засчитывается |
| --- | --- | --- |
| 1 | Joined | профиль загрузился |
| 2 | Laptop Or Park Job | сел за общий ноутбук в парке, получил деньги с доски заказов или ломбарда, подобрал картридж |
| 3 | First Game Started | начат первый проект (в т. ч. на ноутбуке) |
| 4 | First Game Released | `gamesReleased ≥ 1` |
| 5 | Garage Bought | куплен гараж ($750) |
| 6 | Studio Named | введено название студии (окно появляется после гаража) |
| 7 | First Hire | первый сотрудник (Мила доступна уже в гараже) |
| 8 | Office Construction Started | оплачена стройка офиса |
| 9 | Office Reached | стройка закончена, этап 2 |
| 10 | Floor 2 Reached | этап 3 |
| 11 | Floor 3 Reached | этап 4 |
| 12 | First Rebirth | первый Rebirth |

Порядок отличается от «название → ноутбук» в задаче: в игре название вводится только после покупки гаража, а найм возможен ещё в гараже, поэтому «Studio Named» и «First Hire» стоят между гаражом и офисом. Имена и порядок шагов меняем **только до запуска** — дашборд склеивает данные по номеру и имени.

## 2. Экономика (Economy)

`LogEconomyEvent`, валюта `Cash`. Все деньги идут через `DataService.addCash` / `trySpend` / `charge` — AnalyticsService оборачивает их и по стеку вызовов (`debug.info`) узнаёт сервис и функцию. Таблицы — `Config/Analytics.sources` и `.sinks`.

- **transactionType** — только стандартные `Enum.AnalyticsEconomyTransactionType`: `IAP`, `Shop`, `ContextualPurchase`, `Gameplay`, `TimedReward`, `Onboarding`.
- **itemSKU** — система (`gameRelease`, `training`, `construction`…), без id предметов — их сотни. Возвраты — `refund…`. Для IAP — ключ товара.
- **CustomField01** — этап студии (`stage1`…`stage4`), **CustomField02** — предмет, если есть (id апгрейда, сотрудника, декора, этап стройки, `genre_rpg`…).
- Не нашли категорию — `Gameplay / other<Сервис>`. Увидели такое в дашборде — дописать строку в `Config/Analytics`.

### Источники (Source)

| transactionType | itemSKU | Откуда (сервис.функция) |
| --- | --- | --- |
| Gameplay | gameRelease | DevelopmentService — релиз игры |
| Gameplay | hitShelf / thiefPenalty | HitService — полка хитов / штраф вора жертве |
| Gameplay | parkJob / pawnshop | StartParkService — доска заказов / ломбард |
| Gameplay | expo | ExpoService — приз выставки |
| Gameplay | quest / achievement | QuestService, AchievementService (через RewardService) |
| Gameplay | dailyBugCatch / dailyBugHunt / dailyInvestor / dailyBlitz | DailyEventService — события дня: пойманный баг, итог охоты, инвестор, блиц-джем |
| Gameplay | safe | SafeService — сейф в парке |
| Gameplay | gotw | GotwService — «Игра недели» |
| Gameplay | contractAdvance / contractBonus | ContractService — аванс / бонус контракта |
| Gameplay | stockSell / dividend | StockService — продажа акций / дивиденды |
| Gameplay | consoleRoyalty / streamer / arcade | ConsoleService, StreamerService, ArcadeService |
| Gameplay | season / gameJam / holiday / tours | SeasonService, GameJamService, HolidayService, TourService |
| Gameplay | coopShare / holdingGoal / rivalPassed | CoopService, HoldingService, RivalService |
| Gameplay | companyEvent / bailiffSale | CompanyEventService, BailiffService (продажа предмета за долг) |
| Gameplay | publishingRoyalty / loan | PerksService («Издательство»), LoanService (кредит) |
| Gameplay | refundResearch / refundFire / refundHolding / refundIpo | возвраты: отмена открытия, увольнение, холдинг, IPO |
| TimedReward | offline / comeback / dailyReward | OfflineService, ComebackService, DailyRewardService |
| TimedReward | groupReward / promoCode / referral | SocialService, CodeService, ReferralService |
| Onboarding | tutorial | TutorialService |
| IAP | ключ товара (`income30`, `starterPack`, `buildSkip`…) | всё, что выдано внутри ProcessReceipt |

### Траты (Sink)

| transactionType | itemSKU | Откуда | CustomField02 |
| --- | --- | --- | --- |
| Shop | garage / upgrade / move | PlotService (по изменению профиля) | id апгрейда / этапа |
| Shop | construction | PlotService — оплата стройки офиса и этажей (раньше было в Other) | `office` / `floor` / `skyscraper` |
| Shop | hire | StaffService.onHire (по новому сотруднику) | id сотрудника |
| Shop | decor / skin / mascot / furnitureStyle / poster | DecorService, SkinService, MascotService, FurnitureStyleService, PosterService | id предмета |
| Shop | consoleEquipment / insurance / adCampaign | ConsoleService.onEquip, CompanyEventService.onBuyInsurance, реклама за $ | id / `ad_30` |
| ContextualPurchase | research | ResearchService — открытие жанра/темы/узла за $ | `genre_rpg` |
| ContextualPurchase | training / staffPerk | StaffService.onUpgradeSkill / onSetPerk (раньше было в Other) | — |
| ContextualPurchase | consoleStage / hitUpdate / repair | ConsoleService.onStage, HitService.onRequestUpdate, починка после события | `stage2` |
| Gameplay | salary / rent | ExpensesService (DataService.charge) | — |
| Gameplay | tax / taxFine | TaxService — оплата / штраф | — |
| Gameplay | stockBuy / ipo | StockService | — |
| Gameplay | companyEventLoss / thiefPenalty | CompanyEventService, HitService (штраф пойманного вора) | — |
| Gameplay | holdingCreate / loanRepay | HoldingService, LoanService | — |

Отделка студии (InteriorFinishService) продаётся только за Robux — это не трата Cash, она видна в ProductPurchased. Обмен между игроками (TradeService) и сброс денег при Rebirth в экономику не пишутся: это перекладывание, а не источник или трата.

## 3. Монетизация

Единая точка — `MonetizationService.processReceipt`:

1. перед выдачей — `AnalyticsService.beginReceipt(productId)`: все `addCash` в этом потоке до конца выдачи пишутся как **IAP** с ключом товара (пакеты дохода, «двойной релиз», стартовый набор, запасная выдача ускорений и подарков);
2. после выдачи — `endReceipt`: кастомное событие **ProductPurchased**, поле — ключ товара, значение — цена в Robux из Config. Повтор квитанции (уже выдано) не пишется. Если выдача упала исключением (квитанция при этом записывается, второй раз не выдаём), ProductPurchased тоже не пишется — ошибка видна только в `warn` сервера. Отложенная квитанция, пришедшая раньше инициализации игрока в аналитике, не теряется: состояние создаётся лениво.

Ключ товара ищется по productId во всех конфигах: `Products` (`income30`, `coffee`, `researchSkip`…; сделки дня — `deal_<ключ>`), `AdCampaigns` (`ad_<id>`), `Social` (`gift_<предмет>`), `Season`, `Console`, `Construction`, `Training`, `Skins`/`Posters`/`Mascots`/`FurnitureStyles`/`InteriorFinishes` (с префиксом). Не нашли — `product<id>`.

Геймпассы — событие **GamePassPurchased** (поле — id геймпасса, только после перепроверки владения).

## 4. Кастомные события (Custom events)

Лимит Roblox — 100 имён на игру. Сейчас **42**, все имена — только из `Config/Analytics.events` (сервисы передают ключ, не имя). Новые не плодить: этапы и виды — в поле CustomField01.

| Имя | Поле CustomField01 / значение |
| --- | --- |
| Rebirth | `rebirthN` / номер (жёсткого предела в коде нет: цена растёт линейно, `baseCost × (N + 1)`, поэтому на практике значений десятки, не больше; номер уже есть в значении — при росте кардинальности поле можно заменить корзинами) |
| HitStolen, ThiefCaught | — / сколько |
| ExpoWin | — / 1 |
| GamePassPurchased | id геймпасса |
| ProductPurchased | ключ товара / цена R$ |
| LanguageChanged | язык (раз за сессию) |
| QuickEvent | `вид_результат` |
| Achievement | id |
| GiftPurchased | `gift_<id>` / 1 другу, 0 себе |
| GroupReward | `group` |
| Offer | `вид_этап` (`starterPack_shown`, `…_purchased`) |
| BailiffSeizure | id предмета / выручка |
| CodeRedeemed | код |
| MascotPurchased, FurnitureStylePurchased | `id_cash` / `id_robux` |
| InteriorFinishPurchased | id |
| CompanyEvent | `id_этап` |
| SeasonTier, SeasonClaim | источник опыта / уровень; `дорожка_уровень` |
| JamSubmit | `first` / `improved`, значение — оценка |
| Hackathon | старт |
| DailyEvent | `id_этап` (`bugHunt_start`, `investors_grant`, `blitzJam_win`) |
| Franchise, Contract, RivalPassed | этап / id студии |
| Coop, Holding | этап |
| Platform, Console, Streamer | платформа релиза; этап консоли; назначен/снят |
| Arcade | `вид_этап` |
| NotifyPrompt, Referral, Trade | этап |
| Tax, Stock | этап / сумма |
| SafeAttempt | `ok` / `wrong` / `slow` / `empty` |
| Comeback | `shown` / `claimed`, значение — дней отсутствия |
| Research | `этап_вид_id` |
| Construction | `этап_этап` (`office_start`, `floor_finish`, `office_buildSkip`) |
| Fans | `источник_знак` (`release_gain`, `release_loss`, `expo_place1_gain`, `expo_place2_gain`, `expo_place3_gain`, `expo_high_gain`, `rebirth_loss`) / на сколько изменилось фанатов студии (по модулю) |

## 5. Что смотреть в первую неделю

Данные в дашборде появляются с задержкой до ~24–48 часов. Смотреть раз в день, сравнивать день к дню.

1. **Удержание D1 / D7** — Analytics → **Retention** (и Overview). Ориентир для тайкуна: D1 ≥ 20–25 %, D7 ≥ 5–8 %. Ниже — сначала смотреть воронку.
2. **Где отваливаются новички** — Analytics → **Funnels → Onboarding**. Самые важные переходы:
   - 1 → 2 (зашёл, но ничего не сделал в парке) — непонятный старт, туториал;
   - 4 → 5 (выпустил игру, но не купил гараж) — темп денег в парке (`Config/StartPark`);
   - 6 → 7 и 7 → 8 (гараж → найм → стройка офиса) — середина первой сессии;
   - 9 → 10 (офис → 2-й этаж, 310 игр и $1,5 млн) — долгий отрезок, ждём здесь основной обрыв;
   - 11 → 12 (3-й этаж → Rebirth).
   Падение больше 40 % на одном шаге — повод для правки баланса или подсказки.
3. **Топ товаров за Robux** — Analytics → **Custom events → ProductPurchased**, разбивка по CustomField01: количество — сколько раз купили, сумма значения — Robux по цене Config. Деньги от Roblox (с учётом комиссии) — **Monetization → Developer Products** и **Passes**. Сравнить с **Offer** (`…_shown` против `…_purchased`) — конверсия предложений.
4. **Баланс источников и трат** — Analytics → **Economy**: Sources vs Sinks по transactionType и itemSKU, фильтр по CustomField01 (этап). Хорошо, когда траты ≈ 60–90 % источников; источники сильно больше — инфляция, деньги некуда тратить (проверить `upgrade`, `construction`, `research`). Строки `other…` — сразу дописать категорию.
   - Среди источников смотреть долю `IAP` и `TimedReward` (offline, comeback): если они больше `gameRelease` — игроки ждут, а не играют.
   - Среди трат — `salary`/`rent`/`tax`: если растут быстрее доходов на этапе, жалобы на «минус» и приставов (BailiffSeizure).
5. **Живые системы** — Custom events: `DailyEvent`, `SafeAttempt`, `Comeback`, `Construction` (`…_buildSkip` — покупают ли ускорения), `Research`.

## Как проверить в Studio

1. Play в Studio новым профилем (или очистить `PlayerData_v1` для своего UserId), смотреть Output.
2. Зайти: `[Analytics] onboarding 1 Joined`. Сесть за ноутбук в парке — `onboarding 2 Laptop Or Park Job`, начать игру — `3 First Game Started`, выпустить — `4 First Game Released`.
3. Купить гараж, ввести название, нанять Милу — шаги 5, 6, 7 по порядку. Включить `StudioDebug` и дать денег — оплатить стройку офиса: шаг 8; дождаться/ускорить — 9.
4. Через минуту — строки `[Analytics] economy Sink Shop/construction office …`, `economy Source Gameplay/gameRelease …`, `economy Sink Gameplay/salary …`. Строк `other…` быть не должно.
5. Прокачать навык сотрудника — `Sink ContextualPurchase/training`. Событие дня (баг/инвестор) — `Source Gameplay/dailyBugCatch` / `dailyInvestor`.
6. Тестовая покупка товара (например, «10 минут дохода») — `economy Source IAP/income10 …` и `custom ProductPurchased value=<цена> field=income10`.
7. Перезайти: шаги воронки не повторяются.
