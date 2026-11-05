from geometry import *
from render_geometry import preview
import sys,subprocess

def crown(m,x,y,z):
 box(m,'CrownBase',(x,y,z),(.64,.16,.1),'FFC93C',mat='Metal')
 for xx,yy in [(-.23,.18),(0,.27),(.23,.18)]:
  box(m,'CrownTooth',(x+xx,y+yy,z),(.15,.32 if xx==0 else .22,.1),'FFC93C',r=rot(z=-25 if xx<0 else 25 if xx>0 else 0),mat='Metal')
 ball(m,'Gem',(x,y+.03,z+.07),(.12,.12,.06),'00E5FF',mat='Neon')
def sign():
 m=model('VipSignFrame')
 for x in (-7.35,7.35):box(m,'FrameSide',(x,0,0),(.2,3.12,.32),'FFC93C',mat='Metal')
 for y in (-1.46,1.46):box(m,'FrameHorizontal',(0,y,0),(14.5,.2,.32),'FFC93C',mat='Metal')
 for y in (-1.64,1.64):box(m,'NeonEdge',(0,y,0),(14.9,.06,.15),'FFE49A',mat='Neon')
 for x in (-6.25,6.25):crown(m,x,1.75,.03)
 return m

def chair():
 m=model('VipChair')
 # Open gold overlays offset clear of the accepted Chair solids, never a duplicate Seat.
 for sign in (-1,1):
  box(m,'ArmOuterTrim',(sign*1.235,2.28,.12),(.07,.13,1.18),'FFC93C',mat='Metal')
  box(m,'SeatSidePiping',(sign*1.2,1.72,0),(.07,.11,1.8),'FFC93C',mat='Metal')
  box(m,'BackOuterTrim',(sign*1.045,2.9,-.82),(.055,1.86,.24),'FFC93C',mat='Metal')
 box(m,'SeatFrontPiping',(0,1.72,1.025),(2.1,.11,.05),'FFC93C',mat='Metal')
 box(m,'BackTopPiping',(0,3.99,-.82),(2.12,.07,.24),'FFC93C',mat='Metal')
 box(m,'BackCrest',(0,3.45,-1.085),(.72,.38,.08),'FFC93C',mat='Metal')
 crown(m,0,3.43,-1.14)
 for j in range(5):
  a=j*TAU/5
  line(m,'FiveStarWheelTrim',(.28*math.sin(a),.535-.190909*.28,.28*math.cos(a)),(.88*math.sin(a),.535-.190909*.88,.88*math.cos(a)),.045,'FFC93C',mat='Metal')
 return m
ASSETS={m['name']:m for m in [sign(),chair()]}
def bounds(ps):
 lo=[1e9]*3;hi=[-1e9]*3
 for p in ps:
  half=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  for i in range(3):lo[i]=min(lo[i],p['p'][i]-half[i]);hi[i]=max(hi[i],p['p'][i]+half[i])
 return lo,hi
if __name__=='__main__':
 (ROOT/'V14/models').mkdir(parents=True,exist_ok=True);(ROOT/'previews').mkdir(exist_ok=True)
 report={}
 for n,m in ASSETS.items():
  f=ROOT/'V14/models'/f'{n}.rbxmx';export(m,f);ps=flatten(m);assert len(ps)<=40
  doc=ET.parse(f);items=list(doc.getroot().iter('Item'));assert {i.get('class') for i in items}<= {'Model','Part'}
  assert all(p['cls']=='Part' and 'light' not in p for p in ps)
  lo,hi=bounds(ps)
  if n=='VipSignFrame':
   # Nothing obstructs the entire live board rectangle14x2.2.
   for p in ps:
    l,h=bounds([p]);assert h[0]<=-7 or l[0]>=7 or h[1]<=-1.1 or l[1]>=1.1
  pr=ROOT/'source/convert.project.json';pr.write_text(json.dumps({'name':n,'tree':{'$path':str(f)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(pr),'-o',str(f.with_suffix('.rbxm'))],check=True)
  assert f.with_suffix('.rbxm').read_bytes().startswith(b'<roblox!')
  preview(ps,ROOT/'previews'/f'{n}.png',yaw=15 if n=='VipSignFrame' else 25,elev=10 if n=='VipSignFrame' else 22,span=19 if n=='VipSignFrame' else 6.5,target=(0,0,0) if n=='VipSignFrame' else (0,2,0),W=1400,H=800 if n=='VipSignFrame' else 1200)
  report[n]={'parts':len(ps),'dimensionsXYZ':[round(hi[i]-lo[i],5) for i in range(3)],'pivot':'board center (0,0,0)' if n=='VipSignFrame' else 'existing Chair base (0,0,0)','lights':0,'Seat':False,'checks':'PASS'}
 pr.unlink();(ROOT/'MODELS_VALIDATION.json').write_text(json.dumps(report,indent=2));print(report)
