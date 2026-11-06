from style_helpers import *
from render_geometry import preview
from PIL import Image,ImageDraw,ImageOps,ImageFont
suffix='ObsidianGold';small=[]
for zone,names in ZONES.items():
 sheet=Image.new('RGB',(1200,len(names)*470),'#ece6dd');d=ImageDraw.Draw(sheet)
 for n,name in enumerate(names):
  a=fromxml(ET.parse(ROOT/'baseline/models'/(name+'.rbxmx')).getroot());b=fromxml(ET.parse(ROOT.parent/'models'/(name+'_'+suffix+'.rbxmx')).getroot());lo,hi=bounds(a);dims=[hi[i]-lo[i] for i in range(3)];target=tuple((lo[i]+hi[i])/2 for i in range(3));span=max(dims)*1.85
  for ix,ps,label in [(0,a,'Classic'),(1,b,suffix)]:
   f=ROOT/'previews'/(name+'_'+label+'.png');preview(ps,f,yaw=23,elev=24,span=span,target=target,W=600,H=435);sheet.paste(Image.open(f),(ix*600,n*470+25));d.text((ix*600+10,n*470+6),name+' '+label,fill='#283345')
  small.append((name,ROOT/'previews'/(name+'_'+suffix+'.png')))
 sheet.save(ROOT/('Classic_vs_'+suffix+'_'+zone+'.png'))
over=Image.new('RGB',(1800,5*270),'#ece6dd');od=ImageDraw.Draw(over)
for i,(name,f) in enumerate(small):
 im=Image.open(f);im.thumbnail((300,235));x=i%6*300;y=i//6*270;over.paste(im,(x,y+25));od.text((x+8,y+7),name,fill='#283345')
over.save(ROOT/'Furniture_ContactSheet.png')
# Actual OfficeDesk model rather than an unrelated concept preview.
im=Image.open(ROOT/'previews'/'OfficeDesk_ObsidianGold.png');im=ImageOps.fit(im,(512,512),Image.Resampling.LANCZOS);im.save(ROOT/'ShopCard_512.png')
