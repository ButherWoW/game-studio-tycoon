# Проверка пачки

PASS: четыре финальных модели,48панелей Transparency=0/Material272. Независимое сравнение XML: CFrame/size/PivotOffset/Model properties, число/классы всех деталей, прочие свойства частей и коллизии идентичны baseline. Поэтому новые геометрические пересечения не появились; старые декоративные стыки не исключаются.

В каждом финале один PointLight, Shadows=false, Range60/Brightness1; удалено ровно3. Никаких Script/LocalScript/ModuleScript/mesh/texture. Все четыре превью просмотрены; дополнительно независимый read-only reviewer подтвердил разрешённый diff всех Item.

VALIDATION.json содержит размеры scope/хеши XML и binary. Проверка бинарного формата выполнена через Rojo и отдельный XML roundtrip; детали/pivot/прозрачность сверены. Кодовый patch — предложение Dev2, в src не применён.

Studio/runtime здесь не проверены. Окончательное отсутствие двойных стен и прозрачности камеры зависит от двух исправлений кода Dev2. Инструкция в README.

Репозиторные проверки: stylua --check src PASS; selene —0ошибок/предупреждений на кэшированной Roblox-библиотеке (обновление API dump было недоступно); rojo build PASS. proposed-remove-superseded-garage.patch проходит git apply --check на базовом main.
