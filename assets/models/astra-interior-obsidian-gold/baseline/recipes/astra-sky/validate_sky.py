from build_sky import *
import itertools, xml.etree.ElementTree as ET
from render_geometry import preview
import numpy as np
from PIL import Image,ImageDraw

def bounds(ps):
 lo=[];hi=[]
 for p in ps:
  R=np.array(p['r']).reshape(3,3);s=np.array(p['s'])/2
  if p['shape']=='ball':e=np.sqrt((R*R)@(s*s))
  elif p['shape']=='cyl':e=np.abs(R[:,0])*s[0]+np.sqrt((R[:,1]*s[1])**2+(R[:,2]*s[2])**2)
  else:e=np.abs(R)@s
  lo.append(np.array(p['p'])-e);hi.append(np.array(p['p'])+e)
 return np.min(lo,axis=0),np.max(hi,axis=0)
def overlap(a,b,t=.025):return all(min(a[1][i],b[1][i])-max(a[0][i],b[0][i])>t for i in range(3))
def placed(n,p,y):
 m=model('Placed');put(m,ASSETS[n],p,y);return flatten(m)
limits={'Skyscraper':(60,14,60,600),'SkyDesk':(8,8,4,250),'SoundStudio':(12,12,10,600),'ArtWall':(14,12,1,250)}
report={'models':{},'checks':[],'studioTested':False,'localBaseY':0,'gamePlacementY':28}
for n,m in ASSETS.items():
 ps=flatten(m);lo,hi=bounds(ps);dims=hi-lo;limit=limits[n]
 assert all(dims[i]<=limit[i]+1e-6 for i in range(3)),(n,dims)
 assert len(ps)<=limit[3] and abs(lo[1])<1e-6,(n,len(ps),lo)
 tree=ET.parse(ROOT/'models'/f'{n}.rbxmx').getroot();items=tree.findall('.//Item')
 assert {i.attrib['class'] for i in items}<={'Part','Model','PointLight'}
 assert all(i.find("./Properties/bool[@name='Shadows']").text=='false' for i in items if i.attrib['class']=='PointLight')
 assert all(i.find("./Properties/bool[@name='Anchored']").text=='true' for i in items if i.attrib['class']=='Part')
 mn=tree.find("./Item[@class='Model']");ref=mn.find("./Properties/Ref[@name='PrimaryPart']").text;pp=tree.find(f".//Item[@referent='{ref}']/Properties")
 def cf(name):
  q=pp.find(f"CoordinateFrame[@name='{name}']");return np.array([float(q.find(a).text) for a in 'XYZ']),np.array([float(q.find(f'R{i}{j}').text) for i in range(3) for j in range(3)]).reshape(3,3)
 p,r=cf('CFrame');o,rr=cf('PivotOffset');assert np.max(abs(p+r@o))<1e-6 and np.max(abs(r@rr-np.eye(3)))<1e-6
 assert (ROOT/'models'/f'{n}.rbxm').read_bytes().startswith(b'<roblox!')
 for p in ps:
  assert min(p['s'])>.001
  R=np.array(p['r']).reshape(3,3);assert np.max(abs(R@R.T-np.eye(3)))<1e-6
 report['models'][n]={'parts':len(ps),'dimensionsXYZ':dims.round(4).tolist(),'min':lo.tolist(),'max':hi.tolist(),'pointLights':sum(bool(p.get('light')) for p in ps),'checks':'PASS'}
instances=[(n+str(i),placed(n,p,y)) for i,(n,p,y) in enumerate(LAYOUT) if n!='Skyscraper']
for (a,pa),(b,pb) in itertools.combinations(instances,2):assert not overlap(bounds(pa),bounds(pb)),(a,b)
shell=[p for p in flatten(ASSETS['Skyscraper']) if p['name'] not in ['Floor','FloorJoint']]
for n,ps in instances:
 for p in shell:assert not overlap(bounds(ps),bounds([p])),('shell',n,p['name'])
lift=([-23,.03,21],[-17,7,27]);entry=([-12,0,29.5],[12,9,30])
for n,ps in instances:
 assert not overlap(bounds(ps),lift),('lift',n)
 assert not overlap(bounds(ps),entry),('entry',n)
for p in shell:
 assert not overlap(bounds([p]),lift),('lift-shell',p['name'])
 assert not overlap(bounds([p]),entry),('entry-shell',p['name'])
for x,z in DESKS:
 bb=bounds(placed('SkyDesk',(x,0,z),0));apron=([bb[0][0],0,bb[1][2]],[bb[1][0],5,bb[1][2]+3])
 for n,ps in instances:
  if np.max(abs(bounds(ps)[0]-bb[0]))<1e-6:continue
  assert not overlap(apron,bounds(ps)),('apron',x,z,n)
 for p in shell:assert not overlap(apron,bounds([p])),('apron-shell',p['name'])
for row in [DESKS[:4],DESKS[4:9],DESKS[9:]]:
 for a,b in zip(row,row[1:]):
  ba=bounds(placed('SkyDesk',(a[0],0,a[1]),0));bb=bounds(placed('SkyDesk',(b[0],0,b[1]),0));assert bb[0][0]-ba[1][0]>=4-1e-6
legacy=[('playerDesk',([-15.8,0,-21.75],[-8.2,5.5,-15.8])),('coffee',([23.5,0,-27.5],[26.5,6,-20.5])),('hitShelf',([-29,0,-20],[-26.2,8,-10]))]
for n,ps in instances:
 for old,bb in legacy:assert not overlap(bounds(ps),bb),('legacy',n,old)
# Front6.4-wide booth door plus6-stud clear forward approach, no other furniture.
boothDoor=([-21.2,0,18.3],[-14.8,6,24.3])
for n,ps in instances:
 if not n.startswith('SoundStudio'):assert not overlap(bounds(ps),boothDoor),('studio-door',n)
for p in shell:assert not overlap(bounds([p]),boothDoor),('studio-door-shell',p['name'])
roof=next(p for p in shell if p['name']=='Roof');assert bounds([roof])[0][1]==13 and bounds([roof])[1][1]==14
assert next(p for p in flatten(ASSETS['Skyscraper']) if p['name']=='Floor')['s']==(58,.02,58)
assert all(bounds([p])[1][1]<=13+1e-6 for p in shell if p['name']!='Roof')
report['checks']=['native Parts only; no scripts/meshes/textures','part/dimension budgets','base Y0 and PrimaryPart PivotOffset','all anchored; orthonormal matrices','peer-model bounds nonintersecting','furniture clear of shell','11 Config stage4 desks','3-stud desk aprons clear','4-stud minimum horizontal desk gaps','lift6x6x7 clear','24x9 front aperture clear','player/coffee/hits reserved volumes clear','6.4-stud booth door with6-stud approach','walls <=13; roof13..14; floor58x58','one light per ceiling fixture, all Shadows=false','binary Rojo exports']
report['limitations']='Not Studio/runtime tested. Gameplay code supplies lift, upper-entry glass, employee positioning and stage Y28. Assembled file is a layout reference; import named templates individually or through Upgrades collection.'
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2))
# Actual exported geometry, only camera cutaways remove roof/nearest shell in overview.
cut=flatten(FULL);cut=[p for p in cut if p['name'] not in ['Roof','LampCase','LampDiffuser','EntranceLintel','FrontBand','FrontGlazing','FrontMullion'] and not (p['name'] in ['SideWallBand','PanoramicSide','WindowMullion','SideNeon'] and p['p'][0]>29)]
preview(cut,ROOT/'previews'/'Sky_Overview_Cutaway.png',yaw=25,elev=45,span=95,target=(0,2,0),W=2000,H=1550)
preview(flatten(ASSETS['SkyDesk']),ROOT/'previews'/'SkyDesk.png',yaw=28,elev=22,span=7.8,target=(0,2.2,0),W=1300,H=1150)
preview(flatten(ASSETS['SoundStudio']),ROOT/'previews'/'SoundStudio.png',yaw=22,elev=30,span=18,target=(0,3,0),W=1500,H=1150)
preview(flatten(ASSETS['ArtWall']),ROOT/'previews'/'ArtWall.png',yaw=12,elev=12,span=19,target=(0,3.7,0),W=1500,H=1000)
preview(flatten(ASSETS['Skyscraper']),ROOT/'previews'/'Skyscraper_Exterior.png',yaw=28,elev=24,span=95,target=(0,6,0),W=1700,H=1200)
# Geometry-plan preview with per-instance boxes and reserved volumes from validated data.
im=Image.new('RGB',(1400,1500),'#eee8e0');d=ImageDraw.Draw(im);scale=19;ox=700;oy=720
pt=lambda x,z:(ox+x*scale,oy+z*scale)
d.rectangle([pt(-30,-30),pt(30,30)],outline='#283345',width=4)
for n,ps in instances:
 lo,hi=bounds(ps);d.rectangle([pt(lo[0],lo[2]),pt(hi[0],hi[2])],fill='#7C4DFF' if n.startswith('SkyDesk') else '#3D7BFF',outline='#283345',width=2);d.text(pt(lo[0],lo[2]),n,fill='white')
for x,z in DESKS:
 bb=bounds(placed('SkyDesk',(x,0,z),0));d.rectangle([pt(bb[0][0],bb[1][2]),pt(bb[1][0],bb[1][2]+3)],outline='#3DDC84',width=3)
d.rectangle([pt(-23,21),pt(-17,27)],outline='#FF5A5F',width=4);d.text(pt(-23,24),'LIFT',fill='#FF5A5F');d.text((50,40),'SKY: CONFIG STAGE4 | green=desk apron3 | red=reserved lift | +Z front at bottom',fill='#283345');im.save(ROOT/'previews'/'Sky_Layout_QA.png')
print(json.dumps(report['models'],indent=2))
