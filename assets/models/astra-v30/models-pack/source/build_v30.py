"""Original native Part V30 equipment, no embedded scripts/textures."""
from geometry import *
import subprocess
DARK='202B48';BLUE='315BD3';CYAN='00DDE8';PINK='FF6EB4';WHITE='E5EDF7';GOLD='FFC93C';GREEN='65DC75'
def table(name,color):
 m=model(name)
 box(m,'Worktop',(0,2.3,-.05),(6,.2,3.9),DARK)
 box(m,'FrontAccent',(0,2.3,1.95),(6,.2,.1),color,mat='Neon')
 for x in [-2.6,2.6]:
  for z in [-1.6,1.6]:box(m,'Leg',(x,1.1,z),(.18,2.2,.18),BLUE)
 for z in [-1.6,1.6]:box(m,'Brace',(0,.5,z),(5.02,.14,.18),BLUE)
 return m

def chiplab():
 m=table('Equip_ChipLab',CYAN)
 # Sealed rear/sides/top of hood; open front for access, shallow glass envelope.
 for x in [-2.5,2.5]:box(m,'GlassSide',(x,3.25,-.8),(.06,1.7,1.8),'8ABAE4',mat='Glass',alpha=.65)
 box(m,'GlassBack',(0,3.25,-1.67),(4.94,1.7,.06),'8ABAE4',mat='Glass',alpha=.65)
 box(m,'HoodTop',(0,4.15,-.8),(5.06,.1,1.8),BLUE)
 box(m,'HoodGlow',(0,4.225,-.8),(4.85,.05,1.6),CYAN,mat='Neon')
 # Own microscope left: base, stalk and body, offset objective avoids physical collision.
 box(m,'Microscope_Base',(-1.35,2.46,-.7),(.8,.12,.8),WHITE)
 box(m,'Microscope_Stem',(-1.55,2.82,-.95),(.15,.6,.15),BLUE)
 box(m,'Microscope_Body',(-1.35,3.18,-.72),(.55,.12,.6),BLUE)
 cyl(m,'Microscope_Objective',(-1.15,2.97,-.5),.3,.16,DARK)
 cyl(m,'Microscope_Eyepiece',(-1.35,3.38,-.72),.28,.18,DARK)
 cyl(m,'SiliconWafer',(.05,2.445,-.6),.09,1.1,'8D96C8')
 # Clean chip samples sit on wafer upper plane.
 box(m,'WaferChip',(.05,2.515,-.6),(.24,.05,.24),GOLD)
 box(m,'Manipulator_Base',(1.45,2.48,-.85),(.6,.16,.6),BLUE)
 box(m,'Manipulator_Column',(1.45,2.95,-.85),(.18,.78,.18),WHITE)
 box(m,'Manipulator_Arm',(1.1,3.40,-.85),(.88,.12,.18),WHITE)
 box(m,'Manipulator_Probe',(.75,3.20,-.85),(.08,.28,.08),CYAN,mat='Neon')
 box(m,'ControlPanel',(1.45,2.46,.8),(1.15,.12,.58),BLUE)
 for x,c in [(1.1,CYAN),(1.45,GOLD),(1.8,GREEN)]:box(m,'ControlKey',(x,2.55,.8),(.22,.06,.28),c)
 return m

def design():
 m=table('Equip_DesignStation',PINK)
 box(m,'TabletFoot',(-1.45,2.45,-.35),(1.3,.1,.7),BLUE)
 box(m,'TabletStand',(-1.45,2.6,-.35),(.18,.2,.18),WHITE)
 box(m,'DrawingTablet',(-1.45,3.45,-.35),(1.95,1.5,.12),BLUE)
 # Abstract own twin-wing console sketch, no text or external texture.
 for x in [-1.88,-1.02]:box(m,'Sketch_Wing',(x,3.5,-.265),(.55,.70,.05),CYAN)
 box(m,'Sketch_Bridge',(-1.45,3.3,-.265),(.31,.16,.05),CYAN)
 box(m,'Sketch_Controller',(-1.45,2.94,-.265),(.72,.12,.05),GOLD)
 box(m,'Printer_Base',(1.25,2.51,-.5),(1.9,.22,1.6),BLUE)
 for x in [.36,2.14]:box(m,'Printer_Side',(x,3.27,-.5),(.12,1.3,1.6),'B8A7E0',mat='Glass',alpha=.6)
 box(m,'Printer_Back',(1.25,3.27,-1.24),(1.66,1.3,.12),'B8A7E0',mat='Glass',alpha=.6)
 box(m,'Printer_Roof',(1.25,3.98,-.5),(1.9,.12,1.6),BLUE)
 box(m,'Printer_Rail',(1.25,3.78,-.5),(1.66,.10,.10),WHITE)
 box(m,'Printer_Head',(1.25,3.64,-.5),(.28,.18,.28),PINK)
 box(m,'Printer_Nozzle',(1.25,3.50,-.5),(.08,.10,.08),GOLD)
 box(m,'PrintBed',(1.25,2.66,-.5),(1.5,.08,1.2),WHITE)
 for x in [.87,1.63]:box(m,'PrintedCase',(x,2.82,-.5),(.50,.24,.8),PINK)
 box(m,'Printer_Indicator',(1.25,4.07,-.5),(1.4,.06,.2),PINK,mat='Neon')
 box(m,'Stylus',(-1.4,2.445,1.2),(1.35,.09,.09),PINK)
 return m

def testbench():
 m=table('Equip_TestBench',GREEN)
 for x in [-1.9,0,1.9]:
  box(m,'MonitorFoot',(x,2.445,-.75),(.65,.09,.6),BLUE)
  box(m,'MonitorStem',(x,2.75,-.75),(.12,.52,.12),WHITE)
  box(m,'MonitorBody',(x,3.55,-.75),(1.65,1.08,.12),BLUE)
  box(m,'MonitorScreen',(x,3.55,-.665),(1.45,.9,.05),DARK)
  for j,h in enumerate([.20,.38,.57]):box(m,'GraphBar',(x-.40+j*.4,3.20+h/2,-.625),(.22,h,.03),[CYAN,GOLD,GREEN][j])
 box(m,'RobotBase',(1.55,2.5,.9),(.8,.2,.65),BLUE)
 box(m,'RobotColumn',(1.55,2.9,.9),(.16,.6,.16),WHITE)
 box(m,'RobotArm',(1.1,3.26,.83),(1.06,.12,.30),WHITE)
 box(m,'RobotClamp',(.61,3.12,.69),(.08,.16,.16),BLUE)
 box(m,'Controller',(.61,2.98,.9),(1.12,.12,.5),BLUE)
 for x in [.18,1.04]:box(m,'ControllerGrip',(x,2.83,.9),(.26,.18,.5),BLUE)
 box(m,'ControllerPad',(.61,3.065,.9),(.24,.05,.2),CYAN)
 for x in [.2,1.02]:box(m,'ControllerKey',(x,3.065,.9),(.12,.05,.12),GOLD)
 box(m,'IndicatorStem',(-2.2,2.70,.9),(.12,.6,.12),WHITE)
 box(m,'Indicator',(-2.2,3.14,.9),(.32,.28,.32),GREEN,mat='Neon')
 return m
ASSETS={m['name']:m for m in [chiplab(),design(),testbench()]}
if __name__=='__main__':
 for name,m in ASSETS.items():
  dest=ROOT/'models'/(name+'.rbxmx');export(m,dest)
  proj=ROOT/'source'/'convert.project.json';proj.write_text(json.dumps({'name':name,'tree':{'$path':str(dest)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(proj),'-o',str(dest.with_suffix('.rbxm'))],check=True)
 proj.unlink();(ROOT/'model-manifest.json').write_text(json.dumps(ASSETS,indent=2)+'\n')
