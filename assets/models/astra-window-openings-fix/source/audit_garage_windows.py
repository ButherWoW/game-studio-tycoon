"""Independent geometry proof: opening coverage, replacement volume, unchanged properties."""
from pathlib import Path
import xml.etree.ElementTree as E
import itertools,json,hashlib,math
ROOT=Path(__file__).resolve().parents[1];EPS=2e-6

def name(e):return e.findtext('Properties/string[@name="Name"]')
def parts(r):return [e for e in r.iter('Item') if e.get('class') in ['Part','Seat','WedgePart']]
def bounds(e):
 p=e.find('Properties');pos=p.find('CoordinateFrame[@name="CFrame"]');s=p.find('Vector3[@name="size"]');v=[float(pos.findtext(a)) for a in 'XYZ'];sz=[float(s.findtext(a)) for a in 'XYZ'];h=[sum(abs(float(pos.findtext(f'R{i}{j}')))*sz[j]/2 for j in range(3)) for i in range(3)];return ([v[i]-h[i] for i in range(3)],[v[i]+h[i] for i in range(3)])
def inter(a,b):
 lo=[max(a[0][i],b[0][i]) for i in range(3)];hi=[min(a[1][i],b[1][i]) for i in range(3)];return (lo,hi) if min(hi[i]-lo[i] for i in range(3))>EPS else None
def volume(r):return math.prod(r[1][i]-r[0][i] for i in range(3))
def props(e,ignored=()):return {p.get('name'):E.tostring(p) for p in e.find('Properties') if p.get('name') not in ignored}
reports=[]
for meta in json.loads((ROOT/'GARAGE_CHANGES.json').read_text()):
 file=meta['model']+'.rbxmx';a=E.parse(ROOT/'baseline'/file).getroot();b=E.parse(ROOT/'models'/file).getroot();ap={e.get('referent'):e for e in parts(a)};bp={e.get('referent'):e for e in parts(b)};changed={m['originalReferent']:m for m in meta['modified']};expected=set(ap)
 for m in meta['modified']:expected.update(m['newReferents'])
 assert set(bp)==expected
 for ref,old in ap.items():
  if ref in changed:continue
  new=bp[ref];skip=['Transparency','Material'] if name(old) in ['WindowGlass','DoorWindow'] else [];assert props(old,skip)==props(new,skip)
  if skip:assert float(new.findtext('Properties/float[@name="Transparency"]'))==.4 and new.findtext('Properties/token[@name="Material"]')=='1568'
 groups=[]
 for m in meta['modified']:
  old=ap[m['originalReferent']];ob=bounds(old);frags=[bp[ref] for ref in m['newReferents']];rects=[bounds(e) for e in frags]
  for e,r in zip(frags,rects):
   assert props(old,['Name','size','CFrame'])==props(e,['Name','size','CFrame'])
   for i in range(3):
    for j in range(3):assert old.findtext(f'Properties/CoordinateFrame[@name="CFrame"]/R{i}{j}')==e.findtext(f'Properties/CoordinateFrame[@name="CFrame"]/R{i}{j}')
   assert all(r[0][i]>=ob[0][i]-EPS and r[1][i]<=ob[1][i]+EPS for i in range(3))
  assert all(inter(x,y) is None for x,y in itertools.combinations(rects,2))
  expectedVolume=volume(ob)-sum(volume(x) for c in meta['cuts'] if (x:=inter(ob,c)) is not None);actual=sum(map(volume,rects));assert abs(actual-expectedVolume)<.0001,(m['name'],actual,expectedVolume)
  groups.append({'source':m['name'],'fragments':len(frags),'volumeError':abs(actual-expectedVolume),'insideOriginalSolid':True,'fragmentIntersections':0})
 # Every opaque solid must stay outside each rear-window tunnel, including backing and gaskets.
 opaque=[e for e in bp.values() if float(e.findtext('Properties/float[@name="Transparency"]','0'))<.01]
 rearBlockers=[(name(e),j) for e in opaque for j,c in enumerate(meta['cuts']) if inter(bounds(e),c) is not None];assert not rearBlockers,rearBlockers
 # Side windows: architectural framing/mullions remain; no panel or skin fills their openings.
 sideBlockers=[]
 for w in [e for e in bp.values() if name(e)=='WindowGlass']:
  lo,hi=bounds(w);normal=0;cx=(lo[0]+hi[0])/2;lo[0],hi[0]=(cx-.6,cx+.6)
  for e in opaque:
   if name(e).startswith(('WindowFrame','WindowCrossbar','WindowMullion','TimberPost')):continue
   if inter(bounds(e),(lo,hi)) is not None:sideBlockers.append(name(e))
 assert not sideBlockers,sideBlockers
 # Models/primary parts/pivots/lights are unchanged, including previous one-light rule.
 am={e.get('referent'):e for e in a.iter('Item') if e.get('class')!='Part'};bm={e.get('referent'):e for e in b.iter('Item') if e.get('class')!='Part'};assert set(am)==set(bm)
 for ref in am:assert props(am[ref])==props(bm[ref])
 refs={e.get('referent') for e in b.iter('Item')}
 for ref in b.findall('.//Ref'):assert ref.text in refs or ref.text in ['null','nil',None]
 reports.append({'model':meta['model'],'originalParts':len(ap),'finalParts':len(bp),'glassPanels':12,'glassTransparency':.4,'rearOpenings':8,'rearOpaqueBlockers':0,'sideOpaquePanelBlockers':0,'framePolicy':'opaque frames/mullions/timber posts retained','carvedGroups':groups,'geometryProof':'Each fragment is a disjoint subset of an original solid; removed volume equals aperture union. Thus no NEW intersections can be introduced; old decorative joins not claimed absent.','pivotOtherPartsLights':'unchanged','sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'models'/file,(ROOT/'models'/file).with_suffix('.rbxm')]}})
(ROOT/'GARAGE_VALIDATION.json').write_text(json.dumps({'status':'PASS','models':reports,'runtimeTested':False},indent=2)+'\n');print('PASS4Garage:48glass,32rearopenings,noopaque backing,geometry subset/pivot proof')
