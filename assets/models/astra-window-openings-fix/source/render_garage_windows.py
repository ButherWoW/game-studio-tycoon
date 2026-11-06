from native_xml import *
from render_geometry import preview
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
(ROOT/'previews').mkdir(exist_ok=True)
# Inspection views hide the real Glass panes in both before/after to isolate backing geometry.
for f in sorted((ROOT/'models').glob('*.rbxmx')):
 ps=[p for p in fromxml(ET.parse(f).getroot()) if p['name'] not in ['WindowGlass','DoorWindow']]
 preview(ps,ROOT/'previews'/(f.stem+'_Openings.png'),yaw=20,elev=23,target=(0,6,0),span=96,W=1000,H=740)
for phase,folder in [('Before','baseline'),('After','models')]:
 ps=[p for p in fromxml(ET.parse(ROOT/folder/'GarageWalls.rbxmx').getroot()) if p['name'] not in ['WindowGlass','DoorWindow']]
 preview(ps,ROOT/'previews'/('GarageRear_'+phase+'.png'),yaw=180,elev=0,target=(0,7.8,-29.5),span=54,W=1400,H=380)
files=sorted((ROOT/'previews').glob('*_Openings.png'));sheet=Image.new('RGB',(1600,1320),'#e7e7ef');d=ImageDraw.Draw(sheet);d.text((20,8),'INSPECTION: Glass panes hidden only in previews; final Glass transparency = 0.4',fill='black')
for i,f in enumerate(files):
 im=Image.open(f);im.thumbnail((800,590));x=(i%2)*800;y=(i//2)*625+56;sheet.paste(im,(x,y));d.text((x+20,y-20),f.stem,fill='black')
sheet.save(ROOT/'previews'/'GARAGE_CONTACT_SHEET.png');s=Image.new('RGB',(1400,820),'#e7e7ef');d=ImageDraw.Draw(s)
for i,phase in enumerate(['Before','After']):
 d.text((20,i*410+8),phase+' - real rear opening inspection; glass omitted in both',fill='black');s.paste(Image.open(ROOT/'previews'/('GarageRear_'+phase+'.png')),(0,i*410+28))
s.save(ROOT/'previews'/'GARAGE_REAR_BEFORE_AFTER.png')
