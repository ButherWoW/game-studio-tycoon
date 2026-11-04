--!strict
-- Точка входа клиента: HUD и окна, потом все остальные контроллеры по алфавиту
-- (новый контроллер достаточно положить в папку Controllers).
-- Каждый контроллер стартует в своём потоке: если один ждёт remotes, которых нет
-- (упал серверный модуль), или падает с ошибкой, остальной интерфейс всё равно появится.

local Controllers = script.Controllers

local ORDER = { "HudController", "CreateGameWindow", "ReleaseWindow" }

local function startController(module: ModuleScript)
	task.spawn(function()
		local ok, err = pcall(function()
			local controller = require(module) :: any
			if type(controller) == "table" and type(controller.start) == "function" then
				controller.start()
			end
		end)
		if not ok then
			warn("[Game Studio Tycoon] Controller " .. module.Name .. " failed to start:", err)
		end
	end)
end

local started: { [string]: boolean } = {}
for _, name in ORDER do
	local module = Controllers:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		startController(module)
	end
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
	startController(module)
end
