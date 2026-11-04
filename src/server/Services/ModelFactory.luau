--!strict
-- Low-poly модели из деталей: мебель апгрейдов и помещения этапов (гараж → офис → этаж → небоскрёб).
-- Каждая модель строится центром основания в (0, 0, 0) и «лицом» к +Z; место на участке
-- задаёт position/rotation в Config/Upgrades и Config/Stages. Участок 60×60, пол модели — y = 0.
-- Если в ServerStorage.Upgrades уже лежит модель (импорт из Studio), WorldService её не трогает.

local ModelFactory = {}

type Opts = {
	material: Enum.Material?,
	transparency: number?,
	shape: Enum.PartType?,
	collide: boolean?,
	reflectance: number?,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Деталь по центру и размеру в координатах модели
local function part(model: Model, size: Vector3, center: Vector3, color: Color3, opts: Opts?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = CFrame.new(center)
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = if opts and opts.material then opts.material else Enum.Material.SmoothPlastic
	if opts then
		if opts.transparency then
			p.Transparency = opts.transparency
		end
		if opts.shape then
			p.Shape = opts.shape
		end
		if opts.collide ~= nil then
			p.CanCollide = opts.collide
		end
		if opts.reflectance then
			p.Reflectance = opts.reflectance
		end
	end
	p.Parent = model
	return p
end

-- Цилиндр по вертикали (в Roblox ось цилиндра — X)
local function cylinder(
	model: Model,
	height: number,
	diameter: number,
	center: Vector3,
	color: Color3,
	opts: Opts?
): Part
	local p = part(model, Vector3.new(height, diameter, diameter), center, color, opts)
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	return p
end

local function light(p: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = p
end

-- Ровная дверь/проём в стене из двух боковых кусков и перемычки
local function wallWithDoor(
	model: Model,
	z: number,
	height: number,
	doorWidth: number,
	color: Color3,
	opts: Opts?
)
	local side = (60 - doorWidth) / 2
	part(model, Vector3.new(side, height, 1), Vector3.new(-30 + side / 2, height / 2, z), color, opts)
	part(model, Vector3.new(side, height, 1), Vector3.new(30 - side / 2, height / 2, z), color, opts)
	local lintel = height - 9
	if lintel > 0 then
		part(model, Vector3.new(doorWidth, lintel, 1), Vector3.new(0, 9 + lintel / 2, z), color, opts)
	end
end

-- Короб помещения: пол, задняя и боковые стены, передняя стена с проёмом 24 studs под кнопки и вход
local function shell(
	model: Model,
	floorColor: Color3,
	floorMaterial: Enum.Material,
	wallColor: Color3,
	wallMaterial: Enum.Material,
	height: number
)
	part(model, Vector3.new(58, 0.1, 58), Vector3.new(0, 0.05, 0), floorColor, { material = floorMaterial })
	part(
		model,
		Vector3.new(60, height, 1),
		Vector3.new(0, height / 2, -29.5),
		wallColor,
		{ material = wallMaterial }
	)
	part(
		model,
		Vector3.new(1, height, 58),
		Vector3.new(-29.5, height / 2, 0),
		wallColor,
		{ material = wallMaterial }
	)
	part(
		model,
		Vector3.new(1, height, 58),
		Vector3.new(29.5, height / 2, 0),
		wallColor,
		{ material = wallMaterial }
	)
	wallWithDoor(model, 29.5, height, 24, wallColor, { material = wallMaterial })
end

-- Окно-полоса в боковой стене (стекло поверх стены)
local function sideWindows(model: Model, x: number, y: number, height: number)
	for z = -20, 20, 10 do
		part(model, Vector3.new(0.3, height, 7), Vector3.new(x, y, z), rgb(170, 210, 240), {
			material = Enum.Material.Glass,
			transparency = 0.4,
		})
	end
end

local function plant(model: Model, at: Vector3)
	cylinder(
		model,
		1.6,
		1.6,
		at + Vector3.new(0, 0.8, 0),
		rgb(200, 120, 80),
		{ material = Enum.Material.Slate }
	)
	part(model, Vector3.new(2.2, 2.2, 2.2), at + Vector3.new(0, 2.8, 0), rgb(70, 160, 70), {
		material = Enum.Material.Grass,
	})
	part(model, Vector3.new(1.4, 1.4, 1.4), at + Vector3.new(0.4, 4, -0.2), rgb(90, 180, 80), {
		material = Enum.Material.Grass,
	})
end

local function box(model: Model, at: Vector3, size: number, color: Color3)
	part(model, Vector3.new(size, size * 0.8, size), at + Vector3.new(0, size * 0.4, 0), color, {
		material = Enum.Material.Cardboard,
	})
end

local function chairSimple(model: Model, at: Vector3, color: Color3, facing: number)
	-- facing: +1 смотрит на +Z, -1 на -Z
	part(model, Vector3.new(1.6, 0.3, 1.6), at + Vector3.new(0, 1.6, 0), color)
	part(model, Vector3.new(1.6, 1.8, 0.25), at + Vector3.new(0, 2.6, -0.7 * facing), color)
	for _, dx in { -0.65, 0.65 } do
		for _, dz in { -0.65, 0.65 } do
			part(model, Vector3.new(0.2, 1.5, 0.2), at + Vector3.new(dx, 0.75, dz), rgb(60, 60, 65))
		end
	end
end

local builders: { [string]: (Model) -> () } = {}

-- ===== Мебель апгрейдов =====

-- Место игрока за компьютером. Seat сажает лицом к своему -Z; facing = поворот вокруг Y
local function pcSeat(m: Model, center: Vector3, size: Vector3, color: Color3, facing: number)
	local seat = Instance.new("Seat")
	seat.Name = "PcSeat"
	seat.Anchored = true
	seat.Size = size
	seat.CFrame = CFrame.new(center) * CFrame.Angles(0, facing, 0)
	seat.Color = color
	seat.Material = Enum.Material.Wood
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.Parent = m
end

-- Старый деревянный стол: столешница на высоте 3 (монитор PC1 ставится на y = 3)
builders.Desk1 = function(m)
	local wood = rgb(150, 105, 60)
	part(m, Vector3.new(6, 0.4, 3), Vector3.new(0, 2.8, 0), wood, { material = Enum.Material.WoodPlanks })
	for _, x in { -2.7, 2.7 } do
		for _, z in { -1.2, 1.2 } do
			part(m, Vector3.new(0.35, 2.6, 0.35), Vector3.new(x, 1.3, z), rgb(120, 85, 50), {
				material = Enum.Material.Wood,
			})
		end
	end
	-- Табурет перед столом: на нём игрок сидит, пока не купит кресло (сидит лицом к столу, −Z)
	cylinder(m, 1.4, 0.3, Vector3.new(0, 0.7, 2.8), rgb(120, 85, 50))
	pcSeat(m, Vector3.new(0, 1.55, 2.8), Vector3.new(1.6, 0.3, 1.6), rgb(150, 105, 60), 0)
	-- Стопка бумаг и кружка: гаражный бардак
	part(m, Vector3.new(1, 0.25, 1.3), Vector3.new(2, 3.12, 0.4), rgb(240, 240, 230))
	cylinder(m, 0.6, 0.5, Vector3.new(-2.3, 3.3, 0.6), rgb(220, 70, 60))
end

-- Второй стол: светлый, на металлических ножках, с тумбой
builders.Desk2 = function(m)
	part(m, Vector3.new(6, 0.3, 3), Vector3.new(0, 2.85, 0), rgb(235, 235, 230))
	for _, x in { -2.8, 2.8 } do
		part(m, Vector3.new(0.2, 2.7, 2.6), Vector3.new(x, 1.35, 0), rgb(90, 95, 105), {
			material = Enum.Material.Metal,
		})
	end
	part(m, Vector3.new(1.6, 2.2, 2.4), Vector3.new(1.8, 1.1, 0), rgb(200, 200, 205))
	part(m, Vector3.new(1.2, 0.15, 0.1), Vector3.new(1.8, 1.8, 1.2), rgb(90, 95, 105))
end

-- Старый «толстый» монитор и клавиатура; стоит на столе (основание = столешница)
builders.PC1 = function(m)
	part(m, Vector3.new(1, 0.15, 0.8), Vector3.new(0, 0.08, 0), rgb(200, 195, 180))
	part(m, Vector3.new(2.2, 1.9, 1.8), Vector3.new(0, 1.15, -0.2), rgb(215, 210, 195))
	part(m, Vector3.new(1.7, 1.4, 0.05), Vector3.new(0, 1.2, 0.72), rgb(40, 90, 120), {
		material = Enum.Material.Neon,
	})
	part(m, Vector3.new(2, 0.12, 0.6), Vector3.new(0, 0.06, 1.3), rgb(200, 195, 180))
end

-- Два плоских монитора, системник с RGB-подсветкой
builders.PCPro = function(m)
	for _, x in { -1.1, 1.1 } do
		part(m, Vector3.new(0.25, 0.9, 0.25), Vector3.new(x, 0.45, -0.2), rgb(40, 40, 45))
		part(m, Vector3.new(2, 1.3, 0.12), Vector3.new(x, 1.5, -0.2), rgb(25, 25, 30))
		part(m, Vector3.new(1.85, 1.15, 0.05), Vector3.new(x, 1.5, -0.12), rgb(60, 140, 255), {
			material = Enum.Material.Neon,
		})
	end
	part(m, Vector3.new(0.9, 2, 1.8), Vector3.new(-3.6, 1, 0), rgb(30, 30, 35))
	part(m, Vector3.new(0.05, 1.6, 0.1), Vector3.new(-3.14, 1, 0.85), rgb(200, 60, 255), {
		material = Enum.Material.Neon,
	})
	part(m, Vector3.new(2.4, 0.12, 0.7), Vector3.new(0, 0.06, 1), rgb(30, 30, 35))
	part(m, Vector3.new(2.3, 0.02, 0.6), Vector3.new(0, 0.13, 1), rgb(255, 80, 200), {
		material = Enum.Material.Neon,
	})
end

-- Геймерское кресло; спинка сзади (−Z), сиденье лицом к +Z
builders.Chair = function(m)
	local red, black = rgb(210, 45, 60), rgb(30, 30, 35)
	cylinder(m, 0.2, 2, Vector3.new(0, 0.1, 0), black)
	part(
		m,
		Vector3.new(0.3, 1.3, 0.3),
		Vector3.new(0, 0.85, 0),
		rgb(90, 90, 95),
		{ material = Enum.Material.Metal }
	)
	-- Сиденье — Seat; кресло стоит повёрнутым на 180°, поэтому Seat разворачиваем к столу (+Z модели)
	pcSeat(m, Vector3.new(0, 1.7, 0), Vector3.new(2, 0.45, 2), black, math.pi)
	part(m, Vector3.new(1.4, 0.06, 1.6), Vector3.new(0, 1.95, 0), red)
	part(m, Vector3.new(2, 3, 0.4), Vector3.new(0, 3.35, -0.85), black)
	part(m, Vector3.new(1.2, 2.6, 0.05), Vector3.new(0, 3.35, -0.63), red)
	for _, x in { -1.05, 1.05 } do
		part(m, Vector3.new(0.25, 0.2, 1.4), Vector3.new(x, 2.4, 0), black)
	end
end

-- Кофемашина на тумбе (не на полу): тумба 3 в высоту, машина сверху
builders.Coffee = function(m)
	part(
		m,
		Vector3.new(2.6, 3, 1.8),
		Vector3.new(0, 1.5, 0),
		rgb(110, 75, 50),
		{ material = Enum.Material.Wood }
	)
	part(
		m,
		Vector3.new(2.8, 0.15, 2),
		Vector3.new(0, 3.07, 0),
		rgb(60, 60, 65),
		{ material = Enum.Material.Granite }
	)
	part(
		m,
		Vector3.new(1.3, 1.7, 1.1),
		Vector3.new(0, 4, -0.2),
		rgb(40, 40, 45),
		{ material = Enum.Material.Metal }
	)
	part(
		m,
		Vector3.new(1.1, 0.3, 0.6),
		Vector3.new(0, 4.65, 0.45),
		rgb(40, 40, 45),
		{ material = Enum.Material.Metal }
	)
	part(m, Vector3.new(0.5, 0.15, 0.05), Vector3.new(0, 4.4, 0.36), rgb(80, 220, 120), {
		material = Enum.Material.Neon,
	})
	cylinder(m, 0.45, 0.4, Vector3.new(0, 3.4, 0.45), rgb(250, 250, 250))
	cylinder(m, 0.45, 0.4, Vector3.new(0.8, 3.4, 0.5), rgb(255, 200, 60))
end

-- Постеры и неоновая вывеска на задней стене; основание = низ рамок, лицом к +Z
builders.Posters = function(m)
	local colors = { rgb(255, 90, 95), rgb(61, 123, 255), rgb(255, 201, 60) }
	for i, x in { -8, 0, 8 } do
		part(m, Vector3.new(3, 4, 0.15), Vector3.new(x, 2, 0), rgb(30, 30, 35))
		part(m, Vector3.new(2.6, 3.6, 0.05), Vector3.new(x, 2, 0.1), colors[i])
		part(m, Vector3.new(1.4, 1.4, 0.05), Vector3.new(x, 2.3, 0.14), rgb(255, 255, 255), {
			shape = Enum.PartType.Ball,
		})
	end
	-- Неоновая вывеска: рамка-полоски над постерами
	local neon = rgb(255, 80, 200)
	part(m, Vector3.new(22, 0.3, 0.2), Vector3.new(0, 5.2, 0.05), neon, { material = Enum.Material.Neon })
	part(m, Vector3.new(22, 0.3, 0.2), Vector3.new(0, 7.4, 0.05), neon, { material = Enum.Material.Neon })
	local sign = part(m, Vector3.new(20, 1.8, 0.1), Vector3.new(0, 6.3, 0.05), rgb(25, 20, 40))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Parent = sign
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = rgb(255, 120, 220)
	text.Text = "GAME STUDIO"
	text.Parent = gui
	light(sign, neon, 14, 1.5)
end

-- «Стены и свет гаража»: начинка гаража — лампы, стеллажи, верстак, шины, коробки
builders.GarageWalls = function(m)
	-- Две подвесные лампы
	for _, x in { -12, 12 } do
		part(m, Vector3.new(0.1, 3, 0.1), Vector3.new(x, 10.5, -8), rgb(40, 40, 40))
		local bulb = part(m, Vector3.new(1, 1, 1), Vector3.new(x, 8.8, -8), rgb(255, 230, 170), {
			material = Enum.Material.Neon,
			shape = Enum.PartType.Ball,
		})
		light(bulb, rgb(255, 220, 160), 28, 1.2)
	end
	-- Стеллаж у левой стены с коробками
	local metal = rgb(120, 125, 130)
	for _, y in { 1, 3.5, 6 } do
		part(
			m,
			Vector3.new(2.5, 0.2, 10),
			Vector3.new(-27.5, y, -4),
			metal,
			{ material = Enum.Material.Metal }
		)
	end
	for _, z in { -8.8, 0.8 } do
		part(
			m,
			Vector3.new(2.5, 7, 0.3),
			Vector3.new(-27.5, 3.5, z),
			metal,
			{ material = Enum.Material.Metal }
		)
	end
	box(m, Vector3.new(-27.5, 1.1, -6), 1.8, rgb(190, 150, 100))
	box(m, Vector3.new(-27.5, 3.6, -1), 1.6, rgb(200, 160, 110))
	box(m, Vector3.new(-27.5, 6.1, -5), 1.4, rgb(180, 140, 95))
	-- Верстак у правой стены
	part(
		m,
		Vector3.new(3, 0.4, 8),
		Vector3.new(27.5, 3, 6),
		rgb(130, 95, 60),
		{ material = Enum.Material.WoodPlanks }
	)
	part(
		m,
		Vector3.new(3, 2.8, 0.4),
		Vector3.new(27.5, 1.4, 2.2),
		rgb(90, 90, 95),
		{ material = Enum.Material.Metal }
	)
	part(
		m,
		Vector3.new(3, 2.8, 0.4),
		Vector3.new(27.5, 1.4, 9.8),
		rgb(90, 90, 95),
		{ material = Enum.Material.Metal }
	)
	part(
		m,
		Vector3.new(0.3, 3, 6),
		Vector3.new(29, 5.5, 6),
		rgb(170, 150, 120),
		{ material = Enum.Material.Wood }
	)
	-- Шины в углу у входа
	for i = 0, 2 do
		cylinder(m, 0.9, 3, Vector3.new(-25, 0.45 + i * 0.9, 24), rgb(25, 25, 25))
	end
	box(m, Vector3.new(24, 0, 24), 2.2, rgb(190, 150, 100))
	box(m, Vector3.new(25.5, 1.76, 24.5), 1.5, rgb(200, 160, 110))
end

-- ===== Помещения этапов (на весь участок) =====

-- Этап 1: гараж — бетонный пол, кирпичные стены, поднятые ворота на входе
builders.Garage = function(m)
	shell(m, rgb(150, 150, 150), Enum.Material.Concrete, rgb(165, 95, 75), Enum.Material.Brick, 12)
	-- Рулонные ворота, поднятые под потолок
	part(
		m,
		Vector3.new(24, 1.6, 1.4),
		Vector3.new(0, 11, 29.6),
		rgb(190, 190, 195),
		{ material = Enum.Material.Metal }
	)
	for _, x in { -12.3, 12.3 } do
		part(
			m,
			Vector3.new(0.6, 12, 1.4),
			Vector3.new(x, 6, 29.6),
			rgb(150, 150, 155),
			{ material = Enum.Material.Metal }
		)
	end
	-- Масляное пятно на полу — гараж всё-таки
	cylinder(m, 0.02, 4, Vector3.new(8, 0.11, 10), rgb(60, 60, 60), { collide = false })
end

-- Этап 2: офис — светлый паркет, белые стены с окнами, растения, кулер
builders.Office = function(m)
	shell(
		m,
		rgb(205, 170, 120),
		Enum.Material.WoodPlanks,
		rgb(240, 240, 235),
		Enum.Material.SmoothPlastic,
		12
	)
	sideWindows(m, -29.2, 6, 5)
	sideWindows(m, 29.2, 6, 5)
	-- Ковёр под рабочей зоной
	part(m, Vector3.new(30, 0.05, 14), Vector3.new(-4, 0.13, -18), rgb(80, 110, 160), {
		material = Enum.Material.Fabric,
		collide = false,
	})
	-- Потолочные светильники
	for _, x in { -14, 0, 14 } do
		local lamp = part(m, Vector3.new(8, 0.2, 1.2), Vector3.new(x, 11.8, -10), rgb(255, 255, 245), {
			material = Enum.Material.Neon,
		})
		light(lamp, rgb(255, 250, 235), 24, 1)
	end
	plant(m, Vector3.new(-26, 0, -26))
	plant(m, Vector3.new(26, 0, 20))
	plant(m, Vector3.new(-26, 0, 20))
	-- Кулер с водой
	part(m, Vector3.new(1.4, 3, 1.4), Vector3.new(26, 1.5, -12), rgb(230, 230, 235))
	cylinder(m, 1.6, 1.2, Vector3.new(26, 3.8, -12), rgb(120, 190, 255), { transparency = 0.3 })
end

-- Этап 3: этаж бизнес-центра — синий ковролин, стеклянные стены, переговорка, диван
builders.Floor = function(m)
	shell(m, rgb(55, 75, 120), Enum.Material.Fabric, rgb(210, 220, 235), Enum.Material.SmoothPlastic, 14)
	sideWindows(m, -29.2, 7, 7)
	sideWindows(m, 29.2, 7, 7)
	-- Переговорка: стол и стулья слева спереди
	part(m, Vector3.new(10, 0.3, 4), Vector3.new(-18, 2.85, 12), rgb(240, 240, 240))
	part(
		m,
		Vector3.new(1, 2.7, 1),
		Vector3.new(-18, 1.35, 12),
		rgb(90, 95, 105),
		{ material = Enum.Material.Metal }
	)
	for _, x in { -21.5, -18, -14.5 } do
		chairSimple(m, Vector3.new(x, 0, 15.2), rgb(40, 40, 50), -1)
		chairSimple(m, Vector3.new(x, 0, 8.8), rgb(40, 40, 50), 1)
	end
	-- Белая доска на левой стене
	part(m, Vector3.new(0.2, 4, 8), Vector3.new(-28.8, 5, 12), rgb(250, 250, 250))
	-- Диван справа спереди
	part(
		m,
		Vector3.new(8, 1.4, 3),
		Vector3.new(18, 0.7, 14),
		rgb(70, 130, 200),
		{ material = Enum.Material.Fabric }
	)
	part(
		m,
		Vector3.new(8, 2.2, 0.8),
		Vector3.new(18, 1.6, 15.6),
		rgb(60, 115, 185),
		{ material = Enum.Material.Fabric }
	)
	plant(m, Vector3.new(26, 0, 8))
	for _, x in { -14, 0, 14 } do
		local lamp = part(m, Vector3.new(10, 0.2, 1.2), Vector3.new(x, 13.8, -8), rgb(235, 245, 255), {
			material = Enum.Material.Neon,
		})
		light(lamp, rgb(230, 240, 255), 26, 1)
	end
end

-- Этап 4: небоскрёб — тёмный глянцевый пол, панорамное окно с городом, неон, зал славы
builders.Skyscraper = function(m)
	part(m, Vector3.new(58, 0.1, 58), Vector3.new(0, 0.05, 0), rgb(25, 25, 32), {
		material = Enum.Material.Marble,
		reflectance = 0.15,
	})
	local wall = rgb(35, 35, 48)
	part(m, Vector3.new(1, 16, 58), Vector3.new(-29.5, 8, 0), wall)
	part(m, Vector3.new(1, 16, 58), Vector3.new(29.5, 8, 0), wall)
	wallWithDoor(m, 29.5, 16, 24, wall)
	-- Задняя стена — панорамное стекло, за ним силуэты города с огнями окон
	part(m, Vector3.new(60, 16, 0.4), Vector3.new(0, 8, -29.5), rgb(120, 160, 220), {
		material = Enum.Material.Glass,
		transparency = 0.6,
	})
	local rng = Random.new(42)
	for x = -26, 26, 6 do
		local h = rng:NextNumber(10, 26)
		local building = part(m, Vector3.new(5, h, 5), Vector3.new(x, h / 2 - 4, -38), rgb(20, 22, 35))
		building.CanCollide = false
		for wy = 2, h - 2, 3 do
			if rng:NextNumber() > 0.4 then
				part(m, Vector3.new(3.6, 0.6, 0.1), Vector3.new(x, wy - 4, -35.45), rgb(255, 220, 120), {
					material = Enum.Material.Neon,
					collide = false,
				})
			end
		end
	end
	-- Неоновые полосы вдоль стен
	for _, x in { -28.9, 28.9 } do
		part(
			m,
			Vector3.new(0.2, 0.3, 56),
			Vector3.new(x, 14, 0),
			rgb(0, 220, 255),
			{ material = Enum.Material.Neon }
		)
		part(
			m,
			Vector3.new(0.2, 0.3, 56),
			Vector3.new(x, 0.6, 0),
			rgb(200, 60, 255),
			{ material = Enum.Material.Neon }
		)
	end
	-- Зал славы: полка с кубками справа
	part(m, Vector3.new(2, 0.3, 12), Vector3.new(27.5, 4, 10), rgb(60, 60, 75))
	for i = 0, 3 do
		local z = 5.5 + i * 3
		cylinder(m, 1.2, 0.8, Vector3.new(27.5, 4.75, z), rgb(255, 200, 60), {
			material = Enum.Material.Metal,
			reflectance = 0.3,
		})
		part(m, Vector3.new(0.8, 0.8, 0.8), Vector3.new(27.5, 5.75, z), rgb(255, 210, 80), {
			material = Enum.Material.Metal,
			shape = Enum.PartType.Ball,
		})
	end
	-- Большой экран на левой стене
	part(m, Vector3.new(0.3, 6, 11), Vector3.new(-28.8, 7, 6), rgb(15, 15, 20))
	part(
		m,
		Vector3.new(0.05, 5.4, 10.4),
		Vector3.new(-28.6, 7, 6),
		rgb(80, 60, 220),
		{ material = Enum.Material.Neon }
	)
	plant(m, Vector3.new(-26, 0, 22))
	plant(m, Vector3.new(26, 0, 22))
end

-- Собрать модель по имени; nil — для этого имени билдера нет
function ModelFactory.build(name: string): Model?
	local builder = builders[name]
	if not builder then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	builder(model)
	model.WorldPivot = CFrame.new()
	return model
end

return ModelFactory
