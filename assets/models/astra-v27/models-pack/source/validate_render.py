from build_v27 import *
from render_geometry import preview
from independent_audit import parse,overlaps,mv,mm,bounds,I,props,cf
from PIL import Image,ImageDraw,ImageFont
import itertools
report=json.loads((ROOT/'INDEPENDENT_VALIDATION.json').read_text());assert report['status']=='PASS'
root,parts=parse(ROOT/'models/ParkSafe.rbxmx');dooritem=next(i for i in root.findall('.//Item') if i.attrib['class']=='Model' and props(i)['Name'].text=='Door');refs={i.attrib['referent'] for i in dooritem.findall('.//Item')};hinge=next(p for p in parts if p['name']=='Hinge');checks=[]
for angle in range(0,116,5):
 R=rot(y=-angle);turned=[]
 for p in parts:
  q=copy.deepcopy({k:v for k,v in p.items() if k!='item'});q['moving']=p['item'].attrib['referent'] in refs
  if q['moving']:q['p']=add(hinge['p'],mv(R,tuple(q['p'][i]-hinge['p'][i] for i in range(3))));q['r']=mm(R,q['r'])
  turned.append(q)
 collisions=[[a['name'],b['name']] for a,b in itertools.combinations(turned,2) if a['moving']!=b['moving'] and overlaps(a,b)]
 checks.append({'angle':angle,'collisions':collisions})
report['doorSweep']={'anglesDegrees':[x['angle'] for x in checks],'positiveVolumeIntersections':checks,'status':'PASS' if not any(x['collisions'] for x in checks) else 'FAIL','note':'Exactly mirrors SafeController axis * rotationY(-angle), Door Model descendants move; includes115deg Back easing overshoot reserve.'}
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n');assert report['doorSweep']['status']=='PASS',checks
for n,m in ASSETS.items():
 ps=flatten(m);dims=report['models'][n]['dimensionsXYZ'];preview(ps,ROOT/'previews'/(n+'.png'),yaw=24,elev=24,target=(0,dims[1]/2,0),span=max(dims)*1.55,W=1100,H=1000)
 preview(ps,ROOT/'previews'/(n+'_Front.png'),yaw=0,elev=8,target=(0,dims[1]/2,0),span=max(dims)*1.35,W=1000,H=1000)
m=copy.deepcopy(ASSETS['ParkSafe']);door=next(c for c in m['children'] if c['name']=='Door');R=rot(y=-90);axis=(-1.555,2.5,1.78)
for p in door['parts']:p['p']=add(axis,mv(R,tuple(p['p'][i]-axis[i] for i in range(3))));p['r']=mm(R,p['r'])
preview(flatten(m),ROOT/'previews/ParkSafe_Open.png',yaw=20,elev=23,target=(0,2.5,.9),span=8,W=1200,H=1000)
s=Image.new('RGB',(1500,900),'#ece6dd');d=ImageDraw.Draw(s);font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',24)
for k,(nm,title) in enumerate([('ParkSafe','ParkSafe:41 Parts'),('ParkSafe_Open','Door open90deg'),('Trophy_Blitz','Trophy_Blitz:19 Parts')]):
 im=Image.open(ROOT/'previews'/(nm+'.png'));im.thumbnail((500,740));s.paste(im,(k*500,(800-im.height)//2));d.text((k*500+15,820),title,font=font,fill='#202b48')
s.save(ROOT/'previews/V27_Models_ContactSheet.png')
