--!strict
-- Точка входа клиента: HUD и окна, потом все остальные контроллеры по алфавиту
-- (новый контроллер достаточно положить в папку Controllers).

local Controllers = script.Controllers

local ORDER = { "HudController", "CreateGameWindow", "ReleaseWindow" }

local started: { [string]: boolean } = {}
for _, name in ORDER do
	require(Controllers:FindFirstChild(name) :: ModuleScript).start()
	started[name] = true
end

local rest = {}
for _, child in Controllers:GetChildren() do
	if child:IsA("ModuleScript") and not started[child.Name] then
		table.insert(rest, child)
	end
end
table.sort(rest, function(a, b)
	return a.Name < b.Name
end)
for _, module in rest do
	local controller = require(module) :: any
	if type(controller) == "table" and type(controller.start) == "function" then
		controller.start()
	end
end
