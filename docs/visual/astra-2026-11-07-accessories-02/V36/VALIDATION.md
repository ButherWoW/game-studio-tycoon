# Validation
PASS: 9/10/27/28 деталей с Handle, каждая модель до 40. Стандартный HatAttachment, все видимые части связаны с Handle, Anchored=false, Massless=true, CanCollide/CanTouch/CanQuery=false.
PASS: 740 пар реальных нативных выпуклых форм, ноль пересечений с допуском 1e-6 stud; невидимый Handle исключён только из геометрического сравнения.
PASS: 4 RBXM→XML roundtrip. Ссылки WeldConstraint Part0Internal/Part1Internal нормализованы к Part0/Part1; readonly Enabled=true при сериализации не сохраняется.
Нет скриптов, света и внешних mesh/texture. Общий лист и финальный ракурс фонаря просмотрены, три ракурса каждого приложены.
НЕ ПРОВЕРЕНО: Studio, настоящий R15, посадка со всеми причёсками, Humanoid:AddAccessory, анимация и FPS. Серая голова не экспортирована.
