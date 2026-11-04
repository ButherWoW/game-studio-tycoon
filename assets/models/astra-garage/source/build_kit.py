"""Original native Roblox models. Standard-library geometry; Pillow only for previews."""
import math, json, copy, random, xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
TAU=2*math.pi
C={'wood':'A0703C','top':'C18B50','edge':'D5A265','darkwood':'6D492D','blue':'3D7BFF','fabric':'285AC4','seam':'224B9A','gold':'FFC93C','warm':'FFD9A0','dark':'252B3C','metal':'444C5B','silver':'AEB4C0','white':'F2EFE6','green':'57A344','leaf':'83BD50','cyan':'58CFFF','concrete':'8C8C8C','pink':'FF6EB4','purple':'9650DC'}
def rgb(c):
 c=C.get(c,c).lstrip('#');return tuple(int(c[i:i+2],16) for i in (0,2,4))
def add(a,b):return tuple(x+y for x,y in zip(a,b))
def mul(a,b):return tuple(sum(a[i*3+k]*b[k*3+j] for k in range(3)) for i in range(3) for j in range(3))
def mv(a,v):return tuple(sum(a[i*3+k]*v[k] for k in range(3)) for i in range(3))
I=(1,0,0,0,1,0,0,0,1)
def rot(x=0,y=0,z=0):
 x,y,z=map(math.radians,(x,y,z));cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
 return mul(mul((cy,0,sy,0,1,0,-sy,0,cy),(1,0,0,0,cx,-sx,0,sx,cx)),(cz,-sz,0,sz,cz,0,0,0,1))
def model(n):return {'name':n,'parts':[],'children':[],'pos':(0,0,0),'r':I}
def part(m,n,p,s,c='dark',shape='box',r=I,mat='SmoothPlastic',collide=False,alpha=0,cls='Part',light=None):
 d=dict(name=n,p=tuple(p),s=tuple(s),c=rgb(c),shape=shape,r=r,mat=mat,collide=collide,alpha=alpha,cls=cls)
 if light:d['light']=light
 m['parts'].append(d);return d
def box(m,n,p,s,c='dark',**kw):return part(m,n,p,s,c,**kw)
def cyl(m,n,p,h,d,c='dark',r=None,**kw):return part(m,n,p,(h,d,d),c,'cyl',r or rot(z=90),**kw)
def ball(m,n,p,s,c='dark',**kw):return part(m,n,p,s,c,'ball',**kw)
def rounded(m,n,p,s,c='dark',rad=.07,**kw):
 # Exact rounded cuboid as 3 slabs, 12 edge cylinders and 8 corner spheres.
 rad=min(rad,min(s)/2-.001)
 if rad<.015:return box(m,n,p,s,c,**kw)
 R=kw.pop('r',I);inner=[v-2*rad for v in s];lit=[kw.pop('light',None)]
 # One PointLight per rounded object: on the first slab only (23 lights per desk lamp hit mobile)
 def emit(nm,off,sz,sh='box',rr=I):
  extra={'light':lit.pop()} if lit and lit[0] else {}
  if lit and not lit[0]:lit.pop()
  return part(m,n+nm,add(p,mv(R,off)),sz,c,sh,mul(R,rr),**kw,**extra)
 for a in range(3):
  sz=inner.copy();sz[a]=s[a];emit('_core'+str(a),(0,0,0),sz)
 for axis in range(3):
  axes=[a for a in range(3) if a!=axis]
  rr=I if axis==0 else rot(z=90) if axis==1 else rot(y=90)
  for a in (-1,1):
   for b in (-1,1):
    off=[0,0,0];off[axes[0]]=a*inner[axes[0]]/2;off[axes[1]]=b*inner[axes[1]]/2
    emit('_edge',off,(inner[axis],2*rad,2*rad),'cyl',rr)
 for x in (-1,1):
  for y in (-1,1):
   for z in (-1,1):emit('_corner',(x*inner[0]/2,y*inner[1]/2,z*inner[2]/2),(2*rad,)*3,'ball')
def line(m,n,a,b,d,c='dark',**kw):
 v=tuple(b[i]-a[i] for i in range(3));length=math.sqrt(sum(t*t for t in v));u=tuple(t/length for t in v)
 ref=(0,1,0) if abs(u[1])<.9 else (0,0,1)
 cross=lambda a,b:(a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
 w=cross(u,ref);wn=math.sqrt(sum(t*t for t in w));w=tuple(t/wn for t in w);v2=cross(w,u)
 r=tuple((u,v2,w)[j][i] for i in range(3) for j in range(3))
 return cyl(m,n,tuple((a[i]+b[i])/2 for i in range(3)),length,d,c,r=r,**kw)
def put(parent,child,p=(0,0,0),yaw=0,name=None):
 c=copy.deepcopy(child);c['pos']=p;c['r']=rot(y=yaw)
 if name:c['name']=name
 parent['children'].append(c);return c

def mug(m,p,color='white',scale=1):
 x,y,z=p;s=scale
 cyl(m,'MugBody',(x,y+.25*s,z),.5*s,.42*s,color)
 cyl(m,'CoffeeSurface',(x,y+.505*s,z),.015*s,.32*s,'493020')
 # Separate rounded handle, open centre.
 for a in range(12):
  t=a*TAU/12;u=(a+1)*TAU/12
  line(m,'MugHandle',(x+.25*s+math.cos(t)*.16*s,y+.27*s+math.sin(t)*.17*s,z),(x+.25*s+math.cos(u)*.16*s,y+.27*s+math.sin(u)*.17*s,z),.055*s,color)
def plant(m,p,scale=1):
 x,y,z=p;s=scale
 rounded(m,'Planter',(x,y+.4*s,z),(.85*s,.8*s,.85*s),'white',rad=.05*s)
 box(m,'Soil',(x,y+.81*s,z),(.68*s,.035*s,.68*s),'darkwood')
 line(m,'Stem',(x,y+.8*s,z),(x,y+2.45*s,z),.13*s,'darkwood')
 for dx,dy,dz,w in [(0,1.8,0,.9),(.43,1.35,.05,.68),(-.4,1.55,-.12,.65),(.1,2.25,-.2,.65),(-.12,1.7,.43,.65)]:
  box(m,'BlockLeaf',(x+dx*s,y+dy*s,z+dz*s),(w*s,.64*s,w*s),'leaf' if dy>1.7 else 'green')
def tablelamp(m,p):
 x,y,z=p
 rounded(m,'LampBase',(x,y+.08,z),(.48,.16,.48),'darkwood',rad=.035)
 box(m,'LampStem',(x,y+.48,z),(.15,.8,.15),'wood')
 rounded(m,'LampShade',(x,y+.94,z),(.6,.65,.6),'warm',rad=.045,mat='Neon',light=(18,.55,'warm'))
 box(m,'LampShadeTop',(x,y+1.28,z),(.64,.05,.64),'edge')
def desk(name='Desk1',stool=True):
 m=model(name)
 rounded(m,'OakTop',(0,2.79,0),(7.6,.42,3.5),'top',rad=.085,collide=True,mat='Wood')
 box(m,'FrontApron',(0,2.45,1.28),(7.1,.27,.16),'wood')
 for x in (-3.45,3.45):
  box(m,'FrameLeg',(x,1.25,-1.3),(.32,2.5,.32),'darkwood',collide=True,mat='Wood')
  box(m,'FootPad',(x,.1,-1.3),(.4,.2,.4),'dark')
 box(m,'DrawerCabinet',(-2.5,1.3,.05),(1.95,2.6,2.9),'silver',collide=True)
 for y in (.55,1.35,2.15):
  rounded(m,'DrawerFront',(-2.5,y,1.53),(1.79,.72,.13),'959BA6',rad=.035)
  rounded(m,'DrawerPull',(-2.5,y+.03,1.64),(.65,.11,.13),'edge',rad=.025)
 box(m,'RightLeg',(3.42,1.25,1.25),(.38,2.5,.38),'darkwood',collide=True)
 line(m,'BackBrace',(-3.4,.65,-1.32),(3.4,.65,-1.32),.15,'metal')
 # subtle plank seams and brass pins, large forms stay close to reference.
 for z in (-.57,.57):box(m,'PlankJoin',(0,3.004,z),(7.35,.009,.018),'B17E45')
 for x in (-3.3,3.3):
  for z in (-1.25,1.25):cyl(m,'BrassPin',(x,3.01,z),.015,.065,'gold')
 plant(m,(2.9,3.01,-.8),.43);tablelamp(m,(2.95,3.01,.8))
 box(m,'PencilCup',(1.95,3.22,-1.02),(.37,.42,.37),'darkwood')
 for i,c in enumerate(['blue','gold','pink','green']):line(m,'Pencil',(1.82+i*.085,3.25,-1.02),(1.77+i*.11,3.93,-1.02),.055,c)
 if stool:
  cyl(m,'StoolStem',(0,.73,2.8),1.35,.24,'metal')
  cyl(m,'StoolBase',(0,.12,2.8),.2,1.3,'metal')
  cyl(m,'StoolRim',(0,1.43,2.8),.18,1.6,'wood')
  part(m,'PcSeat',(0,1.57,2.8),(1.4,.16,1.4),'wood',cls='Seat',collide=True)
 return m

def pc(name='PC1',pro=False):
 m=model(name);dark='dark'
 for x in ([-1.12,1.12] if pro else [0]):
  rounded(m,'MonitorFoot',(x,.09,0),(1.2,.18,.8),'metal',rad=.06)
  box(m,'MonitorStand',(x,.53,-.12),(.25,.85,.23),'metal')
  width=2.12 if pro else 2.65;height=1.55 if pro else 1.9
  rounded(m,'MonitorCase',(x,1.5,-.1),(width,height,.45 if pro else .8),'dark',rad=.085)
  rounded(m,'ScreenInset',(x,1.53,.15 if pro else .325),(width-.2,height-.2,.035),'101D35',rad=.035)
  screenz=.177 if pro else .353
  box(m,'BlueScreen',(x,1.55,screenz),(width-.32,height-.35,.012),'318BF0',mat='Neon')
  # original geometric platform scene, not texture IDs.
  for k in range(3):
   xx=x-.72+k*.56; yy=1.05+k*.2
   box(m,'ScreenTerrain',(xx,yy,screenz+.014),(.54,.2,.012),'leaf')
   box(m,'ScreenTerrainSoil',(xx,yy-.14,screenz+.015),(.54,.1,.012),'wood')
  box(m,'ScreenCloud',(x-.62,2.02,screenz+.017),(.43,.12,.012),'white')
  box(m,'ScreenCloud',(x+.38,2.1,screenz+.017),(.4,.09,.012),'white')
  box(m,'ScreenAvatar',(x,1.7,screenz+.025),(.16,.22,.018),'gold')
  cyl(m,'PowerLED',(x+width/2-.17,.72 if pro else .64,screenz+.015),.025,.055,'cyan',r=rot(y=90),mat='Neon')
 # Tower on left, fits top of desktop.
 rounded(m,'Tower',(-2.45,1.05,-.1),(1.05,2.1,1.65),'metal',rad=.07)
 box(m,'TowerFront',(-2.45,1.05,.75),(.88,1.91,.06),'dark')
 for yy in (.55,1.2):
  cyl(m,'FanOuter',(-2.45,yy,.8),.04,.59,'blue',r=rot(y=90),mat='Neon')
  cyl(m,'FanInset',(-2.45,yy,.825),.04,.44,'dark',r=rot(y=90))
  for a in range(5):
   t=a*TAU/5
   box(m,'FanBlade',(-2.45+math.sin(t)*.115,yy+math.cos(t)*.115,.853),(.12,.21,.025),'silver',r=rot(z=-a*72))
  cyl(m,'FanHub',(-2.45,yy,.87),.035,.12,'dark',r=rot(y=90))
 box(m,'DriveSlot',(-2.45,1.82,.79),(.57,.07,.035),'silver')
 for i in range(6):box(m,'TowerVent',(-3,1.1,-.66+i*.2),(.012,.65,.055),'dark')
 cyl(m,'TowerSwitch',(-2.15,1.6,.81),.035,.09,'cyan',r=rot(y=90),mat='Neon')
 rounded(m,'Keyboard',(0,.11,1.62),(2.55,.22,.82),'metal',rad=.045)
 for row in range(4):
  for col in range(12):box(m,'Keycap',(-1.08+col*.195,.252,1.34+row*.17),(.16,.065,.13),'blue' if row==3 else 'silver')
 box(m,'SpaceBar',(0,.3,1.88),(.91,.06,.12),'blue')
 rounded(m,'MouseMat',(2,.025,1.5),(1.05,.05,1.12),'seam',rad=.02)
 ball(m,'Mouse',(2,.19,1.5),(.43,.31,.68),'dark')
 box(m,'MouseSplit',(2,.33,1.36),(.015,.02,.2),'silver')
 cyl(m,'MouseWheel',(2,.35,1.35),.12,.07,'blue',r=rot(z=0))
 # native short cable segments behind monitor.
 for k in range(5):line(m,'Cable',(.25+k*.31,.07,-.65-k*.1),(.56+k*.31,.07,-.75-k*.1),.035,'dark')
 return m

def chair():
 m=model('Chair')
 cyl(m,'GasLift',(0,.85,0),1.4,.24,'silver')
 cyl(m,'GasSleeve',(0,.52,0),.55,.38,'dark')
 for a in range(5):
  t=a*TAU/5;end=(math.sin(t)*1.1,.22,math.cos(t)*1.1)
  line(m,'FiveStarBase',(0,.43,0),end,.14,'dark')
  cyl(m,'Caster',add(end,(0,-.1,0)),.22,.3,'dark',r=rot(y=a*72))
 rounded(m,'SeatCushion',(0,1.72,0),(2.05,.4,1.95),'fabric',rad=.13,collide=True)
 # +Z-facing model; project Chair is rotated 180 degrees, matching PcSeat.
 part(m,'PcSeat',(0,1.93,0),(1.7,.08,1.5),'fabric',cls='Seat',r=rot(y=180),collide=True,alpha=1)
 rounded(m,'BackShell',(0,2.84,-.82),(1.99,2.16,.4),'seam',rad=.14)
 rounded(m,'BackCushion',(0,2.88,-.57),(1.74,1.9,.22),'fabric',rad=.09)
 rounded(m,'LumbarPad',(0,2.23,-.4),(1.48,.35,.18),'blue',rad=.05)
 for x in (-.68,.68):box(m,'UpholsteryStitch',(x,2.92,-.444),(.022,1.48,.012),'5280D8')
 for x in (-1.05,1.05):
  line(m,'ArmSupport',(x,1.65,-.2),(x,2.23,-.1),.12,'metal')
  rounded(m,'Armrest',(x,2.28,.12),(.28,.17,1.2),'dark',rad=.06)
 return m

def coffee():
 m=model('Coffee')
 rounded(m,'OakCounter',(0,2.81,0),(6.9,.38,2.7),'top',rad=.075,mat='Wood',collide=True)
 box(m,'Cabinet',(0,1.35,0),(6.55,2.7,2.45),'wood',mat='Wood',collide=True)
 for x in (-2.18,0,2.18):
  box(m,'CupboardDoor',(x,1.43,1.26),(2.06,2.3,.12),'top',mat='Wood')
  line(m,'CabinetHandle',(x+.65,1.3,1.38),(x+.65,1.95,1.38),.08,'dark')
 for x in (-2.8,2.8):
  for z in (-.95,.95):box(m,'CabinetFoot',(x,.15,z),(.28,.3,.28),'dark')
 rounded(m,'CoffeeMachine',(-1.35,4.05,-.25),(2.05,2.1,1.6),'metal',rad=.09)
 box(m,'BrewRecess',(-1.35,3.82,.57),(1.6,1.3,.07),'dark')
 rounded(m,'MachineHeader',(-1.35,4.73,.66),(1.89,.55,.17),'silver',rad=.04)
 box(m,'Display',(-1.7,4.76,.76),(.55,.22,.018),'cyan',mat='Neon')
 for x in (-1.05,-.76):cyl(m,'BrewButton',(x,4.78,.78),.03,.12,'gold',r=rot(y=90))
 for x in (-1.53,-1.17):cyl(m,'CoffeeSpout',(x,4.32,.78),.27,.12,'silver')
 box(m,'DripTray',(-1.35,3.14,.64),(1.85,.15,.8),'dark')
 for i in range(9):box(m,'DripGrille',(-2.07+i*.18,3.23,.64),(.065,.025,.68),'silver')
 cyl(m,'BeanHopper',(-1.35,5.25,-.25),.45,.8,'593A26')
 cyl(m,'HopperLid',(-1.35,5.51,-.25),.08,.91,'dark')
 mug(m,(-1.38,3.24,.85),'white',.88)
 for x in (.6,1.8):
  cyl(m,'Canister',(x,3.49,-.38),.95,.76,'white')
  cyl(m,'CanisterLid',(x,4.01,-.38),.12,.82,'gold')
 mug(m,(2.4,3,.6),'blue');mug(m,(1.15,3,.6),'white')
 return m

def sofa():
 m=model('Sofa')
 for x in (-3.6,3.6):
  for z in (-1,1):cyl(m,'SofaLeg',(x,.25,z),.5,.25,'darkwood')
 rounded(m,'SofaBase',(0,.8,0),(8.4,.8,3.05),'seam',rad=.14,collide=True)
 rounded(m,'Back',(0,2.03,-1.2),(8.35,2.08,.6),'fabric',rad=.18,collide=True)
 for x in (-2.48,0,2.48):
  rounded(m,'SeatPillow',(x,1.33,.13),(2.35,.45,2.25),'fabric',rad=.12,collide=True)
  rounded(m,'BackPillow',(x,2.14,-.83),(2.34,1.6,.45),'fabric',rad=.12)
 for x in (-4.1,4.1):rounded(m,'Arm',(x,1.55,0),(.63,1.55,3.2),'blue',rad=.14,collide=True)
 for x in (-2.85,2.85):rounded(m,'GoldCushion',(x,2.01,-.28),(1.12,1.1,.4),'gold',rad=.12,r=rot(z=12 if x<0 else -12))
 return m

def coffee_table():
 m=model('CoffeeTable')
 rounded(m,'Top',(0,1.57,0),(5.8,.35,2.5),'top',rad=.085,mat='Wood',collide=True)
 box(m,'MagazineShelf',(0,.65,0),(4.8,.16,1.9),'wood',mat='Wood')
 for x in (-2.35,2.35):
  for z in (-.85,.85):box(m,'Leg',(x,.76,z),(.22,1.52,.22),'darkwood',collide=True)
 plant(m,(0,1.75,0),.56)
 for i,c in enumerate(['blue','gold']):box(m,'Book',(-1.65,1.8+i*.16,.2),(1.15,.14,.7),c)
 return m

def rug():
 m=model('Rug')
 rounded(m,'GoldBorder',(0,.045,0),(21,.09,23),'gold',rad=.04)
 rounded(m,'BlueWoven',(0,.1,0),(20.5,.035,22.5),'seam',rad=.015)
 for x in (-10.05,10.05):box(m,'Binding',(x,.124,0),(.035,.01,22),'fabric')
 # deliberate sparse woven stripes instead of thousands of fibres.
 for z in range(-10,11):box(m,'Weave',(0,.124,z),(19.9,.009,.016),'31579E')
 return m

def shelf(decor=False):
 m=model('HitShelf')
 if not decor:
  # Game template: slots from ModelFactory.hitShelfSlot (2 rows x 5, step 2, cartridges 1.4x1.6
  # centred at Y 1.2 / 3.5, Z 0.1). The game places real hit cartridges itself.
  box(m,'Back',(0,2.85,-.7),(11.2,5.7,.2),'darkwood',mat='Wood')
  for x in (-5.6,5.6):box(m,'Upright',(x,2.95,0),(.3,5.9,1.7),'wood',mat='Wood',collide=True)
  for y in (.3,2.6,4.9):box(m,'Shelf',(0,y,0),(11,.2,1.6),'top',mat='Wood',collide=True)
  box(m,'TopLight',(0,4.7,.65),(10.4,.09,.13),'warm',mat='Neon',light=(14,.35,'warm'))
  return m
 box(m,'Back',(0,3.55,-.8),(7.3,6.8,.26),'darkwood',mat='Wood')
 for x in (-3.5,3.5):box(m,'Upright',(x,3.6,0),(.28,7.2,1.7),'wood',mat='Wood',collide=True)
 for y in (.2,2.35,4.5,6.65):box(m,'Shelf',(0,y,0),(7.3,.22,1.8),'top',mat='Wood',collide=True)
 colors=['blue','pink','purple','green','gold','cyan','FF874B','CDA660','76BDEB']
 for row in range(3):
  for col in range(3):
   x=-2.25+col*2.25;y=.95+row*2.15
   rounded(m,'GameCartridge',(x,y,.26),(1.55,1.25,.34),colors[row*3+col],rad=.06)
   box(m,'CartridgeLabel',(x,y+.06,.45),(1.2,.88,.025),'dark')
   # Simple original glyphs built from geometry; no uploaded textures.
   if (row+col)%3==0:
    for a in range(5):
     t=a*TAU/5
     ball(m,'StarGlyph',(x+math.sin(t)*.2,y+math.cos(t)*.2,.48),(.18,.18,.04),'gold')
   elif (row+col)%3==1:
    box(m,'PixelGlyph',(x,y,.48),(.53,.22,.04),'white');box(m,'PixelGlyph',(x,y,.48),(.22,.53,.04),'white')
   else:
    box(m,'DiamondGlyph',(x,y,.48),(.38,.38,.04),'cyan',r=rot(z=45))
   for j in range(5):box(m,'CartridgeContact',(x-.3+j*.15,y-.56,.46),(.085,.1,.035),'gold')
 box(m,'TopLight',(0,6.5,.65),(6.4,.09,.13),'warm',mat='Neon',light=(14,.35,'warm'))
 return m

def pendant():
 m=model('PendantLamp')
 cyl(m,'CeilingCap',(0,0,0),.14,.6,'dark')
 line(m,'Cable',(0,-.08,0),(0,-1.65,0),.075,'dark')
 # stepped rounded metal shade with glowing underside.
 for i,(d,h) in enumerate([(1.05,.3),(1.45,.3),(1.85,.3),(2.25,.2)]):cyl(m,'Shade',(0,-1.8-i*.23,0),h,d,'metal')
 cyl(m,'ShadeRim',(0,-2.6,0),.1,2.35,'dark')
 cyl(m,'Diffuser',(0,-2.66,0),.05,2.14,'warm',mat='Neon',light=(32,1.25,'warm'))
 ball(m,'Bulb',(0,-2.78,0),(.55,.4,.55),'warm',mat='Neon')
 return m

def planter():
 m=model('Plant');plant(m,(0,0,0),1.65);return m

def sign():
 m=model('StudioSign')
 rounded(m,'SignBack',(0,0,0),(15,2.8,.35),'darkwood',rad=.15)
 rounded(m,'GoldPanel',(0,0,.2),(14.65,2.45,.12),'gold',rad=.05,mat='Neon')
 rounded(m,'SignFace',(0,0,.28),(14.2,2.02,.08),'wood',rad=.03)
 for x in (-6.6,6.6):cyl(m,'SignScrew',(x,0,.35),.025,.12,'gold',r=rot(y=90))
 return m

def posters():
 m=model('Posters')
 for i,x in enumerate((-4.5,0,4.5)):
  box(m,'Frame',(x,2.5,0),(3.6,4.8,.2),'edge',mat='Wood')
  box(m,'Mat',(x,2.5,.12),(3.33,4.53,.04),'white')
  box(m,'Artwork',(x,2.5,.15),(3.05,4.25,.035),['blue','purple','FF884B'][i])
  if i==0:
   for k in range(3):box(m,'PlatformArt',(x-.6+k*.4,1.1+k*.65,.19),(1.25-k*.2,.35,.035),'leaf')
   box(m,'FlagPole',(x+.25,3.6,.2),(.07,.9,.04),'gold');box(m,'Flag',(x+.58,3.95,.2),(.65,.35,.04),'gold')
  elif i==1:
   rounded(m,'ControllerArt',(x,2.5,.21),(1.9,.9,.035),'gold',rad=.016)
   box(m,'DPad',(x-.5,2.5,.24),(.1,.45,.025),'dark');box(m,'DPad',(x-.5,2.5,.24),(.45,.1,.025),'dark')
   for yy in (-.17,.17):ball(m,'ArtButton',(x+.5,2.5+yy,.24),(.15,.15,.025),'dark')
  else:
   cyl(m,'ArtSun',(x+.5,3.5,.21),.03,.75,'gold',r=rot(y=90))
   for dx in (-.65,.4):box(m,'AbstractMountain',(x+dx,1.8,.22),(1.3,1.3,.035),'purple',r=rot(z=45))
 return m

def garage():
 m=model('GarageWalls')
 box(m,'ConcreteFloor',(0,-.12,0),(60,.24,60),'concrete',collide=True,mat='Concrete')
 # large concrete tiles with restrained grout.
 for i in range(-4,5):
  box(m,'FloorJointX',(i*6,.006,0),(.035,.012,59.7),'7F8080')
  box(m,'FloorJointZ',(0,.007,i*6),(59.7,.012,.035),'7F8080')
 # side panels with actual window apertures at the front half.
 for x in (-29.5,29.5):
  box(m,'SideWallBottom',(x,2.1,0),(1,4.2,59),'wood',mat='Wood',collide=True)
  box(m,'SideWallTop',(x,11.7,0),(1,2.6,59),'wood',mat='Wood',collide=True)
  for za,zb in [(-29,-9),(-1,9),(17,29)]:box(m,'SideWallPier',(x,7.25,(za+zb)/2),(1,6.1,zb-za),'wood',mat='Wood',collide=True)
  for z in (-5,13):
   box(m,'WindowGlass',(x,7.25,z),(.1,5.4,7.5),'8BBED2',alpha=.62,mat='Glass')
   for zz in (-3.8,3.8):box(m,'WindowFrame',(x,7.25,z+zz),(1.1,5.9,.2),'darkwood')
   for yy in (4.4,7.25,10.1):box(m,'WindowCrossbar',(x,yy,z),(1.1,.18,7.8),'darkwood')
   box(m,'WindowMullion',(x,7.25,z),(1.1,5.7,.18),'darkwood')
  # siding grooves only on opaque bands.
  for y in (1.1,2.2,3.3,11.2,12.3):box(m,'SidingJoin',(x+(.506 if x<0 else -.506),y,0),(.018,.035,58.6),'darkwood')
  for z in (-28,-15,0,15,28):
   box(m,'TimberPost',(x+(.65 if x<0 else -.65),6.5,z),(.65,13,.65),'darkwood',mat='Wood')
   box(m,'StoneFoot',(x+(.65 if x<0 else -.65),.65,z),(1.05,1.3,1.1),'silver',mat='Concrete')
 # Timber siding on opaque wall piers; narrow grooves catch warm light.
 for x in (-28.985,28.985):
  for za,zb in [(-29,-9),(-1,9),(17,29)]:
   for y in (4.5,5.6,6.7,7.8,8.9,10):box(m,'SidingJoin',(x,y,(za+zb)/2),(.016,.032,zb-za),'darkwood')
 # rear wall and two sectional garage doors, as in reference.
 box(m,'RearWall',(0,6.5,-29.5),(60,13,1),'wood',mat='Wood',collide=True)
 for yy in (1.1,2.2,3.3,4.4,5.5,6.6,7.7,8.8,9.9,11,12.1):box(m,'RearSiding',(0,yy,-28.985),(59.6,.025,.016),'darkwood')
 # Doors at the sides of the rear wall: the centre stays free for Posters (Config: X 0, Z -28.8)
 for x in (-17.6,17.6):
  box(m,'DoorDarkRecess',(x,5.15,-28.89),(14.3,10.3,.13),'dark')
  for k in range(7):
   y=.75+k*1.47
   box(m,'DoorPanel',(x,y,-28.73),(13.65,1.37,.15),'999B9E',mat='Metal',collide=True)
   for xx in (-5.9,5.9):
    box(m,'DoorHinge',(x+xx,y,-28.59),(.18,.32,.09),'silver')
  for dx in (-4.65,-1.55,1.55,4.65):
   box(m,'WindowGasket',(x+dx,8.14,-28.61),(2.75,.98,.07),'dark')
   box(m,'DoorWindow',(x+dx,8.14,-28.55),(2.45,.74,.06),'8BBED2',mat='Glass',alpha=.15)
  for dx in (-7.3,7.3):box(m,'DoorRail',(x+dx,5.4,-28.35),(.14,10.8,.2),'silver',mat='Metal')
  rounded(m,'DoorHandle',(x,1.65,-28.49),(1.35,.15,.18),'dark',rad=.04)
 # front open facade: no wall or collider across entrance.
 for x in (-29.5,29.5):box(m,'FrontCorner',(x,6.5,29),(1.2,13,1.2),'darkwood',mat='Wood',collide=True)
 box(m,'FrontHeader',(0,12.6,29),(60,.8,1),'darkwood',mat='Wood')
 # exposed pitched frame at rear; roof separate, no visual obstruction from above.
 for z in (-29,0,29):
  line(m,'Rafter',(-29,13,z),(0,18,z),.48,'wood')
  line(m,'Rafter',(0,18,z),(29,13,z),.48,'wood')
 for x in (-28,28):box(m,'EaveBeam',(x,13.1,0),(.55,.6,59),'top',mat='Wood')
 for x,z in [(-15,-8),(15,-8),(-15,13),(15,13)]:put(m,pendant(),(x,14,z))
 put(m,sign(),(0,11.35,-28.6))
 return m

def roof():
 m=model('GarageRoof')
 angle=math.degrees(math.atan2(5,29))
 for x in (-14.5,14.5):
  box(m,'RoofPlane',(x,15.7,0),(29.75,.3,61),'darkwood',r=rot(z=angle if x<0 else -angle),mat='Wood',collide=True)
  for z in range(-30,31,3):box(m,'RoofSeam',(x,15.91,z),(29.7,.06,.06),'wood',r=rot(z=angle if x<0 else -angle))
 return m

def bench():
 m=model('WallBench')
 rounded(m,'Cushion',(0,1.55,0),(5.8,.35,1.7),'fabric',rad=.09,collide=True)
 for x in (-2.5,2.5):box(m,'Leg',(x,.7,0),(.35,1.4,1.4),'darkwood',collide=True)
 return m

ASSETS={'Desk1':desk(),'Desk2':desk('Desk2',False),'PC1':pc(),'PCPro':pc('PCPro',True),'Chair':chair(),'Coffee':coffee(),'Posters':posters(),'GarageWalls':garage(),'GarageRoof':roof(),'Sofa':sofa(),'CoffeeTable':coffee_table(),'HitShelf':shelf(),'Plant':planter(),'PendantLamp':pendant(),'StudioSign':sign(),'Rug':rug(),'WallBench':bench()}
# Standalone lamps and sign have pivot at ceiling / sign centre by design.
FULL=model('AstraGarage_ReferenceLayout')
def scaled(src,factor):
 result=copy.deepcopy(src)
 def visit(m):
  m['pos']=tuple(v*factor for v in m['pos'])
  for p in m['parts']:
   p['p']=tuple(v*factor for v in p['p']);p['s']=tuple(v*factor for v in p['s'])
   if p.get('light'):p['light']=(p['light'][0]*factor,*p['light'][1:])
  for c in m['children']:visit(c)
 visit(result);return result
put(FULL,scaled(ASSETS['GarageWalls'],.75))
# no roof in display model, to keep mobile overhead view and reference readability.
for i,(x,z,yaw) in enumerate([(-11.5,-12,0),(11.5,-12,0),(-11.5,1,0),(11.5,1,0)]):
 put(FULL,ASSETS['Desk2'],(x,0,z),yaw,f'Workstation{i+1}_Desk')
 put(FULL,ASSETS['PCPro'] if i==3 else ASSETS['PC1'],(x,3,z-.8),yaw,f'Workstation{i+1}_PC')
 put(FULL,ASSETS['Chair'],(x,0,z+3.1),180,f'Workstation{i+1}_Chair')
put(FULL,ASSETS['Coffee'],(-18.5,0,-6),90)
put(FULL,shelf(True),(18.8,0,-4),-90)
put(FULL,ASSETS['Posters'],(-21.64,2.1,-13),90)
put(FULL,ASSETS['Sofa'],(0,0,15.4),180)
put(FULL,ASSETS['CoffeeTable'],(0,0,11))
put(FULL,ASSETS['Rug'],(0,.01,7))
for p in [(-18.8,0,-18.5),(18.8,0,-18.5),(-18.8,0,18.5),(18.8,0,18.5)]:put(FULL,ASSETS['Plant'],p)
# Nested, disabled seats for scene staging? Functional seats remain enabled, intentional.
UPGRADES=model('Upgrades')
for n in ['Desk1','PC1','GarageWalls','Chair','Desk2','Coffee','Posters','PCPro','HitShelf']:put(UPGRADES,ASSETS[n])

# Native Roblox XML export: no scripts, no network texture/mesh IDs.
MAT={'SmoothPlastic':272,'Neon':288,'Wood':512,'WoodPlanks':528,'Metal':1088,'Concrete':816,'Glass':1568}
serial=0
def prop(props,typ,name,value):
 e=ET.SubElement(props,typ,{'name':name});e.text=str(value);return e
def vec(props,name,v):
 e=ET.SubElement(props,'Vector3',{'name':name})
 for n,t in zip('XYZ',v):ET.SubElement(e,n).text=f'{t:.7g}'
def frame(props,name,p=(0,0,0),r=I):
 e=ET.SubElement(props,'CoordinateFrame',{'name':name})
 for n,v in zip(['X','Y','Z']+[f'R{i}{j}' for i in range(3) for j in range(3)],list(p)+list(r)):ET.SubElement(e,n).text=f'{v:.8g}'
def refid():
 global serial;serial+=1;return 'RBX'+str(serial)
def write_model(m,parent,worldp=(0,0,0),worldr=I):
 pos=add(worldp,mv(worldr,m['pos']));rr=mul(worldr,m['r'])
 rootid=refid();item=ET.SubElement(parent,'Item',{'class':'Model','referent':refid()});props=ET.SubElement(item,'Properties')
 prop(props,'string','Name',m['name']);prop(props,'Ref','PrimaryPart',rootid)
 # Invisible root fixes exact base pivot and stays nonqueryable.
 root=dict(name='Pivot',p=pos,s=(.05,.05,.05),r=rr,c=(0,0,0),shape='box',mat='SmoothPlastic',collide=False,alpha=1,cls='Part')
 write_part(root,item,rootid)
 for p in m['parts']:
  p=copy.deepcopy(p);p['p']=add(pos,mv(rr,p['p']));p['r']=mul(rr,p['r']);write_part(p,item)
 for child in m['children']:write_model(child,item,pos,rr)
 return item

def write_part(p,parent,referent=None):
 it=ET.SubElement(parent,'Item',{'class':p['cls'],'referent':referent or refid()});pr=ET.SubElement(it,'Properties')
 prop(pr,'string','Name',p['name']);vec(pr,'size',p['s']);frame(pr,'CFrame',p['p'],p['r'])
 color=ET.SubElement(pr,'Color3',{'name':'Color'})
 for k,v in zip('RGB',p['c']):ET.SubElement(color,k).text=f'{v/255:.7g}'
 for n,v in [('Anchored',True),('CanCollide',p['collide']),('CanTouch',p['cls']=='Seat'),('CanQuery',p['collide'] or p['cls']=='Seat'),('CastShadow',p['mat']!='Neon' and p['alpha']<.5)]:prop(pr,'bool',n,str(v).lower())
 prop(pr,'float','Transparency',p['alpha']);prop(pr,'token','Material',MAT[p['mat']]);prop(pr,'token','TopSurface',0);prop(pr,'token','BottomSurface',0)
 if p['cls']=='Part':prop(pr,'token','shape',{'box':1,'ball':0,'cyl':2}[p['shape']])
 if p['cls']=='Seat':prop(pr,'bool','Disabled','false')
 if p.get('light'):
  ra,br,co=p['light'];li=ET.SubElement(it,'Item',{'class':'PointLight','referent':refid()});lp=ET.SubElement(li,'Properties');prop(lp,'string','Name','WarmLight');prop(lp,'float','Range',ra);prop(lp,'float','Brightness',br);prop(lp,'bool','Shadows','true' if ra>=30 else 'false')
  e=ET.SubElement(lp,'Color3',{'name':'Color'})
  for k,v in zip('RGB',rgb(co)):ET.SubElement(e,k).text=str(v/255)
 return it

def export(m,path,place=False):
 global serial;serial=0
 root=ET.Element('roblox',{'version':'4','xmlns:xmime':'http://www.w3.org/2005/05/xmlmime','xmlns:xsi':'http://www.w3.org/2001/XMLSchema-instance'})
 ET.SubElement(root,'External').text='null';ET.SubElement(root,'External').text='nil'
 target=root
 if place:
  ws=ET.SubElement(root,'Item',{'class':'Workspace','referent':refid()});pr=ET.SubElement(ws,'Properties');prop(pr,'string','Name','Workspace');target=ws
  lighting=ET.SubElement(root,'Item',{'class':'Lighting','referent':refid()});lp=ET.SubElement(lighting,'Properties');prop(lp,'string','Name','Lighting');prop(lp,'float','Brightness',2);prop(lp,'float','ClockTime',15)
  for name,col in [('Ambient','AFA4A1'),('OutdoorAmbient','B0B7CA')]:
   e=ET.SubElement(lp,'Color3',{'name':name})
   for k,v in zip('RGB',rgb(col)):ET.SubElement(e,k).text=str(v/255)
 write_model(m,target)
 ET.ElementTree(root).write(path,encoding='utf-8',xml_declaration=True)

def flatten(m,wp=(0,0,0),wr=I):
 pos=add(wp,mv(wr,m['pos']));r=mul(wr,m['r']);out=[]
 for p in m['parts']:
  p=copy.deepcopy(p);p['p']=add(pos,mv(r,p['p']));p['r']=mul(r,p['r']);out.append(p)
 for child in m['children']:out.extend(flatten(child,pos,r))
 return out

def meshes(p):
 sx,sy,sz=[v/2 for v in p['s']]
 if p['shape']=='box':
  vs=[(x*sx,y*sy,z*sz) for x,y,z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
  fs=[(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(0,1,5,4),(3,7,6,2)]
 elif p['shape']=='cyl':
  N=12;vs=[(x*sx,math.cos(i*TAU/N)*sy,math.sin(i*TAU/N)*sz) for x in (-1,1) for i in range(N)];fs=[tuple(reversed(range(N))),tuple(range(N,2*N))]+[(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)]
 else:
  N=10;K=6;vs=[(sx*math.sin(j*math.pi/K)*math.cos(i*TAU/N),sy*math.cos(j*math.pi/K),sz*math.sin(j*math.pi/K)*math.sin(i*TAU/N)) for j in range(K+1) for i in range(N)]
  fs=[(j*N+i,j*N+(i+1)%N,(j+1)*N+(i+1)%N,(j+1)*N+i) for j in range(K) for i in range(N)]
 return [add(p['p'],mv(p['r'],v)) for v in vs],fs

def render(parts,path,yaw=32,elev=28,target=(0,3,0),span=82,W=1800,H=1200):
 # Geometry preview of the actual native Parts, not an AI concept.
 yaw,elev=map(math.radians,(yaw,elev));right=(math.cos(yaw),0,-math.sin(yaw));forward=(math.sin(yaw)*math.cos(elev),math.sin(elev),math.cos(yaw)*math.cos(elev));up=(-math.sin(yaw)*math.sin(elev),math.cos(elev),-math.cos(yaw)*math.sin(elev))
 dot=lambda a,b:sum(x*y for x,y in zip(a,b));scale=W/span
 def project(v):
  v=tuple(v[i]-target[i] for i in range(3));return (W/2+dot(v,right)*scale,H*.53-dot(v,up)*scale,dot(v,forward))
 polys=[];light=(-.35,.8,.5)
 for p in parts:
  if p['alpha']>.8:continue
  vs,fs=meshes(p);pv=[project(v) for v in vs]
  for face in fs:
   a,b,c=[vs[i] for i in face[:3]];u=tuple(b[i]-a[i] for i in range(3));v=tuple(c[i]-a[i] for i in range(3));n=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]);mag=math.sqrt(dot(n,n))
   if mag<1e-9:continue
   n=tuple(t/mag for t in n)
   if dot(n,forward)<-.01:continue
   shade=.68+.32*max(0,dot(n,light));shade=max(shade,.95) if p['mat']=='Neon' else shade
   col=tuple(min(255,int(c*shade)) for c in p['c']);alpha=int(255*(1-p['alpha']))
   polys.append((sum(pv[i][2] for i in face)/len(face),[(pv[i][0],pv[i][1]) for i in face],col,alpha))
 im=Image.new('RGB',(W,H),'#E8E1D8');draw=ImageDraw.Draw(im,'RGBA')
 for _,pts,col,al in sorted(polys,key=lambda f:f[0]):draw.polygon(pts,fill=(*col,al))
 im.save(path)

if __name__=='__main__':
 manifest=[]
 for name,m in ASSETS.items():
  export(m,ROOT/'models'/f'{name}.rbxmx');ps=flatten(m)
  manifest.append({'name':name,'file':f'models/{name}.rbxmx','parts':len(ps),'seats':sum(p['cls']=='Seat' for p in ps)})
 export(FULL,ROOT/'Garage_Assembled.rbxmx');export(FULL,ROOT/'Garage_Showcase.rbxlx',True);export(UPGRADES,ROOT/'Upgrades_Import.rbxmx')
 (ROOT/'manifest.json').write_text(json.dumps({'assets':manifest,'assembledParts':len(flatten(FULL)),'notes':'All geometry original. Native anchored Parts. No Script/LocalScript/ModuleScript or external asset dependencies.'},indent=2))
 (ROOT/'source'/'scene.json').write_text(json.dumps(flatten(FULL),separators=(',',':')))
 render(flatten(FULL),ROOT/'previews'/'Garage_Overview.png',yaw=24,elev=31,target=(0,3,0),span=88)
 render(flatten(FULL),ROOT/'previews'/'Garage_Front.png',yaw=-24,elev=20,target=(0,4,0),span=83)
 ws=model('Workstation');put(ws,ASSETS['Desk2']);put(ws,ASSETS['PC1'],(0,3,-.8));put(ws,ASSETS['Chair'],(0,0,3.1),180)
 render(flatten(ws),ROOT/'previews'/'Workstation.png',yaw=30,elev=25,target=(0,2,0),span=14,W=1500,H=1100)
 render(flatten(ASSETS['Coffee']),ROOT/'previews'/'Coffee.png',yaw=28,elev=20,target=(0,2.5,0),span=11,W=1500,H=1100)
 print(json.dumps({'models':len(ASSETS),'parts':len(flatten(FULL)),'output':str(ROOT)}))
