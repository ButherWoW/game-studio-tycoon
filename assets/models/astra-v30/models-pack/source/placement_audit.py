"""V30 actual-XML placement check using current Config/Console, Upgrades and Decor.
Run --repo PATH. Does not mutate code or scene; surfaces may touch, positive overlaps rejected.
"""
from independent_audit import parse,overlaps,props,bounds,mv,mm
from pathlib import Path
import re,json,math,itertools,argparse,hashlib
ROOT=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,required=True);REPO=ap.parse_args().repo

def rotation(yaw):
 a=math.radians(yaw);c=math.cos(a);s=math.sin(a);return[c,0,s,0,1,0,-s,0,c]
def placed(ps,xyz=(0,0,0),yaw=0,scale=1):
 r=rotation(yaw);out=[]
 for p in ps:
  q={k:v for k,v in p.items() if k!='item'};q['p']=[a+b for a,b in zip(xyz,mv(r,[x*scale for x in p['p']]))];q['r']=mm(r,p['r']);q['s']=[v*scale for v in p['s']];out.append(q)
 return out
def parts(path):return parse(path)[1]
def modelpath(n):
 for folder in ['astra-sky','astra-garage','astra-decor-v9']:
  p=REPO/'assets/models'/folder/'models'/(n+'.rbxmx')
  if p.exists():return p
 raise FileNotFoundError(n)
cfg=REPO/'src/shared/Config/Console.luau';text=cfg.read_text()
entries=re.findall(r'model = "(Equip_[^"]+)",\s*position = Vector3.new\(([^)]+)\),[^\n]*\n\s*rotation = (-?[\d.]+)',text);assert len(entries)==3
E={}
for name,xyz,yaw in entries:E[name]=placed(parts(ROOT/'models'/(name+'.rbxmx')),[float(x.strip()) for x in xyz.split(',')],float(yaw))
obstacles=[];obstacleSources=[]
def add(name,ps):
 for p in ps:obstacles.append((name+'/'+p['name'],p))
# Actual stage4 furniture config,14? current13 interiors + source shell.
up=REPO/'src/shared/Config/Upgrades.luau';rows=re.findall(r'\{\s*4,\s*(?:nil|"[^"]*"),\s*"([^"]*)",\s*"[^"]*",\s*[\d_]+,\s*"(SkyDesk|SoundStudio|ArtWall)",\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+),',up.read_text());assert len(rows)==13
for id,n,x,z,yaw in rows:add(id,placed(parts(modelpath(n)),[float(x),0,float(z)],float(yaw)))
# Floor supporting planes excluded; roof and all walls/props included.
add('Skyscraper',[p for p in parts(modelpath('Skyscraper')) if p['name'] not in ['Floor','FloorJoint']])
# Actual Decor.list slots[4], preserving rotations, importScale and ceiling/wall offsets.
dec=REPO/'src/shared/Config/Decor.luau';dt=dec.read_text();blocks=re.findall(r'\{\s*id = "([^"]+)"(.*?)\n\t\},',dt,re.S);decor=[]
for id,body in blocks:
 n=re.search(r'model = "([^"]+)"',body)
 if not n:continue
 slots=re.findall(r'slot\(([^)]+)\)',body);assert len(slots)==4,(id,slots)
 vals=[v.strip() for v in slots[3].split(',')];x,z,yaw=map(float,vals[:3]);y=0 if len(vals)==3 else {'CEILING':12,'WALL_SIGN':8}.get(vals[3],float(vals[3]) if re.fullmatch(r'-?[\d.]+',vals[3]) else 0)
 sc=re.search(r'importScale = ([\d.]+)',body);sc=float(sc[1]) if sc else 1
 add('Decor/'+id,placed(parts(modelpath(n[1])),[x,y,z],yaw,sc));decor.append(id)
# Real current display location; check all three states, because previous design is swapped.
pos=re.search(r'modelPosition = Vector3.new\(([^)]+)\)',text);xyz=[float(x.strip()) for x in pos[1].split(',')];yaw=float(re.search(r'modelRotation = (-?[\d.]+)',text)[1])
console=[]
for n in ['Console_Design','Console_Prototype','Console_Launch']:
 p=REPO/'assets/models/astra-console-v23/models'/(n+'.rbxmx');console += [(n+'/'+q['name'],q) for q in placed(parts(p),xyz,yaw)]
# Named positive-volume reserve boxes, at actual constrained parts of front row.
reserves=[]
def reserve(n,lo,hi):reserves.append((n,{'p':[(a+b)/2 for a,b in zip(lo,hi)],'r':rotation(0),'s':[b-a for a,b in zip(lo,hi)]}))
# Preserve 3-stud (+Z) employee aprons on existing SkyDesks.
for id,n,x,z,yaw in rows:
 if n=='SkyDesk':
  lo,hi=bounds(placed(parts(modelpath(n)),[float(x),0,float(z)],float(yaw)));reserve(id+'_3studApron',[lo[0],0,hi[2]],[hi[0],6,hi[2]+3])
reserve('Lift',[-23,0,21],[-17,7,27]);reserve('Buttons',[-6,0,22],[6,5,29])
# Existing front wall plant(26,22) conservative envelope; source XML plant already in shell when present.
reserve('FrontRightPlant',[24.7,0,20.7],[27.3,5,23.3])
report={'scope':'Actual local floor-relative coordinates; equipmentY0.5 retained as configured, no code changes','configSHA256':hashlib.sha256(cfg.read_bytes()).hexdigest(),'stage4Furniture':len(rows),'decorSlots4':decor,'consoleDisplayPosition':xyz,'consoleDisplayRotation':yaw,'equipment':{},'runtimeTested':False,'limitation':'Does not claim liveNPCpaths or furniture skin variants; geometry check includes currentclassic source models and conservative lift/button/plant reserves'}
for name,ps in E.items():
 conflicts=[];checks=0
 for a in ps:
  for n,b in obstacles+console+reserves:
   checks+=1
   if overlaps(a,b):conflicts.append([a['name'],n])
 for other,otherps in E.items():
  if other<=name:continue
  for a,b in itertools.product(ps,otherps):
   checks+=1
   if overlaps(a,b):conflicts.append([a['name'],other+'/'+b['name']])
 # Each station must also have a clear 3-stud working approach in local+Z.
 xyzEntry,yawEntry=next((xyz,yaw) for n,xyz,yaw in entries if n==name);base=[float(x.strip()) for x in xyzEntry.split(',')];apron=placed([{'name':'Approach3','p':[0,2.5,3.5],'r':rotation(0),'s':[6,5,3]}],base,float(yawEntry))[0]
 apronHits=[n for n,b in obstacles+console+reserves if overlaps(apron,b)]
 for other,otherps in E.items():
  if other!=name:apronHits += [other+'/'+b['name'] for b in otherps if overlaps(apron,b)]
 report['equipment'][name]={'approach3Conflicts':apronHits,'worldBounds':bounds(ps),'pairChecks':checks,'positiveVolumeIntersections':conflicts,'status':'PASS' if not conflicts and not apronHits else 'FAIL'}
report['status']='PASS' if all(r['status']=='PASS' for r in report['equipment'].values()) else 'FAIL'
(ROOT/'PLACEMENT_VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
