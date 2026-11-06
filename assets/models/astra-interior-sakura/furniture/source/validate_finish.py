"""Independent comparison of final XML with accepted classic snapshots."""
from pathlib import Path
import xml.etree.ElementTree as E
import json,hashlib,math
ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'baseline/manifest.json').read_text());results={}
PARTS={'Part','Seat','WedgePart'}
def pr(e):return {v.attrib['name']:v for v in e.find('Properties')}
def txt(e):return E.tostring(e,encoding='unicode')
def geom(e):
 p=pr(e);return tuple(txt(p[n]) for n in ['CFrame','size','shape'] if n in p)
def content(model,n):
 s=n.lower()
 if model=='Posters':return n not in ['Frame','Pivot']
 if model=='ArtWall':return n not in ['ArtFrame','FrameGlow','GalleryFoot','GalleryPost']
 if model=='NeonSign':return n in ['ControllerNeon','DPadHorizontal','DPadVertical','ActionDot']
 return any(w in s for w in ['screen','pixel','character','cloud','appheader','timeline','editor','chart','trophy','ship','status','led','taplever','fadercap','mixknob','keycap','spacebar','keyboard','powerbutton','star','button','book','sodacan','canmark','fish','controllerpad','controllerbutton']) or n in ['Key','Space','FanHub','MarqueeGem','WatchFace','Display']
def bounds(items,visible=False):
 lo=[1e9]*3;hi=[-1e9]*3
 for e in items:
  p=pr(e)
  if visible and float(p.get('Transparency',E.Element('float')).text or '0')>=.99:continue
  cf=p['CFrame'];pos=[float(cf.findtext(k)) for k in 'XYZ'];size=[float(p['size'].findtext(k)) for k in 'XYZ'];r=[[float(cf.findtext(f'R{i}{j}')) for j in range(3)] for i in range(3)]
  for i in range(3):h=sum(abs(r[i][j])*size[j]/2 for j in range(3));lo[i]=min(lo[i],pos[i]-h);hi[i]=max(hi[i],pos[i]+h)
 return lo,hi
for zone,names in manifest['zones'].items():
 for name in names:
  src=ROOT/'baseline/models'/f'{name}.rbxmx';dst=ROOT.parent/'models'/f'{name}_Sakura.rbxmx';a=E.parse(src).getroot();b=E.parse(dst).getroot();ai=a.findall('.//Item');bi=b.findall('.//Item');assert len(ai)==len(bi)
  shape=0;changed=0;protected=0;seats=0;lights=0;shadowChanges=[]
  for idx,(x,y) in enumerate(zip(ai,bi)):
   assert x.attrib==y.attrib,(name,idx,'item identity changed')
   xp,yp=pr(x),pr(y);assert set(xp)==set(yp),(name,idx,'properties changed');cls=x.attrib['class'];allowed=set()
   if cls in PARTS:allowed={'Color','Color3uint8','Material'};shape+=1;assert geom(x)==geom(y)
   if cls=='PointLight':allowed={'Color','Shadows'};lights+=1;assert yp['Shadows'].text=='false'
   if cls=='PointLight' and xp['Shadows'].text!=yp['Shadows'].text:shadowChanges.append({'name':xp['Name'].text,'from':xp['Shadows'].text,'to':yp['Shadows'].text})
   for k in xp:
    if idx==0 and k=='Name':assert yp[k].text==name+'_Sakura';continue
    if k not in allowed:assert txt(xp[k])==txt(yp[k]),(name,idx,k)
   if cls in PARTS:
    if any(txt(xp[k])!=txt(yp[k]) for k in allowed if k in xp):changed+=1
    n=xp['Name'].text
    if content(name,n):
     protected+=1
     for k in allowed:
      if k in xp:assert txt(xp[k])==txt(yp[k]),(name,n,'art content modified')
    if cls=='Seat' or n.startswith('BlueSeat') or n=='SeatCushion':seats+=1
  assert changed>0,(name,'no appearance change');aps=[e for e in ai if e.attrib['class']in PARTS];bps=[e for e in bi if e.attrib['class']in PARTS];assert bounds(aps)==bounds(bps)
  forbidden={'Script','LocalScript','ModuleScript','MeshPart','SpecialMesh','Texture','Decal','SurfaceAppearance'};assert not {e.attrib['class'] for e in bi}&forbidden
  binary=dst.with_suffix('.rbxm');assert binary.read_bytes().startswith(b'<roblox!')
  nativeBounds=bounds(bps);lo,hi=bounds(bps,True);results[name]={'zone':zone,'partsClassic':shape,'partsVariant':shape,'changedAppearanceParts':changed,'protectedArtworkParts':protected,'functionalSeatPartsPreserved':seats,'lightsPreserved':lights,'dimensionsXYZ':[hi[i]-lo[i] for i in range(3)],'classicVisibleBounds':[lo,hi],'classicAllNativeBounds':nativeBounds,'lowestYUnchanged':lo[1],'boundsIdentical':True,'geometryPropertiesIdentical':True,'allOtherPropertiesIdenticalExceptRequiredLightShadowFlag':True,'requiredShadowChanges':shadowChanges,'hierarchyAndReferencesIdentical':True,'pairsCoveredByGeometryIdentity':shape*(shape-1)//2,'newIntersections':0,'baselineIntersectionGraph':'unchanged; existing classic primitive joints are not asserted overlap-free','sha256XML':hashlib.sha256(dst.read_bytes()).hexdigest(),'sha256RBXM':hashlib.sha256(binary.read_bytes()).hexdigest(),'status':'PASS'}
assert len(results)==29
(ROOT/'VALIDATION.json').write_text(json.dumps({'expected':29,'ready':29,'theme':'Sakura','method':'Independent XML comparison; hierarchy/references/geometry invariant; only appearance and required Shadows=false flag may differ','intersectionMethod':'Identical native geometry implies identical pairwise intersection graph; no added Parts','sourceSHA256Verified':all(hashlib.sha256((ROOT/'baseline/models'/f'{n}.rbxmx').read_bytes()).hexdigest()==manifest['sha256'][n] for n in results),'models':results,'status':'PASS','runtimeTested':False,'mountingOriginNote':'Classic model origins remain exact: hanging/wall templates are not ground-normalized; any existing negative/positive minY is retained.'},indent=2)+'\n');print('PASS29Sakura models; preserved geometry and functional XML')
