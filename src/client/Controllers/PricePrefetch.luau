--!strict
-- Загружает живые цены R$ всех товаров и геймпассов при старте (RobuxPrice, Managed Pricing),
-- чтобы окна показывали региональную цену сразу, а не цену из Config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local RobuxPrice = require(script.Parent.Parent.RobuxPrice)

local CONFIGS = {
	"AdCampaigns",
	"Console",
	"Construction",
	"FurnitureStyles",
	"GamePasses",
	"InteriorFinishes",
	"Mascots",
	"Posters",
	"Products",
	"Season",
	"Skins",
	"Social",
	"Training",
}

local PricePrefetch = {}

function PricePrefetch.start()
	local configs = Shared.Config
	for _, name in CONFIGS do
		local module = configs:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local ok, config = pcall(require, module)
			if ok then
				RobuxPrice.prefetchConfig(config)
			end
			task.wait() -- не пачкой в один кадр
		end
	end
end

return PricePrefetch
