from build_finish import *
from render_geometry import preview
from PIL import Image,ImageDraw,ImageFont
for name in MANIFEST['sources']:
 ps=fromxml(ET.parse(ROOT.parent/'models'/f'{name}_Aurora.rbxmx').getroot());lo,hi=bounds(ps);dims=[hi[i]-lo[i] for i in range(3)];target=tuple((lo[i]+hi[i])/2 for i in range(3));span=max(dims)*1.55
 preview(ps,ROOT/'previews'/f'{name}_Aurora.png',yaw=25,elev=22,target=target,span=span,W=720,H=560)
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',16)
sheet=Image.new('RGB',(1800,1740),'#e1e8ef');d=ImageDraw.Draw(sheet)
for i,name in enumerate(MANIFEST['sources']):
 im=Image.open(ROOT/'previews'/f'{name}_Aurora.png');im.thumbnail((350,252));x=i%5*360;y=i//5*290;sheet.paste(im,(x+(360-im.width)//2,y+25));d.text((x+8,y+5),name+'_Aurora',font=font,fill='#172b42')
sheet.save(ROOT/'Aurora_Furniture_ContactSheet.png')
ps=fromxml(ET.parse(ROOT.parent/'models/SkyDesk_Aurora.rbxmx').getroot());lo,hi=bounds(ps);preview(ps,ROOT/'ShopCard_512.png',yaw=25,elev=25,target=tuple((lo[i]+hi[i])/2 for i in range(3)),span=max(hi[i]-lo[i] for i in range(3))*1.5,W=512,H=512)
