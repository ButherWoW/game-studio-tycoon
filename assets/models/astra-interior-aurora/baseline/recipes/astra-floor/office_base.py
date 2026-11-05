from geometry import *

def plant(m,x,y,z,s=1):
 box(m,'IvoryPlanter',(x,y+.4*s,z),(.9*s,.8*s,.9*s),'white',collide=True)
 box(m,'Soil',(x,y+.81*s,z),(.72*s,.025*s,.72*s),'darkwood')
 cyl(m,'Stem',(x,y+1.4*s,z),1.2*s,.12*s,'darkwood')
 for dx,dy,dz,w in [(0,1.8,0,.9),(.4,1.3,.04,.62),(-.4,1.5,-.12,.65),(.12,2.25,-.1,.62),(-.1,1.65,.42,.64)]:box(m,'Foliage',(x+dx*s,y+dy*s,z+dz*s),(w*s,.6*s,w*s),'leaf' if dy>1.7 else 'green')

def chair(m,x=0,z=1.2,yaw=0):
 c=model('TaskChair')
 # This chair is tucked inside the 4-stud footprint; staffing code retains its clear front zone.
 cyl(c,'Lift',(0,.8,0),1.3,.18,'silver')
 for a in range(5):
  t=a*TAU/5;end=(math.sin(t)*.62,.13,math.cos(t)*.62)
  line(c,'BaseSpoke',(0,.29,0),end,.1,'metal')
  cyl(c,'Caster',(end[0],.11,end[2]),.17,.22,'dark',r=rot(y=a*72))
 rounded(c,'BlueSeat',(0,1.52,0),(1.55,.3,1.28),'fabric',rad=.09,collide=True)
 rounded(c,'BlueBack',(0,2.35,.57),(1.55,1.45,.24),'fabric',rad=.07,collide=True)
 box(c,'BackInset',(0,2.36,.706),(1.2,1.1,.025),'seam')
 for xx in (-.84,.84):
  box(c,'ArmStem',(xx,1.64,0),(.09,.5,.1),'metal')
  box(c,'ArmPad',(xx,1.96,-.05),(.17,.12,.72),'dark')
 # Decorative furniture only; NPCs are positioned by StaffService, not seated by a Seat instance.
 put(m,c,(x,0,z),yaw)

def office_desk():
 m=model('OfficeDesk')
 rounded(m,'OakDesktop',(0,2.85,-.65),(6,.3,2.5),'top',rad=.07,mat='Wood',collide=True)
 for x in (-2.7,2.7):
  for z in (-1.65,.3):box(m,'WhiteLeg',(x,1.35,z),(.2,2.7,.2),'white',collide=True)
  box(m,'FootRail',(x,.1,-.67),(.3,.2,2.2),'silver',collide=True)
 box(m,'Underframe',(0,2.63,-1.5),(5.5,.18,.18),'silver')
 box(m,'Pedestal',(-2.05,1.2,-.7),(1.3,2.4,1.9),'white',collide=True)
 for y in (.45,1.2,1.95):
  box(m,'Drawer',(-2.05,y,.285),(1.17,.65,.08),'E4E8ED')
  box(m,'Handle',(-2.05,y,.35),(.5,.08,.08),'silver')
 # Thick monitor and original pixel landscape. Screen front is +Z.
 box(m,'MonitorFoot',(0,3.07,-1.3),(.9,.14,.55),'silver')
 box(m,'MonitorStem',(0,3.45,-1.45),(.16,.65,.16),'metal')
 rounded(m,'MonitorBezel',(0,4.05,-1.38),(2.55,1.5,.29),'dark',rad=.05)
 box(m,'Screen',(0,4.06,-1.222),(2.33,1.28,.018),'blue',mat='Neon')
 box(m,'AppHeader',(0,4.59,-1.207),(2.3,.13,.012),'273C65')
 for i in range(3):
  x=-.75+i*.62;y=3.7+i*.13
  box(m,'PixelIsland',(x,y,-1.203),(.55,.13,.016),'green')
  box(m,'PixelSoil',(x,y-.1,-1.202),(.55,.07,.016),'wood')
 box(m,'Cloud',(-.5,4.35,-1.201),(.4,.09,.016),'white')
 box(m,'Cloud',(.55,4.4,-1.201),(.5,.07,.016),'white')
 box(m,'Character',(0,4.2,-1.2),(.14,.2,.02),'gold')
 cyl(m,'MonitorLED',(1.08,3.39,-1.21),.025,.045,'cyan',r=rot(y=90),mat='Neon')
 box(m,'MiniTower',(1.95,3.58,-1.25),(.65,1.16,1),'white',collide=False)
 box(m,'TowerFace',(1.95,3.58,-.73),(.53,1.03,.04),'dark')
 for y in (3.3,3.62):
  cyl(m,'Fan',(1.95,y,-.7),.025,.29,'blue',r=rot(y=90),mat='Neon')
  cyl(m,'FanHub',(1.95,y,-.68),.02,.15,'dark',r=rot(y=90))
 box(m,'PowerButton',(1.95,3.96,-.69),(.12,.07,.025),'cyan',mat='Neon')
 box(m,'Keyboard',(0,3.07,-.05),(2.06,.14,.55),'silver')
 for row in range(3):
  for col in range(10):box(m,'Key',(-.9+col*.2,3.17,-.23+row*.18),(.16,.045,.12),'white' if row<2 else 'blue')
 box(m,'Space',(0,3.21,.14),(.72,.04,.09),'blue')
 box(m,'MousePad',(1.61,3.018,.03),(.67,.035,.7),'seam')
 ball(m,'Mouse',(1.61,3.11,.03),(.34,.19,.49),'dark')
 plant(m,-2.1,3,-1.2,.37)
 chair(m)
 return m

def office():
 m=model('Office')
 box(m,'Floor',(0,.01,0),(60,.02,60),'top',mat='Wood',collide=True)
 # Sparse plank joints; all rooted at the same bottom-plane as furniture.
 for z in range(-28,30,2):box(m,'PlankJoint',(0,.022,z),(59.7,.005,.017),'B69677')
 for row,z in enumerate(range(-27,28,4)):
  for x in range(-24+(row%2)*6,30,12):box(m,'PlankEnd',(x,.022,z),(.018,.005,3.95),'B69677')
 # White rear wall with large side windows and opaque central art section.
 box(m,'RearBase',(0,1.1,-29.75),(60,2.2,.5),'white',collide=True)
 box(m,'RearHeader',(0,12,-29.75),(60,2,.5),'white',collide=True)
 box(m,'CentralWall',(0,6.6,-29.75),(18,8.8,.5),'white',collide=True)
 for x in (-19.5,19.5):
  box(m,'RearWindow',(x,6.6,-29.75),(20.5,8.6,.08),'B7DDE9',alpha=.64,mat='Glass',collide=True)
  for xx in (-10.25,0,10.25):box(m,'WindowMullion',(x+xx,6.6,-29.75),(.14,8.8,.5),'silver')
  box(m,'WindowTransom',(x,6.7,-29.75),(20.5,.14,.5),'silver')
 for x in (-29.75,29.75):
  box(m,'SideBase',(x,1.1,0),(.5,2.2,59.5),'white',collide=True)
  box(m,'SideHeader',(x,12,0),(.5,2,59.5),'white',collide=True)
  box(m,'SideGlass',(x,6.6,0),(.08,8.6,59.3),'B7DDE9',alpha=.64,mat='Glass',collide=True)
  for z in range(-28,30,8):box(m,'SideMullion',(x,6.6,z),(.5,8.8,.16),'silver')
  box(m,'SideTransom',(x,6.7,0),(.5,.14,59.3),'silver')
  box(m,'Skirting',(x+(.3 if x<0 else -.3),.28,0),(.12,.5,59),'silver')
 # Front fully open below lintel: all purchase buttons Z22..29 stay unobstructed.
 box(m,'EntranceHeader',(0,12,29.75),(60,2,.5),'white')
 for x in (-29.75,29.75):box(m,'EntranceColumn',(x,5.5,29.75),(.5,11,.5),'white',collide=True)
 # Slim beams and four pendant panels; exactly one light per fixture.
 for x in (-15,15):box(m,'CeilingBeam',(x,12.7,0),(.22,.22,59.5),'silver')
 for x in (-12,12):
  for z in (-15,7):
   lamp=model('CeilingPanel')
   for xx in (-1.4,1.4):line(lamp,'Suspension',(xx,0,0),(xx,-.65,0),.035,'silver')
   box(lamp,'PanelCase',(0,-.71,0),(4,.16,1.1),'white')
   box(lamp,'Diffuser',(0,-.8,0),(3.8,.035,.9),'warm',mat='Neon',light=(32,.45,'warm'))
   put(m,lamp,(x,12.6,z))
 # Built-in reception niche, away from Config furniture and purchase strip.
 for x,z in [(-24,-24),(24,16),(-25,19)]:plant(m,x,0,z,1.35)
 box(m,'ReceptionBench',(18,1.2,11),(6,.28,1.8),'fabric',collide=True)
 for x in (15.7,20.3):box(m,'BenchLeg',(x,.53,11),(.22,1.06,1.4),'silver',collide=True)
 box(m,'BenchBack',(18,2,10.2),(6,1.4,.22),'fabric',collide=True)
 # two simple artworks in the niche.
 for x,c in [(16,'blue'),(20,'green')]:
  box(m,'NicheArtFrame',(x,5,-29.42),(2.7,3.3,.15),'white')
  box(m,'NicheArt',(x,5,-29.32),(2.4,3,.03),c)
 return m
