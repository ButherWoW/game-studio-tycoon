from native_xml import *
from render_geometry import preview
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
(ROOT/'previews').mkdir(exist_ok=True)
for f in sorted((ROOT/'models').glob('*.rbxmx')):
 ps=fromxml(ET.parse(f).getroot());preview(ps,ROOT/'previews'/(f.stem+'_Front.png'),yaw=20,elev=23,target=(0,6,0),span=96,W=1000,H=740)
 # Inside-side view cuts away only the near side to reveal opposite now-opaque panels.
 cut=[p for p in ps if not(p['p'][0]>28 and any(s in p['name'] for s in ['Side','Window','Timber','StoneFoot','Siding','FrontCorner'])) and p['name'] not in ['Rafter','EaveBeam','CeilingCap','Cable','Shade','ShadeRim','Bulb']]
 preview(cut,ROOT/'previews'/(f.stem+'_Cutaway.png'),yaw=26,elev=38,target=(0,4,0),span=96,W=1000,H=740)
files=sorted((ROOT/'previews').glob('*_Front.png'));sheet=Image.new('RGB',(1600,1250),'#e7e7ef');d=ImageDraw.Draw(sheet)
for i,f in enumerate(files):
 im=Image.open(f);im.thumbnail((800,590));x=(i%2)*800;y=(i//2)*625+28;sheet.paste(im,(x,y));d.text((x+20,y-20),f.stem,fill='black')
sheet.save(ROOT/'previews'/'CONTACT_SHEET.png')
