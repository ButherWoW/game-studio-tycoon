"""Independent contract check against the original exported snapshots."""
from pathlib import Path
import xml.etree.ElementTree as E
import json,hashlib,subprocess,tempfile
R=Path(__file__).resolve().parents[1];targets={'WindowGlass','DoorWindow'}
def parts(root):return [e for e in root.iter('Item') if e.get('class') in ('Part','Seat','WedgePart')]
def props(e):return {p.get('name'):E.tostring(p) for p in e.find('Properties')}
def geometry(e):
 p=e.find('Properties');result=[]
 for tag in ['size','CFrame','PivotOffset']:
  node=p.find(f'*[@name="{tag}"]');result.append((tag,E.tostring(node) if node is not None else None))
 return tuple(result)

report=[]
for f in sorted((R/'models').glob('*.rbxmx')):
 a=E.parse(R/'baseline'/f.name).getroot();b=E.parse(f).getroot();ap,bp=parts(a),parts(b);assert len(ap)==len(bp);count=0
 for old,new in zip(ap,bp):
  assert old.get('class')==new.get('class');assert geometry(old)==geometry(new)
  x,y=props(old),props(new);name=new.findtext('Properties/string[@name="Name"]');allowed={'Transparency','Material'} if name in targets else set();assert {k:v for k,v in x.items() if k not in allowed}=={k:v for k,v in y.items() if k not in allowed}
  if name in targets:
   count+=1;assert new.findtext('Properties/float[@name="Transparency"]')=='0';assert new.findtext('Properties/token[@name="Material"]')=='272'
 assert count==12
 for e in b.findall('.//Item[@class="Model"]'):
  name=e.findtext('Properties/string[@name="Name"]');old=next(x for x in a.findall('.//Item[@class="Model"]') if x.get('referent')==e.get('referent'));assert props(e)==props(old)
 lights=b.findall('.//Item[@class="PointLight"]');assert len(a.findall('.//Item[@class="PointLight"]'))==4
 assert len(lights)==1 and lights[0].findtext('Properties/bool[@name="Shadows"]')=='false'
 assert float(lights[0].findtext('Properties/float[@name="Range"]'))==60
 assert float(lights[0].findtext('Properties/float[@name="Brightness"]'))==1
 assert not any(e.get('class') in ('Script','LocalScript','ModuleScript','MeshPart','SpecialMesh','Decal','Texture') for e in b.iter('Item'))
 assert (f.with_suffix('.rbxm')).read_bytes().startswith(b'<roblox!')
 report.append({'model':f.stem,'parts':len(bp),'opaquePanels':count,'geometryAndModelPivot':'byte-identical XML properties to accepted snapshot','otherPartProperties':'identical','newGeometryIntersections':0,'baselineInternalDecorativeJoints':'preserved; not claimed absent','lights':1,'lightShadows':False,'sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [f,f.with_suffix('.rbxm')]}})
(R/'VALIDATION.json').write_text(json.dumps({'status':'PASS','models':report,'runtimeTested':False,'limits':'Unchanged geometry implies no NEW geometric intersections; this is not a claim of zero pre-existing internal decorative joins. Runtime double-shell removal is a separate Dev2 patch.'},indent=2)+'\n');print('PASS:',len(report),'models;48opaque panels;geometry/pivots unchanged')
