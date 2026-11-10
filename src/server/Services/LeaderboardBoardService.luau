--!strict
-- Физические доски лидеров на площади у спавна (запрос Dev 1, issue #14 п. 4): «Лучшая оценка»,
-- «Всего игр», «Фанаты студии». Сервер только ставит детали (тег LeaderboardBoard, атрибут Kind),
-- содержимое рисует клиент (LeaderboardBoards) из QuestRemotes.LeaderboardData — на языке игрока.
-- Данные — те же топ-10 из LeaderboardService. Рамка Neon: светится ночью.

local CollectionService = game:GetService("CollectionService")

local TAG = "LeaderboardBoard"
local KINDS = { "best", "games", "fans" }
local BOARD_SIZE = Vector3.new(9, 11, 0.5)
local RADIUS = 17 -- от центра площади (сама площадка 16×16 остаётся свободной)
local ANGLES = { 20, 60, 100, 140, 180, 220, 260, 300, 340 } -- кандидаты, берём первые свободные
local PATH_CLEAR = 5 -- до плиты дорожки
local PATH_PREFIXES =
	{ "^GardenWalk_", "^PondWalk_", "^Promenade_", "^BridgeExit_", "^PlotApproach_", "^Path_" }

local LeaderboardBoardService = {}

local function spawnCenter(): (Vector3, number)
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn and spawn:IsA("BasePart") then
		return Vector3.new(spawn.Position.X, 0, spawn.Position.Z), spawn.Position.Y
	end
	return Vector3.zero, 0
end

local function isWalk(name: string): boolean
	for _, prefix in PATH_PREFIXES do
		if string.find(name, prefix) then
			return true
		end
	end
	return false
end

local function nearWalk(point: Vector3, walks: { BasePart }): boolean
	for _, walk in walks do
		local here = walk.CFrame:PointToObjectSpace(point)
		local half = walk.Size / 2
		if math.abs(here.X) < half.X + PATH_CLEAR and math.abs(here.Z) < half.Z + PATH_CLEAR then
			return true
		end
	end
	return false
end

local function isFree(cframe: CFrame): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = CollectionService:GetTagged(TAG)
	-- С 1 stud над землёй: без травы и плит, но со стволами, фонарями и мебелью
	local parts = workspace:GetPartBoundsInBox(
		cframe * CFrame.new(0, 1 + BOARD_SIZE.Y / 2, 0),
		Vector3.new(BOARD_SIZE.X + 2, BOARD_SIZE.Y, 4),
		params
	)
	for _, part in parts do
		if part.CanCollide or part.Transparency < 1 then
			return false
		end
	end
	return true
end

local function part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function build(kind: string, cframe: CFrame)
	local model = Instance.new("Model")
	model.Name = "LeaderboardBoard_" .. kind
	local board = part(
		"Board",
		BOARD_SIZE,
		cframe * CFrame.new(0, BOARD_SIZE.Y / 2 + 1.2, 0),
		Color3.fromRGB(26, 30, 48),
		Enum.Material.SmoothPlastic,
		model
	)
	board:SetAttribute("Kind", kind)
	CollectionService:AddTag(board, TAG)
	local half = BOARD_SIZE.X / 2
	-- Светящаяся рамка (Neon) сверху и снизу и две опоры
	part(
		"GlowTop",
		Vector3.new(BOARD_SIZE.X + 0.6, 0.3, 0.8),
		board.CFrame * CFrame.new(0, BOARD_SIZE.Y / 2 + 0.15, 0),
		Color3.fromRGB(255, 201, 60),
		Enum.Material.Neon,
		model
	)
	part(
		"GlowBottom",
		Vector3.new(BOARD_SIZE.X + 0.6, 0.3, 0.8),
		board.CFrame * CFrame.new(0, -BOARD_SIZE.Y / 2 - 0.15, 0),
		Color3.fromRGB(255, 201, 60),
		Enum.Material.Neon,
		model
	)
	for _, side in { -1, 1 } do
		part(
			"Leg",
			Vector3.new(0.5, 1.4, 0.5),
			cframe * CFrame.new(side * (half - 0.8), 0.7, 0),
			Color3.fromRGB(60, 64, 80),
			Enum.Material.Metal,
			model
		)
	end
	model.Parent = workspace
end

function LeaderboardBoardService.start()
	if workspace:FindFirstChild("LeaderboardBoards") or #CollectionService:GetTagged(TAG) > 0 then
		return
	end
	local center, y = spawnCenter()
	local walks = {}
	for _, item in workspace:GetDescendants() do
		if item:IsA("BasePart") and isWalk(item.Name) then
			table.insert(walks, item)
		end
	end
	local placed = 0
	for _, angle in ANGLES do
		if placed >= #KINDS then
			break
		end
		local rad = math.rad(angle)
		local pos = Vector3.new(center.X + math.cos(rad) * RADIUS, y, center.Z + math.sin(rad) * RADIUS)
		-- Лицом к центру площади (перед детали у SurfaceGui Front — это −Z)
		local cframe = CFrame.lookAt(pos, Vector3.new(center.X, y, center.Z))
		if not nearWalk(pos, walks) and isFree(cframe) then
			placed += 1
			build(KINDS[placed], cframe)
		end
	end
	if placed < #KINDS then
		warn(
			"[LeaderboardBoardService] Свободных мест на площади только для досок:",
			placed
		)
	end
end

return LeaderboardBoardService
