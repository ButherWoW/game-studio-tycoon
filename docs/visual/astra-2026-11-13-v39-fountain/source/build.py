"""Native script-free fountain; true sloping bowl panels, no tiered disk approximation."""
from geometry import *
import numpy as np
import subprocess, os

ROOT=Path(__file__).resolve().parents[1]
STONE='B5B9C8'; EDGE='777FA1'; GOLD='D9AA50'; WATER='55B9D2'
M=model('Fountain')

def right_prism(name,q,a,b,thickness,color):
    q,a,b=map(lambda x:np.array(x,dtype=float),(q,a,b))
    ey=(b-q)/np.linalg.norm(b-q);ez=-(a-q)/np.linalg.norm(a-q);ex=np.cross(ey,ez)
    R=np.column_stack((ex,ey,ez))
    assert abs(np.dot(ey,ez))<1e-8 and np.linalg.det(R)>.999999
    p=q+(b-q)/2+(a-q)/2
    part(M,name,tuple(p),(thickness,float(np.linalg.norm(b-q)),float(np.linalg.norm(a-q))),color,
         shape='wedge',r=tuple(R.reshape(-1)),cls='WedgePart',collide=True)

def triangle(name,a,b,c,thickness,color):
    a,b,c=map(lambda x:np.array(x,dtype=float),(a,b,c))
    # Longest side ensures the altitude foot is on the segment.
    choices=[(a,b,c),(b,c,a),(c,a,b)];a,b,c=max(choices,key=lambda t:np.linalg.norm(t[1]-t[0]))
    u=b-a;foot=a+u*np.dot(c-a,u)/np.dot(u,u)
    for end in (a,b):
        if np.linalg.norm(end-foot)>1e-6:right_prism(name,foot,end,c,thickness,color)

def ring(name,ri,yi,ro,yo,thick,color,n=24):
    # Small mortar joints prevent the extruded neighbouring panels from overlapping.
    gap=math.radians(0.8)
    for i in range(n):
        a=TAU*i/n+gap/2;b=TAU*(i+1)/n-gap/2
        pts=[(r*math.cos(t),y,r*math.sin(t)) for r,y,t in [(ri,yi,a),(ro,yo,a),(ro,yo,b),(ri,yi,b)]]
        triangle(f'{name}_{i:02d}',pts[0],pts[1],pts[2],thick,color)
        triangle(f'{name}_{i:02d}',pts[0],pts[2],pts[3],thick,color)

# Bounds and base pivot match the accepted 10.8-stud foundation; local Y=0.
cyl(M,'Foundation',(0,.15,0),.3,10.8,EDGE,collide=True)
ring('BasinRim',4.8,.64,5.3,.64,.60,STONE,n=24)
cyl(M,'BasinWater',(0,.435,0),.03,9.4,WATER)
# Stems start above water: no opaque stem passes through any water volume.
cyl(M,'PedestalFoot',(0,.36,0),.12,1.8,EDGE,collide=True)
cyl(M,'Pedestal',(0,1.23,0),1.56,1.3,STONE,collide=True)
cyl(M,'LowerBowlFloor',(0,2.045,0),.07,1.3,EDGE,collide=True)
ring('LowerBowlPanel',.65,2.10,2.05,2.70,.08,STONE,n=24)
cyl(M,'LowerWater',(0,2.61,0),.03,3.30,WATER)
cyl(M,'UpperStem',(0,3.055,0),.86,.70,EDGE,collide=True)
cyl(M,'UpperBowlFloor',(0,3.525,0),.08,.70,EDGE,collide=True)
ring('UpperBowlPanel',.35,3.60,1.125,3.98,.065,STONE,n=20)
cyl(M,'UpperWater',(0,3.91,0),.03,1.68,WATER)
cyl(M,'Nozzle',(0,4.025,0),.20,.26,GOLD)
box(M,'JetTop',(0,4.14,0),(.14,.03,.14),WATER)
# Relief: large spaced teardrop medallions, no busy microdetail or baked lettering.
for i in range(8):
    t=TAU*i/8;r=.71
    ball(M,f'PedestalRelief_{i}',(r*math.cos(t),1.28,r*math.sin(t)),(.12,.48,.12),GOLD)
for i in range(12):
    t=TAU*(i+.5)/12;r=5.10
    ball(M,f'RimPearl_{i}',(r*math.cos(t),1.04,r*math.sin(t)),(.20,.20,.20),GOLD)
# Compatible full-bowl emitters; invisible proxy volumes are deliberately not solid geometry.
box(M,'LowerBowl',(0,2.70,0),(4.1,.03,4.1),WATER,alpha=1)
box(M,'UpperBowl',(0,3.98,0),(2.25,.03,2.25),WATER,alpha=1)
# Native cylinders use X as their long axis; use a box proxy for the ripple radius calculation.
# Rename the real water disc; proxy gives FountainFx a world-Y thickness and correct diameter.
for p in M['parts']:
    if p['name']=='BasinWater':p['name']='BasinWaterSurface'
box(M,'BasinWater',(0,.435,0),(9.4,.03,9.4),WATER,alpha=1)

if __name__=='__main__':
    (ROOT/'models').mkdir(exist_ok=True)
    export(M,ROOT/'models/Fountain.rbxmx')
    (ROOT/'geometry.json').write_text(json.dumps(M,indent=2)+'\n')
    rojo=os.environ.get('ROJO','/Users/erland/.local/gst-tools/rojo')
    project=ROOT/'source/fountain.project.json'
    project.write_text(json.dumps({'name':'Fountain','tree':{'$path':'../models/Fountain.rbxmx'}}))
    subprocess.run([rojo,'build',str(project),'-o',str(ROOT/'models/Fountain.rbxm')],check=True)
    print('Parts:',len(M['parts']))
