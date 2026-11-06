from build_spawnpad import *
from render_geometry import preview
from PIL import Image,ImageDraw,ImageFont
ps=flatten(ASSETS['SpawnPad'])
preview(ps,ROOT/'previews/SpawnPad_ThreeQuarter.png',yaw=30,elev=39,target=(0,.16,0),span=12,W=1200,H=950)
preview(ps,ROOT/'previews/SpawnPad_Top.png',yaw=0,elev=90,target=(0,.16,0),span=10.5,W=1100,H=1100)
im=Image.new('RGB',(1800,1000),'#ece6dd');d=ImageDraw.Draw(im);font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',24)
for i,name in enumerate(['SpawnPad_ThreeQuarter','SpawnPad_Top']):
 p=Image.open(ROOT/'previews'/(name+'.png'));p.thumbnail((880,880));im.paste(p,(i*900,65));d.text((i*900+24,20),'SpawnPad: '+('3/4 view' if i==0 else 'flat top view'),font=font,fill='#253247')
d.text((24,954),str(len(ps))+' native Parts / 8 x 0.32 x 8 studs / flat continuous surface / no external texture',font=font,fill='#253247');im.save(ROOT/'previews/SpawnPad_ContactSheet.png')
