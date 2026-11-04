--!strict
-- Последние данные игрока с сервера и язык интерфейса — общие для всех контроллеров.

local LocalizationService = game:GetService("LocalizationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local LanguageRemotes = require(ReplicatedStorage.Shared.LanguageRemotes)
local Texts = require(ReplicatedStorage.Shared.Config.Texts)
local Genres = require(ReplicatedStorage.Shared.Config.Genres)
local Topics = require(ReplicatedStorage.Shared.Config.Topics)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)

local ClientState = {}

-- Снимок из DataService.replicate (nil, пока сервер не прислал)
ClientState.data = nil :: any
ClientState.developing = false

-- Код языка Roblox ("pt-br", "nb-no", "zh-cn"…) -> код из Texts.languages; нет такого -> en
local LOCALE_ALIASES: { [string]: string } = {
	nb = "no",
	nn = "no",
	zh = "zh-cn",
	ua = "uk",
	sh = "sr",
}

local function languageFromLocale(locale: string): Texts.Lang
	local id: string = (locale:lower():gsub("_", "-"))
	if Texts.isLanguage(id) then
		return id
	end
	local base = id:match("^(%a+)") or ""
	base = LOCALE_ALIASES[base] or base
	return if Texts.isLanguage(base) then base else "en"
end

ClientState.lang = languageFromLocale(LocalizationService.RobloxLocaleId) :: Texts.Lang
-- Сочетания, которые игрок уже выпускал в этой сессии: "genre/topic" -> лучшая оценка
ClientState.knownCombos = {} :: { [string]: number }

local changed = Instance.new("BindableEvent")
-- Отдельный сигнал смены языка: окна, которые открываются при входе (название студии,
-- офлайн-доход, награда за вход, банк), перерисовываются, когда придёт сохранённый язык (отчёт #2, п. 3)
local langChangedEvent = Instance.new("BindableEvent")
ClientState.langChanged = langChangedEvent.Event
local seatChangedEvent = Instance.new("BindableEvent")
ClientState.seatChanged = seatChangedEvent.Event

-- Сидит ли игрок за своим компьютером (Seat «PcSeat» на своём участке, см. PlotService.isAtPc)
function ClientState.atPc(): boolean
	local player = game:GetService("Players").LocalPlayer
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat or seat.Name ~= "PcSeat" then
		return false
	end
	-- Общий ноутбук в парке — компьютер, пока нет гаража (атрибут ставит PlotService)
	if seat:GetAttribute("Public") == true then
		return player:GetAttribute("OwnsGarage") ~= true
	end
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild(tostring(player:GetAttribute("PlotName")))
	return plot ~= nil and seat:IsDescendantOf(plot)
end

local function watchSeat(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		seatChangedEvent:Fire(ClientState.atPc())
	end)
end
do
	local player = game:GetService("Players").LocalPlayer
	if player.Character then
		task.spawn(watchSeat, player.Character)
	end
	player.CharacterAdded:Connect(watchSeat)
end
ClientState.changed = changed.Event

function ClientState.t(key: string, vars: { [string]: any }?): string
	return Texts.format(ClientState.lang, key, vars)
end

-- Сменить язык: перерисовать интерфейс и (если save ~= false) запомнить выбор на сервере
function ClientState.setLang(code: string, save: boolean?)
	if not Texts.isLanguage(code) then
		return
	end
	if save ~= false then
		LanguageRemotes.SetLanguage:FireServer(code)
	end
	if code ~= ClientState.lang then
		ClientState.lang = code
		langChangedEvent:Fire()
		changed:Fire()
	end
end

-- ===== Без спойлеров на релизе (отчёт #2, п. 6) =====
-- Сервер начисляет доход до того, как окно релиза откроет оценки. Пока окно «раскрывает»
-- оценку, HUD показывает деньги без дохода этой игры, а тост «хит» ждёт раскрытия.
local REVEAL_TIMEOUT = 15 -- окно так и не сказало «раскрыто» — всё равно показываем
-- Тост хита приходит раньше GameReleased: столько ждём, не начнётся ли раскрытие
local REVEAL_GRACE = 0.3

local hiddenCash = 0
local revealToken = 0
local revealPending = false
local afterReveal: { () -> () } = {}

-- Окно релиза начало показ: прячем доход (revenue − погашение кредита) до markRevealed
function ClientState.beginReveal(hidden: number): number
	revealToken += 1
	hiddenCash += math.max(hidden, 0)
	revealPending = true
	local token = revealToken
	task.delay(REVEAL_TIMEOUT, function()
		ClientState.markRevealed(token)
	end)
	changed:Fire()
	return token
end

-- Оценка показана (или окно закрыто): деньги в HUD и отложенные тосты — сразу
function ClientState.markRevealed(token: number)
	if token ~= revealToken or not revealPending then
		return
	end
	revealPending = false
	hiddenCash = 0
	local queued = afterReveal
	afterReveal = {}
	changed:Fire()
	for _, callback in queued do
		task.spawn(callback)
	end
end

-- Деньги для HUD: без дохода релиза, оценку которого игрок ещё не увидел
function ClientState.displayCash(): number
	local data = ClientState.data
	local cash = if data then tonumber(data.cash) or 0 else 0
	return if revealPending then math.max(cash - hiddenCash, 0) else cash
end

-- Выполнить после раскрытия оценки (если релиз сейчас раскрывается или вот-вот начнётся)
function ClientState.afterReveal(callback: () -> ())
	task.delay(REVEAL_GRACE, function()
		if revealPending then
			table.insert(afterReveal, callback)
		else
			callback()
		end
	end)
end

-- Текст из конфига на языке игрока: перевод по ключу из Locales, иначе поля ru/en конфига
function ClientState.localText(key: string, ru: string, en: string): string
	return Texts.lookup(ClientState.lang, key) or (if ClientState.lang == "ru" then ru else en)
end

-- Имя жанра или темы на языке игрока: перевод genre_<id>/topic_<id>, иначе name/nameEn
function ClientState.localName(item: { name: string, nameEn: string }): string
	local id = (item :: any).id
	local prefix = if type(id) ~= "string"
		then nil
		elseif (Genres :: any)[id] == item then "genre_"
		elseif (Topics :: any)[id] == item then "topic_"
		elseif (Stages :: any)[(item :: any).level] == item then "stage_"
		else nil
	if prefix then
		local translated = Texts.lookup(ClientState.lang, prefix .. id)
		if translated then
			return translated
		end
	end
	return if ClientState.lang == "ru" then item.name else item.nameEn
end

Remotes.DataChanged.OnClientEvent:Connect(function(data)
	ClientState.data = data
	changed:Fire()
end)

Remotes.DevelopmentProgress.OnClientEvent:Connect(function()
	if not ClientState.developing then
		ClientState.developing = true
		changed:Fire()
	end
end)

Remotes.GameReleased.OnClientEvent:Connect(function(info)
	ClientState.developing = false
	if type(info.genreId) == "string" and type(info.topicId) == "string" then
		local key = info.genreId .. "/" .. info.topicId
		ClientState.knownCombos[key] = math.max(ClientState.knownCombos[key] or 0, info.score)
	end
	changed:Fire()
end)

return ClientState
