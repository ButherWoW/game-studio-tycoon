# V27 — InvestorNPC: классический костюм и InvestorCase

Оригинальные investor_shirt.png и investor_pants.png, ровно585×559RGBA: тёмно-синий костюм, светлая рубашка, золотая бабочка, лацканы, манжеты и аккуратная обувь. Все18панелей соответствуют существующей официальной UV-развёртке классической одежды; разделители и область вне UV полностью прозрачны. Исходные SVG и генераторы сохранены. Это расширение собственного геометрического комплекта одежды V12, без генерации предположительной UV-карты нейросетью.

InvestorCase — корневой Accessory, не коллекция Model:14нативных деталей при лимите20. Синий кейс с золотыми застёжками и двумя видимыми стопками монет. Handle + RightGripAttachment, все остальные13деталей жёстко приварены к Handle. Геометрия unanchored/Massless, без CanCollide/CanTouch/CanQuery; нет скриптов, внешних mesh/texture/Decal и света. В папке два формата RBXMX/RBXM: импортировать только один.

## Проверки

VALIDATION.json создаётся независимым разбором экспортированного XML. Проверены структура Accessory, имена,14деталей, стандартный Attachment, ссылки13WeldConstraint, свойства физики,91пара геометрии SAT — без объёмных пересечений. Проверка PNG сравнивает точную маску18UV-панелей с реальной альфой, весь остальной холст прозрачен. Размеры и SHA-256 приложены.

investor_preview.png512×512 — рендер реальных текстур и геометрии на условном блочном R15-совместимом манекене, не Studio-скриншот. Ручка сдвинута наружу через localAttachmentX0.5, чтобы кейс не входил в ногу канонического манекена. Фактические ориентации Attachment и BodyScale NPC проверить в Studio.

## Подключение

Dev1: загрузить investor_shirt.png и investor_pants.png как Classic Shirt/Pants и передать корректные texture IDs Dev2 для Images.investor.shirt/pants. Импортировать корневой Accessory под именем InvestorCase в ServerStorage.DailyEvents; не переименовывать в Investor_Briefcase.

Текущий DailyEventService.dressInvestor находит InvestorCase и добавляет через StaffAppearance.addAccessory. Если готового шаблона InvestorNPC нет, существующий код строит NPC по IDs одежды. Дополнительный runtime-манекен в этой пачке не нужен.

Dev2/Dev1: проверить «Час инвесторов», надевание костюма и кейса, фактический RightGripAttachment, масштаб, рукав/талия/ботинки, idle/walk и отсутствие пересечений с ногами и мебелью. Внутренних скриптов/логики/цен/ID эта пачка не меняет. Загрузка и тест в Studio здесь не выполнялись.

## Воспроизведение

Python3 + Pillow + NumPy; node с @resvg/resvg-js; Rojo для RBXM.

    python3 source/build_investor.py
    node source/rasterize.cjs
    python3 source/render_investor.py
    python3 source/validate_investor.py

UV_MAP.json хранит координаты панелей, source-svg/ — оригинальное векторное оформление, accessory-manifest.json — геометрию кейса. Изображения/модель сделаны кодом из собственных простых форм, ImageGen не использовался.
