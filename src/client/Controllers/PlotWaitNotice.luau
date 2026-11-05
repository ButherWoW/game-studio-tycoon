--!strict
-- На сервере не больше 12 участков (WorldService, PLOT_COUNT): 13-й игрок встаёт в очередь
-- PlotService и раньше не видел ничего, кроме пустого мира (аудит P1-5). Сервер ставит атрибут
-- игрока PlotWaiting = место в очереди; пока он есть — плашка сверху по центру.

local Players = game:GetService("Players")

local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local PLATE_WIDTH = 560
local PLATE_HEIGHT = 56
local PLATE_TOP = 12

local PlotWaitNotice = {}

function PlotWaitNotice.start()
	local screen = Instance.new("ScreenGui")
	screen.Name = "PlotWaitNotice"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 30 -- над HUD и плашками: без участка играть всё равно нельзя
	screen.Enabled = false

	local plate = Instance.new("Frame")
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.Position = UDim2.new(0.5, 0, 0, PLATE_TOP)
	plate.Size = UDim2.new(0.9, 0, 0, PLATE_HEIGHT)
	plate.BackgroundColor3 = Ui.colors.panel
	plate.BackgroundTransparency = 0.1
	Ui.corner(plate)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(PLATE_WIDTH, PLATE_HEIGHT)
	limit.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Ui.colors.money
	stroke.Parent = plate
	plate.Parent = screen

	local label = Ui.label(plate, "", PLATE_HEIGHT - 16, Ui.titleFontFor(ClientState.lang))
	label.Position = UDim2.fromOffset(12, 8)
	label.Size = UDim2.new(1, -24, 1, -16)
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center

	local function refresh()
		local position = tonumber(player:GetAttribute("PlotWaiting"))
		if position and position > 0 and player:GetAttribute("PlotName") == nil then
			label.Font = Ui.titleFontFor(ClientState.lang)
			label.Text = ClientState.t("fixc_plot_waiting", { n = math.floor(position) })
			screen.Enabled = true
		else
			screen.Enabled = false
		end
	end

	player:GetAttributeChangedSignal("PlotWaiting"):Connect(refresh)
	player:GetAttributeChangedSignal("PlotName"):Connect(refresh)
	ClientState.langChanged:Connect(refresh)
	screen.Parent = player:WaitForChild("PlayerGui")
	refresh()
end

return PlotWaitNotice
