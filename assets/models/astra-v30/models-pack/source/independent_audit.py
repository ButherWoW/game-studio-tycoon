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

report={'method':'Independent RBXMX XML parser + 15-axis OBB SAT; no builder imports','toleranceStuds':EPS,'models':{},'runtimeTested':False}
for name,limit,wantlights in [('Equip_ChipLab',80,0),('Equip_DesignStation',80,0),('Equip_TestBench',80,0)]:
 path=ROOT/'models'/(name+'.rbxmx');root,ps=parse(path);items=root.findall('.//Item');classes=sorted({x.attrib['class'] for x in items});assert set(classes)<={'Model','Part','PointLight'},classes
 refs=[x.attrib['referent'] for x in items];assert len(set(refs))==len(refs)
 lo,hi=bounds(ps);size=[hi[i]-lo[i] for i in range(3)];assert len(ps)<=limit
 assert all(size[i]<=[6,5,4][i]+EPS for i in range(3)),size
 assert abs(lo[1])<EPS and abs(lo[0]+hi[0])<EPS and abs(lo[2]+hi[2])<EPS,(lo,hi)
 for p in ps:
  pr=props(p['item']);assert pr['Anchored'].text=='true';assert pr['CanCollide'].text=='false'
  assert all(math.isfinite(x) for x in p['p']+p['r']+p['s']) and min(p['s'])>0
  ax=axes(p);assert all(abs(dot(ax[i],ax[j])-(1 if i==j else 0))<EPS for i in range(3) for j in range(3))
 lights=[x for x in items if x.attrib['class']=='PointLight'];assert len(lights)==wantlights
 assert all(props(x)['Shadows'].text=='false' for x in lights)
 model=root.find('./Item');mp=props(model);primary=mp['PrimaryPart'].text
 pp=props(next(x for x in items if x.attrib['referent']==primary));pos,rot=cf(pp['CFrame']);off,offr=cf(pp['PivotOffset']);pivot=[pos[i]+mv(rot,off)[i] for i in range(3)];orientation=mm(rot,offr)
 assert max(abs(x) for x in pivot)<EPS and max(abs(x-y) for x,y in zip(orientation,I))<EPS
 intersections=[];checks=0
 for a,b in itertools.combinations(ps,2):
  checks+=1
  if overlaps(a,b):intersections.append([a['name'],b['name']])
 assert (ROOT/'models'/(name+'.rbxm')).read_bytes().startswith(b'<roblox!')
 report['models'][name]={'status':'PASS' if not intersections else 'FAIL','parts':len(ps),'budget':limit,'bounds':[lo,hi],'dimensionsXYZ':size,'baseY':lo[1],'pivotXYZ':pivot,'identityPivotRotation':True,'faceConvention':'+Z in manifest; identity model pivot verified','pointLights':len(lights),'lightShadowsFalse':True,'nativeClasses':classes,'anchored':True,'noncolliding':True,'finiteOrthonormal':True,'uniqueReferences':True,'intersectionPairChecks':checks,'positiveVolumeIntersections':intersections}
report['status']='PASS' if all(x['status']=='PASS' for x in report['models'].values()) else 'FAIL'
(ROOT/'INDEPENDENT_VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
