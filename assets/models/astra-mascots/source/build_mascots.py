from geometry import *

SPECS=[('pixel_cat','ordinary','blue pixel cat with square head, turquoise muzzle, pink inner square ears and a stepped tail'),('bug_beetle','ordinary','mint beetle with blue shell, six short legs and big round navy glasses'),('coffee_cup','ordinary','living ivory coffee mug with gold rim, brown coffee top, blue handle and tiny feet'),('floppy_dog','ordinary','blue floppy-disk puppy with ivory muzzle, dark floppy ears and a silver disk shutter on forehead'),('cloud_ghost','ordinary','friendly ivory cloud ghost with three rounded cloud lobes, small waving arms and blue cheeks'),('controller_bunny','rare','purple bunny with tall blue joystick ears capped by cyan balls, ivory muzzle and cyan paw accents'),('robo_owl','rare','blue robot owl with huge silver eye rings, cyan eye lights and gold beak'),('slime_star','rare','mint round slime with golden blocky star on forehead and cyan belly glow'),('neon_fox','epic','purple fox with tall pointed ears, cyan neon markings, ivory muzzle and large purple cyan-tipped tail'),('dragon_byte','epic','green tiny byte dragon with blue block wings, gold little horns and cyan belly'),('golden_trophy','legendary','living golden trophy with two side handles, big friendly eyes, royal-blue feet and neon gold star'),('cosmic_whale','legendary','small floating navy cosmic whale with purple fins, cyan belly and gold block star markings')]

def eyes(m,y,z,sep=.36,sz=.43):
 for x in [-sep,sep]:
  ball(m,'EyeWhite',(x,y,z),(sz,sz*1.15,.14),'white')
  ball(m,'Pupil',(x,y,z+.085),(sz*.5,sz*.68,.07),'1E1E2E')
  ball(m,'EyeGlint',(x-.04,y+.055,z+.13),(.055,.065,.025),'white')
def smile(m,y,z):
 for a,b in [((-.15,y+.04,z),(0,y-.04,z)),((0,y-.04,z),(.15,y+.04,z))]:line(m,'Smile',a,b,.045,'1E1E2E')
def feet(m,c='blue',y=.17):
 for x in [-.42,.42]:ball(m,'Foot',(x,y,.18),(.52,.34,.65),c)
def star(m,p,sz=.42,c='gold',neon=False):
 x,y,z=p
 box(m,'StarCore',p,(sz*.75,sz*.75,.09),c,mat='Neon' if neon else 'SmoothPlastic',r=rot(z=45))
 for a in [90,18,162,234,306]:
  xx=x+math.cos(math.radians(a))*sz*.42;yy=y+math.sin(math.radians(a))*sz*.42
  box(m,'StarPoint',(xx,yy,z),(sz*.36,sz*.36,.09),c,r=rot(z=a-45),mat='Neon' if neon else 'SmoothPlastic')
def make(id):
 m=model('Mascot_'+id)
 if id=='pixel_cat':
  box(m,'Body',(0,.8,0),(1.35,1.1,1.05),'blue');feet(m)
  box(m,'Head',(0,1.65,.05),(1.65,1.15,1.2),'blue')
  for x in [-.59,.59]:box(m,'Ear',(x,2.26,0),(.47,.55,.48),'blue');box(m,'InnerEar',(x,2.28,.255),(.25,.3,.04),'pink')
  box(m,'Muzzle',(0,1.42,.68),(.85,.42,.2),'cyan');eyes(m,1.82,.69);smile(m,1.38,.8)
  for j in range(3):box(m,'PixelTail',(.8+j*.16,.58+j*.23,-.4),(.35,.36,.35),'blue')
 elif id=='bug_beetle':
  ball(m,'Body',(0,.85,0),(1.6,1.35,1.55),'cyan');ball(m,'Shell',(0,1.02,-.38),(1.6,1.2,.9),'blue')
  ball(m,'Head',(0,1.8,.33),(1.55,1.25,1.1),'leaf')
  for x in [-.88,.88]:
   for z in [-.5,0,.5]:line(m,'Leg',(x*.7,.55,z),(x,.16,z+.12),.16,'dark')
  eyes(m,1.85,.91,sz=.39)
  for x in [-.36,.36]:
   for yoff in [-.26,.26]:box(m,'GlassesRim',(x,1.85+yoff,.97),(.6,.07,.08),'dark')
   for xx in [-.28,.28]:box(m,'GlassesSide',(x+xx,1.85,.97),(.07,.52,.08),'dark')
  box(m,'Bridge',(0,1.85,1.0),(.17,.07,.07),'dark')
  for x in [-.48,.48]:line(m,'Antenna',(x,2.15,.17),(x*1.3,2.57,.1),.08,'dark');ball(m,'AntennaTip',(x*1.3,2.57,.1),(.2,.2,.2),'gold')
  smile(m,1.5,.91)
 elif id=='coffee_cup':
  cyl(m,'Body',(0,1.25,0),1.7,1.55,'white');cyl(m,'Rim',(0,2.1,0),.15,1.67,'gold');cyl(m,'Coffee',(0,2.19,0),.06,1.35,'6D4732');feet(m)
  for a,b in [((.7,1.75,0),(1.14,1.75,0)),((1.14,1.75,0),(1.14,1.0,0)),((1.14,1,0),(.7,1,0))]:line(m,'Handle',a,b,.21,'blue')
  eyes(m,1.48,.77);smile(m,1.08,.8)
 elif id=='floppy_dog':
  box(m,'Body',(0,1.0,0),(1.55,1.55,.75),'blue');feet(m)
  box(m,'DiskShutter',(0,1.65,.41),(.83,.55,.08),'silver');box(m,'ShutterSlot',(.15,1.65,.46),(.2,.3,.025),'dark')
  for x in [-.88,.88]:ball(m,'FloppyEar',(x,1.58,.08),(.45,1.0,.55),'dark')
  box(m,'Muzzle',(0,.95,.5),(.85,.45,.32),'white');eyes(m,1.26,.45,sz=.27);ball(m,'Nose',(0,1.05,.7),(.22,.15,.13),'dark');smile(m,.88,.69)
  line(m,'Tail',(.5,.65,-.35),(.9,1.1,-.55),.18,'blue')
 elif id=='cloud_ghost':
  ball(m,'Body',(0,1.16,0),(1.6,1.95,1.2),'white')
  for x,y in [(-.58,1.62),(0,1.95),(.58,1.62)]:ball(m,'CloudLobe',(x,y,0),(.95,1.0,1.2),'white')
  for x in [-.99,.99]:ball(m,'Arm',(x,1.3,.15),(.5,.4,.45),'white')
  for x in [-.5,0,.5]:ball(m,'CloudFoot',(x,.27,0),(.55,.5,.8),'white')
  eyes(m,1.55,.62);smile(m,1.17,.65)
  for x in [-.57,.57]:ball(m,'Cheek',(x,1.25,.6),(.25,.12,.07),'blue')
 elif id=='controller_bunny':
  ball(m,'Body',(0,.87,0),(1.32,1.3,1.0),'purple');feet(m,'cyan');ball(m,'Head',(0,1.64,.03),(1.62,1.2,1.15),'purple')
  for x in [-.47,.47]:cyl(m,'EarStick',(x,2.35,0),.8,.22,'blue');ball(m,'EarCap',(x,2.75,0),(.43,.43,.43),'cyan',mat='Neon')
  ball(m,'Muzzle',(0,1.38,.59),(.85,.4,.2),'white');eyes(m,1.8,.62);smile(m,1.35,.73)
 elif id=='robo_owl':
  ball(m,'Body',(0,1.23,0),(1.7,1.9,1.2),'blue');feet(m,'gold');ball(m,'Head',(0,1.94,0),(1.85,1.14,1.2),'blue')
  for x in [-.47,.47]:ball(m,'EyeRing',(x,1.98,.58),(.85,.85,.17),'silver');ball(m,'EyeLens',(x,1.98,.7),(.64,.64,.15),'cyan',mat='Neon');ball(m,'Pupil',(x,1.98,.8),(.27,.39,.08),'dark')
  box(m,'Beak',(0,1.55,.75),(.23,.32,.25),'gold',r=rot(z=45))
  for x in [-.94,.94]:ball(m,'Wing',(x,1.04,0),(.39,.98,.72),'silver')
  for x in [-.55,.55]:box(m,'Ear',(x,2.5,0),(.35,.38,.36),'blue',r=rot(z=25*x))
 elif id=='slime_star':
  ball(m,'Body',(0,1.1,0),(2,2.05,1.55),'leaf');feet(m,'leaf');ball(m,'Belly',(0,.68,.68),(1.1,.65,.17),'cyan',mat='Neon');eyes(m,1.24,.76);smile(m,.94,.84);star(m,(0,1.89,.64),.38)
 elif id=='neon_fox':
  ball(m,'Body',(0,.8,0),(1.2,1.1,.95),'purple');feet(m,'purple');ball(m,'Head',(0,1.6,.12),(1.65,1.2,1.15),'purple')
  for x in [-.55,.55]:box(m,'TallEar',(x,2.24,.02),(.44,.85,.44),'purple',r=rot(z=-x*15));box(m,'EarNeon',(x,2.28,.26),(.2,.5,.04),'cyan',mat='Neon')
  ball(m,'Muzzle',(0,1.39,.7),(.9,.42,.3),'white');eyes(m,1.77,.74);ball(m,'Nose',(0,1.48,.89),(.2,.15,.12),'dark');smile(m,1.3,.87)
  ball(m,'Tail',(1,.92,-.42),(.85,1.5,.75),'purple',r=rot(z=-28));ball(m,'TailTip',(1.2,1.45,-.42),(.55,.6,.6),'cyan',mat='Neon')
 elif id=='dragon_byte':
  ball(m,'Body',(0,.95,0),(1.3,1.4,1.1),'green');feet(m,'green');box(m,'Belly',(0,.9,.56),(.72,.9,.1),'cyan',mat='Neon');ball(m,'Head',(0,1.92,.16),(1.55,1.13,1.18),'leaf')
  ball(m,'Snout',(0,1.72,.77),(.95,.48,.55),'leaf');eyes(m,2.06,.72,sz=.29);smile(m,1.61,1.03)
  for x in [-.5,.5]:box(m,'Horn',(x,2.55,.06),(.2,.5,.2),'gold',r=rot(z=-x*18))
  for x in [-.95,.95]:box(m,'ByteWing',(x,1.38,-.24),(.77,.8,.16),'blue',r=rot(z=x*25));box(m,'WingPixel',(x*1.32,1.55,-.24),(.3,.4,.2),'cyan',mat='Neon')
  line(m,'Tail',(0,.6,-.4),(.7,.75,-1.05),.25,'green')
 elif id=='golden_trophy':
  cyl(m,'Body',(0,1.55,0),1.25,1.6,'gold');cyl(m,'Rim',(0,2.2,0),.16,1.8,'gold');cyl(m,'InnerCup',(0,2.29,0),.04,1.48,'B78318');cyl(m,'Stem',(0,.65,0),.65,.35,'gold');cyl(m,'Base',(0,.28,0),.24,1.25,'blue');feet(m,'blue')
  for x in [-1,1]:
   for a,b in [((x*.72,1.94,0),(x*1.25,1.94,0)),((x*1.25,1.94,0),(x*1.25,1.25,0)),((x*1.25,1.25,0),(x*.72,1.25,0))]:line(m,'Handle',a,b,.17,'gold')
  eyes(m,1.68,.8,sz=.36);smile(m,1.35,.83);star(m,(0,1.07,.81),.26,neon=True)
 elif id=='cosmic_whale':
  ball(m,'Body',(0,1.1,0),(1.9,1.65,1.5),'244176');ball(m,'Belly',(0,.76,.51),(1.5,.8,.8),'cyan',mat='Neon');eyes(m,1.42,.75,sz=.3);smile(m,1.04,.91)
  for x in [-1.05,1.05]:ball(m,'Flipper',(x,.9,0),(.74,.25,.68),'purple',r=rot(z=x*20))
  line(m,'TailStem',(0,1.0,-.55),(0,1.3,-1.3),.3,'244176')
  for x in [-.4,.4]:ball(m,'TailFluke',(x,1.36,-1.32),(.85,.25,.52),'purple')
  star(m,(.62,1.74,.55),.23);star(m,(-.55,1.85,.35),.18)
 return m

ASSETS={id:make(id) for id,_,_ in SPECS}

if __name__=='__main__':
 from render_geometry import preview
 import numpy as np
 from PIL import Image,ImageDraw,ImageFont
 reports=[]
 for i,(id,tier,desc) in enumerate(SPECS):
  m=ASSETS[id];lo=np.array([1e9]*3);hi=-lo
  for p in m['parts']:
   r=np.array(p['r']).reshape(3,3);s=np.array(p['s'])/2
   ext=np.sqrt((r*r)@(s*s)) if p['shape']=='ball' else np.abs(r)@s
   lo=np.minimum(lo,np.array(p['p'])-ext);hi=np.maximum(hi,np.array(p['p'])+ext)
  if hi[1]-lo[1]<2:
   factor=2.2/(hi[1]-lo[1])
   for p in m['parts']:p['p']=tuple(v*factor for v in p['p']);p['s']=tuple(v*factor for v in p['s'])
   lo*=factor;hi*=factor
  # Place base at zero and footprint center exactly at origin.
  off=np.array([(lo[0]+hi[0])/2,lo[1],(lo[2]+hi[2])/2])
  for p in m['parts']:p['p']=tuple(np.array(p['p'])-off)
  assert 2<=hi[1]-lo[1]<=3,(id,hi-lo)
  assert len(m['parts'])<=60,(id,len(m['parts']))
  assert m['parts'][0]['name']=='Body'
  assert tier!='ordinary' or all(p['mat']!='Neon' for p in m['parts'])
  batch=ROOT/f'batch-{i//4+1}';(batch/'models').mkdir(parents=True,exist_ok=True);(batch/'previews').mkdir(exist_ok=True)
  export(m,batch/'models'/f'Mascot_{id}.rbxmx')
  preview(flatten(m),batch/'previews'/f'Mascot_{id}.png',yaw=20,elev=15,span=4.3,target=(0,(hi[1]-lo[1])/2,0),W=600,H=600)
  reports.append({'id':id,'tier':tier,'parts':len(m['parts']),'height':float(hi[1]-lo[1]),'pivot':[0,0,0],'face':'+Z','primaryPart':'Body','pointLights':0,'checks':'PASS'})
 font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',24)
 for b in range(3):
  batch=ROOT/f'batch-{b+1}';sheet=Image.new('RGB',(1200,1320),'#ece6dd');d=ImageDraw.Draw(sheet)
  for j,(id,_,_) in enumerate(SPECS[b*4:b*4+4]):
   x=(j%2)*600;y=(j//2)*660;im=Image.open(batch/'previews'/f'Mascot_{id}.png');sheet.paste(im,(x,y));d.text((x+300,y+620),id,anchor='mm',font=font,fill='#283345')
  sheet.save(batch/'Models_ContactSheet.png');(batch/'VALIDATION.json').write_text(json.dumps(reports[b*4:b*4+4],indent=2))
 (ROOT/'VALIDATION.json').write_text(json.dumps(reports,indent=2))
 print(json.dumps(reports,indent=2))
