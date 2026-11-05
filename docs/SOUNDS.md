# Звуки и музыка

Ключи, громкость и id — `src/shared/Config/Sounds.luau`. Движок — `src/client/Controllers/SoundController.luau`,
игровые моменты (remotes и атрибуты) — `src/client/Controllers/SoundEvents.luau`.

## Правило лицензии

Берём **только бесплатное** аудио из Creator Store от:

- **Roblox** (user 1) — официальные звуки интерфейса и SFX;
- **ProSoundEffects** (user 7462895450, verified) — лицензионный партнёр Roblox, библиотека SFX;
- **APMOfficial** (APM Music, user 7462718749, verified) — лицензионный партнёр Roblox, музыка и стинги.

Такое аудио Roblox разрешает в любой игре. **Аудио случайных авторов не ставим** (даже с галочкой verified):
риск авторских прав и того, что ассет закроют как приватный. DistroKid тоже не берём — там встречаются каверы.

Как заменить: Studio → Toolbox → Audio → вставить id в поиск → послушать → поменять `id` в `Config/Sounds.luau`.
`id = 0` — звук выключен (код молчит).

## Как устроено

- **Громкость:** музыка (looped) — SoundGroup «Music», остальное — «Effects»; ползунки в Настройках.
  «Меньше эффектов» на звук не влияет.
- **Антиспам:** `Sounds.throttle` — минимальная пауза по ключу (монеты ≤ 8/с, тосты 0.5 с, приставы 2 с…).
- **3D:** `SoundController.playAt(key, part)` — звук у детали, слышно до 60 studs (`rollOffMax`),
  дальше 80 studs (`hearDistance`) не играем совсем.
- **Эмиттеры (строители):** сервер вешает на деталь тег CollectionService `SoundEmitter` и атрибут
  `SoundKey = "construction_hammer"` (необязательно `SoundMin` / `SoundMax`, сек; по умолчанию 0.6–1.5) —
  клиент сам стучит, пока игрок ближе 80 studs. Снял тег / удалил деталь — тишина.
- **Свой звук кнопки:** `button:SetAttribute("SoundKey", "tab_switch")` — вместо обычного click.
- **Музыка по месту:** раз в секунду смотрим, где игрок: парк и чужие участки — `music_park`; свой участок
  на этапе гаража — `music_garage`; в офисе — по этажу (высота над полом участка): `music_office`,
  `music_floor2`, `music_floor3`; пока идёт Золотой час — `music_golden` везде. Смена — затухание 1.5 с,
  старый трек ставится на паузу и продолжает с того же места.

## Для других фич (ключи есть, вызов — в их коде)

```lua
local SoundController = require(script.Parent.SoundController) -- из Controllers
SoundController.play("research_start")        -- 2D
SoundController.playAt("construction_done", part) -- 3D у детали
```

| Фича | Ключи |
|---|---|
| Стройка (PlotService / строители) | `construction_hammer` (тег `SoundEmitter` на строителе), `construction_done` |
| Исследования (ResearchWindow) | `research_start`, `research_done` |
| Обучение навыкам (TeamWindow) | `training_start`, `training_done` (`level_up` уже играет StaffFeel на «навык +1») |
| Консоль | `console_stage_done`, `console_launched` — уже подключены к `ConsoleNotice` (stageDone / launched) |

## Таблица звуков

Длительность — по данным Creator Store (0 — меньше полсекунды).

| Ключ | id | Название | Автор | Сек | Где играет | Проверить на слух |
|---|---|---|---|---|---|---|
| click | 15675032796 | Roblox_UI_Small_Click | Roblox | 0 | любая кнопка | [ ] |
| card_select | 10066968815 | (Dev 1) | Roblox | — | выбор жанра/темы | [ ] |
| unlock | 17208327798 | Roblox GUI - Aura | Roblox | 2 | открыли жанр/тему, пинг события дня | [ ] |
| buy | 10066947742 | (Dev 1) | Roblox | — | покупка апгрейда, найм | [ ] |
| cant_afford | 17208353912 | Roblox GUI - Negative | Roblox | 0 | не хватает денег | [ ] |
| dev_start | 16480577565 | (Dev 1) | Roblox | — | старт разработки | [ ] |
| dev_tick | 16480551554 | (Dev 1) | Roblox | — | тик разработки | [ ] |
| critic_reveal | 15675028888 | Roblox_UI_Whoosh_02 | Roblox | 1 | оценка критика | [ ] |
| score_low | 17208214688 | Roblox GUI - Call Decline | Roblox | 1 | итог 1–4 | [ ] |
| score_mid | 17208361335 | Roblox GUI - Notification High | Roblox | 2 | итог 5–7 | [ ] |
| score_high | 12222253 | (Dev 1) | Roblox | — | итог 8–10 | [ ] |
| money | 127645268874265 | CoinTransfer_01 | Roblox | 2 | доход за игру, заказ в парке выполнен | [ ] |
| record | 15675043410 | Roblox_UI_Tonal_Stinger | Roblox | 1 | рекорд студии | [ ] |
| move_office | 16480578036 | (Dev 1) | Roblox | — | переезд | [ ] |
| music_garage | 15675069601 | Roblox_UI_Loop_Calm_Music | Roblox | 95 | свой участок, гараж | [ ] |
| music_office | 9047104752 | Monday Morning | APMOfficial | 142 | офис, 1-й этаж | [ ] |
| music_floor2 | 9046863579 | City Lights | APMOfficial | 120 | 2-й этаж | [ ] |
| music_floor3 | 9047105702 | Light Dreamer | APMOfficial | 150 | 3-й этаж | [ ] |
| music_park | 9047104571 | Home Town Easy | APMOfficial | 141 | парк, чужие участки | [ ] |
| music_golden | 9043828640 | Sunshine In Hawaii | APMOfficial | 157 | Золотой час | [ ] |
| tab_switch | 17208408337 | Roblox GUI - Tab | Roblox | 1 | вкладки Магазина, Студии, Rebirth | [ ] |
| window_open | 17208405682 | Roblox GUI - Swipe | Roblox | 1 | открылось окно (Ui.windowOpened) | [ ] |
| window_close | 17208186900 | Roblox GUI - Back | Roblox | 1 | закрылось окно | [ ] |
| error | 17208353912 | Roblox GUI - Negative | Roblox | 0 | ошибки биржи/сейфа/Rebirth/подарков, лимит жуков | [ ] |
| toast | 17208372272 | Roblox GUI - Notification Low | Roblox | 3 | тосты хитов, сезона/джема, биржи, соц. | [ ] |
| unlock_feature | 15675016548 | Roblox_UI_Piano_Hello | Roblox | 4 | 🆕 открылась система (FeatureGate) | [ ] |
| achievement | 1848016523 | Global Success StingA | APMOfficial | 8 | достижение | [ ] |
| level_up | 9117887138 | Power Up Sweeteners 3 (SFX) | ProSoundEffects | 2 | навык сотрудника +1 | [ ] |
| training_start | 17208323435 | Roblox GUI - Equip | Roblox | 1 | (для фичи обучения) | [ ] |
| training_done | 9126073001 | Synth Sparkle Tone High Pitch Bell Tone Ding (SFX) | ProSoundEffects | 1 | (для фичи обучения) | [ ] |
| research_start | 17208399163 | Roblox GUI - Send | Roblox | 1 | (для фичи исследований) | [ ] |
| research_done | 1839901345 | Powered Up Chimes | APMOfficial | 5 | (для фичи исследований) | [ ] |
| coin_pickup | 9113849492 | Coins Or Keys Jingle 6 (SFX) | ProSoundEffects | 1 | подобрал картридж (ParkNotice cartridge) | [ ] |
| pawn_sell | 9113728756 | Cash Register 5 (SFX) | ProSoundEffects | 1 | ломбард (ParkNotice pawn) | [ ] |
| payday | 9113849651 | Coin Throws 3 (SFX) | ProSoundEffects | 1 | зарплата команде (PaydayCount) | [ ] |
| tax_paid | 9114026047 | Date Stamp Big Office Impact Good Squeak 2 (SFX) | ProSoundEffects | 1 | налог оплачен (TaxBill → 0) | [ ] |
| bailiff_knock | 9114141047 | Door Knock 2 (SFX) | ProSoundEffects | 2 | пришли приставы / забрали вещь | [ ] |
| theft_alarm | 9113085764 | Alarm Buzzer 5 (SFX) | ProSoundEffects | 1 | у тебя крадут хит (HitAlarm) | [ ] |
| gift_received | 15675055424 | Roblox_UI_Cute_Pop | Roblox | 3 | подарок / награда группы | [ ] |
| purchase_robux_thanks | 17208380755 | Roblox GUI - Purchase | Roblox | 1 | покупка за Robux прошла | [ ] |
| daily_event_start | 9116395089 | Magic Glows Soft Clusters Of Chiming Hits 4 (SFX) | ProSoundEffects | 2 | началось событие дня | [ ] |
| golden_hour | 1837762485 | Golden (sting a) | APMOfficial | 11 | начался Золотой час | [ ] |
| bug_catch | 12222152 | splat.wav | Roblox | 0 | поймал жука | [ ] |
| investor_grant | 9113728042 | Cash Register 1 (SFX) | ProSoundEffects | 2 | грант инвестора | [ ] |
| blitz_win | 1837762472 | Victory Dance (sting a) | APMOfficial | 11 | победа в блиц-джеме | [ ] |
| company_event_good | 1847213234 | Catchy Uplift E | APMOfficial | 6 | хорошее событие компании | [ ] |
| company_event_bad | 1843027392 | Power Out | APMOfficial | 3 | плохое событие, банкротство на бирже | [ ] |
| construction_hammer | 9114756156 | Hammer Nail Into Wood 9 (SFX) | ProSoundEffects | 1 | (строители, эмиттер 3D) | [ ] |
| construction_done | 1840076509 | Through the Roof (sting) | APMOfficial | 2 | (стройка готова) | [ ] |
| safe_beep | 9113936355 | Cordless Phone Sony Digital 900 1 (SFX) | ProSoundEffects | 0 | кнопки клавиатуры сейфа | [ ] |
| safe_wrong | 9119159511 | Siren Blat 2 (SFX) | ProSoundEffects | 1 | неверный код (3D у сейфа) | [ ] |
| safe_open | 9045298695 | Crack The Safe | APMOfficial | 5 | сейф открыт (3D у сейфа) | [ ] |
| elevator_ding | 9114302479 | Elevator Bell Synth Chimes 11 (SFX) | ProSoundEffects | 3 | лифт (3D у пульта) | [ ] |
| door | 9114150997 | Door Push Open 1 (SFX) | ProSoundEffects | 1 | вошёл на свой участок / вышел | [ ] |
| rebirth_whoosh | 9125805579 | Rising Whoosh Hissing Build Up (SFX) | ProSoundEffects | 1 | Rebirth | [ ] |
| confetti_pop | 9113263649 | Balloon Pop 3 (SFX) | ProSoundEffects | 0 | конфетти переезда | [ ] |
| mascot_squeak | 9120222027 | Toy Squeak 1 (SFX) | ProSoundEffects | 1 | взял маскота | [ ] |
| qte_hit | 15675059323 | Roblox_UI_Bright_Click | Roblox | 0 | быстрое событие: хорошо | [ ] |
| qte_miss | 15675062723 | Roblox_UI_Whistle_Low | Roblox | 0 | быстрое событие: промах | [ ] |
| qte_perfect | 9126073318 | Synth Sparkle Tone High Pitch Bell Tone Ding (SFX) | ProSoundEffects | 2 | быстрое событие: идеально | [ ] |
| stock_buy | 9113728625 | Cash Register 1 (SFX) | ProSoundEffects | 1 | купил акции | [ ] |
| stock_sell | 9113849445 | Coins Or Keys Jingle 5 (SFX) | ProSoundEffects | 2 | продал акции | [ ] |
| ipo_bell | 9125485591 | Desk Bell Counter Service Single Ringing (SFX) | ProSoundEffects | 5 | IPO | [ ] |
| console_stage_done | 1840076509 | Through the Roof (sting) | APMOfficial | 2 | этап консоли готов | [ ] |
| console_launched | 1836473422 | Victory Fanfare Sting | APMOfficial | 10 | консоль вышла | [ ] |

## Поисковые запросы

API (без авторизации), оставляли только `purchasePrice = 0` и авторов Roblox / ProSoundEffects / APMOfficial:

```
curl -s "https://apis.roblox.com/toolbox-service/v2/assets:search?searchCategoryType=Audio&query=<слова>&maxPageSize=30"
```

(+ `&pageToken=<nextPageToken>`, до 4 страниц). Запросы: `coin`, `whoosh`, `notification`, `Roblox_UI`,
`Roblox GUI`, `pop`, `chime`, `achievement`, `success`, `fail`, `hammer nail`, `hammer`, `keypad beep`,
`button beep`, `buzzer wrong`, `vault door`, `elevator bell`, `door open`, `knock door`, `cash register`,
`squeak toy`, `bell ring single`, `alarm`, `stamp`, `splat`, `power up`, `sting`, `ding`, `fight bell`;
музыка (`audioType = Music`): `lofi`, `chill office`, `corporate`, `upbeat business`, `fanfare`, `victory`,
`sunshine`, `technology`, `inspiring`.

## Риски

- Подобрано по названию, на слух никто не проверял — Dev 1 отмечает чекбоксы и меняет неудачные id.
- Длинные стинги APM (8–11 с: achievement, golden_hour, blitz_win, console_launched) могут перекрывать музыку.
- Если Roblox закроет ассет, `Sound` молча не играет — игра не ломается.
