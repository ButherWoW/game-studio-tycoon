from build_office import *
import itertools

def bounds(parts):
 lo=[float('inf')]*3;hi=[-float('inf')]*3
 for p in parts:
  if p['alpha']==1:continue
  # conservative OBB -> AABB, including the native shape's full bounds.
  half=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  for i in range(3):lo[i]=min(lo[i],p['p'][i]-half[i]);hi[i]=max(hi[i],p['p'][i]+half[i])
 return lo,hi

def overlap(a,b,tol=.035):return all(min(a[1][i],b[1][i])-max(a[0][i],b[0][i])>tol for i in range(3))

def instance(name,p,y):
 m=model('Placement');put(m,ASSETS[name],p,y);return flatten(m)

report={'sourceCommit':'c6e3f71','models':{},'checks':[],'studioTested':False}
for n,m in ASSETS.items():
 ps=flatten(m);lo,hi=bounds(ps);dims=[round(hi[i]-lo[i],4) for i in range(3)]
 assert len(ps)<=(600 if n=='Office' else 250),(n,len(ps))
 assert abs(lo[1])<1e-6,(n,lo)
 for part_ in ps:
  assert min(part_['s'])>=.001
 assert n!='Office' or dims[0]<=60.0001 and dims[2]<=60.0001 and dims[1]<=14.0001
 assert n!='OfficeDesk' or dims[0]<=8.0001 and dims[2]<=4.0001
 assert n!='Cooler' or dims[0]<=2.0001 and dims[2]<=2.0001
 assert n!='MeetingRoom' or dims[0]<=14.0001 and dims[2]<=10.0001
 report['models'][n]={'parts':len(ps),'dimensionsXYZ':dims,'min':lo,'max':hi,'pointLights':sum(bool(p.get('light')) for p in ps)}
 # Check every transform is orthonormal.
 for pp in ps:
  r=pp['r']
  for i in range(3):
   for j in range(3):assert abs(sum(r[i*3+k]*r[j*3+k] for k in range(3))-(1 if i==j else 0))<1e-6
# Peer model volumes: no bounding-volume intersections.
placed=[(n+'_'+str(i),instance(n,p,y)) for i,(n,p,y) in enumerate(LAYOUT) if n!='Office']
for (a,pa),(b,pb) in itertools.combinations(placed,2):assert not overlap(bounds(pa),bounds(pb)),(a,b)
# Furniture against shell geometry, excluding intentional support surfaces at Y<=.03.
shell=[p for p in flatten(ASSETS['Office']) if p['p'][1]+p['s'][1]/2>.03]
for n,ps in placed:
 for p in shell:assert not overlap(bounds(ps),bounds([p])),(n,p['name'])
# Explicit adjacent-row aisle check from actual generated bounds.
a=bounds(instance('OfficeDesk',(2,0,-20),0));b=bounds(instance('OfficeDesk',(12,0,-20),0))
assert b[0][0]-a[1][0]>=4-1e-6
# Entry jambs have inner faces at +/-3.2, giving 6.4 studs.
jambs=[p for p in flatten(ASSETS['MeetingRoom']) if p['name']=='DoorJamb']
assert len(jambs)==2
inner=sorted([p['p'][0] for p in jambs])
assert abs((inner[1]-.1)-(inner[0]+.1)-6.4)<1e-6
# Employee apron is 3 studs beyond the front, full width of each office desk.
for n,p,y in LAYOUT:
 if n!='OfficeDesk':continue
 bb=bounds(instance(n,p,y));apron=([bb[0][0],0,bb[1][2]],[bb[1][0],5,bb[1][2]+3])
 for other,ps in placed:
  if bounds(ps)==bb:continue
  assert not overlap(apron,bounds(ps)),('front-clearance',other)
 for pp in shell:assert not overlap(apron,bounds([pp])),('front-clearance',pp['name'])
# Existing carried-over garage furniture uses current Config positions; conservative safe volumes.
legacy=[('playerDesk',([-15.8,0,-21.75],[-8.2,5.5,-15.8])),('coffee',([23.5,0,-27.5],[26.5,6,-20.5])),('hitShelf',([-29,0,-20],[-26.2,8,-10]))]
for n,ps in placed:
 for old,bb in legacy:assert not overlap(bounds(ps),bb),('legacy',n,old)
# Facing +Z and front door 6.4 studs, reserved approach remains empty.
entry=([-17.2,0,14.98],[-10.8,6,20.98])
for n,ps in placed:
 if not n.startswith('MeetingRoom'):assert not overlap(entry,bounds(ps)),('meeting-entrance',n)
report['checks']=['part budgets','dimension limits','base Y=0','orthonormal transforms','no peer-model AABB overlaps','no intersections with shell walls or fixed decor','3-stud clear desk aprons','4-stud minimum gap between adjacent desk row','6.4-stud meeting doorway + 6-stud approach','reserved existing Desk1/PC1/Chair/Coffee/HitShelf footprints']
# Exactly four lights, one per ceiling panel; small objects have no point lights.
assert sum(bool(p.get('light')) for p in flatten(ASSETS['Office']))==4
# Models written as XML and read by the Roblox-aware Rojo parser for binary conversion.
for n,m in ASSETS.items():export(m,ROOT/'models'/f'{n}.rbxmx')
export(FULL,ROOT/'Office_Assembled.rbxmx')
templates=model('Upgrades')
for m in ASSETS.values():put(templates,m)
export(templates,ROOT/'Office_Upgrades_Import.rbxmx')
rojo='/Users/erland/.local/gst-tools/rojo'
for f in sorted((ROOT/'models').glob('*.rbxmx'))+[ROOT/'Office_Assembled.rbxmx',ROOT/'Office_Upgrades_Import.rbxmx']:
 project=ROOT/'source'/'convert.project.json';project.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(f)}}))
 run=subprocess.run([rojo,'build',str(project),'-o',str(f.with_suffix('.rbxm'))],capture_output=True,text=True);assert run.returncode==0,run.stderr
project.unlink()
place={'name':'Astra Office Showcase','tree':{'$className':'DataModel','Workspace':{'$className':'Workspace','Office':{'$path':'../Office_Assembled.rbxmx'},'Spawn':{'$className':'SpawnLocation','$properties':{'Anchored':True,'Neutral':True,'Transparency':1,'CanCollide':False,'Size':[4,.1,4],'Position':[0,.3,25]}}},'Lighting':{'$className':'Lighting','$properties':{'Brightness':2,'ClockTime':14,'Ambient':[.52,.54,.57],'OutdoorAmbient':[.65,.69,.75],'GlobalShadows':True,'EnvironmentDiffuseScale':1,'EnvironmentSpecularScale':.7}}}}
project=ROOT/'source'/'showcase.project.json';project.write_text(json.dumps(place,indent=2))
for ext in ('rbxl','rbxlx'):
 run=subprocess.run([rojo,'build',str(project),'-o',str(ROOT/('Office_Showcase.'+ext))],capture_output=True,text=True);assert run.returncode==0,run.stderr
report['binaryConversion']='6 RBXM files + RBXL/RBXLX place built with Rojo 7.4.4'
report['limitation']='Geometric checks and file parsing passed. Not play-tested in Roblox Studio. StaffService positions NPC at local Z=3.5; included tucked chair is decorative and needs deliberate seating integration if NPC should actually sit in it.'
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report['models'],indent=2))
