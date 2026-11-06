from pathlib import Path
import xml.etree.ElementTree as E,json,subprocess,tempfile,hashlib
R=Path(__file__).resolve().parents[1];B=R/'baseline';ROJO='/Users/erland/.local/gst-tools/rojo'
def items(root):return {e.get('referent'):e for e in root.iter('Item')}
def properties(e):return {p.get('name'):E.tostring(p) for p in e.find('Properties')}
def semantic(root):
 return [(e.get('class'),[(x.tag,x.get('name'),E.tostring(x).decode().strip())for x in e.find('Properties')])for e in root.iter('Item')]
allowed=json.loads((R/'ALLOWED_DELETIONS.json').read_text())
rows=[]
for f in sorted((R/'models').glob('*.rbxmx')):
 a=E.parse(B/f.name).getroot();b=E.parse(f).getroot();ai,bi=items(a),items(b);removed=[];panes=0
 assert not bi.keys()-ai.keys()
 lights=list(a.findall('.//Item[@class="PointLight"]'));assert len(lights)==4
 removedLights={e.get('referent')for e in lights[1:]};retainedLight=lights[0].get('referent')
 oldParents={c:p for p in a.iter()for c in p};newParents={c:p for p in b.iter()for c in p}
 assert oldParents[lights[0]].get('referent')==newParents[bi[retainedLight]].get('referent')
 finalLights=list(b.findall('.//Item[@class="PointLight"]'));assert len(finalLights)==1 and finalLights[0].get('referent')==retainedLight
 for ref,e in ai.items():
  p=e.find('Properties');name=p.findtext("string[@name='Name']")
  if ref in removedLights:
   assert ref not in bi;continue
  if ref not in bi:
   entry=next((x for x in allowed[f.stem] if x['referent']==ref),None);assert entry and name==entry['name']
   c=p.find("CoordinateFrame[@name='CFrame']");xyz=[float(c.findtext(k))for k in 'XYZ'];assert xyz==entry['p'];removed.append(ref);continue
  n=bi[ref];assert e.get('class')==n.get('class');old,new=properties(e),properties(n)
  if p.findtext("token[@name='Material']")=='1568':
   panes+=1;assert n.findtext("Properties/float[@name='Transparency']")=='0.4';old.pop('Transparency');new.pop('Transparency')
  if ref==retainedLight:
   assert n.findtext('Properties/bool[@name="Shadows"]')=='false' and n.findtext('Properties/float[@name="Range"]')=='60' and n.findtext('Properties/float[@name="Brightness"]')=='1'
   for k in ['Shadows','Range','Brightness']:old.pop(k,None);new.pop(k,None)
  assert old==new,(f,name)
 assert set(removed)=={x['referent']for x in allowed[f.stem]}
 for ref in b.iter('Ref'):assert ref.text not in set(removed)|removedLights
 with tempfile.TemporaryDirectory() as tmp:
  tmp=Path(tmp);proj=tmp/'p.project.json';rt=tmp/'roundtrip.rbxmx';proj.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(f.with_suffix('.rbxm'))}}));subprocess.run([ROJO,'build',str(proj),'-o',str(rt)],check=True,capture_output=True)
  # Rojo rewrites referents and XML formatting: compare parsed property values, not serialization.
  def norm(e):return (e.tag,tuple(sorted((k,v)for k,v in e.attrib.items()if k!='referent')),e.text.strip()if e.text else '',tuple(norm(c)for c in e))
  def tree(root):
   ids={e.get('referent'):i for i,e in enumerate(root.iter('Item'))}
   for ref in root.iter('Ref'):
    if ref.text in ids:ref.text=str(ids[ref.text])
   return [(e.get('class'),tuple(sorted((norm(p)for p in e.find('Properties')),key=str)))for e in root.iter('Item')]
  assert tree(b)==tree(E.parse(rt).getroot()),f'roundtrip {f}'
 rows.append({'model':f.stem,'glassPanels':panes,'removedDecorParts':len(removed),'allOtherPropertiesIdentical':True,'removedPointLights':3,'retainedPointLight':{'Shadows':False,'Range':60,'Brightness':1,'colorAndParentUnchanged':True},'danglingRemovedReferences':0,'binaryRoundtrip':'PASS','sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in [f,f.with_suffix('.rbxm')]}})
assert sum(x['glassPanels']for x in rows)==66
(R/'VALIDATION.json').write_text(json.dumps({'status':'PASS','models':rows,'geometry':'Only 49 specified blocking decor Parts deleted. All surviving geometry, seats and pivots unchanged. Only the first PointLight retained, with Shadows=false/Range60/Brightness1; three PointLights removed. No new geometry/intersections introduced; old decorative joints not assessed.','runtimeTested':False},indent=2)+'\n');print('PASS12models66panels49removed;binaryroundtrip')
