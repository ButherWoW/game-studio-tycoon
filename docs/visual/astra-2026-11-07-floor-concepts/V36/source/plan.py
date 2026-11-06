from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,sys,math

from convex_support import parse,support,np
ROOT=Path(__file__).resolve().parents[1];REPO=Path('/private/tmp/game-studio-tycoon-visual-upload-20261104')
FONT='/System/Library/Fonts/Supplemental/Arial.ttf'
def font(n):return ImageFont.truetype(FONT,n)
def asset_bounds(group,name,x,z,yaw=0):
 ps=parse(REPO/f'assets/models/{group}/models/{name}.rbxmx')
 a=math.radians(yaw);R=np.array([[math.cos(a),0,math.sin(a)],[0,1,0],[-math.sin(a),0,math.cos(a)]])
 for p in ps:p['p']=R@p['p']+np.array([x,0,z]);p['R']=R@p['R']
 lo=[min(support(p,-np.eye(3)[i])[i]for p in ps)for i in range(3)]
 hi=[max(support(p,np.eye(3)[i])[i]for p in ps)for i in range(3)]
 return {'name':name,'box':[lo[0],lo[2],hi[0],hi[2]],'height':[lo[1],hi[1]]}
def reserve(n,b):return {'name':n,'box':b,'height':[0,8]}
legacy=[reserve('Player desk',[-15.8,-21.75,-8.2,-15.8]),reserve('Coffee',[23.5,-27.5,26.5,-20.5]),reserve('Hits',[-29,-20,-26.2,-10])]
floors={2:[],3:[]}
for x,z in [(0,-20),(9,-20),(18,-20),(-12,-6),(-2,-6),(8,-6),(18,-6)]:floors[2].append(asset_bounds('astra-floor','FloorDesk',x,z))
floors[2]+=[asset_bounds('astra-floor','ServerRoom',26.5,-14,-90),asset_bounds('astra-floor','Lounge',2,11)]
for x,z in [(-3,-20),(5,-20),(13,-20),(21,-20),(-18,-8),(-9,-8),(0,-8),(9,-8),(18,-8),(-6,4),(6,4)]:floors[3].append(asset_bounds('astra-sky','SkyDesk',x,z))
floors[3]+=[asset_bounds('astra-sky','SoundStudio',-18,14),asset_bounds('astra-sky','ArtWall',15,16)]
zones=[
 {'id':'A','floor':2,'name':'Green lounge','box':[-4,6,8,16],'height':[0,5],'replace':'Lounge','idea':'Upgrade existing lounge within its reserved 12x10 footprint'},
 {'id':'B','floor':2,'name':'Game gallery','box':[-27,-29,-17,-28.6],'height':[3,8],'replace':None,'idea':'Shallow wall-mounted artwork, no floor furniture'},
 {'id':'C','floor':3,'name':'Panorama corner','box':[17,5,27,11],'height':[0,5],'replace':None,'idea':'Two reading chairs, side table and plant facing east windows'},
 {'id':'D','floor':3,'name':'Acoustic art','box':[8,15.5,22,16.5],'height':[0,9],'replace':'ArtWall','idea':'Replace existing ArtWall with acoustic art within its 14x1 footprint; leave glazing untouched'}
]
lift=reserve('LIFT',[-23,21,-17,27]);approach=reserve('Lift approach',[-23,15,-17,21]);buttons=reserve('Keep clear / buttons',[-29,22,29,29])
def overlap(a,b):
 return min(a[2],b[2])-max(a[0],b[0])>1e-6 and min(a[3],b[3])-max(a[1],b[1])>1e-6
checks=[]
for q in zones:
 assert all(-29.000001<=v<=29.000001 for v in q['box'])
 targets=floors[q['floor']]+legacy+[lift,approach,buttons]
 bad=[t['name']for t in targets if t['name']!=q['replace'] and overlap(q['box'],t['box'])]
 assert not bad,(q['id'],bad)
 checks.append({'idea':q['id'],'overlapsExceptExplicitReplacement':bad,'liftClear':True,'buttonsBandClear':True})
for floor,objects in floors.items():
 im=Image.new('RGB',(1200,1160),'#f3eee4');d=ImageDraw.Draw(im);scale=14;cx=600;cz=560
 def xy(x,z):return(cx+x*scale,cz+z*scale)
 def rect(b,fill,outline,width=2):
  d.rectangle((*xy(b[0],b[1]),*xy(b[2],b[3])),fill=fill,outline=outline,width=width)
 d.text((36,20),f'V36 / FLOOR {floor} / CONCEPT ENVELOPES',font=font(28),fill='#243345')
 d.text((36,60),'Top view: -Z rear / +Z front. Coordinates in studs.',font=font(19),fill='#556070')
 rect([-30,-30,30,30],'#faf8f1','#26364a',4)
 for v in range(-24,25,6):
  d.line((*xy(v,-29),*xy(v,29)),fill='#e2ddd1')
  d.line((*xy(-29,v),*xy(29,v)),fill='#e2ddd1')
 rect(buttons['box'],'#f1dfb8','#c39544');d.text(xy(-3,24),'CLEAR',font=font(15),fill='#8a632d')
 for o in objects+legacy:
  rect(o['box'],'#c6d3de','#637c92')
  x=(o['box'][0]+o['box'][2])/2;z=(o['box'][1]+o['box'][3])/2
  d.text(xy(x-1.8,z),o['name'].replace('Desk',''),font=font(12),fill='#23384a')
 rect(lift['box'],'#efc2bd','#b6504a',3);d.text(xy(-22,23),'LIFT',font=font(16),fill='#8a302e')
 rect(approach['box'],None,'#b6504a')
 for q in zones:
  if q['floor']!=floor:continue
  rect(q['box'],'#9dd3b2','#236947',3)
  # Labels outside the room with connector for thin wall panels.
  b=q['box'];x=(b[0]+b[2])/2;z=(b[1]+b[3])/2
  if q['id']=='B':anchor=(180,105);d.line((anchor[0]+100,anchor[1]+30,*xy(x,z)),fill='#236947',width=2)
  elif q['id']=='D':anchor=(1020,740);d.line((*xy(x,z),anchor[0],anchor[1]),fill='#236947',width=2)
  else:anchor=xy(x-2,z-1)
  d.text(anchor,q['id']+' / '+q['name'],font=font(18),fill='#174b34')
 d.text((36,1010),'Blue: current assets / Green: proposed envelope / Red: lift',font=font(20),fill='#243345')
 d.text((36,1045),'A replaces Lounge; D replaces ArtWall. B is raised wall art. Proposal only.',font=font(18),fill='#556070')
 d.text((36,1080),'Preview only: shell plants, purchase buttons and live changes require Studio verification.',font=font(17),fill='#885c37')
 im.save(ROOT/f'floor_{floor}_plan.png')
report={'status':'PASS for proposed envelopes vs listed assets/reservations','zones':zones,'checks':checks,'floors':floors,'legacyReservations':legacy,'limitations':['No detailed new models created. Internal part intersections cannot yet be tested.','Existing shell plants/decor and live Studio changes not exhaustively included.','Wall artwork must occupy opaque panel sections, not cover active glass.','Minimum passage geometry must be checked again after modeling.'],'runtimeTested':False}
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(checks,indent=2))
