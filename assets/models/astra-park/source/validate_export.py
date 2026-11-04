from build_park import *
import itertools,subprocess
from PIL import Image,ImageDraw,ImageFont

def occupied(point,existing=()):
 if math.hypot(*point)<9:return True
 if any(dist(point,(o['x'],o['z']))<o['radius']+5 for o in OBSTACLES):return True
 if any(dist(point,q)<r+5 for _,q,r in RESERVES):return True
 if any(dist(point,q)<14 for q in existing):return True
 return False

def grass(point):return all(segdist(point,a,b)>w+.5 for a,b,w in PATHS)

report={'sourceCommit':'5cf9cd6','parkParts':len(flatten(PARK)),'trees':len(PLACEMENTS),'species':{},'components':{},'checks':[],'studioTested':False}
assert len(flatten(PARK))<=600
assert len(PLACEMENTS)>=18
for n in ('TreeBroadleaf','TreePine','TreeBirch'):report['species'][n]=sum(p['name']==n for p in PLACEMENTS);assert report['species'][n]>0
for p in PLACEMENTS:assert 10<=p['height']<=25
for n,m in ASSETS.items():
 lo,hi=bounds(m);dims=[round(hi[i]-lo[i],5) for i in range(3)]
 report['components'][n]={'parts':len(flatten(m)),'dimensionsXYZ':dims,'min':lo,'max':hi,'pointLights':sum(bool(p.get('light')) for p in flatten(m))}
 assert abs(lo[1])<1e-6,(n,lo)
 assert len(flatten(m))<=(600 if n=='Park' else 250)
 for pp in flatten(m):
  assert min(pp['s'])>=.001
  r=pp['r']
  for i in range(3):
   for j in range(3):assert abs(sum(r[i*3+k]*r[j*3+k] for k in range(3))-(1 if i==j else 0))<1e-6
assert report['components']['Park']['dimensionsXYZ'][0]==140
assert report['components']['Park']['dimensionsXYZ'][2]==140
# Geometry above walkable ground respects clear central square and existing interactive props.
for o in OBSTACLES:
 p=(o['x'],o['z']);r=o['radius']
 assert not(abs(p[0])<8+r and abs(p[1])<8+r),('spawn-clearance',o['name'])
 for n,q,rr in RESERVES:assert dist(p,q)>=r+rr+1,('interactive',o['name'],n)
 if o['name']!='PondBridge':
  assert math.hypot(*p)+r<=(69.001 if o.get('outerGrove') else 59.001)
  for a,b,w in PATHS:assert segdist(p,a,b)>=r+w-.001,('path',o['name'])
for a,b in itertools.combinations(OBSTACLES,2):assert dist((a['x'],a['z']),(b['x'],b['z']))>=a['radius']+b['radius']+1,('peer',a['name'],b['name'])
# All props fit inside landscape radius69; with 12 plots the nearest front is >122.
assert all(math.hypot(o['x'],o['z'])+o['radius']<=69.001 for o in OBSTACLES)
report['plotIntegration']={'designPlotCount':12,'current12PlotRadius':12*80/(2*math.pi),'minimumRecommendedPlotRingRadius':102,'smallServerNote':'WorldService currently gives 6/7 plots radius90 (front60), which overlaps a diameter140 park. Dev2 must increase minimum ring radius or adapt landscape before use on such servers.'}
assert sum(bool(p.get('light')) for p in flatten(PARK))==8
# Measure grass-only free points across multiple radial bands, not a ring of fixed spawns.
rng=random.Random(1505);total=20000;valid=grassCount=0;bands=[0,0,0];bandTotal=[0,0,0]
for _ in range(total):
 radius=math.sqrt(rng.uniform(100,52**2));p=polar(radius,rng.uniform(0,360));j=0 if radius<24 else 1 if radius<38 else 2;bandTotal[j]+=1
 if not occupied(p):
  valid+=1
  if grass(p):grassCount+=1;bands[j]+=1
assert valid/total>.2
assert grassCount/total>.08
assert all(v>30 for v in bands)
# Approximate actual service rejection sampling: 6 cartridges, spacing14, clearance5, 40 tries.
complete=0;placedCounts=[]
for trial in range(200):
 rr=random.Random(10000+trial);selected=[]
 for _ in range(6):
  for _ in range(40):
   p=polar(math.sqrt(rr.uniform(100,52**2)),rr.uniform(0,360))
   if not occupied(p,selected):selected.append(p);break
 placedCounts.append(len(selected));complete+=len(selected)==6
assert complete>=180,('artifact-sampling',complete)
report['artifactSampling']={'areaMin':10,'areaMax':52,'clearance':5,'spacing':14,'triesPerSpot':40,'sampleCount':total,'freeAllSurfacesFraction':valid/total,'freeGrassFraction':grassCount/total,'freeGrassSamplesByRadius':{'10-24':bands[0],'24-38':bands[1],'38-52':bands[2]},'trials':200,'trialsWithAllSixPlaced':complete,'note':'Offline geometric simulation using conservative obstacle circles. Not a Studio raycast/play test. No fixed spawn points are exported.'}
report['checks']=['140-stud ground diameter','clear 16x16 spawn plaza above shared ground','three tree species; all installed trees height10..25','no footprint overlaps between landscape props','no tall props in six bench/board/pawn reserves','no tree/bush/bed/light/bin footprints on paths','bridge is deliberate walkable crossing above pond','all props within radius69; clear of current 12-plot ring; explicit min-ring102 requirement for 6/7 plots','grass clearings in inner/middle/outer artifact bands','one shadowless light per lamp','part budgets/transforms/base pivots','all native models round-tripped through Rojo']
for n,m in ASSETS.items():export(m,ROOT/'models'/f'{n}.rbxmx')
# Reconstruct each serialized Model pivot from its real PrimaryPart and PivotOffset.
# Compare with source hierarchy to verify zero-extra-Part pivot optimization.
def readcf(e):
 return tuple(float(e.find(k).text) for k in ('X','Y','Z')),tuple(float(e.find(f'R{i}{j}').text) for i in range(3) for j in range(3))
def expected(m,wp=(0,0,0),wr=I):
 p=add(wp,mv(wr,m['pos']));r=mul(wr,m['r']);out=[(m['name'],p,r)]
 for c in m['children']:out.extend(expected(c,p,r))
 return out
for name,m in ASSETS.items():
 doc=ET.parse(ROOT/'models'/f'{name}.rbxmx');byref={i.attrib['referent']:i for i in doc.iter('Item')}
 models=[i for i in doc.iter('Item') if i.attrib['class']=='Model']
 exp=expected(m);assert len(models)==len(exp)
 for item,(nm,ep,er) in zip(models,exp):
  props=item.find('Properties');primary=byref[props.find('Ref[@name="PrimaryPart"]').text];pr=primary.find('Properties')
  p,r=readcf(pr.find('CoordinateFrame[@name="CFrame"]'));op,orr=readcf(pr.find('CoordinateFrame[@name="PivotOffset"]'))
  actualp=add(p,mv(r,op));actualr=mul(r,orr)
  assert max(abs(actualp[i]-ep[i]) for i in range(3))<1e-5,(name,nm,'pivot-position')
  assert max(abs(actualr[i]-er[i]) for i in range(9))<1e-6,(name,nm,'pivot-rotation')
  assert primary.attrib['class']=='Part'
 assert all(i.attrib['class'] in ('Model','Part','PointLight') for i in doc.iter('Item'))
report['checks']+=['all PrimaryPart+PivotOffset transforms reconstructed and verified; no added invisible pivot Parts']

# A Folder of tiny invisible collision-free registration proxies, not a gigantic Park obstacle.
# Dev 2 must attach this Folder to StartPark before collectObstacles runs.
root=ET.Element('roblox',{'version':'4'});ET.SubElement(root,'External').text='null';ET.SubElement(root,'External').text='nil'
folder=ET.SubElement(root,'Item',{'class':'Folder','referent':refid()});props=ET.SubElement(folder,'Properties');prop(props,'string','Name','LandscapeObstacles')
for o in OBSTACLES:
 p={'name':o['name'],'p':(o['x'],.1,o['z']),'s':(2*o['radius'],.02,2*o['radius']),'r':I,'c':(0,0,0),'shape':'box','mat':'SmoothPlastic','collide':False,'alpha':1,'cls':'Part'}
 write_part(p,folder)
ET.ElementTree(root).write(ROOT/'LandscapeObstacles.rbxmx',encoding='utf-8',xml_declaration=True)
(ROOT/'layout.json').write_text(json.dumps({'center':[0,0,0],'designPlotCount':12,'minimumPlotRingRadius':102,'groundDiameter':140,'spawnPlaza':[16,16],'exitPorts':[{'angleDegrees':a,'pointXZ':polar(69.25,a)} for a in range(0,360,30)],'treePlacements':PLACEMENTS,'obstacles':OBSTACLES,'interactiveReserves':[{'name':n,'centerXZ':q,'radius':r} for n,q,r in RESERVES],'integration':'Park visual root is Workspace sibling, not one Model child inside StartPark. Attach LandscapeObstacles Folder inside StartPark before obstacle collection. Exclude ground/paths/plaza from obstacle registration.'},indent=2))
rojo='/Users/erland/.local/gst-tools/rojo'
for f in sorted((ROOT/'models').glob('*.rbxmx'))+[ROOT/'LandscapeObstacles.rbxmx']:
 project=ROOT/'source'/'convert.project.json';project.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(f)}}))
 run=subprocess.run([rojo,'build',str(project),'-o',str(f.with_suffix('.rbxm'))],capture_output=True,text=True);assert run.returncode==0,run.stderr
project.unlink()
place={'name':'Astra Park Showcase','tree':{'$className':'DataModel','Workspace':{'$className':'Workspace','Park':{'$path':'../models/Park.rbxmx'},'Spawn':{'$className':'SpawnLocation','$properties':{'Anchored':True,'Neutral':True,'Transparency':1,'CanCollide':False,'Size':[8,.1,8],'Position':[0,.2,0]}}},'Lighting':{'$className':'Lighting','$properties':{'Brightness':2,'ClockTime':14,'Ambient':[.52,.56,.52],'OutdoorAmbient':[.64,.7,.68],'GlobalShadows':True,'EnvironmentDiffuseScale':1,'EnvironmentSpecularScale':.5}}}}
project=ROOT/'source'/'showcase.project.json';project.write_text(json.dumps(place,indent=2))
for ext in ('rbxl','rbxlx'):
 run=subprocess.run([rojo,'build',str(project),'-o',str(ROOT/('Park_Showcase.'+ext))],capture_output=True,text=True);assert run.returncode==0,run.stderr
report['binaryConversion']='9 model RBXM + 1 Folder RBXM + RBXL/RBXLX showcase'
report['limitation']='Not tested in Studio. Gameplay integration, obstacle registry timing, path blending to actual plot entrances, FPS and artifact raycasts need Dev1/Dev2 checks. Park asset itself does not add laptops/jobs/pawn gameplay.'
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2))
# A QA plan: green dots are free grass test candidates, never gameplay spawn instances.
W=1400;H=1560;scale=9;ox=W/2;oy=720
im=Image.new('RGB',(W,H),'#f3f0e9');d=ImageDraw.Draw(im)
pt=lambda p:(ox+p[0]*scale,oy+p[1]*scale)
d.ellipse((ox-70*scale,oy-70*scale,ox+70*scale,oy+70*scale),fill='#acd48e')
for a,b,w in PATHS:d.line([pt(a),pt(b)],fill='#d9c9a3',width=round(w*2*scale))
for o in OBSTACLES:
 x,y=pt((o['x'],o['z']));r=o['radius']*scale;d.ellipse((x-r,y-r,x+r,y+r),fill='#69835c')
for _,q,r in RESERVES:
 x,y=pt(q);rr=r*scale;d.ellipse((x-rr,y-rr,x+rr,y+rr),outline='#bf754b',width=3)
for x in range(-50,51,2):
 for z in range(-50,51,2):
  p=(x,z)
  if 10<=math.hypot(x,z)<=52 and not occupied(p) and grass(p):
   xx,yy=pt(p);d.ellipse((xx-2,yy-2,xx+2,yy+2),fill='#276c44')
d.rectangle((ox-8*scale,oy-8*scale,ox+8*scale,oy+8*scale),fill='#ded6c5',outline='#ffffff',width=3)
try:font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',24)
except OSError:font=ImageFont.load_default()
d.text((40,30),'PARK / ARTIFACT GRASS COVERAGE',fill='#283345',font=font)
d.text((40,1400),'Green dots: free grass candidates in radius10..52, not fixed spawn points.',fill='#283345',font=font)
d.text((40,1440),f'{len(PLACEMENTS)} trees / {len(flatten(PARK))} visible Parts / grass candidates {grassCount/total:.1%}',fill='#283345',font=font)
im.save(ROOT/'previews'/'ArtifactCoverage_QA.png')
print(json.dumps({'parts':report['parkParts'],'trees':report['trees'],'species':report['species'],'sampling':report['artifactSampling']},indent=2))
