from pathlib import Path
from convex_support import *
import json,tempfile,subprocess
ROOT=Path(__file__).resolve().parents[1]
def value(e):
 t=(e.text or '').strip()
 try:t=float(t)
 except ValueError:pass
 return(e.tag,tuple(sorted(e.attrib.items())),t,tuple(value(c)for c in e))
def norm(r):
 ids={e.get('referent'):str(i)for i,e in enumerate(r.iter('Item'))}
 for e in r.iter('Ref'):
  if e.text in ids:e.text=ids[e.text]
 return[(e.get('class'),sorted([value(p)for p in e.find('Properties')],key=str))for e in r.iter('Item')]
def equal(a,b):
 if isinstance(a,(float,int))and isinstance(b,(float,int)):return abs(a-b)<=1e-6
 if isinstance(a,(list,tuple))and isinstance(b,(list,tuple)):return len(a)==len(b)and all(equal(x,y)for x,y in zip(a,b))
 return a==b
rows=[]
for f in sorted((ROOT/'models').glob('Mascot_*.rbxmx')):
 r=E.parse(f).getroot();parts=parse(f);cert,bad=audit(parts);assert not bad;assert len(parts)<=100
 assert {i.get('class')for i in r.iter('Item')}=={'Model','Part'}
 model=r.find('Item');assert model.findtext("Properties/string[@name='Name']")==f.stem
 ref=model.findtext("Properties/Ref[@name='PrimaryPart']");primary=next(i for i in r.iter('Item')if i.get('referent')==ref)
 assert primary.findtext("Properties/string[@name='Name']")=='Body'
 pr=primary.find('Properties')
 def frame(n):
  t=pr.find("CoordinateFrame[@name='"+n+"']")
  return np.array([float(t.findtext(a))for a in 'XYZ']),np.array([[float(t.findtext('R'+str(i)+str(j)))for j in range(3)]for i in range(3)])
 p,R=frame('CFrame');off,rr=frame('PivotOffset');assert np.max(np.abs(p+R@off))<1e-6
 for i in r.findall(".//Item[@class='Part']"):assert i.findtext("Properties/bool[@name='Anchored']")=='true'
 lo=np.array([min(support(p,-np.eye(3)[i])[i]for p in parts)for i in range(3)]);hi=np.array([max(support(p,np.eye(3)[i])[i]for p in parts)for i in range(3)])
 assert abs(lo[1])<1e-6 and abs(lo[0]+hi[0])<1e-6 and abs(lo[2]+hi[2])<1e-6
 with tempfile.TemporaryDirectory()as temp:
  temp=Path(temp);project=temp/'p.project.json';project.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(f.with_suffix('.rbxm'))}}));out=temp/'out.rbxmx'
  subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(project),'-o',str(out)],check=True,capture_output=True);assert equal(norm(E.parse(out).getroot()),norm(r))
 rows.append({'name':f.stem,'parts':len(parts),'dimensionsXYZ':(hi-lo).tolist(),'pairs':len(cert),'overlaps':bad,'BodyPrimaryPart':True,'pivotY0':True,'allAnchored':True,'binaryRoundtrip':'PASS','runtimeTested':False})
(ROOT/'INDEPENDENT_VALIDATION.json').write_text(json.dumps(rows,indent=2)+'\n');print(json.dumps(rows,indent=2))
