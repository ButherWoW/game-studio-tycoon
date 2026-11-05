"""V28 original native Part trophies, hall pedestals and billboard."""
from geometry import *
import subprocess
GOLD='FFC93C';BLUE='315BD3';DARK='202B48';CYAN='00DDE8'
def trophy():
 m=model('Trophy_GOTW')
 box(m,'Base',(0,.12,0),(1.15,.24,.88),DARK)
 box(m,'GoldFoot',(0,.29,0),(.92,.10,.68),GOLD)
 box(m,'Stem',(0,.49,0),(.22,.30,.22),GOLD)
 box(m,'Joystick_Base',(0,.74,0),(.98,.20,.65),GOLD)
 box(m,'Joystick_Top',(0,.87,0),(.84,.06,.51),BLUE)
 box(m,'Joystick_Stick',(-.18,1.18,0),(.13,.56,.13),GOLD)
 # Own faceted block knob, clearly joystick-shaped, not any real console controller.
 ball(m,'Joystick_Knob',(-.18,1.73,0),(.54,.54,.54),GOLD)
 for z in [-.12,.12]:box(m,'ActionButton',(.23,.945,z),(.18,.09,.12),GOLD)
 return m

def pedestal(rank,h,col):
 m=model('HallPedestal_'+str(rank))
 box(m,'Base',(0,.09,0),(4,.18,4),DARK)
 box(m,'Body',(0,h/2,0),(3.4,h-.36,3.4),col)
 box(m,'Top',(0,h-.09,0),(4,.18,4),col)
 box(m,'Plate',(0,h*.5,1.74),(2.6,.42,.08),DARK)
 for x in [-1.72,1.72]:box(m,'Accent',(x,h*.5,0),(.04,h-.48,2.8),BLUE)
 return m

def billboard():
 m=model('Billboard')
 for x in [-5.4,5.4]:
  box(m,'Foot',(x,.1,0),(1.6,.2,1.4),DARK)
  box(m,'Support',(x,1.65,0),(.36,2.9,.36),BLUE)
 box(m,'BackPanel',(0,6.05,-.1),(15.4,5.3,.2),DARK)
 box(m,'Screen',(0,6.05,.08),(14.8,5.3,.16),'173451')
 for x in [-7.85,7.85]:box(m,'FrameSide',(x,6.05,0),(.3,5.3,.5),BLUE)
 for y in [3.25,8.85]:box(m,'FrameHorizontal',(0,y,0),(16,.3,.5),BLUE)
 for x in [-7.80,7.80]:box(m,'NeonSide',(x,6.05,.275),(.08,5.15,.05),CYAN,mat='Neon')
 for y in [3.36,8.74]:box(m,'NeonHorizontal',(0,y,.275),(15.22,.08,.05),CYAN,mat='Neon')
 return m
ASSETS={m['name']:m for m in [trophy(),pedestal(1,3,GOLD),pedestal(2,2.25,'C0C7D1'),pedestal(3,1.5,'CD7F32'),billboard()]}
if __name__=='__main__':
 for name,m in ASSETS.items():
  dest=ROOT/'models'/(name+'.rbxmx');export(m,dest)
  proj=ROOT/'source'/'convert.project.json';proj.write_text(json.dumps({'name':name,'tree':{'$path':str(dest)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(proj),'-o',str(dest.with_suffix('.rbxm'))],check=True)
 proj.unlink();(ROOT/'model-manifest.json').write_text(json.dumps(ASSETS,indent=2)+'\n')
