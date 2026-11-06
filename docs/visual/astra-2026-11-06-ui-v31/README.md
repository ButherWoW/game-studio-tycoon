# V31 — меню, туториал, аркада и окна

15 PNG с настоящей прозрачностью, без текста и цифр. Стрелка туториала сделана первой: жёлтая, строго вниз, без тени, остриё по центральной оси. Все файлы256×256, кроме arcade_coin.png128×128.

| Файл | Ключ Config/Images |
| --- | --- |
| tut_arrow.png | Images.tutorial.arrow |
| menu_stock.png | Images.menu.menu_stock |
| menu_tax.png | Images.menu.menu_tax |
| menu_rivals.png | Images.menu.menu_rivals |
| arcade_target.png | Images.arcade.target |
| arcade_car.png | Images.arcade.car |
| arcade_barrier.png | Images.arcade.barrier |
| arcade_runner.png | Images.arcade.runner |
| arcade_coin.png | Images.arcade.coin |
| win_stock.png | Images.windows.stock |
| win_ipo.png | Images.windows.ipo |
| win_tax.png | Images.windows.tax |
| win_rivals.png | Images.windows.rivals |
| win_offline.png | Images.windows.offline |
| win_comeback.png | Images.windows.comeback |

## Изготовление и проверка

Встроенный OpenAI ImageGen, отдельный запрос на каждый PNG, прозрачность запрошена явно. PROMPTS.json хранит точные запросы, пути к исходникам и цепочки исправлений. При уменьшении сохранена исходная альфа, фон не вырезался по цвету.

VALIDATION.json содержит размеры, альфу, прозрачные углы, границы значимого рисунка, SHA-256 и визуальную проверку. V31_ContactSheet.png показывает иконки на белом фоне и тёмном поле аркады#161826 при128px, а также при40px. Отдельно проверяются вид машины строго сверху носом вверх и правое направление бега героя. На кубке конкурентов — звезда, без цифры.

## Подключение

Dev1: загрузить15Images, передать filename → Image ID. Dev2: назначить существующим ключам из таблицы; код уже подготовлен в PR223. Цены, Config и игровая логика этой пачкой не меняются.

В Studio после модерации проверить стрелку на экране и над участком, все пять мини-игр аркады, меню биржи/налогов/конкурентов, заголовки и крупные иконки окон. Проверить чтение при32–40px, кнопки и картинки на телефоне844×390, отсутствие подложки и обрезки. Ориентацию спрайтов не менять при загрузке. Здесь нет Roblox-загрузки или runtime-теста.
