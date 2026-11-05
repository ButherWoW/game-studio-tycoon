from build_themes import *
from render_geometry import preview
from itertools import combinations
import numpy as np

def bb_overlap(a,b,t=.0001):return all(min(a[1][i],b[1][i])-max(a[0][i],b[0][i])>t for i in range(3))
def floor_cover(ps,foot):
 rects=[]
 for p in ps:
  assert p['shape']=='box' and np.max(abs(np.array(p['r'])-np.array(I)))<1e-7
  lo,hi=bounds([p]);rects.append((round(lo[0],6),round(hi[0],6),round(lo[2],6),round(hi[2],6)))
 xs=sorted({v for r in rects for v in r[:2]});zs=sorted({v for r in rects for v in r[2:]});assert [xs[0],xs[-1],zs[0],zs[-1]]==foot
 area=0;cells=0
 for a,b in zip(xs,xs[1:]):
  for c,d in zip(zs,zs[1:]):
   x=(a+b)/2;z=(c+d)/2;count=sum(A<=x<=B and C<=z<=D for A,B,C,D in rects);assert count==1,('floor cell',a,b,c,d,count);area+=(b-a)*(d-c);cells+=1
 assert abs(area-(foot[1]-foot[0])*(foot[3]-foot[2]))<1e-6
 assert all(not bb_overlap(bounds([a]),bounds([b])) for a,b in combinations(ps,2))
 return {'compressedCells':cells,'coverageMultiplicity':1,'areaStuds2':round(area,6),'gaps':0,'overlappingCells':0}

def pivot(root):
 mn=root.find("./Item[@class='Model']");ref=mn.findtext("Properties/Ref[@name='PrimaryPart']");pr=root.find(f".//Item[@referent='{ref}']/Properties");p,R=readframe(pr);o,rr=readframe(pr,'PivotOffset') if pr.find("CoordinateFrame[@name='PivotOffset']") is not None else ((0,0,0),I);return np.array(p)+np.array(R).reshape(3,3)@np.array(o)

def validate(theme):
 t=THEMES[theme];dest=ROOT;man=json.loads((dest/'manifest.json').read_text());report={'sourceCommit':man['sourceCommit'],'theme':t['suffix'],'studioTested':False,'ceilingColor':t['ceilingColor'],'ceilingMaterial':t['ceilingMaterial'],'models':{}}
 for name in SHELLS:
  key=name+'_'+t['suffix'];root=ET.parse(dest/'models'/f'{key}.rbxmx').getroot();ps=fromxml(root);meta=man['models'][key];floor=[p for p in ps if p['name'] in meta['floorPartNames']];assert len(floor)==169;coverage=floor_cover(floor,meta['floorXZ']);base=ET.parse(ROOT/'baseline/models'/f'{name}.rbxmx').getroot();bps=fromxml(base);oldfloor=next(p for p in bps if p['name'] in ['Floor','ConcreteFloor']);olo,ohi=bounds([oldfloor]);flo=bounds(floor)
  assert all(all(bounds([p])[0][i]>=olo[i]-1e-6 and bounds([p])[1][i]<=ohi[i]+1e-6 for i in range(3)) for p in floor),('outside old floor volume',name)
  assert abs(flo[0][1]-meta['floorY'][0])<1e-6 and abs(flo[1][1]-meta['floorY'][1])<1e-6
  assert np.max(abs(pivot(root)))<1e-6
  assert len(ps)<=600,(name,len(ps))
  refs={e.get('referent'):e for e in native_parts(root)};newrefs=meta['newAccentReferents']+meta['newEntryReferents'];new=[parsepart(refs[r]) for r in newrefs];old=[parsepart(e) for r,e in refs.items() if r not in newrefs and r not in meta['modifiedStructuralReferents'] and parsepart(e)['alpha']<.99 and not parsepart(e)['name'].startswith('FinishFloor_')];struct=[parsepart(refs[r]) for r in meta['modifiedStructuralReferents']];stage=furniture_parts(name)
  hits=[(a['name'],b['name']) for a in new+struct for b in old if sat(a,b)];assert not hits,(name,theme,'new architecture/base',hits[:8])
  furniture_hits=[(a['name'],b['owner'],b['name']) for a in new+struct for b in stage if sat(a,b)];assert not furniture_hits,(name,theme,'new architecture/stage',furniture_hits[:8])
  self_hits=[(a['name'],b['name']) for a,b in combinations(new+struct,2) if sat(a,b)];assert not self_hits,(name,theme,'new architecture/new',self_hits[:8])
  envelopes=[]
  for fn,pos,yaw in STAGES[name]:
   R=rot(y=yaw);furn=fromxml(ET.parse(ROOT/'baseline/models'/f'{fn}.rbxmx').getroot())
   for p in furn:p['p']=add(pos,mv(R,p['p']));p['r']=mul(R,p['r'])
   l,h=bounds(furn);envelopes.append((fn,([v-.2 for v in l],[v+.2 for v in h])))
  envelope_hits=[(a['name'],fn) for a in new+struct for fn,bb in envelopes if bb_overlap(bounds([a]),bb)]
  assert not envelope_hits,(name,theme,'V15-compatible expanded furniture envelope',envelope_hits)
  lo,hi=bounds(ps);blo,bhi=bounds(bps)
  assert all(abs(lo[i]-blo[i])<1e-5 and abs(hi[i]-bhi[i])<1e-5 for i in range(3)),(name,'shell AABB differs',lo,hi,blo,bhi)
  lift=([-23,.03,21],[-17,7,27])
  solid=[p for p in ps if p['alpha']<.99 and not p['name'].startswith('FinishFloor_')]
  assert all(not bb_overlap(bounds([p]),lift) for p in solid),(name,'lift blocked')
  if name!='GarageWalls':
   entry=([-12,.03,29.5],[12,9,30]);assert all(not bb_overlap(bounds([p]),entry) for p in solid),(name,'entry blocked')
  if name!='GarageWalls':assert all(bounds([p])[1][1]<=13+1e-6 for p in solid if p['name']!='Roof'),(name,'wall height')
  roofs=[p for p in ps if p['name']=='Roof'];assert len(roofs)==(1 if name=='Skyscraper' else 0)
  if roofs:assert bounds(roofs)[0][1]==13 and bounds(roofs)[1][1]==14
  classes={e.get('class') for e in root.iter('Item')};assert classes<={'Model','Part','PointLight'}
  lights=root.findall(".//Item[@class='PointLight']");assert all(e.findtext("Properties/bool[@name='Shadows']")=='false' for e in lights)
  assert len(lights)==len(base.findall(".//Item[@class='PointLight']"));assert all(len(e.findall("./Item[@class='PointLight']"))<=1 for e in native_parts(root))
  assert (dest/'models'/f'{key}.rbxm').read_bytes().startswith(b'<roblox!')
  report['models'][key]={'parts':len(ps),'dimensionsXYZ':[round(hi[i]-lo[i],5) for i in range(3)],'boundsMin':lo,'boundsMax':hi,'pivot':[0,0,0],'floorPartNames':meta['floorPartNames'],'floorXZ':meta['floorXZ'],'floorY':meta['floorY'],'floorCoverage':coverage,'floorFloorPairs':len(floor)*(len(floor)-1)//2,'floorFloorOverlaps':0,'floorSupportDelta':'Every floor tile lies inside the old slab volume; existing0...02 foot contact is inherited and not increased.','newArchitectureParts':len(new)+len(struct),'newArchitectureBaseSAT':{'pairs':(len(new)+len(struct))*len(old),'overlaps':0},'newArchitectureStageSAT':{'pairs':(len(new)+len(struct))*len(stage),'overlaps':0},'newArchitectureSelfSAT':{'pairs':(len(new)+len(struct))*(len(new)+len(struct)-1)//2,'overlaps':0},'stageFurnitureStyleEnvelope':{'expansionEachSideStuds':.2,'modelCount':len(envelopes),'pairs':(len(new)+len(struct))*len(envelopes),'overlaps':0,'purpose':'Conservative compatibility envelope for all accepted V15 furniture styles; support floor contact excluded.'},'pointLights':len(lights),'lightShadows':False,'roof':bool(roofs),'checks':'PASS'}
 report['checks']=['169 axis-aligned box floor segments, exact compressed-grid coverage once','floor partitions remain in old slab volume, no coplanar decal overlays','same model pivot and total shell AABB','new architecture vs actual shell/stage furniture/new architecture OBB SAT zero','floor tiles pairwise nonintersecting','lift6x6x7 empty above common floor','24x9 entry for office floors; accepted open Garage exception','no roof except thirdfloor13..14','office floor walls<=13; accepted high garage rafters preserved','native Part/Model/PointLight only','one shadowless light per existing source','<=600 Parts per shell','Rojo binary exports']
 (dest/'VALIDATION.json').write_text(json.dumps(report,indent=2));print(theme,{n:m['parts'] for n,m in report['models'].items()},flush=True)
 return report

def cutaway_parts(name,theme):
 t=THEMES[theme];root=ET.parse(ROOT/'models'/f'{name}_{t["suffix"]}.rbxmx').getroot();ps=fromxml(root);out=[]
 for p in ps:
  n=p['name'];x,y,z=p['p']
  if n=='Roof' or n.startswith(('Front','PremiumFront','PremiumEntry','Entrance')):continue
  if n in ['CeilingBeam','Suspension','PanelCase','Diffuser','LampCase','LampDiffuser']:continue
  if name=='GarageWalls' and n in ['Rafter','EaveBeam','CeilingCap','Cable','Shade','ShadeRim','Bulb']:continue
  # Near (+X) external side cut away; actual geometry remains in model exports.
  if x>28 and any(w in n for w in ['Side','Window','Timber','StoneFoot','Siding','Skirting']):continue
  out.append(p)
 return out+furniture_parts(name)

def render(theme):
 t=THEMES[theme];dest=ROOT
 for name in SHELLS:
  ps=cutaway_parts(name,theme);preview(ps,dest/'previews'/f'{name}_{t["suffix"]}_Furnished.png',yaw=26,elev=43,span=94,target=(0,2.7,0),W=1800,H=1400)
 preview(cutaway_parts('Office',theme),dest/'previews'/'ShopCard_FullRoom_QA_512.png',yaw=26,elev=47,span=95,target=(0,2.7,0),W=512,H=512)
 preview(cutaway_parts('Office',theme),dest/'previews'/'Office_Detail.png',yaw=20,elev=26,span=32,target=(0,6.3,-24),W=1400,H=1100)
 preview(cutaway_parts('Office',theme),dest/'ShopCard_512.png',yaw=20,elev=26,span=32,target=(0,6.3,-24),W=512,H=512)

if __name__=='__main__':
 for theme in THEMES:validate(theme)
 for theme in THEMES:render(theme)
