--!strict
-- Настройки игрока (окно 🌐 → вкладка «⚙️ Настройки»). Хранятся в профиле (profile.settings),
-- сервер (SettingsService) принимает только ключи и значения отсюда. Применяет клиент
-- (SettingsController, SoundController, TitleTags…), уведомления — сервер (NotifyService).

export type Values = {
	musicVolume: number, -- множитель громкости музыки 0..1 (SoundGroup «Music»)
	sfxVolume: number, -- множитель громкости звуков 0..1 (SoundGroup «Effects»)
	lowGraphics: boolean, -- «Меньше эффектов»: частицы, искры, конфетти, вспышки
	hideTitles: boolean, -- не показывать титулы над чужими игроками
	hideCapital: boolean, -- не показывать имя и «Капитал» над головой игроков
	hideGuide: boolean, -- не показывать стрелки на земле и подсказку внизу экрана
	hideMascots: boolean, -- не показывать чужих маскотов
	notifications: boolean, -- пинги «Событие дня скоро» (NotifyService.wantsPings)
	wallFade: boolean, -- «Прозрачные стены»: в виде студии стены между камерой и героем полупрозрачные
}

export type Kind = "volume" | "toggle"

local Settings = {}

Settings.defaults = {
	musicVolume = 1,
	sfxVolume = 1,
	lowGraphics = false,
	hideTitles = false,
	hideCapital = false,
	hideGuide = false,
	hideMascots = false,
	notifications = true,
	wallFade = false,
} :: Values

-- Порядок в окне: ключ, вид, ключ текста, (необязательно) ключ пояснения под подписью
Settings.list = {
	{ key = "musicVolume", kind = "volume", text = "set_music" },
	{ key = "sfxVolume", kind = "volume", text = "set_sfx" },
	{ key = "lowGraphics", kind = "toggle", text = "set_low_gfx" },
	{ key = "hideTitles", kind = "toggle", text = "set_hide_titles" },
	{ key = "hideCapital", kind = "toggle", text = "set_hide_capital" },
	{ key = "hideGuide", kind = "toggle", text = "set_hide_guide" },
	{ key = "hideMascots", kind = "toggle", text = "set_hide_mascots" },
	{ key = "notifications", kind = "toggle", text = "set_notify" },
	{ key = "wallFade", kind = "toggle", text = "setting_wallfade", hint = "setting_wallfade_hint" },
} :: { { key: string, kind: Kind, text: string, hint: string? } }

Settings.volumeStep = 0.1 -- шаг кнопок − / +

local kinds: { [string]: Kind } = {}
for _, item in Settings.list do
	kinds[item.key] = item.kind
end

-- Проверенное значение настройки или nil (неизвестный ключ, мусор, NaN)
function Settings.clean(key: any, value: any): any
	local kind = if type(key) == "string" then kinds[key] else nil
	if kind == "toggle" then
		return if type(value) == "boolean" then value else nil
	elseif kind == "volume" then
		if type(value) ~= "number" or value ~= value then
			return nil
		end
		-- Округляем до шага: в профиль не попадает 0.30000000000000004
		local perUnit = math.floor(1 / Settings.volumeStep + 0.5)
		return math.floor(math.clamp(value, 0, 1) * perUnit + 0.5) / perUnit
	end
	return nil
end

-- Полный набор настроек из сырых данных профиля: чего нет или мусор — значение по умолчанию
function Settings.sanitize(raw: any): Values
	local values = table.clone(Settings.defaults) :: any
	if type(raw) == "table" then
		for key in kinds do
			local value = Settings.clean(key, raw[key])
			if value ~= nil then
				values[key] = value
			end
		end
	end
	return values :: Values
end

return Settings
