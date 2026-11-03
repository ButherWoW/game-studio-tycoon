--!strict
-- Точка входа сервера. Сначала базовые сервисы в нужном порядке, потом все остальные
-- модули из Services по алфавиту: новую фичу достаточно положить в папку, править этот файл не нужно.

local Services = script.Services

local ORDER = {
	"WorldService", -- пол, участки, заглушки моделей (если их нет в плейсе)
	"DataService",
	"PlotService",
	"DevelopmentService",
	"MonetizationService",
	"UnlockService",
}

local started: { [string]: boolean } = {}
for _, name in ORDER do
	require(Services:FindFirstChild(name) :: ModuleScript).start()
	started[name] = true
end

local rest = {}
for _, child in Services:GetChildren() do
	if child:IsA("ModuleScript") and not started[child.Name] then
		table.insert(rest, child)
	end
end
table.sort(rest, function(a, b)
	return a.Name < b.Name
end)
for _, module in rest do
	local service = require(module) :: any
	if type(service) == "table" and type(service.start) == "function" then
		service.start()
	end
end

print("[Game Studio Tycoon] Server started")
