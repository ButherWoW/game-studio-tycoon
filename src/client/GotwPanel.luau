--!strict
-- Вкладка «🏆 Игра недели» окна 📊 (RivalWindow): топ-10 игр недели между серверами, своя лучшая
-- игра и победители прошлой недели. Не контроллер: RivalWindow зовёт render(frame).
-- Данные — GotwService (GotwRemotes.GotwBoard), здесь только показ.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Genres = require(Shared.Config.Genres)
local Gotw = require(Shared.Config.Gotw)
local GotwRemotes = require(Shared.GotwRemotes)
local Texts = require(Shared.Config.Texts)
local Images = require(Shared.Config.Images)
local ArtIcon = require(script.Parent.ArtIcon)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local ROW_HEIGHT = 46
local MEDALS = { "🥇", "🥈", "🥉" }

local player = Players.LocalPlayer

local GotwPanel = {}

local state: any = nil
local changedEvent = Instance.new("BindableEvent")
-- Пришла новая таблица: окно перерисует вкладку, плашка воскресенья обновит лидера
GotwPanel.changed = changedEvent.Event

GotwRemotes.GotwBoard.OnClientEvent:Connect(function(data: any)
	if type(data) == "table" then
		state = data
		changedEvent:Fire()
	end
end)

function GotwPanel.request()
	GotwRemotes.GotwRequest:FireServer()
end

-- Лидер недели для плашки: { name, studio } или nil
function GotwPanel.leader(): any
	local rows = if type(state) == "table" then state.rows else nil
	local first = if type(rows) == "table" then rows[1] else nil
	return if type(first) == "table" then first else nil
end

local function genreName(id: any): string
	local genre = if type(id) == "string" then Genres[id] else nil
	return if genre then ClientState.localName(genre) else ""
end

local function line(parent: Instance, text: string, order: number, color: Color3?, height: number?): TextLabel
	local label = Ui.label(parent, text, height or 26, nil, color or Ui.colors.muted)
	label.LayoutOrder = order
	label.Size = UDim2.new(1, -8, 0, height or 26)
	return label
end

local function row(parent: Instance, entry: any, order: number)
	local rank = tonumber(entry.rank) or 0
	local you = entry.userId == player.UserId
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = if you then Color3.fromRGB(40, 62, 52) else Color3.fromRGB(44, 46, 66)
	frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	frame.LayoutOrder = order
	Ui.corner(frame, 10)
	local place = MEDALS[rank] or (rank .. ".")
	local title = Ui.label(
		frame,
		string.format("%s %s", place, tostring(entry.name)),
		24,
		nil,
		if you then Ui.colors.good else Ui.colors.text
	)
	title.Position = UDim2.fromOffset(10, 2)
	title.Size = UDim2.new(0.66, -10, 0, 24)
	local sub = Ui.label(
		frame,
		ClientState.t("gotw_row_by", {
			studio = tostring(entry.studio),
			player = tostring(entry.player),
			genre = genreName(entry.genreId),
		}),
		18,
		Enum.Font.GothamMedium,
		Ui.colors.muted
	)
	sub.Position = UDim2.fromOffset(10, 25)
	sub.Size = UDim2.new(0.66, -10, 0, 18)
	local score =
		Ui.label(frame, "★ " .. tostring(entry.score), 22, nil, Ui.scoreColor(tonumber(entry.score) or 0))
	score.TextXAlignment = Enum.TextXAlignment.Right
	score.Position = UDim2.new(0.66, 0, 0, 2)
	score.Size = UDim2.new(0.34, -10, 0, 22)
	local money = Ui.label(frame, Texts.money(tonumber(entry.revenue) or 0), 18, nil, Ui.colors.money)
	money.TextXAlignment = Enum.TextXAlignment.Right
	money.Position = UDim2.new(0.66, 0, 0, 25)
	money.Size = UDim2.new(0.34, -10, 0, 18)
	frame.Parent = parent
end

local function duration(seconds: number): string
	local s = math.max(math.floor(seconds), 0)
	local days = s // 86400
	local hours = (s % 86400) // 3600
	if days > 0 then
		return ClientState.t("gotw_time_days", { days = days, hours = hours })
	end
	return string.format("%d:%02d", hours, (s % 3600) // 60)
end

-- Нарисовать вкладку в frame (ScrollingFrame с UIListLayout); footer — подпись внизу окна
function GotwPanel.render(frame: Instance, footer: TextLabel?)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local title = line(frame, ClientState.t("gotw_title"), nextOrder(), Ui.colors.money, 32)
	title.Font = Ui.titleFontFor(ClientState.lang)
	-- Иконка «Игры недели» Астры (Images.misc.gotwIcon, V28) вместо 🏆
	ArtIcon.prefix(title, "🏆", Images.misc.gotwIcon, 30)
	line(frame, ClientState.t("gotw_how"), nextOrder(), nil, 40).TextWrapped = true
	if type(state) ~= "table" then
		line(frame, ClientState.t("quests_loading"), nextOrder())
		if footer then
			footer.Text = ""
		end
		return
	end
	local endsAt = tonumber(state.endsAt) or 0
	line(
		frame,
		ClientState.t("gotw_ends", {
			week = tostring(state.weekKey),
			time = duration(endsAt - workspace:GetServerTimeNow()),
		}),
		nextOrder(),
		Ui.colors.text
	)
	local rows = if type(state.rows) == "table" then state.rows else {}
	if state.available ~= true then
		line(frame, ClientState.t("gotw_unavailable"), nextOrder(), Ui.colors.bad)
	elseif #rows == 0 then
		line(frame, ClientState.t("gotw_empty"), nextOrder())
	end
	for _, entry in rows do
		if type(entry) == "table" then
			row(frame, entry, nextOrder())
		end
	end
	local last = if type(state.last) == "table" then state.last else {}
	if #last > 0 then
		local head = line(frame, ClientState.t("gotw_last_title"), nextOrder(), Ui.colors.money, 28)
		head.Font = Ui.titleFontFor(ClientState.lang)
		for i = 1, math.min(#last, 3) do
			if type(last[i]) == "table" then
				row(frame, last[i], nextOrder())
			end
		end
	end
	line(
		frame,
		ClientState.t(
			"gotw_rewards",
			{ minutes = Gotw.rewardMinutes[1], last = Gotw.rewardMinutes[#Gotw.rewardMinutes] }
		),
		nextOrder(),
		nil,
		40
	).TextWrapped =
		true
	if footer then
		local mine = state.mine
		footer.Text = if type(mine) == "table"
			then ClientState.t("gotw_mine", {
				name = tostring(mine.name),
				score = tostring(mine.score),
				revenue = Texts.money(tonumber(mine.revenue) or 0),
			})
			else ClientState.t("gotw_mine_none")
	end
end

return GotwPanel
