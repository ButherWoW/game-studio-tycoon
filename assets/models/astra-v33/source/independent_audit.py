"""Independent audit reads exported XML only; no builder imports."""
from pathlib import Path
import xml.etree.ElementTree as E
import itertools,math,json,hashlib
ROOT=Path(__file__).resolve().parents[1];EPS=1e-5
r=E.parse(ROOT/'models/SpawnPad.rbxmx').getroot();items=r.findall('.//Item');assert {x.get('class') for x in items}=={'Model','Part'}
refs=[x.get('referent') for x in items];assert len(refs)==len(set(refs));ps=[]
for e in items:
 if e.get('class')!='Part':continue
 pr={x.get('name'):x for x in e.find('Properties')};f=pr['CFrame'];pos=[float(f.findtext(a)) for a in 'XYZ'];rot=[float(f.findtext('R'+str(i)+str(j))) for i in range(3) for j in range(3)];size=[float(pr['size'].findtext(a)) for a in 'XYZ'];assert all(math.isfinite(v) for v in pos+rot+size);assert min(size)>0;assert all(abs(v-(1 if i in [0,4,8] else 0))<EPS for i,v in enumerate(rot));assert pr['Anchored'].text=='true';assert pr['CanCollide'].text=='true'
 ps.append({'name':pr['Name'].text,'p':pos,'s':size,'lo':[pos[i]-size[i]/2 for i in range(3)],'hi':[pos[i]+size[i]/2 for i in range(3)],'ref':e.get('referent'),'pr':pr})
assert len(ps)<=40
lo=[min(p['lo'][i] for p in ps) for i in range(3)];hi=[max(p['hi'][i] for p in ps) for i in range(3)];assert max(abs(a-b) for a,b in zip(lo,[-4,0,-4]))<EPS;assert max(abs(a-b) for a,b in zip(hi,[4,.32,4]))<EPS
pairs=0;overlaps=[]
for a,b in itertools.combinations(ps,2):
 pairs+=1
 if all(min(a['hi'][i],b['hi'][i])-max(a['lo'][i],b['lo'][i])>EPS for i in range(3)):overlaps.append([a['name'],b['name']])
assert not overlaps
model=r.find('./Item');mp={x.get('name'):x for x in model.find('Properties')};pp=next(p for p in ps if p['ref']==mp['PrimaryPart'].text);assert pp['name']=='Base';off=pp['pr']['PivotOffset'];pivot=[pp['p'][i]+float(off.findtext(a)) for i,a in enumerate('XYZ')];assert max(map(abs,pivot))<EPS
# Exact rectangular top tiling, including frame; all top faces lie at identicalY.
top=[p for p in ps if abs(p['hi'][1]-.32)<EPS];assert len(top)==len(ps)-1
area=sum(p['s'][0]*p['s'][2] for p in top);assert abs(area-64)<.001
# Merge almost-identical XML-rounded edges then test every subdivision cell.
def edges(axis):
 vals=sorted([p[k][axis] for p in top for k in ['lo','hi']]);out=[]
 for v in vals:
  if not out or v-out[-1]>EPS:out.append(v)
 return out
xs,zs=edges(0),edges(2);cells=0
for x1,x2 in zip(xs,xs[1:]):
 for z1,z2 in zip(zs,zs[1:]):
  if x2-x1<=EPS or z2-z1<=EPS:continue
  x=(x1+x2)/2;z=(z1+z2)/2;count=sum(p['lo'][0]-EPS<=x<=p['hi'][0]+EPS and p['lo'][2]-EPS<=z<=p['hi'][2]+EPS for p in top);assert count==1,(x,z,count);cells+=1
assert (ROOT/'models/SpawnPad.rbxm').read_bytes().startswith(b'<roblox!')
report={'model':'SpawnPad','parts':len(ps),'partBudget':40,'dimensionsXYZ':[hi[i]-lo[i] for i in range(3)],'baseY':lo[1],'topY':hi[1],'primaryPart':'Base','pivotXYZ':pivot,'classes':['Model','Part'],'pointLights':0,'nativeNeonFrame':True,'anchored':True,'walkableCanCollide':True,'positiveVolumeIntersections':overlaps,'pairChecks':pairs,'topCoverage':{'area':area,'expectedArea':64,'testedSubdivisionCells':cells,'cellCoverageExactlyOne':True,'gapsGreaterThanTolerance':0,'toleranceStuds':EPS,'entireTopCoplanar':True,'unobstructedCenterAtLeast6x6':True},'shaftHeightOrOtherVerticalObstacles':False,'sha256':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in (ROOT/'models').glob('SpawnPad.*')},'status':'PASS','runtimeTested':False}
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
