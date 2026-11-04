--!strict
-- Плашка хакатона в общем стеке под HUD (Ui.bannerStack, LayoutOrder 5): за минуту —
-- «скоро», во время — «×2 скорость» с отсчётом. И короткие уведомления сезона и джема
-- (LiveOpsRemotes.LiveOpsToast): новый уровень сезона, заявка в джем, награда за джем.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LiveOpsRemotes = require(ReplicatedStorage.Shared.LiveOpsRemotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Ui = require(script.Parent.Parent.Ui)

local BANNER_HEIGHT = 28
local BANNER_WIDTH = 400
local TOAST_HEIGHT = 32
local TOAST_WIDTH = 420
local TOAST_SECONDS = 4
local HACKATHON_COLOR = Color3.fromRGB(150, 110, 255)

local LiveOpsBanner = {}

local function clock(seconds: number): string
	seconds = math.max(seconds, 0)
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function showToast(stack: Frame, payload: any)
	if type(payload) ~= "table" or type(payload.key) ~= "string" then
		return
	end
	local old = stack:FindFirstChild("LiveOpsToast")
	if old then
		old:Destroy()
	end
	local toast = Ui.label(
		stack,
		ClientState.t(payload.key, if type(payload.vars) == "table" then payload.vars else nil),
		TOAST_HEIGHT,
		Ui.titleFontFor(ClientState.lang),
		Ui.colors.money
	)
	toast.Name = "LiveOpsToast"
	toast.LayoutOrder = 6
	toast.Size = UDim2.fromOffset(TOAST_WIDTH, TOAST_HEIGHT)
	toast.BackgroundTransparency = 0.1
	toast.BackgroundColor3 = Ui.colors.panel
	toast.TextXAlignment = Enum.TextXAlignment.Center
	Ui.corner(toast, 10)
	task.delay(TOAST_SECONDS, function()
		if toast.Parent then
			toast:Destroy()
		end
	end)
end

function LiveOpsBanner.start()
	local stack = Ui.bannerStack()
	local banner = Ui.label(stack, "", BANNER_HEIGHT, Ui.titleFontFor(ClientState.lang), Ui.colors.text)
	banner.Name = "HackathonBanner"
	banner.LayoutOrder = 5
	banner.Size = UDim2.fromOffset(BANNER_WIDTH, BANNER_HEIGHT)
	banner.BackgroundTransparency = 0.2
	banner.BackgroundColor3 = HACKATHON_COLOR
	banner.TextXAlignment = Enum.TextXAlignment.Center
	banner.Visible = false
	Ui.corner(banner, 10)

	LiveOpsRemotes.LiveOpsToast.OnClientEvent:Connect(function(payload)
		showToast(stack, payload)
	end)

	task.spawn(function()
		-- Объявление «начинается» — один раз на окно
		local announced = 0
		while true do
			local startsAt = ReplicatedStorage:GetAttribute("HackathonStartsAt")
			local endsAt = ReplicatedStorage:GetAttribute("HackathonEndsAt")
			local multiplier = ReplicatedStorage:GetAttribute("HackathonMultiplier") or 2
			local announce = tonumber(ReplicatedStorage:GetAttribute("HackathonAnnounceSeconds")) or 60
			local now = os.time()
			local visible = false
			if type(startsAt) == "number" and type(endsAt) == "number" then
				banner.Font = Ui.titleFontFor(ClientState.lang)
				if now >= startsAt and now < endsAt then
					visible = true
					banner.Text =
						ClientState.t("hackathon_active", { x = multiplier, time = clock(endsAt - now) })
					if announced ~= startsAt then
						announced = startsAt
						showToast(stack, { key = "hackathon_started", vars = { x = multiplier } })
					end
				elseif now < startsAt and startsAt - now <= announce then
					visible = true
					banner.Text =
						ClientState.t("hackathon_soon", { x = multiplier, time = clock(startsAt - now) })
				end
			end
			banner.Visible = visible
			task.wait(1)
		end
	end)
end

return LiveOpsBanner
