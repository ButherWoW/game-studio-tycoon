"""V7 original seasonal props plus a preview-only three-storey OfficeBuilding."""
from geometry import *
from office_base import office
from floor_base import floor_shell
from sky_base import shell
import subprocess

def pumpkin():
 m=model('Pumpkin')
 # Plump lobes and a friendly light face, never scary.
 ball(m,'PumpkinCore',(0,1.0,0),(2.55,2,2.45),'E8892A')
 for i in range(8):
  t=i*TAU/8
  ball(m,'PumpkinLobe',(.66*math.sin(t),1,.64*math.cos(t)),(1.32,1.95,1.32),['F69B34','F7A23D','ED8F27','F8A538'][i%4])
 line(m,'Stem',(0,1.86,0),(.16,2.48,-.08),.24,'668245',mat='Wood')
 line(m,'Vine',(.06,2.2,0),(.41,2.24,.14),.075,'74A454')
 ball(m,'StemLeaf',(.43,2.25,.15),(.52,.12,.3),'74A454')
 for x in [-.48,.48]:
  ball(m,'FriendlyEye',(x,1.22,1.224),(.23,.34,.085),'FFD572',mat='Neon')
  ball(m,'EyeGlint',(x-.04,1.29,1.269),(.07,.08,.018),'FFF3C4',mat='Neon')
 pts=[(-.55,.78,1.24),(-.28,.65,1.25),(0,.61,1.255),(.28,.65,1.25),(.55,.78,1.24)]
 for i,(a,b) in enumerate(zip(pts,pts[1:])):line(m,'Smile',a,b,.1,'FFD572',mat='Neon',**({'light':(5,.22,'FFD572')} if i==0 else {}))
 return m

def sign():
 m=model('HalloweenSign')
 for x in [-.92,.92]:
  box(m,'Foot',(x,.07,0),(.55,.14,.75),'383247')
  box(m,'Post',(x,1.65,0),(.16,3.16,.18),'383247')
 box(m,'Shield',(0,3,0),(2.8,1.9,.21),'383247')
 for x in [-1.32,1.32]:box(m,'OrangeOutline',(x,3,.12),(.08,1.73,.045),'FF9A32',mat='Neon')
 for y in [2.11,3.89]:box(m,'OrangeOutline',(0,y,.12),(2.72,.08,.045),'FF9A32',mat='Neon')
 # Original cheerful pumpkin pictogram made of physical shapes; no lettering.
 for x in [-.36,0,.36]:ball(m,'PumpkinIcon',(x,3,.16),(.88,1.12,.1),'FF9A32',mat='Neon')
 box(m,'IconStem',(.06,3.68,.17),(.13,.33,.06),'A1D45C',r=rot(z=-15),mat='Neon')
 for x in [-.25,.25]:ball(m,'IconEye',(x,3.13,.225),(.12,.17,.025),'383247')
 line(m,'IconSmile',(-.3,2.89,.227),(0,2.77,.227),.07,'383247');line(m,'IconSmile',(0,2.77,.227),(.3,2.89,.227),.07,'383247')
 box(m,'Glow',(0,3,-.08),(2.5,1.6,.03),'FF9A32',mat='Neon',light=(6,.28,'FF9A32'))
 return m

def tree():
 m=model('HolidayTree')
 cyl(m,'Trunk',(0,.8,0),1.6,.6,'9C6B3F',mat='Wood')
 # Stepped evergreen tiers, eight-point horizontal outlines using rotated native cuboids.
 for i,(w,y,h) in enumerate([(5.1,2.8,2.7),(4.2,4.65,2.3),(3.25,6.3,2.05),(2.3,7.8,1.8),(1.25,9.0,1.25)]):
  box(m,'EvergreenTier',(0,y,0),(w,h,w),'3D8D62')
  # Trunk-side tier is compact and bounded, all ornaments inside6x6 footprint.
  for j in range(6):
   a=j*TAU/6+i*.37;r=(w/2+.08)/max(abs(math.sin(a)),abs(math.cos(a)))
   ball(m,'Ornament',(math.cos(a)*r,y-h*.28,math.sin(a)*r),(.35,.35,.35),['FF6EB4','FFC93C','79D5ED'][j%3],mat='Neon')
 for i in range(25):
  y=1.9+i*.285;a=i*.98
  tiers=[(5.1,2.8,2.7),(4.2,4.65,2.3),(3.25,6.3,2.05),(2.3,7.8,1.8),(1.25,9.,1.25)]
  widths=[w for w,cy,h in tiers if cy-h/2<=y<=cy+h/2];w=max(widths) if widths else 1.25;r=(w/2+.08)/max(abs(math.sin(a)),abs(math.cos(a)))
  ball(m,'FairyBulb',(math.sin(a)*r,y,math.cos(a)*r),(.11,.11,.11),'FFD9A0',mat='Neon')
 # Original eight-ray faceted star topper.
 for a in [0,45,90,135]:box(m,'StarRay',(0,10.22,0),(.15,1.05,.14),'gold',r=rot(z=a),mat='Neon',**({'light':(10,.3,'warm')} if a==0 else {}))
 ball(m,'StarCenter',(0,10.22,.04),(.38,.38,.2),'gold',mat='Neon')
 for x,z,c,w in [(-1.6,1.55,'blue',1.15),(1.3,1.8,'pink',1.05),(.4,-1.8,'gold',.85)]:
  h=.75 if c!='pink' else 1.05
  box(m,'Gift',(x,h/2,z),(w,h,w),c)
  box(m,'GiftRibbonFront',(x,h/2,z+w/2+.012),(.12,h,.024),'white')
  box(m,'GiftRibbonTop',(x,h+.012,z),(.12,.024,w),'white')
 return m

def building():
 m=model('OfficeBuilding');factor=39.6/42
 for level,base in enumerate([office(),floor_shell(),shell()]):
  c=model(['OfficeExterior','FloorExterior','TopExterior'][level])
  ps=flatten(base)
  # Building is exterior preview/move art. Remove furniture, plants, ceiling lights and floor joints.
  accepted=['Floor','RearBase','RearHeader','CentralWall','RearWindow','WindowMullion','WindowTransom','SideBase','SideHeader','SideGlass','SideMullion','SideTransom','Skirting','EntranceHeader','EntranceColumn','FrontSideBase','FrontSideGlazing','FrontMullion','SideWallBand','PanoramicSide','SideNeon','RearWallBand','PanoramicRear','RearMullion','RearNeon','EntranceLintel','FrontBand','FrontGlazing','Roof']
  for p in ps:
   if p['name'] not in accepted:continue
   p=copy.deepcopy(p);p.pop('light',None)
   p['p']=(p['p'][0],(p['p'][1]+level*14)*factor,p['p'][2]);p['s']=(p['s'][0],p['s'][1]*factor,p['s'][2]);c['parts'].append(p)
  # Thin continuous separator fills original inter-storey clearance13..14.
  if level<2:box(c,'StoreySeparator',(0,(level*14+13.5)*factor,0),(60,factor,60),'B0B7C3')
  if level==0:
   # Accepted ground shell originally had an open full front. Add matching facade side glazing.
   for x in [-21,21]:
    box(c,'GroundFacadeBase',(x,.55*factor,29.75),(18,1.1*factor,.5),'white')
    box(c,'GroundFacadeGlass',(x,5.05*factor,29.75),(18,7.9*factor,.08),'B7DDE9',alpha=.64,mat='Glass')
   box(c,'GroundLintel',(0,10*factor,29.75),(60,2*factor,.5),'white')
  if level>0:box(c,'PreviewEntryGlass',(0,(level*14+4.5)*factor,29.75),(24,9*factor,.08),'91B5CA',alpha=.76,mat='Glass')
  for p in c['parts']:p['name']=f'L{level+1}_'+p['name']
  m['children'].append(c)
 # Ground slab provides the outer preview Model's own valid PrimaryPart at base origin.
 box(m,'PreviewFoundation',(0,.005,0),(58,.01,58),'C8A27A')
 return m

ASSETS={m['name']:m for m in [pumpkin(),sign(),tree(),building()]}
# Furniture/props have exact footprint-center pivots. Building keeps world origin.
def bounds(ps):
 lo=[float('inf')]*3;hi=[-float('inf')]*3
 for p in ps:
  h=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  for i in range(3):lo[i]=min(lo[i],p['p'][i]-h[i]);hi[i]=max(hi[i],p['p'][i]+h[i])
 return lo,hi
for n,m in ASSETS.items():
 if n=='OfficeBuilding':continue
 lo,hi=bounds(m['parts']);off=(-(lo[0]+hi[0])/2,-lo[1],-(lo[2]+hi[2])/2)
 for p in m['parts']:p['p']=add(p['p'],off)
if __name__=='__main__':
 for n,m in ASSETS.items():
  dest=ROOT/'models'/f'{n}.rbxmx';export(m,dest);pr=ROOT/'source'/'convert.project.json';pr.write_text(json.dumps({'name':n,'tree':{'$path':str(dest)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(pr),'-o',str(dest.with_suffix('.rbxm'))],check=True)
 pr.unlink()
