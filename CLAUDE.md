# Контекст проекта для Claude

Этот файл читает Claude (в VS Code / Claude Code) при открытии репозитория. Держите его актуальным.

## Проект
- **Build Your Game Studio Tycoon** (название выбрано 05.11, #4; рус. «Создай свою игровую студию») — Roblox-тайкун в духе Game Dev Tycoon: игрок открывает студию в гараже, делает игры (жанр + тема + фокус по 4 направлениям), получает оценку 1–10 и доход, покупает апгрейды, нанимает сотрудников, переезжает в офис/небоскрёб, делает Rebirth.
- Язык общения с командой: **русский**. Названия в коде — английские, комментарии можно на русском.
- Роадмап: `docs/ROADMAP.md`. Инструкция для второго разработчика: `docs/DEV2.md`.

## Роли
- **Dev 1 — Claude (на ПК владельца)**: с 2026-11-05 по решению владельца ведёт **всё**, кроме визуала: **весь код в `src/`** (пишет и сам вливает в `main` через PR), Roblox Studio (плейс, модели в `ServerStorage.Upgrades`), тесты и отчёты в Issues, публикация, Creator Dashboard (товары/геймпассы → ID в `Config`), геймдизайн, баланс, тексты.
- **Dev 2 — Claude (ButherWoW, без Studio)**: с 2026-11-05 **не участвует** — его работу забрал Dev 1. Если Dev 2 вернётся, владелец скажет отдельно.
- Репозиторий: **https://github.com/ButherWoW/game-studio-tycoon** (перенесён 2026-11-04 из `erlbro-debug/game-studio-tycoon`, тот больше не используется). Источник правды — репозиторий.
- На ПК владельца Claude работает из VS Code: терминал есть, `gh` залогинен (ButherWoW), Rokit в `%USERPROFILE%\.rokit\bin` (rojo/stylua/selene), git — встроенный в GitHub Desktop (`%LOCALAPPDATA%\GitHubDesktop\app-*\resources\app\git\cmd`, добавлять в PATH). Код в Studio — через `rojo build -o build.rbxl` или `rojo serve` + плагин Rojo.

## Технически
- Rojo (`default.project.json`): `src/shared` → ReplicatedStorage.Shared, `src/server` → ServerScriptService.Server, `src/client` → StarterPlayerScripts.Client.
- Инструменты через Rokit: rojo, stylua, selene. CI: `.github/workflows/ci.yml` (stylua --check, selene, rojo build).
- Все файлы `--!strict`. Перед коммитом: `stylua src`, `selene src`, `rojo build -o build.rbxl`.
- **Деньги, очки, оценки считает только сервер.** Все `OnServerEvent` валидируют вход.
- Баланс — только в `src/shared/Config/*`. Формулы — `src/shared/Formulas.luau`.
- Сохранения: `DataService` (DataStore `PlayerData_v1`, автосейв 60 с, BindToClose). Новые поля профиля добавлять в `defaultProfile()`.

## Решения по геймдизайну (согласовано с владельцем)
- Основной донат — **рекламная кампания** для выпущенной игры: +30% / +50% / +75% / +100% к доходу (Developer Products, `Config/AdCampaigns.luau`). Бонусы не складываются, максимум +100%, действуют ограниченное время (15 мин). Две нижние доступны и за игровую валюту.
- Остальная монетизация (план): геймпассы x2 деньги, авто-релиз, быстрая разработка, доп. слот, VIP-офис, легендарный сотрудник; продукты: мгновенное завершение, пакеты валюты, патч (+1 к оценке), кофе, сезонный пропуск, декор. Без платных лутбоксов.
- Цены в Robux пока примерные, не финальные.

## Статус (обновлено 2026-11-05, Dev 1)
- **05.11, Dev 1:** Фаза 7 в main (#169): `TaxService`, `StockService`, `StockNoise`, окна `TaxWindow` (слот 18) и `StockWindow` (слот 19), конфиги `Tax`, `Stocks`. Звуки (#167), геймпассы (#168), товары (#165) — ID тестовой вселенной v2. В Studio есть `ServerStorage.StudioDebug` (BindableFunction, только Studio): `Invoke("phase7")`, `Invoke("set", путь, значение)`, `Invoke("call", Сервис, функция, ...)`. Плейс v2 опубликован v48.
- **Живой роадмап** — https://claude.ai/artifact/DBE2ganRvAWPGTxQrgVQVp (источник правды по статусам шагов); `docs/ROADMAP.md` — краткая сводка.
- **Весь код по роадмапу в `main`** (04.11: смёржены #38 → #41 → #49, #25, #50). Дальше — тест в Studio и «Отчёт #2» (#20), по нему Dev 2 исправляет.
- **Плейсы:** «Game Studio Tycoon» (Place ID 91848575533083) и «Game Studio Tycoon v2» (75334772365832). Модель гаража из Creator Store (132604421) стоит в `ServerStorage.Upgrades.Garage` плейса (в репо `assets/models` ещё нет).
- **Тестовые деньги** в Studio: `Config/Debug.studioStartCash` ($999 999); для замеров баланса ставить 0.
- **Роли (с 2026-11-05):** Dev 1 — всё, кроме визуала (код, Studio, тесты, публикация, Dashboard); Dev 3 (GPT Астра) — визуал (#26, `docs/VISUAL.md`). Dev 2 не участвует.
- **Robux-товары:** 43 Developer Products созданы во вселенной v2 (10774624686), ID в `Config` (#165). Для основной игры нужен свой набор. Геймпассы (6) ещё не созданы.
- **Ждём:** владелец — название игры (#4); Dev 1 — мёрдж и «Отчёт #2» (#20), ID звуков (#22), продукты/геймпассы в Dashboard (5.10); Астра — визуал и иконка (#26).
- **Перед релизом:** заменить тестовые модели без коммерческой лицензии, проверить переводы носителями, `studioForce` праздников = nil, `studioStartCash` не влияет на живые серверы (проверено в коде).

## Как работать в каждой сессии
0. **Сначала прочитай GitHub сам:** `gh issue list -R ButherWoW/game-studio-tycoon`, `gh pr list -R ButherWoW/game-studio-tycoon` и новые комментарии в них (особенно в #14 — сообщения от Dev 2). PR от Dev 2 — из веток того же репозитория: проверь (`stylua`, `selene`, `rojo build`) в Studio по разделу «Как проверить в Studio», смёрджи или ответь в PR. Задачи, которые Dev 2 пометил «забрал Dev 2», не делай.
1. Открой `docs/ROADMAP.md` — найди первый шаг со статусом ⏳ или ⬜ для Claude (Studio, модели, тесты). Код в `src/` пишет Dev 2: твоя работа с ним — проверить PR в Studio и смёрджить.
2. Сделай шаг, проверь (`stylua`, `rojo build`, тест в Studio, если доступен).
3. Обнови прогресс в двух местах:
   - `docs/ROADMAP.md`: ⬜ → ✅, пересчитай проценты фазы и общий прогресс (всего 44 шага);
   - страница-роадмап для владельца: https://claude.ai/artifact/DBE2ganRvAWPGTxQrgVQVp (artifact slug `629b218b-43b8-4c7c-af0d-0f26eed49373`). В её HTML меняй только блок `PHASES` (статус шага `"todo"` → `"doing"` → `"done"`) и `UPDATED`; проценты страница считает сама. Обновлять через edit_version.
4. Коротко обнови раздел «Статус» в этом файле.
