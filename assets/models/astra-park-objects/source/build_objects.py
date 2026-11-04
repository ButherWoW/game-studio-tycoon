"""Original native Roblox Parts; no gameplay scripts, imported meshes or textures."""
from geometry import *
WOOD='9C6B3F';TRIM='E3BB85';IRON='344C49';BLUE='3D7BFF';STONE='D7CFBA'
def bench():
 m=model('ParkBench')
 for x in (-2.45,2.45):
  for z in (.25,1.1):box(m,'BenchLeg',(x,.85,z),(.22,1.7,.22),IRON,collide=True,mat='Metal')
  box(m,'ArmPost',(x,2.1,.8),(.16,1.05,.16),IRON)
  box(m,'ArmRest',(x,2.65,.7),(.24,.15,1.35),IRON)
 box(m,'PcSeat',(0,1.8,.65),(4.6,.3,1.15),WOOD,cls='Seat',collide=True,mat='WoodPlanks')
 for y in (2.3,2.8,3.3):box(m,'BackSlat',(0,y,1.34),(5.45,.34,.22),WOOD,mat='WoodPlanks',collide=True)
 for x in (-2.4,2.4):box(m,'BackSupport',(x,2.5,1.28),(.15,1.7,.16),IRON)
 for x in (-1.05,1.05):box(m,'TableFoot',(x,.13,-.85),(.65,.26,1.05),IRON,collide=True);box(m,'TableLeg',(x,1.35,-.85),(.15,2.45,.15),IRON,collide=True)
 box(m,'TableTop',(0,2.65,-.85),(3.25,.24,1.2),WOOD,collide=True,mat='WoodPlanks')
 box(m,'LaptopBase',(0,2.82,-.78),(1.65,.1,.82),'dark')
 box(m,'Keyboard',(0,2.88,-.68),(1.36,.025,.35),'silver')
 box(m,'Trackpad',(0,2.885,-.42),(.45,.03,.16),'metal')
 box(m,'LaptopLid',(0,3.36,-1.19),(1.7,1.04,.12),'dark')
 box(m,'LaptopScreen',(0,3.36,-1.12),(1.45,.8,.025),'cyan',mat='Neon')
 for x,y,w in [(-.35,3.55,.5),(.12,3.32,.85),(-.2,3.12,.8)]:box(m,'ScreenBlocks',(x,y,-1.102),(w,.08,.012),'blue')
 return m

def board():
 m=model('JobBoard')
 for x in (-2.9,2.9):
  box(m,'Post',(x,3.1,0),(.35,6.2,.48),WOOD,collide=True,mat='Wood')
  box(m,'PostFoot',(x,.12,0),(.7,.24,.9),IRON,collide=True)
 box(m,'Board',(0,4.15,0),(6.4,3.9,.3),'B68B5B',collide=True)
 for x in (-3.25,3.25):box(m,'FrameSide',(x,4.15,.04),(.22,4.25,.46),WOOD,mat='Wood')
 for y in (2.08,6.22):box(m,'FrameHorizontal',(0,y,.04),(6.72,.22,.46),WOOD,mat='Wood')
 box(m,'Header',(0,6.62,0),(6.9,.55,.7),BLUE)
 # Abstract pinned paper sheets: no words, logos or brands.
 for i,x in enumerate((-2.1,0,2.1)):
  box(m,'JobPaper',(x,4.2,.18),(1.65,2.65,.04),['FFF2C4','E8F1E8','BFE3F3'][i])
  ball(m,'Pin',(x,5.36,.23),(.14,.14,.1),'gold')
  box(m,'TaskIcon',(x,4.65,.21),(.55,.55,.025),['blue','green','pink'][i])
  for y,w in ((4.05,1.12),(3.7,.9),(3.35,1.12)):box(m,'TaskLine',(x,y,.211),(w,.09,.025),'9FADAF')
 return m

def pawn():
 m=model('Pawnshop')
 box(m,'Floor',(0,.12,0),(8.8,.24,6.8),'D6C9A9',collide=True)
 box(m,'BackWall',(0,3,-3.1),(8.4,5.8,.3),'E7D9B9',collide=True)
 for x in (-4,4):
  box(m,'SideWall',(x,2.4,-.7),(.3,4.5,4.8),'E7D9B9',collide=True)
  box(m,'FrontPost',(x,3.2,2.4),(.3,6,.3),WOOD,collide=True)
 box(m,'Roof',(0,6.35,0),(9.7,.45,7.7),'3B7867',collide=True)
 box(m,'Counter',(0,1.55,2.25),(7.5,2.6,.85),WOOD,collide=True,mat='WoodPlanks')
 box(m,'CounterTop',(0,2.98,2.25),(8,.25,1.3),TRIM,collide=True)
 box(m,'CounterAccent',(0,1.7,2.69),(6.7,.45,.03),'gold')
 for y in (1.3,3.4):
  box(m,'BackShelf',(0,y,-2.5),(7.2,.18,.9),WOOD)
  for i,x in enumerate((-2.5,-1.25,0,1.25,2.5)):
   box(m,'TradeCartridge',(x,y+.48,-2.45),(.73,.78,.25),['blue','pink','green','gold','purple'][i])
   box(m,'CartridgeLabel',(x,y+.5,-2.31),(.48,.32,.02),'white')
 box(m,'DisplayCartridge',(2.7,3.45,2.3),(.8,.7,.25),'blue')
 box(m,'DisplayLabel',(2.7,3.46,2.44),(.5,.3,.025),'gold')
 box(m,'SignPanel',(0,5.3,2.58),(4.4,1.35,.18),'dark')
 # Two large cartridge and coin pictograms, without any text.
 box(m,'SignCartridge',(-.8,5.3,2.7),(.8,.95,.08),'blue')
 box(m,'SignLabel',(-.8,5.37,2.75),(.55,.4,.025),'white')
 cyl(m,'SignCoin',(.8,5.3,2.72),.1,.95,'gold',r=rot(y=90))
 box(m,'CounterLamp',(0,5.9,1.7),(1.4,.1,.5),'warm',mat='Neon',light=(12,.45,'warm'))
 return m

def fountain():
 m=model('Fountain')
 cyl(m,'Foundation',(0,.15,0),.3,10.8,STONE,collide=True)
 cyl(m,'BasinWater',(0,.43,0),.12,9.8,'72CDDC')
 # Segmented annular rim, open water center, no opaque disk hiding water.
 for i in range(24):
  t=TAU*i/24;x,z=math.cos(t)*5.05,math.sin(t)*5.05
  box(m,'BasinRim',(x,.52,z),(.62,.65,1.38),STONE,r=rot(y=-math.degrees(t)),collide=True)
 cyl(m,'Pedestal',(0,1.35,0),1.9,1.3,'B2C1B5',collide=True)
 cyl(m,'LowerBowl',(0,2.3,0),.35,4.1,STONE,collide=True)
 cyl(m,'LowerWater',(0,2.49,0),.04,3.7,'72CDDC')
 cyl(m,'UpperStem',(0,3.1,0),1.1,.7,'B2C1B5',collide=True)
 cyl(m,'UpperBowl',(0,3.68,0),.3,2.25,STONE)
 cyl(m,'UpperWater',(0,3.85,0),.04,1.95,'72CDDC')
 ball(m,'JetTop',(0,4.6,0),(.36,.6,.36),'A4E6EB')
 cyl(m,'Jet',(0,4.18,0),.6,.15,'A4E6EB')
 for i in range(6):
  t=TAU*i/6
  for r,y in ((1.2,3.65),(1.55,3.1),(2.05,2.6),(2.4,1.9),(2.65,1.1)):
   ball(m,'WaterCascade',(r*math.cos(t),y,r*math.sin(t)),(.12,.48,.12),'A4E6EB')
 return m
ASSETS={n:f() for n,f in [('ParkBench',bench),('JobBoard',board),('Pawnshop',pawn),('Fountain',fountain)]}
if __name__=='__main__':
 for n,m in ASSETS.items():export(m,ROOT/'models'/f'{n}.rbxmx')
