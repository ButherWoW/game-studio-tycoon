# Validation

PASS: 30/16/13/12 деталей с Handle, до 40 на модель. Стандартный HatAttachment, сварки каждого видимого Part/WedgePart с Handle; Anchored=false, Massless=true, CanCollide/CanTouch/CanQuery=false.
PASS: 632 пары реальных нативных выпуклых форм, ноль пересечений при допуске 1e-6 stud. Прозрачные Glass детали включены; невидимый Handle исключён только из геометрии.
PASS: четыре бинарных RBXM→XML roundtrip; ссылки WeldConstraint Part0Internal/Part1Internal нормализованы к Part0/Part1, readonly Enabled=true не сохраняется при сериализации.
Нет скриптов/источников света/внешних mesh/texture.
Просмотрены общий лист и финальные ушки наушников; три ракурса приложены. Neon и Glass в офлайн-рендере приблизительные.
НЕ ПРОВЕРЕНО: Studio, реальная посадка R15, совместимость с причёсками, Humanoid:AddAccessory, анимация/FPS. Серая голова не экспортирована.
