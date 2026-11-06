--!strict
-- Очередь всплывающих окон, которые открываются сами (награда за вход, «Пока тебя не было»,
-- предложение банка, подсказка о забастовке). Раньше при входе они ложились друг на друга
-- (DisplayOrder 15 и 25) и выскакивали поверх туториала. Теперь — по одному: следующее ждёт,
-- пока закроются окна, кончится туториал и событие разработки уйдёт с экрана (busy), и ещё
-- GAP_SECONDS после этого. Открытие по кнопке (меню, плашка) идёт мимо очереди — сразу.
-- Не контроллер: общий модуль DailyRewardWindow, OfflineWindow, ComebackWindow, LoanWindow, StrikeTip;
-- busy() берёт и карточка события компании (CompanyEventController).

local Players = game:GetService("Players")

local OfferClient = require(script.Parent.OfferClient)
local Ui = require(script.Parent.Ui)

local CHECK_SECONDS = 0.5
local GAP_SECONDS = 1 -- пауза между окнами: не выскакивают одно за другим в тот же кадр

local PopupQueue = {}

type Entry = { key: string, show: () -> () }

local player = Players.LocalPlayer
local queue: { Entry } = {}
local running = false
local freeSince = 0 -- os.clock(), с какого момента ничего не мешает

-- Экран занят: открыто окно игры, идёт вступление или туториал, окно предложения или событие
-- разработки (выбор или быстрое) на экране
function PopupQueue.busy(): boolean
	if
		Ui.anyWindowOpen()
		or player:GetAttribute("TutorialActive") == true
		or player:GetAttribute("IntroActive") == true
	then
		return true
	end
	if OfferClient.popupOpen() then
		return true
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	for _, name in { "DevEventPopup", "QuickEventPopup" } do
		local screen = playerGui and playerGui:FindFirstChild(name)
		if screen and #screen:GetChildren() > 0 then
			return true
		end
	end
	return false
end

-- В очереди ещё есть окна (карточка события компании их пропускает вперёд)
function PopupQueue.pending(): boolean
	return #queue > 0
end

-- Один шаг очереди. Ошибка в show одного окна не должна навсегда оставить running = true
-- (иначе ни одно окно входа больше не откроется) — аудит P2-6
local function step()
	local now = os.clock()
	if PopupQueue.busy() then
		freeSince = now
	elseif now - freeSince >= GAP_SECONDS then
		local entry = table.remove(queue, 1)
		if entry then
			-- show сама проверяет, актуально ли ещё окно (награду могли уже забрать)
			local ok, err = pcall(entry.show)
			if not ok then
				warn("[PopupQueue] popup " .. entry.key .. " failed:", err)
			end
		end
		freeSince = now
	end
end

local function run()
	running = true
	while #queue > 0 do
		task.wait(CHECK_SECONDS)
		local ok, err = pcall(step)
		if not ok then
			warn("[PopupQueue] step failed:", err)
		end
	end
	running = false
end

-- Предложения доната ждут, пока очередь окон входа (награда, офлайн-доход…) не опустеет:
-- стартовый набор не выскакивает между наградой за вход и «Пока тебя не было»
OfferClient.addBlocker(PopupQueue.pending)

-- Поставить окно в очередь; окно с тем же key заменяется (не показываем дважды)
function PopupQueue.push(key: string, show: () -> ())
	PopupQueue.remove(key)
	table.insert(queue, { key = key, show = show })
	if not running then
		task.spawn(run)
	end
end

-- Убрать из очереди (окно больше не нужно: награду забрали, предложение сняли)
function PopupQueue.remove(key: string)
	for i = #queue, 1, -1 do
		if queue[i].key == key then
			table.remove(queue, i)
		end
	end
end

return PopupQueue
