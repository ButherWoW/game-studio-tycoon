--!strict
-- Точка входа клиента.

local Controllers = script.Controllers

require(Controllers.HudController).start()
require(Controllers.CreateGameWindow).start()
require(Controllers.ReleaseWindow).start()
