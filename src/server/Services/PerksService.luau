--!strict
-- Платные и исследовательские «перки», которым не место в DevelopmentService (5.9, 3.8):
--   * тумблер «Авто-релиз» (сам авто-релиз — DevelopmentService.maybeAutoRelease);
--   * «Издательство»: роялти с последних игр раз в Research.PUBLISHING.intervalSeconds, онлайн;
--   * VIP-офис: золотая табличка над участком.
-- Данные — (profile :: any).perks = { autoRelease, royalties } (лениво, defaultProfile не трогаем).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local PaidRemotes = require(Shared.PaidRemotes)
local GamePasses = require(Shared.Config.GamePasses)
local Research = require(Shared.Config.Research)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local ShopService = require(script.Parent.ShopService)
local ResearchService = require(script.Parent.ResearchService)
local DevelopmentService = require(script.Parent.DevelopmentService)

type PerksData = {
	autoRelease: boolean, -- тумблер в HUD; по умолчанию ВЫКЛЮЧЕН (с 06.11 игрок включает сам)
	autoReleaseOptIn: boolean?, -- true: решение по тумблеру уже принято, миграцию «выкл» не повторяем
	royalties: { number }, -- доход последних игр, старые в начале
}

local TOGGLE_COOLDOWN = 0.5
local VIP_CHECK_SECONDS = 5 -- геймпасс могут купить посреди сессии
local VIP_SIGN_NAME = "VipSign"

local PerksService = {}
local lastToggle: { [Player]: number } = {}

local function getData(player: Player): PerksData?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local p = profile :: any
	if type(p.perks) ~= "table" then
		p.perks = { autoRelease = false, autoReleaseOptIn = true, royalties = {} }
	end
	local data = p.perks :: PerksData
	-- 06.11 (владелец): «Авто-релиз» бесконечно выпускал «Игра 2», «Игра 3»… сам, пока игрок сидит за ПК.
	-- Теперь по умолчанию выключен; старым сохранениям один раз ставим «выкл» (потом выбор игрока не трогаем)
	if type(data.autoRelease) ~= "boolean" or data.autoReleaseOptIn ~= true then
		data.autoRelease = false
		data.autoReleaseOptIn = true
	end
	if type(data.royalties) ~= "table" then
		data.royalties = {}
	end
	-- Из сохранения берём только конечные неотрицательные числа
	local clean = {}
	for _, value in data.royalties do
		if type(value) == "number" and value == value and value >= 0 and value < math.huge then
			table.insert(clean, value)
		end
	end
	while #clean > Research.PUBLISHING.maxGames do
		table.remove(clean, 1)
	end
	data.royalties = clean
	return data
end

function PerksService.isAutoReleaseOn(player: Player): boolean
	local data = getData(player)
	return data ~= nil and data.autoRelease
end

-- Роялти в минуту; 0, пока «Издательство» не изучено
function PerksService.royaltyPerMinute(player: Player): number
	if not ResearchService.getModifiers(player).publishing then
		return 0
	end
	local data = getData(player)
	if not data then
		return 0
	end
	local total = 0
	for _, revenue in data.royalties do
		total += revenue
	end
	return math.floor(total * Research.PUBLISHING.share)
end

-- Вызывает DevelopmentService.release: запоминаем доход игры для роялти
function PerksService.onGameReleased(player: Player, revenue: number)
	if type(revenue) ~= "number" or revenue ~= revenue or revenue < 0 or revenue == math.huge then
		return
	end
	local data = getData(player)
	if not data then
		return
	end
	table.insert(data.royalties, math.floor(revenue))
	while #data.royalties > Research.PUBLISHING.maxGames do
		table.remove(data.royalties, 1)
	end
end

local function onSetAutoRelease(player: Player, enabled: any)
	if type(enabled) ~= "boolean" then
		return
	end
	local now = os.clock()
	local last = lastToggle[player]
	if last and now - last < TOGGLE_COOLDOWN then
		return
	end
	lastToggle[player] = now
	local data = getData(player)
	if not data then
		return
	end
	data.autoRelease = enabled
	data.autoReleaseOptIn = true
	DevelopmentService.pushState(player)
end

local function payRoyalties()
	local interval = Research.PUBLISHING.intervalSeconds
	for _, player in Players:GetPlayers() do
		if not DataService.get(player) then
			continue
		end
		local perMinute = PerksService.royaltyPerMinute(player)
		if perMinute > 0 then
			DataService.addCash(player, math.floor(perMinute * interval / 60))
		end
		-- Заодно обновляем HUD: «Издательство» или слот могли появиться без релиза
		DevelopmentService.pushState(player)
	end
end

-- Золотая табличка «VIP» над участком. Модель: PlotService.rebuild сносит модели участка,
-- а мы ставим её заново по plotChanged и проверкой раз в VIP_CHECK_SECONDS
local function makeSign(plot: BasePart): Model
	local effects = GamePasses.effects
	local model = Instance.new("Model")
	model.Name = VIP_SIGN_NAME
	local part = Instance.new("Part")
	part.Name = "Plate"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Metal
	part.Color = effects.vipSignColor
	part.Size = effects.vipSignSize
	part.CFrame = plot.CFrame * CFrame.new(effects.vipSignOffset)
	part.Parent = model
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(70, 45, 0)
		label.Text = "👑 VIP"
		label.Parent = gui
		gui.Parent = part
	end
	model.PrimaryPart = part
	model.Parent = plot
	return model
end

local function refreshSign(player: Player)
	local plot = PlotService.getPlot(player)
	if not plot then
		return
	end
	local existing = plot:FindFirstChild(VIP_SIGN_NAME)
	local owns = ShopService.ownsPass(player, "vipOffice")
	if owns and not existing then
		makeSign(plot)
	elseif not owns and existing then
		existing:Destroy()
	end
end

function PerksService.start()
	PaidRemotes.SetAutoRelease.OnServerEvent:Connect(onSetAutoRelease)
	Players.PlayerRemoving:Connect(function(player)
		lastToggle[player] = nil
	end)
	PlotService.plotChanged:Connect(function(player: Player)
		refreshSign(player)
	end)

	task.spawn(function()
		while true do
			task.wait(Research.PUBLISHING.intervalSeconds)
			local ok, err = pcall(payRoyalties)
			if not ok then
				warn("[PerksService] Royalties failed:", err)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(VIP_CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(refreshSign, player)
				if not ok then
					warn("[PerksService] VIP sign failed:", err)
				end
			end
		end
	end)
end

return PerksService
