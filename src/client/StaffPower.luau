--!strict
-- Мощность команды с сервера (StaffRemotes.StaffPower): скорость разработки от команды, прибавка
-- к оценке по направлениям, перерывы и «сколько потеряем» без каждого сотрудника.
-- Не контроллер: общий модуль для окна «Команда», HUD и тостов «было → стало».

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skills = require(ReplicatedStorage.Shared.Config.Skills)

export type Power = {
	speed: number,
	quality: { [string]: number },
	review: number,
	breaks: number,
	losses: { [string]: { speed: number, review: number } },
}

local StaffPower = {}

-- Значки направлений (без языка)
StaffPower.icons =
	{ gameplay = "🎮", graphics = "🎨", sound = "🎵", story = "📖" } :: { [string]: string }

StaffPower.power = nil :: Power?

local changed = Instance.new("BindableEvent")
StaffPower.changed = changed.Event

local function num(value: any): number
	return if type(value) == "number" and value == value then value else 0
end

-- Разобрать мощность из сети (сервер, но всё равно проверяем типы)
function StaffPower.parse(raw: any): Power
	local source = if type(raw) == "table" then raw else {}
	local quality = {}
	for _, key in Skills.keys do
		quality[key] = num(type(source.quality) == "table" and source.quality[key])
	end
	local losses = {}
	if type(source.losses) == "table" then
		for id, loss in source.losses do
			if type(id) == "string" and type(loss) == "table" then
				losses[id] = { speed = num(loss.speed), review = num(loss.review) }
			end
		end
	end
	return {
		speed = num(source.speed),
		quality = quality,
		review = num(source.review),
		breaks = math.max(math.floor(num(source.breaks)), 0),
		losses = losses,
	}
end

-- +45% / −15%
function StaffPower.percent(value: number): string
	local n = math.floor(value * 100 + 0.5)
	return (if n < 0 then "−" else "+") .. tostring(math.abs(n)) .. "%"
end

-- +0.35 / −0.1 (без лишних нулей)
function StaffPower.score(value: number): string
	local text = string.format("%.2f", math.abs(value)):gsub("0+$", ""):gsub("%.$", "")
	return (if value < -0.004 then "−" else "+") .. text
end

-- «🎮 +0.1 · 🎨 +0.2 …» — только ненулевые направления
function StaffPower.qualityLine(power: Power): string
	local parts = {}
	for _, key in Skills.keys do
		local value = power.quality[key] or 0
		if math.abs(value) > 0.004 then
			table.insert(parts, StaffPower.icons[key] .. " " .. StaffPower.score(value))
		end
	end
	return table.concat(parts, " · ")
end

-- Короткая строка для HUD: «👥 ⚡ +45% · ⭐ +0.4 · ☕ 2»
function StaffPower.compact(power: Power): string
	local line = "👥 ⚡ "
		.. StaffPower.percent(power.speed)
		.. " · ⭐ "
		.. StaffPower.score(power.review)
	if power.breaks > 0 then
		line ..= " · ☕ " .. power.breaks
	end
	return line
end

-- В своём потоке: StaffRemotes ждут сервер, а модуль нужен HUD с первой секунды (аудит P2-20)
task.spawn(function()
	local StaffRemotes = require(ReplicatedStorage.Shared.StaffRemotes)
	StaffRemotes.StaffPower.OnClientEvent:Connect(function(raw: any)
		StaffPower.power = StaffPower.parse(raw)
		changed:Fire()
	end)
end)

return StaffPower
