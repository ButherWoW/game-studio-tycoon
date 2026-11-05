"""Original V23 primitive console stages. Native Parts only; no game scripts."""
from geometry import *
import subprocess
BLUE='315BD3';DARK='202B48';CYAN='00DDE8';GOLD='FFC93C';WOOD='C8A27A';WHITE='E4EDF5';GREEN='278E76'

def table(n):
 m=model(n)
 box(m,'Worktop',(0,2.52,0),(5.6,.24,5.2),WOOD)
 for x in [-2.4,2.4]:
  for z in [-2.0,2.0]:box(m,'Leg',(x,1.2,z),(.32,2.4,.32),DARK)
 for z in [-2,2]:box(m,'LowerBrace',(0,.48,z),(4.48,.18,.32),DARK)
 return m

def controller(m,y=2.43,z=1.45):
 box(m,'Controller_Center',(0,y,z),(1.2,.24,.5),BLUE)
 for x in [-.78,.78]:box(m,'Controller_Grip',(x,y,z+.12),(.36,.24,.86),BLUE)
 box(m,'Controller_CyanPad',(0,y+.15,z),(.6,.06,.24),CYAN)
 for dx,dz in [(-.075,0),(.075,0),(0,-.075),(0,.075)]:box(m,'Controller_Direction',(-.78+dx,y+.145,z+dz),(.07,.05,.07),WHITE)
 for dz in [-.08,.08]:box(m,'Controller_Action',(.78,y+.145,z+dz),(.11,.05,.11),GOLD)

def closed_console(m,y=2.31):
 box(m,'Console_Base',(0,y+.08,-.6),(3.6,.16,2.2),DARK)
 for x in [-1.15,1.15]:
  box(m,'Console_Wing',(x,y+.735,-.65),(1.3,1.15,1.7),BLUE)
  box(m,'Console_GoldCap',(x,y+1.335,-.65),(1.1,.05,1.5),GOLD)
  box(m,'Console_CyanFront',(x,y+1.13,.22),(.92,.1,.04),CYAN,mat='Neon')
  for j in range(3):box(m,'Console_Vent',(x,y+.49+j*.14,.215),(.72,.055,.03),DARK)
 box(m,'Console_Bridge',(0,y+.41,-.65),(1.,.5,.64),BLUE)
 box(m,'Console_CyanBridge',(0,y+.69,-.65),(.96,.06,.55),CYAN,mat='Neon')
 box(m,'Console_GoldDiamond',(0,y+.745,-.65),(.22,.05,.22),GOLD,r=rot(y=45))

def launch():
 m=model('Console_Launch')
 box(m,'Plinth_Base',(0,.12,0),(5.6,.24,5.2),DARK)
 box(m,'Plinth_Stem',(0,1.065,0),(3.6,1.65,3.2),BLUE)
 box(m,'Plinth_Collar',(0,1.98,0),(5.,.18,4.6),GOLD)
 box(m,'DisplayTop',(0,2.19,0),(5.6,.24,5.2),DARK)
 for z in [-2.45,2.45]:box(m,'Display_CyanEdge',(0,2.33,z),(5.1,.04,.08),CYAN,mat='Neon',light=(8,.55,'77E9FF') if z>0 else None)
 for x in [-2.65,2.65]:box(m,'Display_CyanSide',(x,2.33,0),(.08,.04,4.5),CYAN,mat='Neon')
 closed_console(m)
 controller(m)
 return m

def outline(m,n,x,z,w,d,y,c=CYAN):
 # Butt-jointed outline, with side rails ending at cross rails.
 for zz in [z-d/2,z+d/2]:box(m,n+'_Horizontal',(x,y,zz),(w,.025,.045),c)
 for xx in [x-w/2+.0225,x+w/2-.0225]:box(m,n+'_Side',(xx,y,z),(.045,.025,d-.045),c)

def design():
 m=table('Console_Design')
 box(m,'BlueprintSheet',(-.45,2.65,-.15),(3.8,.02,3.7),'19426A')
 y=2.6725
 outline(m,'Sketch_Base',-.45,-.55,2.8,1.9,y)
 outline(m,'Sketch_LeftWing',-1.35,-.55,.78,1.34,y)
 outline(m,'Sketch_RightWing',.45,-.55,.78,1.34,y)
 box(m,'Sketch_Bridge',(-.45,y,-.55),(.6,.025,.22),CYAN)
 outline(m,'Sketch_Controller',-.45,1.,1.35,.48,y)
 for xx in [-.9,0]:box(m,'Sketch_Button',(xx,y,1.),(.1,.025,.1),GOLD)
 for z,c in [(-1.65,GOLD),(-.75,'FF7E9C'),(.15,CYAN)]:
  box(m,'Pencil_Body',(2.02,2.71,z),(.13,.14,.55),c)
  box(m,'Pencil_Tip',(2.02,2.71,z+.34),(.09,.14,.13),DARK)
  box(m,'Pencil_Eraser',(2.02,2.71,z-.34),(.13,.14,.13),WHITE)
 for z,c in [(.8,BLUE),(1.3,CYAN),(1.8,GOLD)]:box(m,'Palette_Swatch',(2.02,2.665,z),(.48,.05,.28),c)
 return m

def prototype():
 m=table('Console_Prototype')
 y=2.64
 box(m,'Console_Base',(0,y+.08,-.6),(3.6,.16,2.2),DARK)
 # Open twin lobes: recessed boards visible, walls butt jointed.
 for x in [-1.15,1.15]:
  box(m,'Board',(x,y+.19,-.65),(1.06,.06,1.46),GREEN)
  for xx in [x-.59,x+.59]:box(m,'CaseSide',(xx,y+.49,-.65),(.12,.66,1.7),BLUE)
  for zz in [-1.44,.14]:box(m,'CaseEnd',(x,y+.49,zz),(1.06,.66,.12),BLUE)
  box(m,'Chip',(x,y+.275,-.91),(.45,.11,.42),DARK)
  box(m,'Capacitor',(x+.31,y+.3,-.36),(.16,.16,.18),GOLD)
  # Clear right-angle wire runs on exposed board; no intersecting strands.
  box(m,'Wire_Cyan_Long',(x-.29,y+.245,-.52),(.06,.05,.62),CYAN)
  box(m,'Wire_Cyan_Short',(x-.13,y+.245,-.18),(.38,.05,.06),CYAN)
  box(m,'Wire_Gold',(x+.34,y+.245,-1.09),(.06,.05,.3),GOLD)
 box(m,'Console_Bridge',(0,y+.41,-.65),(1.,.5,.64),BLUE)
 box(m,'PrototypeIndicator',(0,y+.69,-.65),(.34,.06,.34),CYAN,mat='Neon')
 # Removed two covers stand in a rear rack; gold face-up and visible.
 for x in [-1.15,1.15]:
  box(m,'LidRackFoot',(x,y+.08,-2.15),(.8,.16,.5),DARK)
  box(m,'LidRackPost',(x,y+.43,-2.26),(.16,.54,.12),DARK)
  box(m,'RemovedCover',(x,y+.85,-2.26),(1.1,.3,.12),GOLD)
 controller(m,y+.12,1.45)
 return m

ASSETS={m['name']:m for m in [design(),prototype(),launch()]}

def bounds(ps):
 lo=[float('inf')]*3;hi=[-float('inf')]*3
 for p in ps:
  h=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  for i in range(3):lo[i]=min(lo[i],p['p'][i]-h[i]);hi[i]=max(hi[i],p['p'][i]+h[i])
 return lo,hi

if __name__=='__main__':
 for n,m in ASSETS.items():
  dest=ROOT/'models'/f'{n}.rbxmx';export(m,dest)
  pr=ROOT/'source'/'convert.project.json';pr.write_text(json.dumps({'name':n,'tree':{'$path':str(dest)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(pr),'-o',str(dest.with_suffix('.rbxm'))],check=True)
 (ROOT/'source'/'convert.project.json').unlink()
 (ROOT/'model-manifest.json').write_text(json.dumps(ASSETS,indent=2)+'\n')
