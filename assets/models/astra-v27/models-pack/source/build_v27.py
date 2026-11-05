"""Original V27 safe and blitz trophy, native Roblox primitives only."""
from geometry import *
import subprocess
BLUE='315BD3';DARK='202B48';GOLD='FFC93C';CYAN='00DDE8';STEEL='62758C';WHITE='E5EDF7'
def safe():
 m=model('ParkSafe')
 box(m,'Base',(0,.15,0),(4,.3,4),DARK)
 box(m,'Body_Left',(-1.85,2.5,0),(.3,4.4,4),STEEL)
 box(m,'Body_Right',(1.85,2.5,0),(.3,4.4,4),STEEL)
 box(m,'Body_Back',(0,2.5,-1.86),(3.4,4.4,.28),STEEL)
 box(m,'Body_Top',(0,4.85,0),(4,.3,4),DARK)
 # Front frame bounds a real hollow opening, rather than a solid body behind the door.
 box(m,'Frame_Bottom',(0,.475,1.60),(3.4,.35,.24),BLUE)
 box(m,'Frame_Top',(0,4.525,1.60),(3.4,.35,.24),BLUE)
 box(m,'Frame_Left',(-1.65,2.5,1.60),(.1,3.7,.24),BLUE)
 box(m,'KeypadPanel',(1.34,2.5,1.60),(.72,3.7,.24),BLUE)
 box(m,'Hinge',(-1.555,2.5,1.78),(.09,3.8,.09),GOLD)
 door=model('Door');door['pos']=(0,0,0)
 box(door,'Panel',(-.29,2.5,1.65),(2.4,3.6,.20),STEEL)
 for y in [.79,4.21]:box(door,'Door_Trim',(-.29,y,1.775),(2.12,.08,.05),GOLD)
 # Octagonal wheel made from eight disconnected ring segments and four spokes.
 cx,cy,z=-.29,2.55,1.91;rad=.47
 for i in range(8):
  a,b=2*math.pi*i/8,2*math.pi*(i+1)/8
  x1,y1=cx+rad*math.cos(a),cy+rad*math.sin(a);x2,y2=cx+rad*math.cos(b),cy+rad*math.sin(b)
  length=math.hypot(x2-x1,y2-y1)-.075;angle=math.degrees(math.atan2(y2-y1,x2-x1))
  box(door,'Wheel_Rim',((x1+x2)/2,(y1+y2)/2,z),(length,.07,.09),GOLD,r=rot(z=angle))
 box(door,'Wheel_Axle',(cx,cy,1.815),(.13,.13,.13),DARK)
 box(door,'Wheel_Hub',(cx,cy,1.91),(.19,.19,.06),GOLD)
 for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
  box(door,'Wheel_Spoke',(cx+dx*.245,cy+dy*.245,z),(.29 if dx else .07,.29 if dy else .07,.06),GOLD)
 m['children'].append(door)
 pad=model('Keypad')
 box(pad,'KeypadBase',(1.34,2.42,1.745),(.58,1.6,.05),DARK)
 for row in range(4):
  for col in range(3):box(pad,f'Button_{row+1}_{col+1}',(1.15+col*.19,2.96-row*.36,1.8025),(.13,.24,.065),CYAN if row==3 else WHITE)
 m['children'].append(pad)
 box(m,'Indicator',(1.34,3.55,1.77),(.34,.18,.1),CYAN,mat='Neon')
 return m

def trophy():
 m=model('Trophy_Blitz')
 box(m,'Base',(0,.075,0),(.94,.15,.72),DARK)
 box(m,'Foot',(0,.205,0),(.7,.11,.52),GOLD)
 box(m,'Stem',(0,.42,0),(.17,.32,.17),GOLD)
 box(m,'CupBottom',(0,.63,0),(.56,.1,.44),GOLD)
 for x in [-.255,.255]:box(m,'CupSide',(x,.9,0),(.05,.44,.44),GOLD)
 for z in [-.195,.195]:box(m,'CupFront',(0,.9,z),(.46,.44,.05),GOLD)
 # Broad crown-like cup rim, sparse chunky handles and central neon lightning crest.
 for x in [-.255,.255]:box(m,'RimSide',(x,1.17,0),(.1,.1,.54),GOLD)
 for z in [-.22,.22]:box(m,'RimFront',(0,1.17,z),(.41,.1,.1),GOLD)
 for x in [-.47,.47]:
  box(m,'HandleOuter',(x,.91,0),(.08,.40,.10),GOLD)
  for y in [.75,1.07]:box(m,'HandleBridge',(x/abs(x)*.365,y,0),(.13,.07,.1),GOLD)
 # Lightning is two separate slanted gold/cyan bars with tiny gap, mounted above cup.
 for p in m['parts']:
  if p['name'] not in ['Base','Foot','Stem']:p['p']=add(p['p'],(0,.28,0))
  elif p['name']=='Stem':p['p']=(0,.56,0);p['s']=(.17,.6,.17)
 box(m,'Blitz_Accent',(0,1.16,.265),(.10,.28,.04),CYAN,r=rot(z=-20),mat='Neon')
 return m
ASSETS={m['name']:m for m in [safe(),trophy()]}
if __name__=='__main__':
 for name,m in ASSETS.items():
  dest=ROOT/'models'/(name+'.rbxmx');export(m,dest)
  proj=ROOT/'source'/'convert.project.json';proj.write_text(json.dumps({'name':name,'tree':{'$path':str(dest)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(proj),'-o',str(dest.with_suffix('.rbxm'))],check=True)
 proj.unlink();(ROOT/'model-manifest.json').write_text(json.dumps(ASSETS,indent=2)+'\n')
