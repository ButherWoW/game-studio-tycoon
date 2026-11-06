--!strict
-- Базовая внешность сотрудников (docs/VISUAL.md, V13; арт Астры — docs/visual/astra-2026-11-05-staff).
-- У каждого своё лицо, причёска и повседневная одежда; платный скин V12 надевается поверх.
-- Как надевается (StaffAppearance.apply):
--   face — Decal на лице (у robo — на экране FaceScreen внутри причёски-монитора);
--   shirt/pants — Shirt/Pants, если игрок не выбрал свой цвет футболки во «Внешности»;
--   причёска — Accessory hair_<id> из ServerStorage.StaffLooks (Dev 1 импортирует hair_<id>.rbxmx);
--   cape — дополнительный Accessory оттуда же (look_legend_cape, на спину).
-- 0 в ID — картинка ещё не загружена: тогда остаются цвета body/pants.
-- body — цвет кожи «по умолчанию» (Внешность → кожа 0); transparency — прозрачность тела (призрак).

export type Look = {
	face: number,
	shirt: number,
	pants: number,
	body: Color3,
	pantsColor: Color3,
	transparency: number?,
	faceOnScreen: boolean?, -- лицо на FaceScreen причёски, а не на голове
	cape: string?, -- имя дополнительного Accessory в папке
}

local StaffLooks = {}

-- Папка с причёсками и плащом в ServerStorage
StaffLooks.folder = "StaffLooks"

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local function look(body: string, pants: string): Look
	return { face = 0, shirt = 0, pants = 0, body = hex(body), pantsColor = hex(pants) }
end

StaffLooks.byId = {
	mila = look("F3C8A6", "32476D"),
	tim = look("EBC19D", "42415C"),
	zoe = look("B87955", "344A43"),
	ilya = look("F1C99C", "3C3A52"),
	oleg = look("DCA87D", "34404F"),
	sara = look("DCA078", "3F5873"),
	max = look("E9BD98", "273B38"),
	nika = look("F0C3A4", "494057"),
	den = look("B98361", "3F4956"),
	aya = look("A96D50", "373C58"),
	leo = look("E7B585", "293B39"),
	vera = look("D8B29D", "494357"),
	robo = look("A5B6CA", "516172"),
	ghost = look("9AD9EA", "72BDD1"),
	legend = look("E8C49E", "443850"),
} :: { [string]: Look }

-- Image ID лиц и одежды (V13, загружены Dev 1 06.11)
StaffLooks.byId.mila.face, StaffLooks.byId.mila.shirt, StaffLooks.byId.mila.pants =
	132323873910661, 132633402299313, 78346802338011
StaffLooks.byId.tim.face, StaffLooks.byId.tim.shirt, StaffLooks.byId.tim.pants =
	91031593890530, 94248376494277, 101455452413399
StaffLooks.byId.zoe.face, StaffLooks.byId.zoe.shirt, StaffLooks.byId.zoe.pants =
	112224809568764, 97051888217917, 129095626162283
StaffLooks.byId.ilya.face, StaffLooks.byId.ilya.shirt, StaffLooks.byId.ilya.pants =
	80573277780075, 85149668979741, 140684891513683
StaffLooks.byId.oleg.face, StaffLooks.byId.oleg.shirt, StaffLooks.byId.oleg.pants =
	121317331896987, 104719580980220, 77190510061804
StaffLooks.byId.sara.face, StaffLooks.byId.sara.shirt, StaffLooks.byId.sara.pants =
	104864586667489, 90512242968894, 108272049662406
StaffLooks.byId.max.face, StaffLooks.byId.max.shirt, StaffLooks.byId.max.pants =
	123632732024185, 125559798006422, 96711101646703
StaffLooks.byId.nika.face, StaffLooks.byId.nika.shirt, StaffLooks.byId.nika.pants =
	80696387437699, 123969862279338, 113961659184783
StaffLooks.byId.den.face, StaffLooks.byId.den.shirt, StaffLooks.byId.den.pants =
	79167752755572, 120117322889394, 76985160558976
StaffLooks.byId.aya.face, StaffLooks.byId.aya.shirt, StaffLooks.byId.aya.pants =
	130521214437494, 110674321472018, 125599594467487
StaffLooks.byId.leo.face, StaffLooks.byId.leo.shirt, StaffLooks.byId.leo.pants =
	93370706720803, 84559512279113, 91215558423731
StaffLooks.byId.vera.face, StaffLooks.byId.vera.shirt, StaffLooks.byId.vera.pants =
	108623917545675, 75657070862267, 107960215362246
StaffLooks.byId.robo.face, StaffLooks.byId.robo.shirt, StaffLooks.byId.robo.pants =
	118349399845343, 118611477543627, 92505975754264
StaffLooks.byId.ghost.face, StaffLooks.byId.ghost.shirt, StaffLooks.byId.ghost.pants =
	125564446341466, 103950221433346, 99553323866951
StaffLooks.byId.legend.face, StaffLooks.byId.legend.shirt, StaffLooks.byId.legend.pants =
	112707931792127, 110553906742255, 83722810976397

StaffLooks.byId.robo.faceOnScreen = true
StaffLooks.byId.ghost.transparency = 0.35
StaffLooks.byId.legend.cape = "look_legend_cape"

function StaffLooks.get(employeeId: string): Look?
	return StaffLooks.byId[employeeId]
end

return StaffLooks
