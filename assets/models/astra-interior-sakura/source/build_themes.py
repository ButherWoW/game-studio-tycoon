import os, shutil
GST_ROJO_BIN=os.environ.get('GST_ROJO') or shutil.which('rojo') or '/Users/erland/.local/gst-tools/rojo'
"""Original premium architectural finishes; exact floor partitions, native parts only."""
from native_xml import *
from decimal import Decimal
import subprocess
THEMES={
 'obsidian-gold':{'suffix':'ObsidianGold','floor':['171823','242635'],'inlay':'D5B169','wall':'272731','frame':'C9A65D','ceilingColor':'242530','ceilingMaterial':'SmoothPlastic','glass':'8394AE','light':'FFE1AB','floorMaterial':'Marble'},
 'sakura':{'suffix':'Sakura','floor':['DEC2A2','F3E8DA'],'inlay':'D7A2B2','wall':'F7EFE5','frame':'BD9570','ceilingColor':'FFF1E8','ceilingMaterial':'SmoothPlastic','glass':'E7DAE3','light':'FFE0B8','floorMaterial':'WoodPlanks'},
 'aurora':{'suffix':'Aurora','floor':['223D5A','31516E'],'inlay':'75BFCF','wall':'263E5C','frame':'8CBFCC','ceilingColor':'23384F','ceilingMaterial':'SmoothPlastic','glass':'8CC8DE','light':'C4ECFF','floorMaterial':'SmoothPlastic'}
}
THEMES={'sakura':THEMES['sakura']}
SHELLS=['GarageWalls','Office','Floor','Skyscraper']
LEGACY=[('Desk1',(-12,0,-20),0),('PC1',(-12,3,-21),0),('Chair',(-12,0,-17.2),180),('Coffee',(25,0,-24),-90),('Posters',(0,3,-28.8),0),('HitShelf',(-27.6,0,-15),90)]
STAGES={
 'GarageWalls':LEGACY+[('Desk2',(4,0,-20),0),('PCPro',(4,3,-21),0)],
 'Office':LEGACY+[('OfficeDesk',(2,0,-20),0),('OfficeDesk',(12,0,-20),0),('OfficeDesk',(-4,0,-8),0),('Cooler',(26,0,-12),-90),('MeetingRoom',(-14,0,10),0)],
 'Floor':[('FloorDesk',(x,0,z),0) for x,z in [(0,-20),(9,-20),(18,-20),(-12,-6),(-2,-6),(8,-6),(18,-6)]]+[('ServerRoom',(26.5,0,-14),-90),('Lounge',(2,0,11),0)],
 'Skyscraper':[('SkyDesk',(x,0,z),0) for x,z in [(-3,-20),(5,-20),(13,-20),(21,-20),(-18,-8),(-9,-8),(0,-8),(9,-8),(18,-8),(-6,4),(6,4)]]+[('SoundStudio',(-18,0,14),0),('ArtWall',(15,0,16),0)]}

def furniture_parts(shell):
 out=[]
 for name,pos,yaw in STAGES[shell]:
  R=rot(y=yaw)
  for p in fromxml(ET.parse(ROOT/'baseline/models'/f'{name}.rbxmx').getroot()):
   if p['alpha']>=.99 and p['cls']!='Seat':continue
   p=copy.deepcopy(p);p['p']=add(pos,mv(R,p['p']));p['r']=mul(R,p['r']);p['owner']=name;out.append(p)
 return out

def make_intervals(size):
 # Decimal cuts: all positions/sizes serialize exactly as short decimal strings.
 D=Decimal;tile=D('9.8') if size==60 else D('9.5');line=D('.16') if size==60 else D('.12');border=D('.2');at=-D(size)/2;out=[]
 out.append((at,at+border,True));at+=border
 for i in range(6):
  out.append((at,at+tile,False));at+=tile
  if i<5:out.append((at,at+line,True));at+=line
 out.append((at,at+border,True));assert at+border==D(size)/2
 return [(float(a),float(b),isline) for a,b,isline in out]

def floor_geometry(name,theme):
 t=THEMES[theme];size=60 if name=='GarageWalls' else 58;y=-.12 if name=='GarageWalls' else .01;h=.24 if name=='GarageWalls' else .02;m=model('FloorPartition');segments=make_intervals(size)
 for i,(a,b,li) in enumerate(segments):
  for j,(c,d,lj) in enumerate(segments):
   inlay=li or lj;col=t['inlay'] if inlay else t['floor'][((i//2)+(j//2))%2]
   box(m,f'FinishFloor_{i:02}_{j:02}',((a+b)/2,y,(c+d)/2),(round(b-a,7),h,round(d-c,7)),col,mat='Metal' if inlay and theme=='obsidian-gold' else t['floorMaterial'] if not inlay else 'SmoothPlastic',collide=True)
 return m

def accent_geometry(shell,theme):
 m=model('WallAccents');t=THEMES[theme];z=-28.95 if shell=='GarageWalls' else -29.44
 if theme=='obsidian-gold':
  # Air-separated art-deco pilasters and a stepped lintel frieze; no thin wall decals.
  for x in [-8.2,-7.8,7.8,8.2]:box(m,'ArtDecoPilaster',(x,9.85,z),(.09,3.6,.035),t['frame'],mat='Metal')
  for x,w,y in [(0,13.3,12.0),(0,10.8,11.76),(0,8.3,11.52)]:box(m,'ArtDecoFrieze',(x,y,z),(w,.07,.035),t['frame'],mat='Metal')
 elif theme=='sakura':
  for x in [-6,6]:
   box(m,'ShojiPaper',(x,10,z),(3.4,2.6,.035),'FFF5EA')
   for dx in [-1.75,1.75]:box(m,'ShojiStile',(x+dx,10,z),(.1,2.6,.05),t['frame'],mat='Wood')
   for y in [8.65,11.35]:box(m,'ShojiRail',(x,y,z),(3.6,.1,.05),t['frame'],mat='Wood')
   # Small original geometric blossom, strictly separated petals in front of paper.
   for j in range(5):
    a=j*TAU/5;ball(m,'SakuraPetal',(x+.28*math.cos(a),10+.28*math.sin(a),z+.055),(.20,.20,.022),'EFA2BF')
   ball(m,'SakuraHeart',(x,10,z+.055),(.11,.11,.022),'D7AE6B')
 elif theme=='aurora':
  for j,x in enumerate([-7.2,-3.6,0,3.6,7.2]):
   y=10.0+.5*math.sin(j*1.1)
   box(m,'AuroraRibbon',(x,y,z),(.18,2.0,.035),['7ED9E2','ACA9E8'][j%2],r=rot(z=-18+j*9),mat='Neon')
 return m

ARCH_PREFIX=('Side','Rear','Front','Entrance','CentralWall','Window','Door','Timber','StoneFoot','Siding','Skirting','Ceiling','LampCase','PanelCase','Diffuser','LampDiffuser','Roof','Rafter','EaveBeam','Shade','Bulb')
def style_shell_part(p,t,theme):
 n=p['name']
 if not n.startswith(ARCH_PREFIX):return None,None
 if p['mat']=='Glass':return t['glass'],'Glass'
 if theme=='sakura' and any(w in n for w in ['Base','Bottom']):return 'EAC8D6','SmoothPlastic'
 if n=='Roof' or n.startswith('Ceiling'):return t['ceilingColor'],t['ceilingMaterial']
 if p['mat']=='Neon' or 'Diffuser' in n:return t['light'],'Neon'
 if any(w in n for w in ['Mullion','Frame','Transom','Join','Rail','Post','Skirting','Beam','Hinge','Handle','Crossbar','LampCase','PanelCase','Rim','Rafter']):return t['frame'],'Metal' if theme!='sakura' else 'Wood'
 if n=='StoneFoot':return t['frame'],'Metal' if theme=='obsidian-gold' else 'Concrete'
 return t['wall'],'Marble' if theme=='obsidian-gold' else 'SmoothPlastic'

def create_shell(name,theme):
 t=THEMES[theme];tree=ET.parse(ROOT/'baseline/models'/f'{name}.rbxmx');root=tree.getroot();mn=root.find("./Item[@class='Model']");mn.find("Properties/string[@name='Name']").text=name+'_'+t['suffix'];parents={child:parent for parent in root.iter() for child in parent};baseparts=native_parts(root)
 remove=[];floor_e=None
 for e in baseparts:
  p=parsepart(e);n=p['name']
  if n in ['Floor','ConcreteFloor']:floor_e=e;remove.append(e)
  elif n in ['FloorJointX','FloorJointZ','FloorJoint','PlankJoint','PlankEnd']:remove.append(e)
  else:
   col,mat=style_shell_part(p,t,theme)
   if col:setcolor(e.find('Properties'),col);setmaterial(e.find('Properties'),mat)
 assert floor_e is not None
 floor_ref=floor_e.get('referent');floor_was_primary=mn.findtext("Properties/Ref[@name='PrimaryPart']")==floor_ref
 for e in remove:parents[e].remove(e)
 modified=[];structural=model('Entrance')
 if name=='Office':
  # Current classic Office is60x11 open: premium shell adopts specified24x9, without moving furniture.
  # Preserve the accepted upper header/beam joints; fill only new Y9..11 with an open soffit.
  box(structural,'PremiumEntrySoffit',(0,10,29.75),(59,2,.5),t['wall'],mat='Marble' if theme=='obsidian-gold' else 'SmoothPlastic',collide=True)
  for x in [-20.75,20.75]:
   box(structural,'PremiumFrontBase',(x,.55,29.75),(17.5,1.1,.5),t['wall'],mat='Marble' if theme=='obsidian-gold' else 'SmoothPlastic',collide=True)
   box(structural,'PremiumFrontGlass',(x,5.05,29.75),(17.5,7.9,.08),t['glass'],mat='Glass',alpha=.64,collide=True)
 for light in root.findall(".//Item[@class='PointLight']"):
  pr=light.find('Properties');sh=pr.find("bool[@name='Shadows']")
  if sh is not None:sh.text='false'
  setcolor(pr,t['light'])
 floors=floor_geometry(name,theme)
 for i,p in enumerate(floors['parts']):
  ref=floor_ref if i==0 else f'PREMIUM_FLOOR_{i}';node=write_part(p,mn,ref)
  if i==0 and floor_was_primary:
   pr=node.find('Properties');frame(pr,'PivotOffset',tuple(-v for v in p['p']))
 for i,p in enumerate(structural['parts']):write_part(p,mn,f'PREMIUM_ENTRY_{i}')
 # Test architectural additions against every actual shell solid and current stage furniture.
 remaining=[p for p in fromxml(root) if p['alpha']<.99 and not p['name'].startswith('FinishFloor_')]
 stage=furniture_parts(name);acc=accent_geometry(name,theme);placed=[];moves=[]
 for i,p in enumerate(acc['parts']):
  resolved=None
  for step in range(16):
   q=copy.deepcopy(p);q['p']=add(p['p'],(0,0,step*.01))
   if not any(sat(q,b) for b in remaining+stage+placed):resolved=q;moves.append(round(step*.01,3));break
  assert resolved is not None,(name,theme,p['name'],'no collision-free wall mount')
  placed.append(resolved);write_part(resolved,mn,f'PREMIUM_ACCENT_{i}')
 return root,{'floorPartNames':[p['name'] for p in floors['parts']],'floorXZ':[-30,30,-30,30] if name=='GarageWalls' else [-29,29,-29,29],'floorY':[-.24,0] if name=='GarageWalls' else [0,.02],'newAccentNames':[p['name'] for p in placed],'newAccentReferents':[f'PREMIUM_ACCENT_{i}' for i in range(len(placed))],'newEntryReferents':[f'PREMIUM_ENTRY_{i}' for i in range(len(structural['parts']))],'modifiedStructuralReferents':modified,'wallNormalOffsetStuds':moves,'ceilingColor':t['ceilingColor'],'ceilingMaterial':t['ceilingMaterial']}

def main():
 for theme,t in THEMES.items():
  dest=ROOT;(dest/'models').mkdir(parents=True,exist_ok=True);(dest/'previews').mkdir(exist_ok=True);manifest={'theme':t['suffix'],'premium':True,'noPriceOrProductIDs':True,'sourceCommit':json.loads((ROOT/'baseline/manifest.json').read_text())['sourceCommit'],'ceilingColor':t['ceilingColor'],'ceilingMaterial':t['ceilingMaterial'],'models':{},'runtimeIntegration':'Separate profile interiorFinish selection; do not reuse furniture.selected. OfficeFloors FloorSlab topY=-.01 remains below floor partition; color its underside with ceilingColor/ceilingMaterial. Do not add full Office/Floor ceilings.'}
  for name in SHELLS:
   root,meta=create_shell(name,theme);f=dest/'models'/f'{name}_{t["suffix"]}.rbxmx';ET.ElementTree(root).write(f,encoding='utf-8',xml_declaration=True);manifest['models'][name+'_'+t['suffix']]=meta
   project=ROOT/'source/convert.project.json';project.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(f)}}));subprocess.run([GST_ROJO_BIN,'build',str(project),'-o',str(f.with_suffix('.rbxm'))],check=True,capture_output=True)
   print(theme,name,'built',flush=True)
  (dest/'manifest.json').write_text(json.dumps(manifest,indent=2))
 project.unlink()
if __name__=='__main__':main()
