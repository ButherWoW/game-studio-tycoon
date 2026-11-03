--!strict
-- Точка входа сервера: запускает все сервисы по порядку.

local Services = script.Services

require(Services.DataService).start()
require(Services.PlotService).start()
require(Services.DevelopmentService).start()
require(Services.MonetizationService).start()
require(Services.UnlockService).start()

print("[Game Studio Tycoon] Server started")
