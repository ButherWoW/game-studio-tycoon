from build_construction import *
from render_geometry import preview
from PIL import Image,ImageDraw
for n,m in ASSETS.items():
 ps=flatten(m);lo,hi=bounds(ps);dims=[hi[i]-lo[i] for i in range(3)];target=(0,(lo[1]+hi[1])/2,(lo[2]+hi[2])/2)
 preview(ps,ROOT/'previews'/(n+'.png'),yaw=27,elev=18 if 'Crane'in n else 30,target=target,span=max(dims)*1.55,W=1100,H=1000)
s=Image.new('RGB',(1800,1100),'#ece6dd');d=ImageDraw.Draw(s)
for i,n in enumerate(ASSETS):
 im=Image.open(ROOT/'previews'/(n+'.png'));im.thumbnail((880,475));x=i%2*900;y=i//2*550;s.paste(im,(x,y+35));d.text((x+20,y+12),n+' / '+str(len(flatten(ASSETS[n])))+' Parts',fill='#253247')
s.save(ROOT/'previews'/'Construction_ContactSheet.png')
