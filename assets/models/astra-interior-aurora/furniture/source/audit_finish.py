"""Independent final XML property audit; geometry is compared without builder imports."""
from pathlib import Path
import xml.etree.ElementTree as ET
import json,hashlib,math
ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'baseline/manifest.json').read_text());report={'theme':'Aurora','models':{},'runtimeTested':False,'method':'Exact final XML node/property comparison against accepted classic snapshots; all geometry unchanged, therefore no new intersection pairs or placement changes.'}
def propmap(e):return {p.attrib['name']:ET.tostring(p,encoding='unicode') for p in e.find('Properties')}
def pvalue(e,name):return e.find(f"./Properties/*[@name='{name}']")
def parts(r):return [e for e in r.iter('Item') if e.attrib['class'] in ['Part','WedgePart','Seat']]
def semantic(model,n):
 low=n.lower()
 if model=='Posters':return n not in ['Frame','Pivot']
 if model=='ArtWall':return n not in ['ArtFrame','FrameGlow','GalleryFoot','GalleryPost']
 if model=='NeonSign':return n in ['ControllerNeon','DPadHorizontal','DPadVertical','ActionDot']
 return any(w in low for w in ['screen','pixel','character','cloud','appheader','timeline','editor','chart','trophy','ship','status','led','taplever','fadercap','mixknob','keycap','spacebar','keyboard','powerbutton','star','button','book','sodacan','canmark','fish','controllerpad','controllerbutton']) or n in ['Key','Space','FanHub','MarqueeGem','WatchFace','Display']

def vector(e,name):return [float(pvalue(e,name).find(a).text) for a in 'XYZ']
def bounds(r):
 lo=[1e9]*3;hi=[-1e9]*3
 for e in parts(r):
  tr=pvalue(e,'Transparency')
  if tr is not None and float(tr.text)>=.99:continue
  cf=pvalue(e,'CFrame');pos=[float(cf.find(a).text) for a in 'XYZ'];rot=[[float(cf.find(f'R{i}{j}').text) for j in range(3)] for i in range(3)];sz=vector(e,'size')
  for i in range(3):
   ex=sum(abs(rot[i][j])*sz[j]/2 for j in range(3));lo[i]=min(lo[i],pos[i]-ex);hi[i]=max(hi[i],pos[i]+ex)
 return [lo,hi]
for name in manifest['sources']:
 bpath=ROOT/'baseline/models'/f'{name}.rbxmx';vpath=ROOT.parent/'models'/f'{name}_Aurora.rbxmx';base=ET.parse(bpath).getroot();variant=ET.parse(vpath).getroot();bi=list(base.iter('Item'));vi=list(variant.iter('Item'));assert len(bi)==len(vi)
 functional=0;geometryParts=0;lights=0;changed=[];shadowCorrections=[];semanticPreserved=0
 for index,(a,b) in enumerate(zip(bi,vi)):
  assert a.attrib==b.attrib,(name,index,'node identity');pa,pb=propmap(a),propmap(b);allowed={'Name'} if index==0 else set()
  if a.attrib['class'] in ['Part','WedgePart','Seat']:
   allowed|={'Color','Color3uint8','Material'};geometryParts+=1
   n=pvalue(a,'Name').text
   if semantic(name,n):
    for key in ['Color','Color3uint8','Material']:assert pa.get(key)==pb.get(key),(name,n,'semantic appearance changed')
    semanticPreserved+=1
   if a.attrib['class']=='Seat' or n.startswith('BlueSeat') or n=='SeatCushion':functional+=1
  if a.attrib['class'] in ['PointLight','SpotLight','SurfaceLight']:
   allowed|={'Color','Shadows'};lights+=1;sh=pvalue(b,'Shadows');assert sh is None or sh.text=='false'
   if pa.get('Shadows')!=pb.get('Shadows'):shadowCorrections.append({'class':a.attrib['class'],'property':'Shadows','before':pvalue(a,'Shadows').text,'after':sh.text})
  assert set(pa)==set(pb),(name,'property schema')
  for key in pa:
   if key not in allowed:assert pa[key]==pb[key],(name,index,key)
  if any(pa.get(k)!=pb.get(k) for k in allowed):changed.append(index)
 assert variant.find('./Item/Properties/string[@name="Name"]').text==name+'_Aurora'
 assert bounds(base)==bounds(variant)
 assert set(e.attrib['class'] for e in vi)<={'Model','Part','WedgePart','Seat','PointLight','SpotLight','SurfaceLight'}
 assert (ROOT.parent/'models'/f'{name}_Aurora.rbxm').read_bytes().startswith(b'<roblox!')
 report['models'][name]={'status':'PASS','partsClassic':geometryParts,'partsVariant':geometryParts,'partBudgetRatio':1,'bounds':bounds(variant),'maxDimensionDelta':0,'functionalPartsUnchanged':functional,'semanticContentPartsPreserved':semanticPreserved,'allNonAppearancePropertiesUnchangedExceptDocumentedShadowPolicy':True,'lightShadowCorrections':shadowCorrections,'lightsPreserved':lights,'newIntersectionPairs':0,'classicInternalIntersections':'Unchanged; existing classic joints/rounded primitive intersections not claimed absent.','sourceSHA256':hashlib.sha256(bpath.read_bytes()).hexdigest(),'variantSHA256':hashlib.sha256(vpath.read_bytes()).hexdigest()}
assert len(report['models'])==29
report['status']='PASS';report['expected']=29;report['ready']=29
report['classicOriginExceptions']={n:report['models'][n]['bounds'][0][1] for n in ['Chair','Posters','PendantLamp','NeonSign']}
report['originPolicy']='Exact accepted classic pivots/CFrames preserved, including original hanging/wall origins.'
report['visualReview']='Author inspected all29 previews and contact sheet;PASS;notStudioTest'
report['totalParts']=sum(x['partsVariant'] for x in report['models'].values())
report['totalFunctionalParts']=sum(x['functionalPartsUnchanged'] for x in report['models'].values())
report['totalSemanticParts']=sum(x['semanticContentPartsPreserved'] for x in report['models'].values())
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:29models; exact geometry/class/name/pivot/functional/light-location preservation; no new intersections')
