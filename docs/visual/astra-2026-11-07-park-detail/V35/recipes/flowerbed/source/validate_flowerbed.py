"""Independent exported-XML audit, conservative15-axis oriented-box SAT."""
from pathlib import Path
import xml.etree.ElementTree as E
import math,itertools,json,hashlib
ROOT=Path(__file__).resolve().parents[1];EPS=1e-6
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def overlap(a,b):
 axes=a['axes']+b['axes']+[cross(x,y) for x in a['axes'] for y in b['axes']]
 delta=[b['p'][i]-a['p'][i] for i in range(3)]
 for axis in axes:
  ln=math.sqrt(dot(axis,axis))
  if ln<1e-10:continue
  axis=[x/ln for x in axis]
  ra=sum(a['s'][j]/2*abs(dot(axis,a['axes'][j])) for j in range(3))
  rb=sum(b['s'][j]/2*abs(dot(axis,b['axes'][j])) for j in range(3))
  if ra+rb-abs(dot(delta,axis))<=EPS:return False
 return True
def main():
 r=E.parse(ROOT/'models/Flowerbed.rbxmx').getroot();items=r.findall('.//Item');ps=[]
 assert {x.get('class') for x in items}=={'Model','Part'}
 assert len({x.get('referent') for x in items})==len(items)
 for e in items:
  if e.get('class')!='Part':continue
  pr={x.get('name'):x for x in e.find('Properties')};f=pr['CFrame'];p=[float(f.findtext(a)) for a in 'XYZ'];rr=[float(f.findtext('R'+str(i)+str(j))) for i in range(3) for j in range(3)];s=[float(pr['size'].findtext(a)) for a in 'XYZ']
  assert all(math.isfinite(v) for v in p+rr+s) and min(s)>0
  assert pr['Anchored'].text=='true'
  axes=[[rr[i*3+j] for i in range(3)] for j in range(3)]
  assert all(abs(dot(axes[i],axes[j])-(1 if i==j else 0))<EPS for i in range(3) for j in range(3))
  ex=[sum(abs(rr[i*3+j])*s[j]/2 for j in range(3)) for i in range(3)]
  ps.append({'name':pr['Name'].text,'p':p,'s':s,'axes':axes,'lo':[p[i]-ex[i] for i in range(3)],'hi':[p[i]+ex[i] for i in range(3)],'ref':e.get('referent'),'pr':pr})
 assert len(ps)<=120
 lo=[min(p['lo'][i] for p in ps) for i in range(3)];hi=[max(p['hi'][i] for p in ps) for i in range(3)];sz=[hi[i]-lo[i] for i in range(3)]
 pairs=list(itertools.combinations(ps,2));bad=[[a['name'],b['name']] for a,b in pairs if overlap(a,b)]
 model=r.find('./Item');pr={x.get('name'):x for x in model.find('Properties')};pp=next(p for p in ps if p['ref']==pr['PrimaryPart'].text);off=pp['pr']['PivotOffset'];ov=[float(off.findtext(a)) for a in 'XYZ'];pivot=[pp['p'][i]+sum(pp['axes'][j][i]*ov[j] for j in range(3)) for i in range(3)]
 report={'model':'Flowerbed','parts':len(ps),'budget':120,'dimensionsXYZ':sz,'bounds':{'min':lo,'max':hi},'baseY':lo[1],'pivotXYZ':pivot,'front':'+Z','allAnchored':True,'nativeClasses':sorted(set(x.get('class') for x in items)),'scriptsLightsMeshesTexturesText':0,'obbSat':{'axes':15,'pairChecks':len(pairs),'toleranceStuds':EPS,'positiveVolumeOverlaps':bad,'count':len(bad),'conservative':'Primitive OBBs used even for ellipsoids. Zero OBB intersections proves zero actual Part volume intersections.'},'runtimeTested':False,'sha256':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in (ROOT/'models').glob('Flowerbed.*')}}
 print(json.dumps(report,indent=2));assert not bad
 assert 3.04<=sz[0]<=4.56 and .976<=sz[1]<=1.464 and 3.04<=sz[2]<=4.56
 assert abs(lo[1])<EPS and max(map(abs,pivot))<EPS
 assert (ROOT/'models/Flowerbed.rbxm').read_bytes().startswith(b'<roblox!')
 report['status']='PASS';(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
