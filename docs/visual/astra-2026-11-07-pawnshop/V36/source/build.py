from geometry import *
from render_geometry import preview
from convex_support import parse,audit,support,np
import subprocess,hashlib
ROOT=Path(__file__).resolve().parents[1]
for folder in ['models','previews']: (ROOT/folder).mkdir(exist_ok=True)
m=model('Pawnshop')
box(m,'Floor',(0,.12,0),(9.6,.24,7.6),'CDBF9D',collide=True,mat='Concrete')
box(m,'BackWall',(0,3.04,-3.6),(8.8,5.6,.30),'E7DEBD',collide=True)
for sign in [-1,1]:
 box(m,'SideWall',(sign*4.55,2.44,-.4),(.30,4.4,6.1),'E7DEBD',collide=True)
 box(m,'FrontPost',(sign*4.55,3.14,2.85),(.30,5.8,.30),'2E6657',collide=True,mat='Wood')
 box(m,'PostCap',(sign*4.55,6.24,2.85),(.30,.40,.30),'D6AA5B')
 # Cap sits in reserved opening of roof: roof split below into independent strips.
box(m,'RoofRear',(0,6.24,-.675),(9.8,.40,6.45),'2E6657',collide=True)
# Rear ends at z2.55; front roof strip starts at3.15, leaves post-cap pockets.
box(m,'RoofFront',(0,6.24,3.525),(9.8,.40,.75),'2E6657',collide=True)
box(m,'RoofMiddle',(0,6.24,2.85),(8.8,.40,.60),'2E6657',collide=True)
for sign in [-1,1]:
 box(m,'RoofSide',(sign*4.8,6.24,2.85),(.2,.40,.60),'2E6657',collide=True)
 # These tiles touch the .3-wide post at x4.4..4.7, roof side x4.7..4.9.
box(m,'Counter',(0,1.44,2.8),(8.4,2.4,.8),'2E6657',collide=True,mat='WoodPlanks')
box(m,'CounterTop',(0,2.76,2.8),(8.8,.24,1.2),'D6AA5B',collide=True,mat='Wood')
box(m,'CounterPanel',(0,1.5,3.225),(7.7,1.4,.05),'E7DEBD')
for x in [-3.6,-2.4,-1.2,0,1.2,2.4,3.6]:
 box(m,'PanelBatten',(x,1.5,3.265),(.035,1.2,.03),'C7BA97')
box(m,'CounterKick',(0,.45,3.225),(8.1,.20,.05),'D6AA5B')
box(m,'Fascia',(0,5.60,3.0),(8.8,.65,.20),'2E6657')
for i in range(11):
 box(m,'AwningStripe',(-4+i*.8,5.11,3.12),(.8,.18,1.32),['EFE4C5','3A816A'][i%2])
for x in [-3.8,0,3.8]:
 box(m,'AwningTie',(x,5.2375,3.0),(.08,.075,.12),'D6AA5B')
# Two shelves with varied-height cartridges and contact labels, no lettering.
for y in [1.2,3.2]:
 box(m,'DisplayShelf',(0,y,-2.90),(7.7,.16,.75),'8D6648',mat='Wood')
 for i,x in enumerate([-3,-1.5,0,1.5,3]):
  h=[.76,.90,.68,.82,.72][i]
  box(m,'Cartridge',(x,y+.08+h/2,-2.85),(.78,h,.30),['3F87BA','D77D7E','D6AA5B','6B9D73','8F7FB3'][i])
  box(m,'CartridgeLabel',(x,y+.08+h*.58,-2.688),(.48,.25,.024),'F3EBD4')
  box(m,'CartridgeNotch',(x,y+.08+h-.09,-2.67),(.18,.08,.012),'283345')
# Point of sale, and boxed cartridges on the counter.
box(m,'RegisterBase',(-2.7,2.94,2.70),(.90,.12,.65),'283345')
box(m,'RegisterBody',(-2.7,3.21,2.68),(.72,.42,.36),'366C62')
box(m,'RegisterScreen',(-2.7,3.21,2.87),(.54,.26,.02),'87CEBD')
for x,col in [(1.5,'D77D7E'),(2.65,'3F87BA')]:
 box(m,'CounterCartridge',(x,3.22,2.70),(.70,.68,.26),col)
 box(m,'CounterLabel',(x,3.26,2.844),(.42,.25,.028),'F3EBD4')
# Roof sign with large original cartridge and coin pictograms.
for x in [-1.4,1.4]:
 box(m,'SignPost',(x,6.67,0),(.13,.46,.13),'D6AA5B',mat='Metal')
box(m,'SignPanel',(0,7.55,0),(4.6,1.30,.24),'1F483F')
box(m,'SignTopTrim',(0,8.235,0),(4.6,.07,.24),'D6AA5B')
box(m,'SignBottomTrim',(0,6.865,.15),(4.6,.07,.06),'D6AA5B')
box(m,'SignCartridge',(-.95,7.55,.19),(1.0,1.04,.14),'69B2AF')
box(m,'SignLabel',(-.95,7.63,.275),(.68,.43,.03),'F4E6BF')
box(m,'SignSlot',(-.95,7.15,.275),(.50,.10,.03),'1F483F')
cyl(m,'SignCoin',(.95,7.55,.20),.16,.99,'EBC165',r=rot(y=90))
cyl(m,'CoinFace',(.95,7.55,.295),.03,.69,'F6D98C',r=rot(y=90))
# One shadowless practical light, tucked above trading window.
box(m,'WindowLamp',(0,5.90,2.0),(2.3,.12,.30),'FFE4B0',mat='Neon',light=(12,.40,'FFE4B0'))
for x in [-.8,.8]:
 box(m,'LampMount',(x,6.0,2.0),(.05,.08,.12),'D6AA5B')
path=ROOT/'models/Pawnshop.rbxmx';export(m,path)
project=ROOT/'source/build.project.json';project.write_text(json.dumps({'name':'Pawnshop','tree':{'$path':str(path)}}))
subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(project),'-o',str(path.with_suffix('.rbxm'))],check=True,capture_output=True);project.unlink()
parts=parse(path);cert,bad=audit(parts);assert not bad,bad
lo=[min(support(p,-np.eye(3)[i])[i]for p in parts)for i in range(3)]
hi=[max(support(p,np.eye(3)[i])[i]for p in parts)for i in range(3)]
assert hi[0]-lo[0]<=10.000001 and hi[2]-lo[2]<=8.000001
assert abs(lo[1])<1e-6 and abs(lo[0]+hi[0])<1e-6 and abs(lo[2]+hi[2])<1e-6
report={'parts':len(parts),'dimensionsXYZ':[hi[i]-lo[i]for i in range(3)],'baseY':lo[1],'pivotXYZ':[0,0,0],'front':'+Z','pairs':len(cert),'overlaps':bad,'lights':1,'lightShadows':False,'scripts':0,'externalMeshTexture':0,'runtimeTested':False}
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n')
(ROOT/'SEPARATION_CERTIFICATES.json').write_text(json.dumps(cert,indent=2)+'\n')
for label,yaw in [('Front',0),('ThreeQuarter',35),('Rear',150)]:
 preview(m['parts'],ROOT/'previews'/('Pawnshop_'+label+'.png'),yaw=yaw,elev=18,target=(0,4.0,0),span=14.5,W=1100,H=1000)
print(json.dumps(report,indent=2))
