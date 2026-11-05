"""Independent audit of final RBXMX, without importing builder geometry.
SAT uses conservative oriented boxes; touching within1e-5 is accepted.
Run from anywhere: python3 path/to/independent_audit.py.
"""
from pathlib import Path
import xml.etree.ElementTree as ET
import math,json,itertools,re
ROOT=Path(__file__).resolve().parents[1]
EPS=1e-5
I=[1.,0.,0.,0.,1.,0.,0.,0.,1.]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def mv(r,v):return [dot(r[i*3:i*3+3],v) for i in range(3)]
def mm(a,b):return [sum(a[i*3+k]*b[k*3+j] for k in range(3)) for i in range(3) for j in range(3)]
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def props(item):return {e.attrib['name']:e for e in item.find('Properties')}
def cf(e):return [float(e.find(k).text) for k in 'XYZ'],[float(e.find(f'R{i}{j}').text) for i in range(3) for j in range(3)]
def axes(p):return [[p['r'][i*3+j] for i in range(3)] for j in range(3)]
def bounds(parts):
 los=[];his=[]
 for p in parts:
  ex=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  los.append([p['p'][i]-ex[i] for i in range(3)]);his.append([p['p'][i]+ex[i] for i in range(3)])
 return [[min(a[i] for a in los) for i in range(3)],[max(a[i] for a in his) for i in range(3)]]
def overlaps(a,b):
 aa,bb=axes(a),axes(b);delta=[b['p'][i]-a['p'][i] for i in range(3)]
 for axis in aa+bb+[cross(x,y) for x in aa for y in bb]:
  norm=math.sqrt(dot(axis,axis))
  if norm<1e-9:continue
  axis=[x/norm for x in axis]
  ra=sum(abs(dot(axis,aa[i]))*a['s'][i]/2 for i in range(3));rb=sum(abs(dot(axis,bb[i]))*b['s'][i]/2 for i in range(3))
  if ra+rb-abs(dot(delta,axis))<=EPS:return False
 return True

def parse(path):
 root=ET.parse(path).getroot();parts=[]
 for item in root.findall('.//Item'):
  if item.attrib['class'] not in ['Part','WedgePart','Seat']:continue
  pr=props(item);p,r=cf(pr['CFrame']);s=[float(pr['size'].find(k).text) for k in 'XYZ']
  parts.append({'name':pr['Name'].text,'p':p,'r':r,'s':s,'item':item,'shape':int(pr['shape'].text) if 'shape'in pr else 1})
 return root,parts


import argparse,hashlib,copy
ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=Path('/private/tmp/game-studio-tycoon-visual-upload-20261104'));arg=ap.parse_args();service=arg.repo/'src/server/Services/ConstructionService.luau';text=service.read_text();assert 'local SIDE_FRONT = 12' in text and 'local SCAFFOLD_IN = 0.8' in text and 'local FENCE = 6.2' in text
# Mirrors CFrame.lookAt directions in ConstructionService.sides; plot local coordinates.
ROTS={'left':[0,0,-1,0,1,0,1,0,0],'right':[0,0,1,0,1,0,-1,0,0],'rear':[-1,0,0,0,1,0,0,0,-1]}
def arrangement(name,distance,tiers=1,corner_inset=0):
 _,raw=parse(ROOT/'models'/(name+'.rbxmx'));lo,hi=bounds(raw);size=[hi[i]-lo[i] for i in range(3)];out=[];summary=[]
 for side in ['left','right','rear']:
  if side=='rear':length=2*distance;center=[0,0,-distance]
  else:
   zmin=-distance+corner_inset;length=12-zmin;center=[-distance if side=='left' else distance,0,(zmin+12)/2]
  count=max(1,math.floor(length/max(size[0],1)+.5));step=length/count;summary.append({'side':side,'length':length,'countPerTier':count,'step':step,'modelWidth':size[0]})
  R=ROTS[side]
  for n in range(count):
   off=-length/2+(n+.5)*step;shift=mv(R,[off,0,0])
   for t in range(tiers):
    parts=[]
    for p in raw:
     q={k:copy.deepcopy(p[k]) for k in ['name','p','r','s','shape']};local=mv(R,p['p']);q['p']=[center[i]+shift[i]+local[i]+(t*size[1] if i==1 else 0) for i in range(3)];q['r']=mm(R,p['r']);parts.append(q)
    out.append({'id':f'{side}_{n}_tier{t}','side':side,'n':n,'tier':t,'parts':parts,'bounds':bounds(parts)})
 return out,summary

def audit(instances):
 bad=[];broad=0;tested=0;vertical=0;neighbors=0;corners=0
 def aabb(a,b):return all(min(a[1][i],b[1][i])-max(a[0][i],b[0][i])>EPS for i in range(3))
 for a,b in itertools.combinations(instances,2):
  if a['side']==b['side'] and a['n']==b['n'] and a['tier']!=b['tier']:vertical+=1
  if a['side']==b['side'] and abs(a['n']-b['n'])==1 and a['tier']==b['tier']:neighbors+=1
  if a['side']!=b['side'] and a['tier']==b['tier']:corners+=1
  if not aabb(a['bounds'],b['bounds']):continue
  broad+=1
  for pa in a['parts']:
   for pb in b['parts']:
    if not aabb(bounds([pa]),bounds([pb])):continue
    tested+=1
    if overlaps(pa,pb):bad.append({'a':a['id'],'b':b['id'],'partA':pa['name'],'partB':pb['name']})
 return {'status':'FAIL' if bad else 'PASS','instances':len(instances),'parts':sum(len(a['parts']) for a in instances),'sameSideNeighborPairs':neighbors,'verticalStackInstancePairs':vertical,'differentSidePairs':corners,'broadPhaseInstancePairs':broad,'narrowPartSATChecks':tested,'intersections':bad,'intersectionCount':len(bad)}
sc,scs=arrangement('Construction_Scaffold',31.9,3);fe,fes=arrangement('Construction_Fence',36.2)
# Corner fix: shorten only the two side rows by full modeldepth/2 +0.1 at rear.
scfix,scfs=arrangement('Construction_Scaffold',31.9,3,1.2)
# Fence sides inset by0.2 at rear, maintaining count6+6+9=21.
fefix,fefs=arrangement('Construction_Fence',36.2,1,.2)
report={'serviceSHA256':hashlib.sha256(service.read_bytes()).hexdigest(),'plot':[60,60],'floorTopHeightsForPlotThickness1':[15,29,43],'tierHeight':15,'method':'Independent XML parser, actual native parts, CFrame.lookAt side rotations, AABB broad phase +15axisOBB SAT; touching accepted','actualServiceScaffold':{'rows':scs,**audit(sc)},'actualServiceFence':{'rows':fes,**audit(fe)},'recommendedScaffold':{'change':'Scaffold side rows only: zMin=-distance+depth/2+0.1; rear row unchanged','rearInset':1.2,'rows':scfs,**audit(scfix)},'recommendedFence':{'change':'Fence side rows only: zMin=-distance+0.2; rear row unchanged','rearInset':.2,'rows':fefs,**audit(fefix)},'legacy60LengthAssumption':'Not applicable: current sides end atZ12, lengths43.9/43.9/63.8. Round counts4+4+6=14, three tiers42, not54.','runtimeTested':False,'limitations':['Models unchanged; recommendations only, no sourcegamecode edits','Plot rotations preserve all relative intersections','NPC routes, neighboringplots, crane and materials need runtime/fullsite checks']}
(ROOT/'CONSTRUCTION_LAYOUT_REVIEW.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if not isinstance(v,dict)},indent=2));print({k:{j:v for j,v in val.items() if j in ['status','instances','parts','intersectionCount']} for k,val in report.items() if isinstance(val,dict)})
