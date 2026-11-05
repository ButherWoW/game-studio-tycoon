from build_console import *
from render_geometry import preview
from PIL import Image,ImageDraw,ImageFont
import itertools,xml.etree.ElementTree as ET

def intersects(a,b,tol=1e-6):
 # SAT oriented boxes, all fifteen axes; touching faces permitted.
 axes=[[a['r'][i*3+j] for i in range(3)] for j in range(3)]+[[b['r'][i*3+j] for i in range(3)] for j in range(3)]
 cross=lambda u,v:(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
 axes+= [cross(u,v) for u in axes[:3] for v in axes[3:6]]
 for axis in axes:
  length=sum(x*x for x in axis)**.5
  if length<1e-9:continue
  axis=[x/length for x in axis]
  delta=abs(sum((b['p'][i]-a['p'][i])*axis[i] for i in range(3)))
  radius=lambda p:sum(p['s'][j]/2*abs(sum(p['r'][i*3+j]*axis[i] for i in range(3))) for j in range(3))
  if delta>=radius(a)+radius(b)-tol:return False
 return True

report={}
for n,m in ASSETS.items():
 ps=flatten(m);lo,hi=bounds(ps);dims=[hi[i]-lo[i] for i in range(3)]
 overlaps=[(a['name'],b['name']) for a,b in itertools.combinations(ps,2) if intersects(a,b)]
 assert not overlaps,(n,overlaps)
 assert abs(lo[1])<1e-6 and abs(lo[0]+hi[0])<1e-6 and abs(lo[2]+hi[2])<1e-6
 assert all(v<=cap for v,cap in zip(dims,[6,5,6]))
 limit={'Console_Design':60,'Console_Prototype':80,'Console_Launch':100}[n];assert len(ps)<=limit
 root=ET.parse(ROOT/'models'/f'{n}.rbxmx').getroot();items=root.findall('.//Item');classes=sorted(set(i.attrib['class'] for i in items));assert set(classes)<={'Model','Part','PointLight'}
 lights=[i for i in items if i.attrib['class']=='PointLight'];assert len(lights)==(1 if n=='Console_Launch' else 0)
 for i in lights:assert i.find("Properties/bool[@name='Shadows']").text=='false'
 for i in items:
  if i.attrib['class']=='Part':
   assert i.find("Properties/bool[@name='Anchored']").text=='true'
   assert i.find("Properties/bool[@name='CanCollide']").text=='false'
 assert(ROOT/'models'/f'{n}.rbxm').read_bytes().startswith(b'<roblox!')
 report[n]={'parts':len(ps),'partLimit':limit,'dimensionsXYZ':dims,'bounds':[lo,hi],'pivot':'center_of_base Y0','front':'+Z','classes':classes,'lights':len(lights),'lightShadows':False,'intersectionPairsChecked':len(ps)*(len(ps)-1)//2,'positiveVolumeIntersections':0,'checks':'PASS'}
 preview(ps,ROOT/'previews'/f'{n}.png',yaw=28,elev=29,target=(0,dims[1]/2,0),span=8.5,W=1200,H=1000)
 preview(ps,ROOT/'previews'/f'{n}_Front.png',yaw=0,elev=10,target=(0,dims[1]/2,0),span=7.8,W=1100,H=850)
 if n=='Console_Prototype':
  preview(ps,ROOT/'previews'/'Console_Prototype_Top.png',yaw=15,elev=62,target=(0,2.7,-.3),span=7.3,W=1200,H=1000)
 if n=='Console_Launch':
  product=[p for p in ps if p['name'].startswith(('Console_','Controller_'))]
  preview(product,ROOT/'previews'/'Console_Product_Closeup.png',yaw=28,elev=29,target=(0,2.9,0),span=5.6,W=1200,H=1000)
(ROOT/'MODELS_VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n')
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',22);im=Image.new('RGB',(1800,1150),'#ece6dd');d=ImageDraw.Draw(im)
for i,n in enumerate(ASSETS):
 for row,suffix in enumerate(['','_Front']):
  pic=Image.open(ROOT/'previews'/f'{n}{suffix}.png');pic.thumbnail((600,480));x=i*600;y=row*570;im.paste(pic,(x,y+45));d.text((x+20,y+14),n+(' — front' if row else ''),font=font,fill='#283345');d.text((x+20,y+530),str(report[n]['parts'])+' native Parts',font=font,fill='#283345')
im.save(ROOT/'previews'/'Console_ContactSheet.png');print(json.dumps(report,indent=2))
