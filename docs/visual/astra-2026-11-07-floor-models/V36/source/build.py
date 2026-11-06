from geometry import *
from render_geometry import preview
from convex_support import parse,audit,support,np
import subprocess,json
ROOT=Path(__file__).resolve().parents[1]
for f in ['models','previews']:(ROOT/f).mkdir(exist_ok=True)
def lounge():
 m=model('Lounge')
 # Sofa modules meet only at support surfaces; no overlapping rounded helper.
 box(m,'SofaBase',(0,.52,-1.8),(7.3,.28,2.2),'9A7655',mat='Wood')
 for x in [-2.8,2.8]:
  for z in [-2.5,-1.1]:
   cyl(m,'SofaFoot',(x,.19,z),.38,.18,'6C513C')
 for sign in [-1,1]:
  box(m,'SeatCushion',(sign*1.58,.91,-1.8),(3.10,.50,2.2),'8AA57D')
  box(m,'BackCushion',(sign*1.58,1.9,-3.20),(3.10,1.80,.60),'92AB84')
  ball(m,'ThrowPillow',(sign*1.9,1.535,-2.77),(.85,.75,.26),'D8D7AE')
  box(m,'BackSupport',(sign*1.58,1.18,-3.59),(3.10,1.60,.18),'9A7655',mat='Wood')
  box(m,'SofaArm',(sign*3.4,1.0,-1.8),(.50,.68,2.2),'718E69')
  # Planter with four disjoint rim beams and an independent inset soil surface.
  x=sign*4.8;z=-2
  box(m,'Planter',(x,.45,z),(1.6,.90,1.6),'BE9565',mat='Wood')
  for dz in [-.74,.74]:box(m,'PlanterRim',(x,.96,z+dz),(1.6,.12,.12),'DBBA86')
  for dx in [-.74,.74]:box(m,'PlanterRim',(x+dx,.96,z),(.12,.12,1.36),'DBBA86')
  box(m,'Soil',(x,.93,z),(1.28,.06,1.28),'5F4C3D')
  box(m,'PlantStem',(x,1.805,z),(.06,1.69,.06),'47714B')
  for dx,y in [(-.405,1.55),(.405,2.08),(-.405,2.4),(.405,1.25)]:
   ball(m,'BroadLeaf',(x+dx,y,z),(.75,.10,.65),'71A568')
  ball(m,'TopLeaf',(x,2.93,z),(.40,.56,.50),'91B675')
 # Coffee table, three legs and two stacked books.
 cyl(m,'TableTop',(0,.95,4.5),.18,2.4,'D6BA8C',mat='Wood')
 for a in [0,120,240]:
  t=math.radians(a);cyl(m,'TableLeg',(.7*math.cos(t),.43,4.5+.7*math.sin(t)),.86,.12,'8D6D4D')
 box(m,'BookPages',(.22,1.11,4.5),(.80,.14,.55),'F1E9D5')
 box(m,'BookCover',(.22,1.195,4.5),(.84,.03,.59),'527B90')
 return m
def artwall():
 m=model('ArtWall')
 for x in [-5.8,5.8]:box(m,'Foot',(x,.15,0),(1.6,.30,1.0),'605D67',mat='Metal')
 for x in [-6.7,6.7]:box(m,'FrameSide',(x,4.20,0),(.20,7.80,.60),'AA845A',mat='Wood')
 box(m,'BackPanel',(0,4.20,-.25),(13,7.80,.16),'252B45')
 box(m,'FrameRail',(0,8.20,-.25),(13.6,.20,.16),'AA845A',mat='Wood')
 box(m,'FrameBottom',(0,.20,-.25),(9.6,.20,.16),'AA845A',mat='Wood')
 for x in [-6.7,6.7]:box(m,'FrameBottomCorner',(x,.20,-.25),(.20,.20,.16),'AA845A',mat='Wood')
 for x,c in [(-4.5,'36415B'),(-1.5,'41415F'),(2.5,'2E3C51')]:
  box(m,'FeltPanel',(x,4.2,-.11),(2.6,6.1,.12),c)
 for x in [4.45,4.70,4.95,5.20,5.45,5.70]:
  box(m,'OakSlat',(x,4.2,-.08),(.12,6.1,.18),'C4A06A',mat='Wood')
 for x in [-6.15,.12]:
  box(m,'GlowAccent',(x,4.20,-.08),(.07,5.7,.18),'55C8D3',mat='Neon')
 # Color blocks remain independent of felt. Geometry substitutes for textures.
 for x,y,w,h,c in [(-4.5,5.8,1.9,1.2,'8F68CF'),(-4.5,3.8,1.4,1.4,'57BBC7'),(-1.5,2.2,1.9,.7,'D3AA69')]:
  box(m,'AbstractTile',(x,y,-.015),(w,h,.07),c)
 # Small central artwork; flush internal canvas with distinct border beams.
 for x in [.19,3.01]:
  box(m,'PictureSide',(x,4.6,.12),(.16,2.3,.12),'D8B780',mat='Wood')
 for y in [3.37,5.83]:
  box(m,'PictureRail',(1.6,y,.12),(2.98,.16,.12),'D8B780',mat='Wood')
 box(m,'Canvas',(1.6,4.6,.12),(2.66,2.30,.06),'80BFC3')
 for x,y,w,h,c in [(1.0,4.1,.65,.8,'688F67'),(1.8,4.3,.60,1.2,'91B778'),(2.48,4.0,.60,.60,'4D785C')]:
  box(m,'Landscape',(x,y,.165),(w,h,.03),c)
 ball(m,'Sun',(2.35,5.27,.17),(.45,.45,.04),'EDCD77')
 # Standoffs attach artwork to the backing without entering adjacent features.
 for x in [.5,2.6]:box(m,'PictureMount',(x,4.6,.02),(.12,.12,.14),'605D67')
 return m
reports=[]
for m in [lounge(),artwall()]:
 name=m['name']
 for q in m['parts']:
  q['collide']=q['name'] in {'SofaBase','SeatCushion','BackCushion','SofaArm','Planter','TableTop','BackPanel'}
 # Ground and center the actual native support bounds before serialization.
 centers=[]
 for axis in [0,2]:
  vs=[v[axis] for q in m['parts'] for v in meshes(q)[0]]
  centers.append((min(vs)+max(vs))/2)
 for q in m['parts']:q['p']=(q['p'][0]-centers[0],q['p'][1],q['p'][2]-centers[1])
 p=ROOT/'models'/(name+'.rbxmx');export(m,p)
 project=ROOT/'source/build.project.json';project.write_text(json.dumps({'name':name,'tree':{'$path':str(p)}}))
 subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(project),'-o',str(p.with_suffix('.rbxm'))],check=True,capture_output=True);project.unlink()
 ps=parse(p);cert,bad=audit(ps);assert not bad,(name,bad)
 lo=[min(support(q,-np.eye(3)[i])[i]for q in ps)for i in range(3)];hi=[max(support(q,np.eye(3)[i])[i]for q in ps)for i in range(3)]
 # Center base footprint without an invisible helper.
 # ArtWall is intentionally asymmetric in Z visually; export shifted actual footprint below.
 reports.append({'name':name,'parts':len(ps),'bounds':[lo,hi],'pairs':len(cert),'overlaps':bad,'runtimeTested':False})
 (ROOT/(name+'_CERTIFICATES.json')).write_text(json.dumps(cert,indent=2)+'\n')
 for label,yaw in [('Front',0),('ThreeQuarter',35),('Rear',150)]:
  preview(m['parts'],ROOT/'previews'/(name+'_'+label+'.png'),yaw=yaw,elev=20,target=(0,1.6,-.3)if name=='Lounge'else(0,4.1,0),span=13.5 if name=='Lounge' else 16.0,W=1100,H=850)
(ROOT/'VALIDATION.json').write_text(json.dumps(reports,indent=2)+'\n')
print(json.dumps(reports,indent=2))
