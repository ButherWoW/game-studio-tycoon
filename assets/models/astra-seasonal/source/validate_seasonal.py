from build_seasonal import *
from render_geometry import preview
import xml.etree.ElementTree as ET
from PIL import Image,ImageDraw
report={'studioTested':False,'models':{},'runtimeScaling':{'Pumpkin_atPlots':1.3,'HolidayTree_atSpawn':1.5},'buildingUse':'preview/move exterior only, not gameplay floor shells','buildingFloorPitch':13.2}
for n,m in ASSETS.items():
 ps=flatten(m);lo,hi=bounds(ps);dims=[hi[i]-lo[i] for i in range(3)]
 assert abs(lo[1])<1e-6,(n,lo)
 if n in ['Pumpkin','HalloweenSign']:assert dims[0]<=3 and dims[2]<=3
 elif n=='HolidayTree':assert dims[0]<=6 and dims[2]<=6 and dims[1]<=12
 else:assert dims[0]<=60+1e-6 and dims[2]<=60+1e-6 and dims[1]<=40;assert len(m['children'])==3
 assert len(ps)<=(600 if n=='OfficeBuilding' else 250)
 root=ET.parse(ROOT/'models'/f'{n}.rbxmx').getroot();items=root.findall('.//Item');assert {i.get('class') for i in items}<={'Part','Model','PointLight'}
 assert all(e.findtext("Properties/bool[@name='Shadows']")=='false' for e in items if e.get('class')=='PointLight')
 assert sum(bool(p.get('light')) for p in ps)==(0 if n=='OfficeBuilding' else 1)
 assert (ROOT/'models'/f'{n}.rbxm').read_bytes().startswith(b'<roblox!')
 report['models'][n]={'parts':len(ps),'dimensionsXYZ':[round(x,4) for x in dims],'baseY':0,'pointLights':sum(bool(p.get('light')) for p in ps),'checks':'PASS'}
 preview(ps,ROOT/'previews'/f'{n}.png',yaw=25,elev=22,span=max(dims)*1.5,target=(0,dims[1]/2,0),W=1500 if n=='OfficeBuilding' else 1100,H=1200 if n=='OfficeBuilding' else 950)
report['checks']=['exact technical names','native class allowlist','script/mesh/texture-free','source Part dimension bounds','baseY0','one shadowless light on each seasonal prop','no lights on exterior building','three building storeys;39.6height','Rojo binary builds']
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2))
im=Image.new('RGB',(1800,1500),'#ece6dd');d=ImageDraw.Draw(im)
for i,n in enumerate(ASSETS):
 pic=Image.open(ROOT/'previews'/f'{n}.png');pic.thumbnail((900,675));x=i%2*900;y=i//2*750;im.paste(pic,(x,y+30));d.text((x+25,y+10),n,fill='#283345');d.text((x+25,y+715),str(report['models'][n]['parts'])+' Parts',fill='#283345')
im.save(ROOT/'previews'/'Seasonal_ContactSheet.png')
print(json.dumps(report,indent=2))
