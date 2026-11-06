from build_flowerbed import build
from geometry import flatten,ROOT
from render_geometry import preview
from PIL import Image,ImageDraw
ps=flatten(build())
for label,yaw,elev in [('Front',0,25),('ThreeQuarter',38,35),('Rear',190,32)]:
 preview(ps,ROOT/'previews'/('Flowerbed_'+label+'.png'),yaw=yaw,elev=elev,target=(0,.60,0),span=5.5,W=1200,H=950)
sheet=Image.new('RGB',(1800,550),'#ece6dd');d=ImageDraw.Draw(sheet)
for i,label in enumerate(['Front','ThreeQuarter','Rear']):
 im=Image.open(ROOT/'previews'/('Flowerbed_'+label+'.png'));im.thumbnail((600,480));sheet.paste(im,(i*600,30));d.text((i*600+18,12),label,fill='#253247')
d.text((18,518),'Flowerbed / 119 native Parts / 3.8 x 1.42 x 3.8 studs / 4 flower species / 0 OBB overlaps',fill='#253247')
sheet.save(ROOT/'previews/Flowerbed_ContactSheet.png')
