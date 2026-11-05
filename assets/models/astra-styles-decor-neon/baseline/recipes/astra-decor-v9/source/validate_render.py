from build_decor import *
from render_geometry import preview
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image,ImageDraw
LIMITS={'BeanBags':(8,3,2.5,60),'Bookshelf':(6,1.5,5,80),'MiniFridge':(2.5,2.5,4,60),'NeonSign':(6,.3,2.5,40),'Aquarium':(6,2,5,80),'ArcadeMachine':(3,2.6,6,80)}
report={}
for name,m in ASSETS.items():
 ps=flatten(m);mins=[];maxs=[]
 for p in ps:
  R=np.array(p['r']).reshape(3,3);s=np.array(p['s'])/2
  # Exact support radii for native primitives, including oriented ellipsoids/cylinders.
  if p['shape']=='ball':ext=np.sqrt((R*R)@(s*s))
  elif p['shape']=='cyl':ext=np.abs(R[:,0])*s[0]+np.sqrt((R[:,1]*s[1])**2+(R[:,2]*s[2])**2)
  else:ext=np.abs(R)@s
  mins.append(np.array(p['p'])-ext);maxs.append(np.array(p['p'])+ext)
 lo=np.min(mins,axis=0);hi=np.max(maxs,axis=0);size=hi-lo;w,d,h,limit=LIMITS[name]
 assert size[0]<=w+1e-6 and size[1]<=h+1e-6 and size[2]<=d+1e-6,(name,size)
 assert len(ps)<=limit
 if name!='NeonSign':
  assert abs(lo[1])<1e-6
  assert abs(lo[0]+hi[0])<1e-6 and abs(lo[2]+hi[2])<1e-6
 else:assert abs((lo[1]+hi[1])/2)<1e-6
 root=ET.parse(ROOT/'models'/f'{name}.rbxmx').getroot();items=root.findall('.//Item');classes={e.attrib['class'] for e in items}
 assert classes<={'Model','Part','PointLight'},classes
 assert len([e for e in items if e.attrib['class']=='Part'])==len(ps)
 lights=[e for e in items if e.attrib['class']=='PointLight']
 assert len(lights)==(1 if name in ['MiniFridge','NeonSign','Aquarium','ArcadeMachine'] else 0)
 assert all(e.find("./Properties/bool[@name='Shadows']").text=='false' for e in lights)
 assert all(e.find("./Properties/bool[@name='Anchored']").text=='true' for e in items if e.attrib['class']=='Part')
 modelnode=root.find("./Item[@class='Model']");primary=modelnode.find("./Properties/Ref[@name='PrimaryPart']").text
 pp=root.find(f".//Item[@referent='{primary}']");props=pp.find('Properties')
 def cf(tag):
  q=props.find(f"CoordinateFrame[@name='{tag}']");pos=np.array([float(q.find(a).text) for a in 'XYZ']);r=np.array([float(q.find(f'R{i}{j}').text) for i in range(3) for j in range(3)]).reshape(3,3);return pos,r
 p,r=cf('CFrame');o,rr=cf('PivotOffset');assert np.max(np.abs(p+r@o))<1e-6 and np.max(np.abs(r@rr-np.eye(3)))<1e-6
 data=(ROOT/'models'/f'{name}.rbxm').read_bytes();assert data.startswith(b'<roblox!')
 report[name]={'parts':len(ps),'limit':limit,'size_W_D_H':[round(float(size[i]),4) for i in [0,2,1]],'bounds_min':lo.tolist(),'bounds_max':hi.tolist(),'pivot':[0,0,0],'pivot_rule':'panel_center' if name=='NeonSign' else 'center_base','lights':len(lights),'light_shadows':False,'classes':sorted(classes),'binary_verified':True,'checks':'PASS'}
 preview(ps,ROOT/'previews'/f'{name}.png',yaw=23 if name!='NeonSign' else 8,elev=17 if name!='NeonSign' else 5,span=max(w,h)*1.4,target=(0,float((lo[1]+hi[1])/2),0),W=1200,H=1000)
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2))
canvas=Image.new('RGB',(1800,1200),'#ece6dd');draw=ImageDraw.Draw(canvas)
for i,(name,m) in enumerate(ASSETS.items()):
 im=Image.open(ROOT/'previews'/f'{name}.png');im.thumbnail((600,500));x=(i%3)*600;y=(i//3)*600;canvas.paste(im,(x,y+35));draw.text((x+30,y+20),name,fill='#283345');draw.text((x+30,y+550),f"{report[name]['parts']} Parts | "+' x '.join(str(a) for a in report[name]['size_W_D_H'])+' W/D/H',fill='#283345')
canvas.save(ROOT/'previews'/'V9_ContactSheet.png')
print(json.dumps(report,indent=2))
