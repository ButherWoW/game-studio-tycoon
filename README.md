# Build Your Game Studio Tycoon (Roblox)

Тайкун в духе **Game Dev Tycoon** для Roblox: открываешь игровую студию в гараже, разрабатываешь и выпускаешь игры, получаешь оценки критиков и деньги, нанимаешь команду и вырастаешь в мировую корпорацию.

> Статус: **Фаза 0–1 (прототип)**. План — [docs/ROADMAP.md](docs/ROADMAP.md). Второму разработчику — [docs/DEV2.md](docs/DEV2.md).

## Core loop

1. Выбрать жанр и тему → распределить фокус (геймплей / графика / звук / сюжет)
2. Студия разрабатывает игру — сотрудники за столами дают очки
3. Релиз → оценка 1–10 → доход
4. Апгрейды офиса, сотрудники, исследования → игры лучше и дороже
5. Rebirth за постоянный множитель

## Быстрый старт

1. Установите [Roblox Studio](https://create.roblox.com/) и [Rokit](https://github.com/rojo-rbx/rokit).
2. Склонируйте репозиторий и установите инструменты:
   ```bash
   git clone <url этого репозитория>
   cd game-studio-tycoon
   rokit install
   ```
3. Запустите синхронизацию: `rojo serve`
4. В Studio установите плагин Rojo, нажмите **Connect** — код появится в плейсе.
5. Для теста в плейсе нужны: `Workspace.Plots` (части Plot1, Plot2…) и `ServerStorage.Upgrades` (модели Desk1, PC1, …). Для сохранений включите *Game Settings → Security → Enable Studio Access to API Services*.

## Структура

```
src/
  server/            ServerScriptService — вся логика денег и оценок
    Services/        DataService, PlotService, DevelopmentService, MonetizationService
  client/            StarterPlayerScripts — UI
  shared/            ReplicatedStorage — конфиги и формулы
    Config/          Genres, Topics, Upgrades, AdCampaigns
```

**Правило №1:** деньги, очки и оценки считает только сервер. Клиент только показывает и просит.

## Как помочь

Читайте [CONTRIBUTING.md](CONTRIBUTING.md). Ищите задачи с меткой `good first issue`.

## Лицензия

MIT — см. [LICENSE](LICENSE).
