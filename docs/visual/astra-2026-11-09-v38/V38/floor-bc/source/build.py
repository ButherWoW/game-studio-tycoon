from geometry import *
from convex_support import parse,audit,support,np
from render_geometry import preview
import subprocess,json,os
ROOT=Path(__file__).resolve().parents[1]
for folder in ['models','previews']:(ROOT/folder).mkdir(exist_ok=True)
def gallery():
 m=model('GameGallery');box(m,'Backing',(0,2.5,-.16),(9.8,5,.08),'E4D2B2')
 for x in [-4.83,4.83]:box(m,'OuterSide',(x,2.5,-.04),(.14,5,.16),'9E7249',mat='Wood')
 for y in [.07,4.93]:box(m,'OuterRail',(0,y,-.04),(9.52,.14,.16),'9E7249',mat='Wood',light=(10,.15,'FFD9A0') if y>4 else None)
 for idx,x in enumerate([-2.9,0,2.9]):
  for dx in [-1.225,1.225]:box(m,'PictureFrameSide',(x+dx,2.8,-.035),(.1,2.65,.13),'A97C4F',mat='Wood')
  for y in [1.425,4.175]:box(m,'PictureFrameRail',(x,y,-.035),(2.55,.1,.13),'A97C4F',mat='Wood')
  box(m,'Canvas',(x,2.8,-.065),(2.35,2.65,.05),['7FC6DE','385369','302A60'][idx])
  # Original shallow game artwork; no text or external image IDs.
  if idx==0:
   box(m,'Meadow',(x,1.9,-.01),(2.20,.70,.04),'6C9D64')
   for dx,y,w,h in [(-.60,2.75,.38,1.0),(0,2.62,.65,.74),(.60,2.90,.38,1.3)]:
    box(m,'CastleTower',(x+dx,y,.035),(w,h,.04),'E9DCC1')
    box(m,'CastleCrenel',(x+dx,y+h/2+.10,.035),(w*.65,.16,.04),'B89E7D')
   box(m,'CastleGate',(x,2.5,.08),(.22,.36,.04),'9F7753');ball(m,'Sun',(x-.70,3.75,.035),(.34,.34,.04),'FFDD7B')
  elif idx==1:
   box(m,'RacingTrack',(x,2.65,-.01),(1.1,2.2,.04),'B7B2A1')
   for dx in [-.78,.78]:
    for y in [1.9,2.45,3.0,3.55]:box(m,'Kerb',(x+dx,y,.035),(.19,.30,.04),'C8705D' if y<3 else 'EBDABF')
   box(m,'CarBody',(x,2.55,.08),(.60,.9,.04),'D8A64A');box(m,'CarCanopy',(x,2.65,.125),(.38,.38,.04),'78C4DC')
   for dx in [-.40,.40]:
    for y in [2.25,2.85]:box(m,'CarWheel',(x+dx,y,.08),(.16,.24,.04),'2E343E')
  else:
   ball(m,'Planet',(x-.5,3.55,.015),(.7,.7,.04),'AD86CE')
   box(m,'Portal',(x+.5,3.45,.015),(.45,1.0,.04),'6DCBDF',mat='Neon')
   for k in range(4):box(m,'SpaceStep',(x-.7+k*.4,1.8+k*.3,.015),(.28,.15,.04),['E9B75E','D38975','A789CE','62C0D0'][k])
   for dx,y in [(-.9,2.8),(.8,2.3),(.1,3.9)]:ball(m,'Star',(x+dx,y,.015),(.09,.09,.04),'FFE7A1')
  box(m,'AwardShelf',(x,.30,.04),(1.70,.10,.30),'AE8053',mat='Wood')
  box(m,'AwardBase',(x,.4,.04),(.50,.10,.12),'BA925B',mat='Metal')
  box(m,'AwardStem',(x,.60,.04),(.12,.30,.08),'D4B16F',mat='Metal')
  ball(m,'AwardEmblem',(x,.95,.04),(.40,.40,.08),['E0B360','79CBDB','B89DD3'][idx],mat='Metal')
 for x in [-4.5,4.5]:
  for dx,h in [(-.10,1.8),(.10,2.2)]:box(m,'AcousticSlat',(x+dx,2.8,-.02),(.12,h,.16),'4F6384')
 for q in m['parts']:q['p']=(q['p'][0],q['p'][1],q['p'][2]+.005)
 return m

def corner():
 m=model('PanoramaCorner');part(m,'Rug',(0,.02,0),(.04,9.6,5.6),'55516D','cyl',rot(z=90))
 for cx in [-2.65,2.65]:
  for dx in [-.83,.83]:
   for z in [-.65,.65]:box(m,'ChairFoot',(cx+dx,.18,z),(.16,.28,.16),'9D754C',mat='Wood')
  box(m,'ChairBase',(cx,.45,.01),(2.20,.26,1.90),'AA8055',mat='Wood')
  box(m,'SeatCushion',(cx,.77,.02),(1.75,.38,1.45),'39867B')
  box(m,'BackCushion',(cx,1.65,-.91),(2.20,1.38,.36),'3A857D')
  for dx in [-1,1]:box(m,'Armrest',(cx+dx,1.10,.04),(.20,.75,1.50),'31776E')
  box(m,'ThrowPillow',(cx,1.35,-.62),(.9,.65,.22),'E4D4A9')
 # Narrow bookshelf behind left chair, avoiding the right panorama window.
 for x in [-4.55,-2.45]:box(m,'BookcaseSide',(x,1.98,-2.55),(.12,3.88,.30),'A77B50',mat='Wood')
 for y in [.10,1.1,2.1,3.1,3.86]:box(m,'BookcaseShelf',(-3.5,y,-2.55),(1.98,.12,.30),'B68C60',mat='Wood')
 for row,y in enumerate([.57,1.57,2.57]):
  for k,c in enumerate(['538A9B','8978A7','C69E72','708C7B']):box(m,'BookSpine',(-4.24+k*.39,y,-2.55),(.26,.8,.24),c)
 cyl(m,'TableBase',(0,.18,.30),.28,1.05,'394350',mat='Metal')
 cyl(m,'TableStem',(0,.55,.30),.46,.36,'394350',mat='Metal')
 cyl(m,'TableTop',(0,.88,.30),.20,1.75,'BB9468',mat='Wood')
 box(m,'TableBookPages',(-.32,1.06,.30),(.55,.16,.42),'E8DFCC')
 box(m,'TableBookCover',(-.32,1.155,.30),(.60,.03,.46),'937CAA')
 cyl(m,'LampBase',(.40,1.04,.30),.12,.30,'9F7D50',mat='Metal')
 cyl(m,'LampStem',(.40,1.28,.30),.36,.08,'9F7D50',mat='Metal')
 ball(m,'LampGlobe',(.40,1.68,.30),(.42,.44,.42),'FFE4A6',mat='Neon',light=(12,.18,'FFD9A0'))
 cyl(m,'PlantPot',(4.14,.44,-1.95),.80,.86,'384D5C')
 cyl(m,'Soil',(4.14,.855,-1.95),.03,.72,'6B533D')
 box(m,'PlantStem',(4.14,1.7975,-1.95),(.055,1.855,.055),'5D8055')
 for dx,y in [(-.253,1.25),(.253,1.65),(-.253,2.10),(.253,2.55)]:ball(m,'Leaf',(4.14+dx,y,-1.95),(.45,.11,.55),'7CA16E')
 ball(m,'PlantTop',(4.14,2.95,-1.95),(.35,.45,.35),'96B283')
 return m

reports=[]
for m in [gallery(),corner()]:
 name=m['name'];assert len(m['parts'])<=100,(name,len(m['parts']))
 for q in m['parts']:q['collide']=name=='PanoramaCorner' and q['name'] in ['ChairBase','SeatCushion','BackCushion','Armrest','TableTop','PlantPot']
 path=ROOT/'models'/(name+'.rbxmx');export(m,path);ps=parse(path);cert,bad=audit(ps)
 if bad:print(name,'BAD',bad,flush=True)
 assert not bad,(name,bad)
 lo=[min(support(q,-np.eye(3)[i])[i]for q in ps)for i in range(3)];hi=[max(support(q,np.eye(3)[i])[i]for q in ps)for i in range(3)]
 assert min(lo)>=-5 and hi[0]<=5 and hi[1]<=5 and hi[2]<=3
 p=ROOT/'source'/'build.project.json';p.write_text(json.dumps({'name':name,'tree':{'$path':str(path)}}));subprocess.run([os.environ.get('ROJO','/Users/erland/.local/gst-tools/rojo'),'build',str(p),'-o',str(path.with_suffix('.rbxm'))],capture_output=True,check=True);p.unlink()
 reports.append({'name':name,'parts':len(ps),'bounds':[lo,hi],'certifiedPairs':len(cert),'overlaps':bad,'pointLights':1,'shadows':False,'scripts':0,'externalMeshesTextures':0,'StudioTested':False});(ROOT/(name+'_CERTIFICATES.json')).write_text(json.dumps(cert,indent=2)+'\n')
 for label,yaw in [('Front',0),('ThreeQuarter',30)]:preview(m['parts'],ROOT/'previews'/(name+'_'+label+'.png'),yaw=yaw,elev=20,target=(0,2.4,0) if name=='GameGallery' else (0,1.6,0),span=11.5,W=1100,H=750)
(ROOT/'VALIDATION.json').write_text(json.dumps(reports,indent=2)+'\n');print(json.dumps(reports,indent=2))
