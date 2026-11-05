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

StaffLooks.byId.robo.faceOnScreen = true
StaffLooks.byId.ghost.transparency = 0.35
StaffLooks.byId.legend.cape = "look_legend_cape"

function StaffLooks.get(employeeId: string): Look?
	return StaffLooks.byId[employeeId]
end

return StaffLooks
