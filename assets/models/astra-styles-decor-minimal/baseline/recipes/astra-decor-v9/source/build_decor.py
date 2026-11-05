"""V9 original native primitive decor. Run build_decor.py then validate_render.py."""
from geometry import *
import subprocess

def beans():
 m=model('BeanBags')
 for i,(x,c) in enumerate([(-2.65,'blue'),(0,'gold'),(2.65,'pink')]):
  ball(m,'SoftBase', (x,.58,.05),(2.5,1.16,2.6),c)
  ball(m,'LoungerBack',(x,1.35,-.48),(2.22,2.12,1.64),c)
  ball(m,'SeatCushion',(x,1.0,.46),(1.98,.48,1.76),c)
  line(m,'FrontStitch',(x-.72,.7,1.19),(x+.72,.7,1.19),.035,'white')
  box(m,'FabricTag',(x+.99,.65,.68),(.13,.21,.05),'white')
 return m

def bookshelf():
 m=model('Bookshelf')
 box(m,'Back',(0,2.5,-.66),(5.8,5,.16),'darkwood',collide=True)
 for x in [-2.78,2.78]:box(m,'Side',(x,2.5,0),(.24,5,1.4),'wood',collide=True)
 for y in [.12,1.32,2.52,3.72,4.88]:box(m,'Shelf',(0,y,0),(5.8,.24,1.4),'wood',collide=True)
 colors=['blue','gold','pink','green','purple','cyan']
 for row,y in enumerate([.72,1.92,3.12]):
  for j in range(7):
   x=-2.26+j*.46;h=.7+((j+row)%3)*.11
   box(m,'Book',(x,y-.4+h/2,.12),(.34,h,.8),colors[(j+row)%6])
   box(m,'SpineStripe',(x,y-.4+h*.7,.535),(.345,.045,.022),'edge')
 # top display: sculptural planet, tiny pot and three stacked albums
 for j in range(3):box(m,'Album',(-1.55,3.93+j*.16,.07),(1.5,.14,.85),colors[j])
 cyl(m,'Planter',(1.4,4.08,.05),.48,.56,'white')
 for x in [1.25,1.5]:ball(m,'Succulent',(x,4.43,.05),(.32,.45,.35),'green')
 ball(m,'DisplayPlanet',(.1,4.23,.1),(.7,.7,.7),'gold')
 return m

def fridge():
 m=model('MiniFridge')
 box(m,'Back',(0,2,-1.05),(2.4,3.52,.24),'dark',collide=True)
 for x in [-1.08,1.08]:box(m,'Side',(x,2,0),(.24,3.52,2.2),'blue',collide=True)
 for y in [.12,3.88]:box(m,'Case',(0,y,0),(2.4,.24,2.2),'blue',collide=True)
 for y in [.5,1.55,2.6]:box(m,'Shelf',(0,y,0),(1.9,.09,1.75),'silver')
 for row,y in enumerate([.88,1.93,2.98]):
  for j,x in enumerate([-.59,0,.59]):
   c=['pink','gold','cyan'][(j+row)%3]
   cyl(m,'SodaCan',(x,y,.05),.62,.39,c)
   cyl(m,'CanLid',(x,y+.32,.05),.035,.39,'silver')
   box(m,'CanMark',(x,y,.251),(.18,.23,.018),'white')
 for x in [-1.02,1.02]:box(m,'DoorFrame',(x,2,1.13),(.12,3.76,.12),'dark')
 for y in [.18,3.82]:box(m,'DoorFrame',(0,y,1.13),(2.16,.12,.12),'dark')
 box(m,'GlassDoor',(0,2,1.13),(1.94,3.5,.055),'cyan',mat='Glass',alpha=.76)
 box(m,'Handle',(.82,2,1.21),(.13,.85,.16),'gold')
 box(m,'InteriorLED',(0,3.72,.7),(1.6,.05,.06),'cyan',mat='Neon',light=(6,.3,'cyan'))
 return m

def neon():
 m=model('NeonSign')
 box(m,'Shield',(0,0,-.055),(5.7,2.3,.16),'dark',collide=True)
 # original winged controller outline, planar tubes entirely inside depth .3
 pts=[(-2,-.65),(-2.18,.05),(-1.6,.68),(-.65,.57),(0,.72),(.65,.57),(1.6,.68),(2.18,.05),(2,-.65),(1.35,-.62),(.88,-.2),(-.88,-.2),(-1.35,-.62),(-2,-.65)]
 for i,(a,b) in enumerate(zip(pts,pts[1:])):line(m,'ControllerNeon',(a[0],a[1],.065),(b[0],b[1],.065),.085,'cyan',mat='Neon',**({'light':(7,.35,'cyan')} if i==0 else {}))
 box(m,'DPadHorizontal',(-1.12,.14,.075),(.52,.1,.1),'pink',mat='Neon')
 box(m,'DPadVertical',(-1.12,.14,.075),(.1,.52,.1),'pink',mat='Neon')
 for x,y,c in [(1.02,.3,'gold'),(1.36,.02,'pink')]:ball(m,'ActionDot',(x,y,.07),(.19,.19,.1),c,mat='Neon')
 return m

def aquarium():
 m=model('Aquarium')
 box(m,'Cabinet',(0,1,0),(5.7,2,1.9),'wood',collide=True)
 for x in [-1.38,1.38]:
  box(m,'CabinetDoor',(x,1,.945),(2.6,1.65,.05),'darkwood')
  box(m,'Handle',(x-.95,1,.975),(.09,.45,.035),'gold')
 for y in [2.1,4.86]:box(m,'TankRim',(0,y,0),(5.9,.2,1.98),'dark')
 box(m,'Sand',(0,2.28,0),(5.55,.17,1.67),'edge')
 box(m,'Water',(0,3.55,-.03),(5.5,2.4,1.65),'cyan',mat='Glass',alpha=.88)
 for x in [-2.8,2.8]:box(m,'GlassSide',(x,3.49,0),(.06,2.58,1.84),'cyan',mat='Glass',alpha=.78)
 for z in [-.91,.91]:box(m,'GlassPanel',(0,3.49,z),(5.66,2.58,.05),'cyan',mat='Glass',alpha=.8)
 for x in [-2,-1.5,1.7,2.15]:
  line(m,'WeedStem',(x,2.35,-.42),(x+.15,3.55,-.43),.07,'green')
  for y,d in [(2.65,-.2),(2.98,.2),(3.25,-.17)]:ball(m,'SeaweedLeaf',(x+d,y,-.42),(.42,.17,.12),'leaf')
 for i,(x,y,z,c) in enumerate([(-1,3.7,.25,'gold'),(.8,3.15,.3,'pink'),(1.1,4.1,-.15,'blue')]):
  ball(m,'FishBody',(x,y,z),(.78,.38,.21),c)
  # fork tail in planar native thin blocks, original graphic fish silhouette
  for sign in [-1,1]:line(m,'FishTail',(x-.34,y,z),(x-.67,y+sign*.2,z),.13,c)
  ball(m,'FishEye',(x+.22,y+.06,z+.105),(.07,.07,.035),'dark')
 for x in [-.4,.15,.6]:ball(m,'Pebble',(x,2.43,.05),(.32,.18,.28),'silver')
 box(m,'TankLED',(0,4.72,0),(4.7,.06,.2),'cyan',mat='Neon',light=(7,.3,'cyan'))
 return m

def arcade():
 m=model('ArcadeMachine')
 box(m,'Base',(0,.18,0),(2.8,.36,2.5),'dark',collide=True)
 box(m,'LowerBody',(0,1.6,-.1),(2.6,2.6,2.1),'blue',collide=True)
 box(m,'FrontPanel',(0,1.65,1.0),(2.32,2.12,.09),'dark')
 for x in [-1.3,1.3]:
  box(m,'TallSide',(x,4.06,-.51),(.24,3.72,1.36),'blue',collide=True)
  box(m,'GoldSideAccent',(x,2,.18),(.26,.12,1.45),'gold')
 box(m,'Rear',(0,4.02,-1.11),(2.6,3.8,.12),'dark',collide=True)
 box(m,'ScreenHousing',(0,4.17,-.28),(2.4,2.35,1.05),'dark')
 box(m,'Screen',(0,4.2,.26),(2.07,1.64,.06),'102943',mat='Neon',light=(6,.25,'cyan'))
 # original abstract planet-runner scene, geometric and brand-free
 for x,y in [(-.78,3.7),(.6,4.7),(.82,4.0),(-.4,4.8)]:box(m,'StarPixel',(x,y,.3),(.055,.055,.02),'white',mat='Neon')
 ball(m,'ScreenPlanet',(.4,4.38,.31),(.42,.42,.035),'pink',mat='Neon')
 box(m,'PlayerShip',(-.45,3.95,.31),(.22,.35,.035),'gold',mat='Neon')
 box(m,'ShipWing',(-.45,3.87,.33),(.5,.1,.03),'cyan',mat='Neon')
 box(m,'ControlDeck',(0,3.02,.46),(2.8,.24,1.55),'dark',collide=True)
 cyl(m,'JoystickBase',(-.65,3.17,.72),.1,.34,'silver')
 cyl(m,'JoystickStem',(-.65,3.35,.72),.34,.09,'metal')
 ball(m,'JoystickBall',(-.65,3.56,.72),(.3,.3,.3),'pink')
 for x,z,c in [(.4,.6,'gold'),(.85,.83,'cyan')]:cyl(m,'Button',(x,3.19,z),.12,.27,c)
 box(m,'Marquee',(0,5.58,-.2),(2.8,.72,1.7),'dark')
 for x,c in [(-.7,'pink'),(0,'gold'),(.7,'cyan')]:ball(m,'MarqueeGem',(x,5.6,.67),(.3,.3,.05),c,mat='Neon')
 box(m,'TopEdge',(0,5.96,-.2),(2.8,.08,1.7),'gold')
 box(m,'CoinSlot',(0,1.78,1.06),(.1,.34,.06),'silver')
 box(m,'Speaker',(0,.8,1.07),(1.4,.45,.05),'metal')
 for x in [-.45,-.15,.15,.45]:box(m,'SpeakerSlot',(x,.8,1.1),(.08,.28,.025),'dark')
 return m

ASSETS={m['name']:m for m in [beans(),bookshelf(),fridge(),neon(),aquarium(),arcade()]}
# Center footprint about the installation pivot; sign uses its backing panel center.
for name,offset in {'BeanBags':-.025,'Bookshelf':.02,'MiniFridge':-.06,'Aquarium':-.00125,'NeonSign':.055}.items():
 for p in ASSETS[name]['parts']:p['p']=(p['p'][0],p['p'][1],p['p'][2]+offset)

if __name__=='__main__':
 for name,m in ASSETS.items():
  dest=ROOT/'models'/f'{name}.rbxmx';export(m,dest)
  project=ROOT/'source'/'convert.project.json';project.write_text(json.dumps({'name':name,'tree':{'$path':str(dest)}}))
  subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(project),'-o',str(dest.with_suffix('.rbxm'))],check=True)
 project.unlink()
