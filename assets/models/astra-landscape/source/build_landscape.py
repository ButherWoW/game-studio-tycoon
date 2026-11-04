"""Original simple modular street/landscape primitives, maximum15 Parts each."""
from geometry import *
import subprocess

def rock(name,s):
 m=model(name)
 ball(m,'StoneCore',(0,.6*s,0),(2*s,1.2*s,1.6*s),'929CA1')
 ball(m,'StoneShoulder',(-.7*s,.35*s,.1*s),(1*s,.7*s,1.1*s),'AEB5B4')
 ball(m,'StoneCap',(.2*s,1.1*s,-.1*s),(1.4*s,.8*s,1.2*s),'BFC3BA')
 return m

def hedge():
 m=model('Hedge')
 for x in [-2.5,0,2.5]:
  cyl(m,'WoodyStem',(x,.55,0),1.1,.18,'745439')
  box(m,'LeafBody',(x,1.55,0),(2.55,2,1.8),'4F9A48')
  box(m,'LeafTop',(x,2.58,0),(2.45,.12,1.7),'72B95A')
 return m

def fence():
 m=model('FenceSection')
 for x in [-2.8,2.8]:
  box(m,'Post',(x,1.5,0),(.3,3,.3),'9C6B3F',collide=True)
  box(m,'PostCap',(x,3.06,0),(.38,.12,.38),'C8A27A')
 for y in [1,2.35]:box(m,'Rail',(0,y,0),(5.3,.22,.17),'C8A27A',collide=True)
 for x in [-1.8,-.6,.6,1.8]:box(m,'Picket',(x,1.6,0),(.23,2.25,.16),'9C6B3F',collide=True)
 return m

def bench():
 m=model('StreetBench')
 for x in [-2.28,2.28]:
  for z in [-.6,.6]:box(m,'Leg',(x,.7,z),(.18,1.4,.18),'406457',collide=True)
  box(m,'ArmSupport',(x,1.65,0),(.13,1.3,.16),'406457')
  box(m,'ArmPad',(x,2.34,0),(.22,.12,1.6),'9C6B3F')
 for z in [-.56,0,.56]:box(m,'SeatSlat',(0,1.53,z),(5.8,.26,.49),'9C6B3F',collide=True)
 for y in [2.02,2.56]:box(m,'BackSlat',(0,y,-.81),(5.8,.42,.2),'C8A27A',collide=True)
 box(m,'BackRail',(0,1.69,-.8),(4.7,.15,.15),'406457')
 return m

ASSETS={m['name']:m for m in [rock('RockSmall',.6),rock('RockMedium',1),rock('RockLarge',1.65),hedge(),fence(),bench()]}
# Exact oriented bounds for these box/cylinder primitives; center every footprint and groundY0.
def bounds(ps):
 lo=[float('inf')]*3;hi=[-float('inf')]*3
 for p in ps:
  h=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  for i in range(3):lo[i]=min(lo[i],p['p'][i]-h[i]);hi[i]=max(hi[i],p['p'][i]+h[i])
 return lo,hi
for m in ASSETS.values():
 lo,hi=bounds(m['parts']);offset=(-(lo[0]+hi[0])/2,-lo[1],-(lo[2]+hi[2])/2)
 for p in m['parts']:p['p']=add(p['p'],offset)
 if m['name'].startswith('Rock'):
  for p in m['parts']:p['collide']=True
if __name__=='__main__':
 for n,m in ASSETS.items():
  dest=ROOT/'models'/f'{n}.rbxmx';export(m,dest)
  pr=ROOT/'source'/'convert.project.json';pr.write_text(json.dumps({'name':n,'tree':{'$path':str(dest)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(pr),'-o',str(dest.with_suffix('.rbxm'))],check=True)
 pr.unlink()
