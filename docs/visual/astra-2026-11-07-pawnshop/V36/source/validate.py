from convex_support import *
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1];r=E.parse(ROOT/'models/Pawnshop.rbxmx').getroot()
items=list(r.iter('Item'));assert {i.get('class')for i in items}=={'Model','Part','PointLight'}
parts=parse(ROOT/'models/Pawnshop.rbxmx');cert,bad=audit(parts);assert not bad
for i in r.findall(".//Item[@class='Part']"):assert i.findtext("Properties/bool[@name='Anchored']")=='true'
lights=r.findall(".//Item[@class='PointLight']");assert len(lights)==1;assert lights[0].findtext("Properties/bool[@name='Shadows']")=='false'
assert len([i for i in r.findall(".//Item[@class='Part']")if i.findtext("Properties/string[@name='Name']")=='Counter'])==1
model=r.find('Item');ref=model.findtext("Properties/Ref[@name='PrimaryPart']");primary=next(i for i in items if i.get('referent')==ref);pr=primary.find('Properties')
def frame(n):
 f=pr.find("CoordinateFrame[@name='"+n+"']")
 return np.array([float(f.findtext(a))for a in 'XYZ']),np.array([[float(f.findtext('R'+str(i)+str(j)))for j in range(3)]for i in range(3)])
p,R=frame('CFrame');off,rot=frame('PivotOffset');assert np.max(np.abs(p+R@off))<1e-6;assert np.max(np.abs(R@rot-np.eye(3)))<1e-6
lo=np.array([min(support(p,-np.eye(3)[i])[i]for p in parts)for i in range(3)]);hi=np.array([max(support(p,np.eye(3)[i])[i]for p in parts)for i in range(3)])
assert abs(lo[1])<1e-6;assert abs(lo[0]+hi[0])<1e-6;assert abs(lo[2]+hi[2])<1e-6;assert hi[0]-lo[0]<=10.000001;assert hi[2]-lo[2]<=8.000001
report={'status':'PASS','parts':len(parts),'pairs':len(cert),'overlaps':bad,'Counter':'present','PrimaryPartPivot':'origin identity','allAnchored':True,'pointLights':1,'shadowless':True,'runtimeTested':False}
(ROOT/'INDEPENDENT_VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
