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

-- Ошибка в одном модуле не должна ронять весь сервер (иначе пустой мир без HUD): пишем warn и идём дальше
local function startModule(module: ModuleScript)
	local ok, err = pcall(function()
		local service = require(module) :: any
		if type(service) == "table" and type(service.start) == "function" then
			service.start()
		end
	end)
	if not ok then
		warn("[Game Studio Tycoon] Service " .. module.Name .. " failed to start:", err)
	end
end

local started: { [string]: boolean } = {}
for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		startModule(module)
	end
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
	startModule(module)
end

print("[Game Studio Tycoon] Server started")
