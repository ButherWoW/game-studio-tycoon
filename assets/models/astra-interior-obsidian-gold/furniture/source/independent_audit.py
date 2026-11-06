"""Appearance-only proof from exported XML, independent of builder palette logic."""
from pathlib import Path
import xml.etree.ElementTree as E
import json,hashlib,copy,math
ROOT=Path(__file__).resolve().parents[1]
SUFFIX='ObsidianGold'
def props(e):return e.find('Properties')
def stripped(root,classic):
 r=copy.deepcopy(root);r.find("./Item[@class='Model']/Properties/string[@name='Name']").text=classic
 for light in r.iter('Item'):
  if light.get('class') in ['PointLight','SpotLight','SurfaceLight']:
   pr=props(light);sh=pr.find("bool[@name='Shadows']")
   if sh is not None:pr.remove(sh)
 for p in r.iter('Properties'):
  for e in list(p):
   if e.get('name') in ['Color','Color3uint8','Material'] and e.tag in ['Color3','Color3uint8','token']:p.remove(e)
 return E.tostring(r)
def parts(r):return [e for e in r.iter('Item') if e.get('class') in ['Part','Seat','WedgePart']]
def vector(e,tag):
 x=e.find("Properties/"+tag);return [float(x.findtext(a)) for a in 'XYZ']
def aabb(ps):
 lo=[math.inf]*3;hi=[-math.inf]*3
 for e in ps:
  p=props(e)
  if float(p.findtext("float[@name='Transparency']",'0'))>=.99:continue
  s=[float(p.find("Vector3[@name='size']").findtext(a)) for a in 'XYZ'];c=p.find("CoordinateFrame[@name='CFrame']");pos=[float(c.findtext(a)) for a in 'XYZ'];r=[float(c.findtext('R'+str(i)+str(j))) for i in range(3) for j in range(3)]
  h=[sum(abs(r[i*3+j])*s[j]/2 for j in range(3)) for i in range(3)]
  for i in range(3):lo[i]=min(lo[i],pos[i]-h[i]);hi[i]=max(hi[i],pos[i]+h[i])
 return [lo,hi]
manifest=json.loads((ROOT/'baseline/manifest.json').read_text());buildManifest=json.loads((ROOT/'manifest.json').read_text());rows={};total=0
for zone,names in manifest['zones'].items():
 for name in names:
  src=ROOT/'baseline/models'/(name+'.rbxmx');dst=ROOT.parent/'models'/(name+'_'+SUFFIX+'.rbxmx');a=E.parse(src).getroot();b=E.parse(dst).getroot();assert b.find("./Item/Properties/string[@name='Name']").text==name+'_'+SUFFIX
  assert stripped(a,name)==stripped(b,name),(name,'nonappearance XML mutation')
  ap,bp=parts(a),parts(b);assert len(ap)==len(bp)
  protected=set(buildManifest['models'][name+'_'+SUFFIX]['protectedSemanticParts'])
  for ae,be in zip(ap,bp):
   if ae.findtext("Properties/string[@name='Name']") in protected:
    for tag in ["Color3[@name='Color']","Color3uint8[@name='Color3uint8']","token[@name='Material']"]:
     aa,bb=props(ae).find(tag),props(be).find(tag);assert (E.tostring(aa) if aa is not None else None)==(E.tostring(bb) if bb is not None else None),(name,'semantic art changed')
  assert aabb(ap)==aabb(bp);cl={x.get('class') for x in b.iter('Item')};assert cl<={'Part','Seat','WedgePart','Model','PointLight','SpotLight','SurfaceLight'},cl
  lights=[x for x in b.iter('Item') if x.get('class') in ['PointLight','SpotLight','SurfaceLight']];assert all(x.findtext("Properties/bool[@name='Shadows']")=='false' for x in lights)
  refs=[x.get('referent') for x in b.iter('Item')];assert len(refs)==len(set(refs))
  seats=[x.findtext("Properties/string[@name='Name']") for x in bp if x.get('class')=='Seat' or (x.findtext("Properties/string[@name='Name']") or '').startswith('BlueSeat') or x.findtext("Properties/string[@name='Name']")=='SeatCushion']
  assert dst.with_suffix('.rbxm').read_bytes().startswith(b'<roblox!');total+=len(bp);bb=aabb(bp)
  rows[name+'_'+SUFFIX]={'zone':zone,'classicParts':len(ap),'variantParts':len(bp),'newParts':0,'bounds':bb,'dimensionsXYZ':[bb[1][i]-bb[0][i] for i in range(3)],'lowerY':bb[0][1],'dimensionDelta':0,'functionalParts':seats,'preservedSemanticNames':sorted(protected),'lights':len(lights),'nonAppearanceProperties':'identical XML after excluding Color/Material, root template name and existing light Shadows; Shadows forced false as required','intersections':'unchanged by exact geometry proof; no new parts or intersections','sha256':hashlib.sha256(dst.read_bytes()).hexdigest(),'status':'PASS'}
assert len(rows)==29
report={'theme':SUFFIX,'expected':29,'ready':len(rows),'totalParts':total,'newParts':0,'lightCorrection':'Classic PendantLamp PointLight Shadows=true corrected to false; no light added or moved','classicOriginExceptions':{n:r['lowerY'] for n,r in rows.items() if abs(r['lowerY'])>1e-5},'sourceCommit':manifest['sourceCommit'],'checks':['exact29V15coverage','all nonappearance XML identical','seat classes/names/behavior/pivot/frames unchanged','all AABB exact','same lights Shadowsfalse','no scripts/mesh/texture/Decal','validRojoRBXM'],'intersectionsNote':'Classic internal geometry is not redesigned: all overlap relationships are mathematically identical because geometry/transparency/tree topology are unchanged. No zero-overlap claim is made for pre-existing classic joints.','models':rows,'status':'PASS','runtimeTested':False}
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS',len(rows),'templates,',total,'Parts; geometry/function identical; lamp shadow correction documented')
