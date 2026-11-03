# Контекст проекта для Claude

Этот файл читает Claude (в VS Code / Claude Code) при открытии репозитория. Держите его актуальным.

## Проект
- **Game Studio Tycoon** — Roblox-тайкун в духе Game Dev Tycoon: игрок открывает студию в гараже, делает игры (жанр + тема + фокус по 4 направлениям), получает оценку 1–10 и доход, покупает апгрейды, нанимает сотрудников, переезжает в офис/небоскрёб, делает Rebirth.
- Язык общения с командой: **русский**. Названия в коде — английские, комментарии можно на русском.
- Роадмап: `docs/ROADMAP.md`. Инструкция для второго разработчика: `docs/DEV2.md`.

## Роли
- **Dev 1 — Claude (на ПК владельца)**: **Roblox Studio** (через computer use: плейс, карта, модели в `ServerStorage.Upgrades`, NPC), **все тесты** и «Отчёт #N» в Issues, ревью и мёрдж PR Dev 2, публикация, Creator Dashboard (ID продуктов → в `Config`). Код в `src/` сам не пишет, только мелкие правки по итогам теста (с комментарием в PR/issue).
- **Dev 2 — Claude (ButherWoW, без Studio)**: **весь код в `src/`** (с 2026-11-04 забрал у Dev 1 по решению владельца), геймдизайн и контент, баланс, тексты. Работает ветками этого репо, PR в `main` с разделом «Как проверить в Studio».
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

## Статус
- Фаза 0 выполнена (репозиторий, структура, CI).
- Фаза 1: код прототипа готов (`DataService`, `PlotService`, `DevelopmentService`, `MonetizationService`, тестовый `HudController`), ждёт проверки Claude в Studio.
- 2026-11-04: репозиторий переехал на ButherWoW; смёржены PR #15 (баги #13) и #16 (новая экономика, 10 жанров, 15 тем, 9 апгрейдов). Прогресс 19/46 (41%).
- Плейс опубликован: **Place ID 91848575533083** («Game Studio Tycoon»). `WorldService` досоздаёт пол, участки и заглушки моделей, так что пересборка из `build.rbxl` ничего не ломает. Сохранения в Studio выключены, пока не включат Game Settings → Security → Enable Studio Access to API Services.
- Тест 2026-11-04 (Claude в Studio): стол встаёт на участок, игра «Space Blaster» — 8/10, +$960 (новая экономика работает).
- Ждём от владельца: выбор названия (#4).
- 2026-11-04: по решению владельца Dev 2 забрал **весь код** (2.4–2.6, 3.3–3.5, 4.3–4.5, 5.4–5.6); смёржены #19 (окна, кнопки) и #23 (раскладка участка). Dev 1: 1.6 (Отчёт #1) → 2.7 модели по схеме #22 → проверка PR Dev 2 в Studio и отчёты.

## Как работать в каждой сессии
0. **Сначала прочитай GitHub сам:** `gh issue list -R ButherWoW/game-studio-tycoon`, `gh pr list -R ButherWoW/game-studio-tycoon` и новые комментарии в них (особенно в #14 — сообщения от Dev 2). PR от Dev 2 — из веток того же репозитория: проверь (`stylua`, `selene`, `rojo build`) в Studio по разделу «Как проверить в Studio», смёрджи или ответь в PR. Задачи, которые Dev 2 пометил «забрал Dev 2», не делай.
1. Открой `docs/ROADMAP.md` — найди первый шаг со статусом ⏳ или ⬜ для Claude (Studio, модели, тесты). Код в `src/` пишет Dev 2: твоя работа с ним — проверить PR в Studio и смёрджить.
2. Сделай шаг, проверь (`stylua`, `rojo build`, тест в Studio, если доступен).
3. Обнови прогресс в двух местах:
   - `docs/ROADMAP.md`: ⬜ → ✅, пересчитай проценты фазы и общий прогресс (всего 44 шага);
   - страница-роадмап для владельца: https://claude.ai/artifact/DBE2ganRvAWPGTxQrgVQVp (artifact slug `629b218b-43b8-4c7c-af0d-0f26eed49373`). В её HTML меняй только блок `PHASES` (статус шага `"todo"` → `"doing"` → `"done"`) и `UPDATED`; проценты страница считает сама. Обновлять через edit_version.
4. Коротко обнови раздел «Статус» в этом файле.
