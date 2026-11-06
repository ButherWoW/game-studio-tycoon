"""Final XML-only audit: actual native convex support-plane certificates, not OBB-only claims."""
from convex_support import *
import json,hashlib,collections
ROOT=Path(__file__).resolve().parents[1];f=ROOT/'models/Pigeon.rbxmx';parts=parse(f);certs,bad=audit(parts,tol=1e-6);assert not bad,bad;assert len(parts)<=60
r=E.parse(f).getroot();assert {e.get('class')for e in r.iter('Item')}=={'Model','Part','WedgePart'}
for e in r.findall('.//Item'):
 if e.get('class')in['Part','WedgePart']:
  assert e.findtext('Properties/bool[@name="Anchored"]')=='true';assert float(e.findtext('Properties/float[@name="Transparency"]'))==0
lo=[min(support(p,-np.eye(3)[i])[i]for p in parts)for i in range(3)];hi=[max(support(p,np.eye(3)[i])[i]for p in parts)for i in range(3)]
assert abs(lo[1])<1e-6;assert max(abs((lo[i]+hi[i])/2)for i in [0,2])<1e-6
model=r.find('Item');ref=model.findtext('Properties/Ref[@name="PrimaryPart"]');first=next(e for e in r.iter('Item')if e.get('referent')==ref);pr=first.find('Properties');cf=pr.find('CoordinateFrame[@name="CFrame"]');off=pr.find('CoordinateFrame[@name="PivotOffset"]');pos=np.array([float(cf.findtext(a))for a in'XYZ']);rot=np.array([[float(cf.findtext(f'R{i}{j}'))for j in range(3)]for i in range(3)]);offset=np.array([float(off.findtext(a))for a in'XYZ']);assert np.max(np.abs(pos+rot@offset))<1e-6
(ROOT/'SEPARATION_CERTIFICATES.json').write_text(json.dumps(certs,indent=2)+'\n')
report={'status':'PASS','nativeParts':len(parts),'partBudget':60,'partClasses':dict(collections.Counter(e.get('class')for e in r.iter('Item'))),'actualConvexPairs':len(certs),'unresolvedOrOverlap':bad,'positiveVolumeIntersections':0,'method':'Analytic native convex support mappings (ellipsoid Ball, elliptic Cylinder, box, six-vertex WedgePart). Accept only a verified separating support plane with gap >= -1e-6 studs. OBB used only as search axes; no claim that all OBBs are disjoint. See per-pair SEPARATION_CERTIFICATES.','certificateMethods':dict(collections.Counter(c['method']for c in certs)),'toleranceStuds':1e-6,'dimensionsXYZ':[hi[i]-lo[i]for i in range(3)],'baseY':lo[1],'footprintCenterXZ':[(lo[i]+hi[i])/2 for i in [0,2]],'pivotXYZ':[0,0,0],'front':'+Z','Anchored':True,'scripts':0,'lights':0,'externalMeshTextureDependencies':0,'runtimeTested':False,'sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in (ROOT/'models').glob('*')}}
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS',len(parts),'Parts',len(certs),'analytic separation planes')
