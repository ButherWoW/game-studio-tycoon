"""Original landscape Park prefab. No gameplay code or artifact spawn points."""
from geometry import *
import random
RNG=random.Random(20261105)
PATHS=[];OBSTACLES=[];PLACEMENTS=[]
GRASS='6BBF59';SAND='D9C9A3';WOOD='9C6B3F'

def polar(r,a):
 t=math.radians(a);return (r*math.cos(t),r*math.sin(t))
def dist(a,b):return math.hypot(a[0]-b[0],a[1]-b[1])
def segdist(p,a,b):
 dx,dz=b[0]-a[0],b[1]-a[1];u=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dz)/(dx*dx+dz*dz)))
 return dist(p,(a[0]+u*dx,a[1]+u*dz))

def path(m,points,width,name):
 for i,(a,b) in enumerate(zip(points,points[1:])):
  length=dist(a,b);yaw=math.degrees(math.atan2(b[0]-a[0],b[1]-a[1]))
  box(m,name+'_segment',((a[0]+b[0])/2,.112,(a[1]+b[1])/2),(width,.024,length+.08),SAND,r=rot(y=yaw))
  PATHS.append((a,b,width/2))
 for x,z in points[1:-1]:cyl(m,name+'_roundJoin',(x,.113,z),.026,width,SAND)

def broadleaf():
 m=model('TreeBroadleaf')
 cyl(m,'Trunk',(0,4,0),8,.8,WOOD,collide=True)
 line(m,'BranchLeft',(0,5.8,0),(-1.9,10.2,.5),.4,WOOD)
 line(m,'BranchRight',(0,6.2,0),(1.9,11,-.6),.4,WOOD)
 for p,s,c in [((0,12,0),(6.8,6.2,6.8),'4F9A48'),((-1.8,10.8,.5),(4.5,4.4,4.5),'72B95A'),((1.7,11.7,-.7),(4.7,4.5,4.8),'8BCB67'),((.4,14.2,.1),(4.5,4.8,4.5),'65B052')]:ball(m,'LeafCrown',p,s,c)
 return m

def birch():
 m=model('TreeBirch')
 cyl(m,'BirchTrunk',(0,6.6,0),13.2,.55,'EFE9D9',collide=True)
 for y in (2.6,5.6,9):box(m,'BarkMark',(.28,y,.02),(.025,.18,.32),'5B6357')
 line(m,'BirchFork',(0,9,0),(1.3,13.6,.3),.18,'EFE9D9')
 for p,s,c in [((0,14.2,0),(4.5,6.3,4.5),'88B94D'),((1.2,15,.3),(3.6,5,3.6),'AED267'),((-.8,16.1,-.2),(3.4,5,3.4),'92C25B')]:ball(m,'BirchCanopy',p,s,c)
 return m

def pine():
 m=model('TreePine')
 cyl(m,'PineTrunk',(0,4,0),8,.65,'745439',collide=True)
 for i in range(5):
  w=6.2-i*1.05
  box(m,'EvergreenTier',(0,7.4+i*2.25,0),(w,3.1,w),['327B57','3C8B60','469B66','56AB70','71BD7E'][i])
 return m

def bush():
 m=model('Bush')
 ball(m,'BushLeft',(-.55,.8,0),(2,1.6,1.9),'4F9A48')
 ball(m,'BushRight',(.6,.85,.12),(1.9,1.7,1.9),'8BCB67')
 return m

def flowerbed():
 m=model('Flowerbed')
 cyl(m,'StoneBorder',(0,.18,0),.36,3.8,'C2B59B',collide=True)
 cyl(m,'Soil',(0,.375,0),.04,3.35,'6F583D')
 for i in range(5):
  x,z=polar(1.05,i*72)
  cyl(m,'FlowerStem',(x,.7,z),.6,.07,'4F9A48')
  ball(m,'Petals',(x,1.06,z),(.54,.22,.54),['FFB4BC','FFD77C','E4D8FC','FFD77C','FFB4BC'][i])
  ball(m,'FlowerCentre',(x,1.19,z),(.16,.06,.16),'gold')
 return m

def lamp():
 m=model('ParkLamp')
 cyl(m,'LampFoot',(0,.15,0),.3,.75,'dark',collide=True)
 cyl(m,'LampPole',(0,3.7,0),7.1,.17,'metal',collide=True)
 box(m,'LanternHousing',(0,7.55,0),(.85,1,.85),'dark')
 box(m,'WarmGlass',(0,7.55,0),(.65,.75,.87),'warm',mat='Neon',light=(18,.4,'warm'))
 box(m,'LanternCap',(0,8.13,0),(1.05,.16,1.05),'dark')
 return m

def bin_():
 m=model('ParkBin')
 cyl(m,'BinBody',(0,.8,0),1.6,.95,'406457',collide=True)
 cyl(m,'BinLid',(0,1.64,0),.12,1.05,'dark')
 box(m,'Opening',(0,1.2,.48),(.55,.28,.04),'dark')
 return m

def pond_bridge():
 m=model('PondBridge')
 # Shallow water sits above the shared ground; no Terrain or hidden imported mesh.
 cyl(m,'PondWater',(0,.18,0),.12,1,'6BB7C9')
 m['parts'][-1]['s']=(.12,15,10)
 for i in range(14):
  t=i*TAU/14
  ball(m,'BankStone',(math.cos(t)*7.6,.3,math.sin(t)*5.1),(1.65,.6,1.4),['B9B6A8','CBC5B4','A5AD9E'][i%3],collide=True)
 for x,z in [(-4,-1.5),(4,1.5),(-2,2.7)]:
  cyl(m,'LilyPad',(x,.255,z),.025,.8,'4F9A48')
  ball(m,'WaterFlower',(x+.12,.34,z),(.3,.15,.3),'FFB4BC')
 # 4.4-stud clear deck, gentle arch, small safe step heights.
 for i in range(13):
  z=-6.6+i*1.1;y=.22+.55*math.sin(math.pi*i/12)
  box(m,'BridgePlank',(0,y+.12,z),(4.4,.24,1.06),WOOD,collide=True)
 for x in (-2.4,2.4):
  nodes=[]
  for i in range(5):
   z=-6.6+i*3.3;y=.22+.55*math.sin(math.pi*i/4)
   box(m,'BridgePost',(x,y+1,z),(.18,2,.18),'745439',collide=True)
   nodes.append((x,y+1.9,z))
  for a,b in zip(nodes,nodes[1:]):line(m,'BridgeHandrail',a,b,.13,WOOD)
 return m

ASSETS={'TreeBroadleaf':broadleaf(),'TreeBirch':birch(),'TreePine':pine(),'Bush':bush(),'Flowerbed':flowerbed(),'ParkLamp':lamp(),'ParkBin':bin_(),'PondBridge':pond_bridge()}
PARK=model('Park')
cyl(PARK,'MeadowGround',(0,.04,0),.08,140,GRASS,collide=True)
box(PARK,'SpawnPlaza',(0,.105,0),(16,.05,16),'DED6C5')
# Six curved main paths connect the clear plaza to a 36-stud promenade.
for a in range(0,360,60):
 pts=[polar(r,a+d) for r,d in [(7.5,0),(15,-5),(24,5),(36,0)]]
 path(PARK,pts,6,'GardenWalk')
loop=[polar(36,15*i) for i in range(25)];path(PARK,loop,4.5,'Promenade')
# Twelve exit ports; the six-plot layout uses every other port. Curves are intentionally mild.
for a in range(0,360,30):
 pts=[polar(r,a+d) for r,d in [(36,0),(47,3),(58,-2),(69.25,0)]]
 path(PARK,pts,6,'PlotApproach')
# Separate spur to bridge, off the central plaza and outside coded laptop locations.
path(PARK,[(-25.45,-25.45),(-29,-29),(-34,-27.4)],4.4,'PondWalk')
path(PARK,[(-34,-40.6),(-33,-45),polar(58,238)],4.4,'BridgeExit')
POND=(-34,-34)
put(PARK,ASSETS['PondBridge'],(POND[0],.08,POND[1]))
OBSTACLES.append({'name':'PondBridge','x':-34,'z':-34,'radius':10.5,'kind':'pond','height':3.1})
# Reserves for game-created props. Not exported as geometry or artifact markers.
RESERVES=[('JobBoard',(0,12),4.3),('Pawnshop',(0,-12),5.4)]
for i in range(6):RESERVES.append((f'Bench{i+1}',polar(28,30+i*60),4.3))
# A few guaranteed open lawn clearings; no fixed cartridge spawn objects are created.
MEADOWS=[polar(43,15),polar(46,75),polar(44,135),polar(48,195),polar(46,255),polar(44,315),polar(18,30),polar(18,210)]

def free(p,r,extra=0,meadows=True,boundary=59):
 if math.hypot(*p)+r>boundary:return False
 if abs(p[0])<8+r+1 and abs(p[1])<8+r+1:return False
 if any(segdist(p,a,b)<r+w+extra for a,b,w in PATHS):return False
 if any(dist(p,q)<r+rr+1.1 for _,q,rr in RESERVES):return False
 if any(dist(p,(o['x'],o['z']))<r+o['radius']+1.3 for o in OBSTACLES):return False
 if meadows and any(dist(p,q)<r+6.5 for q in MEADOWS):return False
 return True

def bounds(m):
 ps=flatten(m);lo=[1e9]*3;hi=[-1e9]*3
 for p in ps:
  half=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  for i in range(3):lo[i]=min(lo[i],p['p'][i]-half[i]);hi[i]=max(hi[i],p['p'][i]+half[i])
 return lo,hi

def footprint_radius(m):
 radius=0
 for p in flatten(m):
  if p['shape']=='ball':
   ss=[(v/2)**2 for v in p['s']];r=p['r']
   a=sum(r[j]**2*ss[j] for j in range(3));d=sum(r[6+j]**2*ss[j] for j in range(3));b=sum(r[j]*r[6+j]*ss[j] for j in range(3))
   extent=math.sqrt((a+d+math.sqrt((a-d)**2+4*b*b))/2)
   value=math.hypot(p['p'][0],p['p'][2])+extent
  elif p['shape']=='cyl':
   r=p['r'];extent=math.hypot(r[0],r[6])*p['s'][0]/2+max(p['s'][1:])/2
   value=math.hypot(p['p'][0],p['p'][2])+extent
  else:
   vs,_=meshes(p);value=max(math.hypot(v[0],v[2]) for v in vs)
  radius=max(radius,value)
 return radius

def scale(src,factor):
 m=copy.deepcopy(src)
 for p in m['parts']:
  p['p']=tuple(v*factor for v in p['p']);p['s']=tuple(v*factor for v in p['s'])
 return m

# Deliberately spaced lamps follow the inner promenade, rather than random clumps.
for i,a in enumerate((15,45,105,135,195,225,285,315)):
 p=polar(32,a);radius=footprint_radius(ASSETS['ParkLamp'])
 assert free(p,radius,.15),('lamp-placement',i,p)
 x,z=p;put(PARK,ASSETS['ParkLamp'],(x,.08,z),0,f'ParkLamp_{i+1:02d}')
 OBSTACLES.append({'name':f'ParkLamp_{i+1:02d}','x':x,'z':z,'radius':radius,'kind':'ParkLamp','height':8.21})

# Place varied crowns reproducibly, rejecting paths, prop reserves, water and other crowns.
for i in range(26):
 name=['TreeBroadleaf','TreePine','TreeBroadleaf','TreeBirch'][i%4]
 factor=RNG.uniform(.8,1.12);tree=scale(ASSETS[name],factor);lo,hi=bounds(tree)
 radius=footprint_radius(tree)
 found=None
 for _ in range(12000):
  r=RNG.uniform(16,55.5);a=RNG.uniform(0,360);p=polar(r,a)
  if free(p,radius,.6):found=p;break
 if found is None:continue
 x,z=found;put(PARK,tree,(x,.08,z),RNG.randrange(360),f'{name}_{i+1:02d}')
 OBSTACLES.append({'name':f'{name}_{i+1:02d}','x':x,'z':z,'radius':radius,'kind':'tree','height':hi[1]})
 PLACEMENTS.append({'name':name,'x':x,'z':z,'scale':factor,'height':hi[1]})
# Outer grove fills the park edge; it lies outside the artifact radius52.
# Designed for the current 12-plot ring. Small 6/7-plot servers need ring radius>=102.
for i in range(12):
 name=['TreeBroadleaf','TreePine','TreeBirch'][i%3]
 factor=.9+(.04*(i%4));tree=scale(ASSETS[name],factor);lo,hi=bounds(tree);radius=footprint_radius(tree)
 found=None
 for rr in (64,63,65):
  for offset in (0,2,-2,4,-4):
   p=polar(rr,15+i*30+offset)
   if free(p,radius,.6,boundary=69):found=p;break
  if found:break
 if not found:continue
 x,z=found;nameid=f'{name}_Outer_{i+1:02d}'
 put(PARK,tree,(x,.08,z),i*37,nameid)
 OBSTACLES.append({'name':nameid,'x':x,'z':z,'radius':radius,'kind':'tree','height':hi[1],'outerGrove':True})
 PLACEMENTS.append({'name':name,'x':x,'z':z,'scale':factor,'height':hi[1],'outerGrove':True})

# Amenities around the promenade, kept clear of six laptop seats and all paths.
for kind,target in [('ParkBin',5),('Flowerbed',5),('Bush',10)]:
 lo,hi=bounds(ASSETS[kind]);radius=footprint_radius(ASSETS[kind])
 for i in range(target):
  found=None
  for _ in range(8000):
   p=polar(RNG.uniform(15,55),RNG.uniform(0,360))
   if free(p,radius,.15,meadows=True):found=p;break
  if found is None:break
  x,z=found;put(PARK,ASSETS[kind],(x,.08,z),RNG.randrange(360),f'{kind}_{i+1:02d}')
  OBSTACLES.append({'name':f'{kind}_{i+1:02d}','x':x,'z':z,'radius':radius,'kind':kind,'height':hi[1]})
ASSETS['Park']=PARK
FULL=PARK
if __name__=='__main__':
 for n,m in ASSETS.items():export(m,ROOT/'models'/f'{n}.rbxmx')
 print('Park parts',len(flatten(PARK)),'trees',len(PLACEMENTS),'obstacles',len(OBSTACLES))
