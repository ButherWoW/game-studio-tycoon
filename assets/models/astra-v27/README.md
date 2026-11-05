# V27 — события дня, инвестор, кубок и сейф

Комплект закрывает весь V27:12 иконок событий, общий баннер, иконка/фон сейфа, одежда инвестора и аксессуар-кейс, Trophy_Blitz и ParkSafe. Изображения и модели разделены по папкам; в игре импортировать только финальные файлы, не источники/превью.

## Содержимое

- events-art-pack/V27/: devent_<id>.png256×256RGBA, devent_banner.png1600×300 без текста, safe_icon.png256×256RGBA и safe_keypad_bg.png512×640 без кнопок/цифр. Промпты встроенного ImageGen и контактлисты рядом.
- investor-pack/: investor_shirt.png и investor_pants.png585×559, InvestorCase как корневой Accessory (14 деталей), preview фактическихUV/геометрии, исходныеSVG и проверки. Костюм, белая рубашка, золотая бабочка, кейс с монетами.
- models-pack/models/: ParkSafe41деталь4×5×4 и Trophy_Blitz19деталей1.02×1.5×0.72, в RBXMX/RBXM. Pivot основанияY0, лицо+Z, без скриптов/mesh/внешних текстур. Подробности в README папки.

## Соответствие событий

Файлы используют актуальные IDs Config/DailyEvents и Images.dailyEvents, которые отличаются от сокращений старого брифа:

| Краткое имя ТЗ | Файл / ключ Images.dailyEvents |
| --- | --- |
| coffee | devent_coffeeRush.png / coffeeRush |
| investors | devent_investors.png / investors |
| bughunt | devent_bugHunt.png / bugHunt |
| cartridges | devent_cartridgeRush.png / cartridgeRush |
| blitzjam | devent_blitzJam.png / blitzJam |
| critics | devent_critics.png / critics |
| pizza | devent_pizza.png / pizza |
| talent | devent_talentHunt.png / talentHunt |
| sale | devent_flashSale.png / flashSale |
| mascots | devent_mascotParade.png / mascotParade |
| golden | devent_golden.png / golden |
| night | devent_nightShift.png / nightShift |

Баннер → Images.dailyEvents.banner, safe_icon → Images.safe.icon, фон → Images.safe.keypadBg, одежда → Images.investor.shirt/pants. Использовать Image ID для картинок и ID соответствующего типа одежды для шаблонов.

## Подключение

Dev1: загрузить15изображений и2шаблона одежды; передать таблицу ID. InvestorCase положить в ServerStorage.DailyEvents как Accessory, не внешний Model. Импортировать ParkSafe в ServerStorage.Upgrades либо ServerStorage, Trophy_Blitz — в согласованную с Dev2 папку. Один формат модели, без дублей.

Dev2: ревью и подключение к существующим ключам/моделям. SafeService уже принимает Keypad как Model с PrimaryPart. Door — отдельный Model сборки со своей панелью, декоративными деталями и ручкой; SafeController поддерживает этот вариант и вращает его вокруг неподвижного Hinge. Движение всей дверцы проверено математически в диапазоне0–115°; внутрь модели код не добавлен. Код сейфа, приз и подсказки в ассеты не записываются; владелец задаёт код существующей панелью. ClueSign не создавался.

## Проверка

Независимый XML/SAT сейфа и кубка:1010пар, ноль положительных пересечений; движение Door проверено с шагом5°. У InvestorCase91пара без пересечений, Handle/Attachment/Welds иUV-маска проверены. Иконки просмотрены целиком и при40px, фон клавиатуры оставлен пустым дляUI. Это проверка файлов/геометрии, не Studio-тест.

После загрузки проверить все события, InvestorsNPC с одеждой/кейсом на реальномR15, кубок, ввод/открывание/закрывание сейфа, его положение у фонтана, подходы и режимы UI. SafeController масштабирует фон по реальному окну: проверить обрезку на телефоне и отсутствие наложения рамки на кнопки/результат. Код/баланс/IDs в этой пачке не меняются, загрузка в Roblox здесь не выполнялась.
