"""Astra V7 second-floor kit. Config c10dcb5. Native Roblox primitives."""
from geometry import *
from office_base import office, office_desk, plant
import subprocess

ELEVATOR={'status':'confirmed-owner-2026-11-05','centerXZ':[-20,24],'width':6,'depth':6,'height':7,'boundsXZ':[-23,-17,21,27],'floorBasesY':[0,14,28],'note':'No furniture/walls/lights in lift volume above common floor; game code provides platform/control. Floor model local pivot Y=0, placement Y=14.'}

def axis_scale(m,axis,factor,children=True):
 # Safe for the orthogonal local frames in this asset. Preserve native Part rotations.
 for p in m['parts']:
  pos=list(p['p']);pos[axis]*=factor;p['p']=tuple(pos)
  p['s']=tuple(p['s'][j]*(1+(factor-1)*abs(p['r'][axis*3+j])) for j in range(3))
 if children:
  for c in m['children']:
   pos=list(c['pos']);pos[axis]*=factor;c['pos']=tuple(pos);axis_scale(c,axis,factor)
 return m

def floor_desk():
 m=office_desk();m['name']='FloorDesk'
 # Main desktop assembly is axis aligned; retain the chair's original human-scale width.
 axis_scale(m,0,5/6,children=False)
 for p in m['parts']:
  if p['name'].startswith('OakDesktop'):p['c']=rgb('DDE6F5');p['mat']='SmoothPlastic';p['name']=p['name'].replace('OakDesktop','CorporateDesktop')
  elif p['name'] in ('Pedestal','Drawer'):p['c']=rgb('2F5DA8' if p['name']=='Pedestal' else 'DDE6F5')
 box(m,'BlueApron',(0,2.63,.44),(4.75,.22,.07),'2F5DA8')
 box(m,'CableTrough',(0,2.45,-1.65),(3.3,.17,.23),'silver')
 for i in range(3):box(m,'CableClip',(-.8+i*.8,2.35,-1.65),(.12,.12,.25),'metal')
 # Desktop top stays at Y=3; no desk lights, no expensive per-desk shadow lights.
 return m

def server_room():
 m=model('ServerRoom')
 # Width 10, depth 4. Config rotation -90 -> X24.5..28.5, inside wall.
 for x in (-4.88,4.88):
  box(m,'SideGlass',(x,3.8,0),(.12,7.6,3.8),'93BACD',mat='Glass',alpha=.62,collide=True)
  for z in (-1.88,1.88):box(m,'CornerPost',(x,3.9,z),(.24,7.8,.24),'metal',collide=True)
  for y in (.1,7.7):box(m,'SideRail',(x,y,0),(.24,.2,4),'metal')
 box(m,'BackGlass',(0,3.8,-1.88),(9.76,7.6,.12),'93BACD',mat='Glass',alpha=.62,collide=True)
 for y in (.1,7.7):box(m,'BackRail',(0,y,-1.88),(10,.2,.24),'metal')
 for x in (-4.15,4.15):
  box(m,'FrontGlass',(x,3.8,1.88),(1.4,7.6,.12),'93BACD',mat='Glass',alpha=.62,collide=True)
  box(m,'EntryJamb',(3.3 if x>0 else -3.3,3.9,1.88),(.2,7.8,.24),'metal',collide=True)
 box(m,'EntryHeader',(0,7.7,1.88),(10,.2,.24),'metal')
 for x in (-3.15,0,3.15):
  box(m,'RackFrame',(x,3.6,-1.04),(2.12,7.2,1.42),'dark',collide=True)
  box(m,'RackToe',(x,.15,-1.02),(2.3,.3,1.5),'metal')
  for i in range(6):
   y=.75+i*1.05
   box(m,'ServerUnit',(x,y,-.28),(1.88,.87,.12),'657083')
   for xx in (-.76,.76):box(m,'RackHandle',(x+xx,y,-.18),(.09,.5,.1),'silver')
   for j in range(3):box(m,'DriveSlot',(x-.44+j*.38,y+.08,-.205),(.28,.25,.025),'dark')
   for j,c in enumerate(['3DDC84','79D5ED']):ball(m,'StatusLED',(x+.37+j*.17,y-.23,-.19),(.07,.07,.025),c,mat='Neon')
  box(m,'RackLabel',(x,6.95,-.28),(.7,.14,.025),'DDE6F5')
 # Indicators are Neon only, zero PointLights for all 18 servers.
 return m

def lounge():
 m=model('Lounge')
 # Floor-standing upholstered sofa, max footprint 12x10, front approach remains open.
 for x in (-3.3,3.3):
  for z in (-4.3,-2.8):box(m,'SofaFoot',(x,.15,z),(.22,.3,.22),'metal',collide=True)
 rounded(m,'SofaBase',(0,.64,-3.5),(8,.68,2.4),'2F5DA8',rad=.09,collide=True)
 # Back can stay squared: the front cushions carry the soft silhouette.
 box(m,'SofaBack',(0,1.85,-4.54),(8,2,.3),'2F5DA8',collide=True)
 for x in (-2.45,0,2.45):
  rounded(m,'SeatCushion',(x,1.12,-3.42),(2.3,.3,1.92),'DDE6F5',rad=.07,collide=True)
  box(m,'BackCushion',(x,1.95,-4.31),(2.28,1.45,.16),'DDE6F5')
 for x in (-3.88,3.88):box(m,'SofaArm',(x,1.24,-3.5),(.24,1.6,2.4),'2F5DA8',collide=True)
 for x in (-2.8,2.8):box(m,'AccentPillow',(x,1.65,-4.04),(.75,.75,.2),'blue',r=rot(z=8 if x<0 else -8))
 # Coffee table centred between seating and display, with free space on both sides.
 rounded(m,'CoffeeTable',(0,1.36,-.38),(4.2,.26,1.65),'top',rad=.06,mat='Wood',collide=True)
 for x in (-1.6,1.6):
  for z in (-.9,.13):box(m,'TableLeg',(x,.615,z),(.14,1.23,.14),'silver',collide=True)
 box(m,'Magazine',(-1.1,1.53,-.5),(.75,.08,.55),'blue')
 cyl(m,'Cup',(.9,1.7,-.4),.4,.28,'white')
 cyl(m,'Coffee',(.9,1.905,-.4),.012,.22,'darkwood')
 # TV cabinet and original unbranded console face back toward sofa (-Z).
 box(m,'MediaCabinet',(0,.7,3.55),(4,1.4,1.25),'DDE6F5',collide=True)
 for x in (-1,1):box(m,'MediaDoor',(x,.7,2.89),(1.85,1.2,.08),'2F5DA8')
 for x in (-1.6,1.6):box(m,'MediaPull',(x,.75,2.82),(.28,.07,.08),'silver')
 box(m,'DisplayStand',(0,1.85,3.68),(.2,.9,.2),'metal')
 box(m,'TVFrame',(0,3.12,3.7),(4.7,2.5,.22),'dark',collide=True)
 box(m,'TVScreen',(0,3.12,3.575),(4.45,2.25,.02),'2F5DA8',mat='Neon')
 # Pixel art trophy, no text, brands, characters or borrowed game graphics.
 for xx in (-.55,.55):box(m,'TrophyHandle',(xx,3.37,3.555),(.18,.5,.025),'gold')
 box(m,'TrophyCup',(0,3.42,3.55),(.9,.6,.025),'gold')
 box(m,'TrophyStem',(0,2.99,3.55),(.18,.3,.025),'gold')
 box(m,'TrophyBase',(0,2.78,3.55),(.72,.12,.025),'gold')
 box(m,'Console',(1.15,1.56,3.3),(1.1,.32,.65),'dark')
 box(m,'ConsoleStripe',(1.15,1.6,2.965),(.85,.04,.025),'blue',mat='Neon')
 for x in (-.9,-.1):
  box(m,'Controller',(x,1.51,3.25),(.55,.17,.35),'dark')
  box(m,'ControllerPad',(x-.14,1.61,3.25),(.15,.04,.04),'silver')
  for z in (3.19,3.31):ball(m,'ControllerButton',(x+.13,1.61,z),(.065,.035,.065),'blue')
 return m

def floor_shell():
 m=office();m['name']='Floor'
 # Remove reception/ground-floor planting; reserve the full right-hand lift pocket.
 remove={'ReceptionBench','BenchLeg','BenchBack','IvoryPlanter','Soil','Stem','Foliage','NicheArt','NicheArtFrame'}
 m['parts']=[p for p in m['parts'] if p['name'] not in remove]
 for p in m['parts']:
  n=p['name']
  if n=='Floor':p['c']=rgb('DDE6F5');p['mat']='SmoothPlastic'
  elif n in ('PlankJoint','PlankEnd'):p['c']=rgb('C8D1E2')
  elif n in ('RearBase','SideBase'):p['c']=rgb('2F5DA8')
  elif n in ('Skirting','EntranceColumn'):p['c']=rgb('B0B7C3')
 # Stacked floors: 58x58 slab, local base Y=0; no roof on level 2.
 for p in m['parts']:
  if p['name']=='Floor':p['s']=(58,p['s'][1],58)
  elif p['name']=='PlankJoint':p['s']=(57.7,p['s'][1],p['s'][2])
 # Front aperture exactly 24x9, the game may place glass in it on upper floors.
 for p in m['parts']:
  if p['name']=='EntranceHeader':p['p']=(0,11.375,29.75);p['s']=(60,3.25,.5)
 # Scale the shell down to 12 studs; header bottom set again after scaling below.
 # Max wall/fixture height 13; no roof, no ceiling slab, floor remains Y=0.
 axis_scale(m,1,1.0)
 for p in m['parts']:
  if p['name']=='EntranceHeader':p['p']=(0,11,29.75);p['s']=(60,4,.5)
 for x in (-20.875,20.875):
  box(m,'FrontSideBase',(x,1.1,29.75),(17.75,2.2,.5),'2F5DA8',collide=True)
  box(m,'FrontSideGlazing',(x,5.6,29.75),(17.75,6.8,.08),'B7DDE9',alpha=.64,mat='Glass',collide=True)
  for xx in (-8.805,0,8.805):box(m,'FrontMullion',(x+xx,5.6,29.75),(.14,6.8,.5),'silver')
 for x,z in [(-24,-24),(-25,18),(-23,5)]:plant(m,x,0,z,1.2)
 # Corporate geometric art on opaque rear panel.
 for x,h in [(-5,1.7),(-2,2.5),(1,3.2),(4,4)]:
  box(m,'GrowthArt',(x,5.5,-29.43),(1.1,h,.06),'2F5DA8')
 return m

ASSETS={'Floor':floor_shell(),'FloorDesk':floor_desk(),'ServerRoom':server_room(),'Lounge':lounge()}
LAYOUT=[('Floor',(0,0,0),0)]+[('FloorDesk',(x,0,z),0) for x,z in [(0,-20),(9,-20),(18,-20),(-12,-6),(-2,-6),(8,-6),(18,-6)]]+[('ServerRoom',(26.5,0,-14),-90),('Lounge',(2,0,11),0)]
FULL=model('AstraSecondFloor_ConfigLayout')
for i,(n,p,yaw) in enumerate(LAYOUT):put(FULL,ASSETS[n],p,yaw,n+('_'+str(i) if n=='FloorDesk' else ''))
if __name__=='__main__':
 for n,m in ASSETS.items():export(m,ROOT/'models'/f'{n}.rbxmx')
 export(FULL,ROOT/'Floor_Assembled.rbxmx')
 print({n:len(flatten(m)) for n,m in ASSETS.items()})
