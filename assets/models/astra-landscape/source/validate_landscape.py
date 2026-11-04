from build_landscape import *
from render_geometry import preview
import xml.etree.ElementTree as ET
from PIL import Image,ImageDraw
report={}
for n,m in ASSETS.items():
 lo,hi=bounds(flatten(m));dims=[hi[i]-lo[i] for i in range(3)];ps=flatten(m)
 assert len(ps)<=15 and abs(lo[1])<1e-6
 assert abs(lo[0]+hi[0])<1e-6 and abs(lo[2]+hi[2])<1e-6
 if n=='Hedge':assert 6<=dims[0]<=8
 if n=='FenceSection':assert dims[0]<=6
 tree=ET.parse(ROOT/'models'/f'{n}.rbxmx').getroot();items=tree.findall('.//Item');assert {i.attrib['class'] for i in items}=={'Part','Model'}
 assert all(i.find("./Properties/bool[@name='Anchored']").text=='true' for i in items if i.attrib['class']=='Part')
 assert (ROOT/'models'/f'{n}.rbxm').read_bytes().startswith(b'<roblox!')
 report[n]={'parts':len(ps),'dimensionsXYZ':[round(d,4) for d in dims],'baseY':0,'pivot':'center_base','classes':['Model','Part'],'lights':0,'checks':'PASS'}
 preview(ps,ROOT/'previews'/f'{n}.png',yaw=25,elev=20,span=max(dims)*1.5,target=(0,dims[1]/2,0),W=1100,H=850)
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2))
im=Image.new('RGB',(1800,1100),'#ece6dd');d=ImageDraw.Draw(im)
for i,n in enumerate(ASSETS):
 p=Image.open(ROOT/'previews'/f'{n}.png');p.thumbnail((600,460));x=i%3*600;y=i//3*550;im.paste(p,(x,y+35));d.text((x+25,y+12),n,fill='#283345');d.text((x+25,y+515),str(report[n]['parts'])+' Parts',fill='#283345')
im.save(ROOT/'previews'/'Landscape_ContactSheet.png')
print(json.dumps(report,indent=2))
