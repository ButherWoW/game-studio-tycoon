--!strict
-- Очередь тостов франшиз, контрактов и конкурентов (как тосты UnlockNotice): по одному,
-- под окнами, над HUD. Не контроллер: общий модуль FranchiseNotice, ContractController, RivalWindow.

local Players = game:GetService("Players")

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local TOAST_SECONDS = 4

local DepthToast = {}

local queue: { { text: string, color: Color3 } } = {}
local showing = false

local function showNext()
	local item = table.remove(queue, 1)
	if not item then
		showing = false
		return
	end
	showing = true
	local screen = Instance.new("ScreenGui")
	screen.Name = "DepthToast"
	screen.DisplayOrder = 4
	screen.ResetOnSpawn = false
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local label = Ui.label(screen, item.text, 36, Ui.titleFontFor(ClientState.lang), item.color)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.24)
	label.Size = UDim2.new(0.9, 0, 0, 36)
	label.BackgroundColor3 = Ui.colors.panel
	label.BackgroundTransparency = 0.2
	Ui.corner(label, 10)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(620, 36)
	limit.Parent = label
	task.delay(TOAST_SECONDS, function()
		screen:Destroy()
		showNext()
	end)
end

function DepthToast.show(text: string, color: Color3?)
	table.insert(queue, { text = text, color = color or Ui.colors.good })
	if not showing then
		showNext()
	end
end

return DepthToast
