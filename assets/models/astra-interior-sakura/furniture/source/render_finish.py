from build_finish import *
from render_geometry import preview,basis
from PIL import Image,ImageDraw,ImageFont,ImageOps
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',18)
for zone,names in ZONES.items():
 for name in names:
  for mode,src in [('Classic',ROOT/'baseline/models'/f'{name}.rbxmx'),('Sakura',ROOT.parent/'models'/f'{name}_Sakura.rbxmx')]:
   ps=fromxml(ET.parse(src).getroot());lo,hi=bounds(ps);dims=[hi[i]-lo[i] for i in range(3)];target=tuple((lo[i]+hi[i])/2 for i in range(3))
   B=basis(26,24);vs=np.concatenate([np.asarray(meshes(p)[0]) for p in ps if p['alpha']<.99]);q=(vs-np.asarray(target))@B.T;mid=(q.min(axis=0)+q.max(axis=0))/2;target=tuple(np.asarray(target)+B[0]*mid[0]+B[1]*mid[1]);span=max(np.ptp(q[:,0]),np.ptp(q[:,1])*800/600)*1.22
   preview(ps,ROOT/'previews'/f'{name}_{mode}.png',yaw=26,elev=24,target=target,span=span,W=800,H=600)
 sheet=Image.new('RGB',(1600,((len(names)+1)//2)*390),'#ece6dd');draw=ImageDraw.Draw(sheet)
 for i,name in enumerate(names):
  x=i%2*800;y=i//2*390;draw.text((x+12,y+4),name+' | Classic / Sakura',font=font,fill='#55414a')
  for j,mode in enumerate(['Classic','Sakura']):
   im=Image.open(ROOT/'previews'/f'{name}_{mode}.png');im.thumbnail((390,330));sheet.paste(im,(x+j*400,y+35))
 sheet.save(ROOT/'previews'/f'{zone.title()}_Classic_vs_Sakura.png')
# A compact overview of all29actual variants.
names=[n for group in ZONES.values() for n in group];s=Image.new('RGB',(1600,((len(names)+3)//4)*290),'#ece6dd');d=ImageDraw.Draw(s)
for i,n in enumerate(names):
 im=Image.open(ROOT/'previews'/f'{n}_Sakura.png');im.thumbnail((390,250));x=i%4*400;y=i//4*290;s.paste(im,(x,y+22));d.text((x+8,y),n,font=font,fill='#55414a')
s.save(ROOT/'previews'/'Sakura_Furniture_ContactSheet.png')
# Square shop collage is actual furniture geometry, no imaginary replacements.
card=Image.new('RGB',(512,512),'#f4e8df');d=ImageDraw.Draw(card);d.text((18,12),'SAKURA',font=font,fill='#9c5272')
for i,n in enumerate(['OfficeDesk','Chair','CoffeeTable','Bookshelf']):
 im=Image.open(ROOT/'previews'/f'{n}_Sakura.png');im.thumbnail((245,220));card.paste(im,(i%2*256,i//2*235+36))
card.save(ROOT/'ShopCard_512.png')
print('Sakura58renders and3comparison sheets complete')
