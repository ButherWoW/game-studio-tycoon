from build_v30 import *
from render_geometry import preview
from PIL import Image,ImageDraw,ImageFont
report=json.loads((ROOT/'INDEPENDENT_VALIDATION.json').read_text());assert report['status']=='PASS'
for name,m in ASSETS.items():
 dims=report['models'][name]['dimensionsXYZ'];preview(flatten(m),ROOT/'previews'/(name+'.png'),yaw=22,elev=25,target=(0,dims[1]/2,0),span=8,W=1200,H=1000)
 preview(flatten(m),ROOT/'previews'/(name+'_Front.png'),yaw=0,elev=10,target=(0,dims[1]/2,0),span=7,W=1200,H=1000)
s=Image.new('RGB',(1800,1100),'#ece6dd');d=ImageDraw.Draw(s);font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',20)
for n,name in enumerate(ASSETS):
 for row,suffix in enumerate(['','_Front']):
  im=Image.open(ROOT/'previews'/(name+suffix+'.png'));im.thumbnail((600,480));s.paste(im,(n*600,row*550));d.text((n*600+12,row*550+495),name+f" /{report['models'][name]['parts']}Parts",font=font,fill='#202b48')
s.save(ROOT/'previews/V30_Equipment_ContactSheet.png');(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n')
