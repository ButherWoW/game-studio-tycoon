from pathlib import Path
import xml.etree.ElementTree as E
import subprocess,tempfile,json,hashlib
from convex_support import parse,audit
ROOT=Path(__file__).resolve().parents[1]
def value(e):
 if len(e):return(e.tag,tuple(sorted(e.attrib.items())),tuple(value(c)for c in e))
 t=e.text or ''
 try:t=float(t)
 except ValueError:pass
 return(e.tag,tuple(sorted(e.attrib.items())),t)
def norm(r):
 for weld in r.findall(".//Item[@class='WeldConstraint']"):
  pr=weld.find('Properties')
  for prop in list(pr):
   name=prop.get('name')
   if name in ['Part0Internal','Part1Internal']:prop.set('name',name.replace('Internal',''))
   if name=='Enabled':
    assert prop.text=='true'
    pr.remove(prop)
 ids={e.get('referent'):str(i)for i,e in enumerate(r.iter('Item'))}
 for e in r.iter('Ref'):
  if e.text in ids:e.text=ids[e.text]
 return[(e.get('class'),sorted([value(p)for p in e.find('Properties')],key=str))for e in r.iter('Item')]
def equivalent(a,b):
 if isinstance(a,(int,float)) and isinstance(b,(int,float)):return abs(a-b)<=1e-6
 if isinstance(a,(tuple,list)) and isinstance(b,(tuple,list)):return len(a)==len(b) and all(equivalent(x,y)for x,y in zip(a,b))
 return a==b
results=[]
for f in sorted((ROOT/'models').glob('*.rbxmx')):
 r=E.parse(f).getroot();items=list(r.iter('Item'));parts=[i for i in items if i.get('class') in ['Part','WedgePart']];assert len(parts)<=40
 ids={i.get('referent')for i in items}
 assert {i.get('class')for i in items}<= {'Model','Accessory','Part','WedgePart','Attachment','WeldConstraint'}
 assert len([i for i in items if i.get('class')=='Accessory'])==1
 for p in parts:
  pr=p.find('Properties')
  for name,expected in [('Anchored','false'),('Massless','true'),('CanCollide','false'),('CanTouch','false'),('CanQuery','false')]:assert pr.findtext("bool[@name='"+name+"']")==expected
 handles=[p for p in parts if p.findtext("Properties/string[@name='Name']")=='Handle'];assert len(handles)==1
 handle=handles[0];hid=handle.get('referent');att=handle.find("Item[@class='Attachment']");assert att is not None
 welds=[i for i in items if i.get('class')=='WeldConstraint'];assert len(welds)==len(parts)-1
 targets=[]
 for w in welds:
  pr=w.find('Properties');assert pr.findtext("Ref[@name='Part0']")==hid
  target=pr.findtext("Ref[@name='Part1']");assert target in ids;targets.append(target)
 assert set(targets)=={p.get('referent')for p in parts if p is not handle}
 certificates,bad=audit([p for p in parse(f)if p['alpha']<.99]);assert not bad
 with tempfile.TemporaryDirectory()as temp:
  temp=Path(temp);project=temp/'p.project.json';project.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(f.with_suffix('.rbxm'))}}))
  out=temp/'out.rbxmx';subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(project),'-o',str(out)],check=True,capture_output=True)
  a=norm(E.parse(out).getroot());b=norm(r)
  if not equivalent(a,b):
   for x,y in zip(a,b):
    if not equivalent(x,y):print('DIFF',x,y);break
   raise AssertionError(f)
 results.append({'file':f.name,'parts':len(parts),'welds':len(welds),'pairChecks':len(certificates),'overlap':0,'binaryRoundtrip':'PASS','structural':'PASS','sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
(ROOT/'INDEPENDENT_VALIDATION.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
