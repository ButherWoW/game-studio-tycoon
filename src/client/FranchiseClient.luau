--!strict
-- Франшизы на клиенте (FranchiseService): снимок с сервера и блок «📚 Франшизы» в окне
-- «Создать игру»: «Новая игра» или «Продолжение франшизы», кандидаты «сделать франшизой».
-- Не контроллер: общий модуль для CreateGameWindow. Решения (жанр, доход, фанаты) — на сервере.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local DepthRemotes = require(Shared.DepthRemotes)
local Franchises = require(Shared.Config.Franchises)
local Genres = require(Shared.Config.Genres)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local ROW_HEIGHT = 36
local GAP = 6
local MAX_NAME_LENGTH = 30

local FranchiseClient = {}

FranchiseClient.state = { list = {}, candidates = {}, serverTime = 0, max = Franchises.maxFranchises } :: any
-- Выбранная франшиза для следующей игры (nil — новая игра)
FranchiseClient.selected = nil :: number?

local changed = Instance.new("BindableEvent")
FranchiseClient.changed = changed.Event
-- Разница часов: сервер прислал serverTime — дальше считаем по GetServerTimeNow

local function list(): { any }
	local value = FranchiseClient.state.list
	return if type(value) == "table" then value else {}
end

local function candidates(): { any }
	local value = FranchiseClient.state.candidates
	return if type(value) == "table" then value else {}
end

function FranchiseClient.find(id: number?): any
	if id == nil then
		return nil
	end
	for _, f in list() do
		if f.id == id then
			return f
		end
	end
	return nil
end

DepthRemotes.FranchiseState.OnClientEvent:Connect(function(state: any)
	if type(state) ~= "table" then
		return
	end
	FranchiseClient.state = state
	-- Франшизы больше нет (старое сохранение, сброс) — снова новая игра
	if FranchiseClient.selected and not FranchiseClient.find(FranchiseClient.selected) then
		FranchiseClient.selected = nil
	end
	changed:Fire()
end)

function FranchiseClient.request()
	DepthRemotes.FranchiseRequest:FireServer()
end

-- Для перерисовки окна: что поменялось в блоке
function FranchiseClient.key(): string
	local parts = { tostring(FranchiseClient.selected) }
	for _, f in list() do
		table.insert(parts, string.format("%s:%s:%s", tostring(f.id), tostring(f.fans), tostring(f.entries)))
	end
	for _, c in candidates() do
		table.insert(parts, tostring(c.key))
	end
	return table.concat(parts, ",")
end

-- Игрок выбрал другой жанр: продолжение франшизы — только в её жанре
function FranchiseClient.genrePicked(genreId: string)
	local f = FranchiseClient.find(FranchiseClient.selected)
	if f and f.genreId ~= genreId then
		FranchiseClient.selected = nil
	end
end

-- «Игра» -> «Игра 2», «Игра 2» -> «Игра 3» (как sequelName на сервере)
function FranchiseClient.sequelName(name: string): string
	local base, number = name:match("^(.-)%s+(%d+)$")
	local hasNumber = base ~= nil and base ~= "" and number ~= nil
	local nextNumber = if hasNumber then (tonumber(number) or 1) + 1 else 2
	local baseName = if hasNumber then base :: string else name
	local suffix = " " .. tostring(math.min(nextNumber, 999))
	local maxBase = MAX_NAME_LENGTH - #suffix
	local length = utf8.len(baseName) or 0
	if length > maxBase then
		baseName = baseName:sub(1, (utf8.offset(baseName, maxBase + 1) or (#baseName + 1)) - 1)
	end
	return baseName .. suffix
end

local function fansText(fans: number): string
	if fans >= 1_000_000 then
		return string.format("%.1fM", fans / 1_000_000)
	elseif fans >= 1_000 then
		return string.format("%.1fk", fans / 1_000)
	end
	return tostring(math.floor(fans))
end
FranchiseClient.fansText = fansText

local function row(parent: Instance, order: number): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	frame.Parent = parent
	return frame
end

-- Блок в прокрутке окна (LayoutOrder = order). onPick(франшиза или nil) — окно подставляет жанр,
-- тему и название-продолжение. Пусто (нет франшиз и кандидатов) — блока нет
function FranchiseClient.build(parent: Instance, order: number, onPick: (any) -> ())
	local all = list()
	local hits = candidates()
	if #all == 0 and #hits == 0 then
		return
	end
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.LayoutOrder = order
	Ui.list(box, GAP)
	box.Parent = parent
	-- Высоту считаем сами (как сетки окна): AutomaticSize вложенных рамок пересчитывается с опозданием
	local n = 0
	local height = -GAP
	local function nextOrder(h: number?): number
		n += 1
		height += (h or 20) + GAP
		return n
	end

	Ui.label(box, ClientState.t("fr_title"), 22, nil, Ui.colors.muted).LayoutOrder = nextOrder(22)

	-- Кнопки по две в ряд: «Новая игра» и франшизы
	local buttons: { { text: string, selected: boolean, pick: any } } = {
		{ text = ClientState.t("fr_new_game"), selected = FranchiseClient.selected == nil, pick = false },
	}
	for _, f in all do
		table.insert(buttons, {
			text = ClientState.t("fr_entry", { name = f.name, fans = fansText(tonumber(f.fans) or 0) }),
			selected = FranchiseClient.selected == f.id,
			pick = f,
		})
	end
	local current: Frame? = nil
	for i, spec in buttons do
		if i % 2 == 1 then
			current = row(box, nextOrder(ROW_HEIGHT))
		end
		local b = Ui.button(
			current :: Frame,
			spec.text,
			if spec.selected then Ui.colors.good else Ui.colors.primary,
			function()
				local f = if spec.pick == false then nil else spec.pick
				FranchiseClient.selected = if f then f.id else nil
				onPick(f)
			end
		)
		b.Size = UDim2.new(0.5, -GAP / 2, 1, 0)
		b.LayoutOrder = i
	end

	local f = FranchiseClient.find(FranchiseClient.selected)
	if f then
		local genre = Genres[f.genreId]
		local hype = math.floor(Franchises.hype(tonumber(f.fans) or 0) * 100 + 0.5)
		Ui.label(
			box,
			ClientState.t("fr_info", {
				genre = if genre then ClientState.localName(genre) else f.genreId,
				hype = hype,
				entries = f.entries,
			}),
			20,
			Enum.Font.GothamMedium,
			Ui.colors.money
		).LayoutOrder =
			nextOrder()
		local since = workspace:GetServerTimeNow() - (tonumber(f.lastAt) or 0)
		if since < Franchises.fatigueSeconds then
			Ui.label(
				box,
				ClientState.t(
					"fr_fatigue_warn",
					{ percent = math.floor((1 - Franchises.fatigueMultiplier) * 100 + 0.5) }
				),
				20,
				Enum.Font.GothamMedium,
				Ui.colors.bad
			).LayoutOrder =
				nextOrder()
		end
	end

	if #hits > 0 then
		local max = tonumber(FranchiseClient.state.max) or Franchises.maxFranchises
		if #all >= max then
			Ui.label(
				box,
				ClientState.t("fr_full", { max = max }),
				20,
				Enum.Font.GothamMedium,
				Ui.colors.muted
			).LayoutOrder =
				nextOrder()
		else
			Ui.label(
				box,
				ClientState.t("fr_hint", { score = Franchises.minScore }),
				20,
				Enum.Font.GothamMedium,
				Ui.colors.muted
			).LayoutOrder =
				nextOrder()
			for _, c in hits do
				local b = Ui.button(
					box,
					ClientState.t("fr_make", { name = c.name, score = c.score }),
					Ui.colors.locked,
					function()
						DepthRemotes.FranchiseCreate:FireServer(c.key)
					end
				)
				b.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
				b.LayoutOrder = nextOrder(ROW_HEIGHT)
			end
		end
	end
	box.Size = UDim2.new(1, 0, 0, math.max(height, 0))
end

return FranchiseClient
