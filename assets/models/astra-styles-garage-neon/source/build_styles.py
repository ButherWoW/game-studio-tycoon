"""V15 variants from exact accepted XML snapshots. Original transforms stay untouched."""
from geometry import *
import subprocess, colorsys
import sys
sys.path.insert(0,'/private/tmp/gst-render-libs')
import numpy as np
MANIFEST=json.loads((ROOT/'baseline/manifest.json').read_text());ZONES=MANIFEST['zones'];STYLES=['Neon']
INV_MAT={v:k for k,v in MAT.items()}

def val(p,tag,name,default=None):return p.findtext(f"{tag}[@name='{name}']",default)
def readvec(p,name):
 e=p.find(f"Vector3[@name='{name}']");return tuple(float(e.findtext(a)) for a in 'XYZ')
def readframe(p,name='CFrame'):
 e=p.find(f"CoordinateFrame[@name='{name}']");return tuple(float(e.findtext(a)) for a in 'XYZ'),tuple(float(e.findtext(f'R{i}{j}')) for i in range(3) for j in range(3))
def native_parts(root):return [e for e in root.iter('Item') if e.get('class') in ['Part','Seat','WedgePart']]
def parsepart(e):
 p=e.find('Properties');pos,r=readframe(p);sz=readvec(p,'size');color=p.find("Color3[@name='Color']")
 if color is not None:c=tuple(round(float(color.findtext(a))*255) for a in 'RGB')
 else:
  packed=int(val(p,'Color3uint8','Color3uint8','0'));c=((packed>>16)&255,(packed>>8)&255,packed&255)
 return dict(name=val(p,'string','Name'),p=pos,r=r,s=sz,c=c,shape={'0':'ball','1':'box','2':'cyl'}.get(val(p,'token','shape','1'),'box'),mat=INV_MAT.get(int(val(p,'token','Material','272')),'SmoothPlastic'),alpha=float(val(p,'float','Transparency','0')),collide=val(p,'bool','CanCollide','false')=='true',cls=e.get('class'))
def fromxml(root):return [parsepart(e) for e in native_parts(root)]
def bounds(ps):
 lo=[float('inf')]*3;hi=[-float('inf')]*3
 for p in ps:
  if p['alpha']>=.99:continue
  h=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  for i in range(3):lo[i]=min(lo[i],p['p'][i]-h[i]);hi[i]=max(hi[i],p['p'][i]+h[i])
 return lo,hi

def sat(a,b,tol=.0001):
 A=np.asarray(a['r']).reshape(3,3);B=np.asarray(b['r']).reshape(3,3);delta=np.array(b['p'])-a['p'];ah=np.array(a['s'])/2;bh=np.array(b['s'])/2
 for axis in list(A.T)+list(B.T)+[np.cross(x,y) for x in A.T for y in B.T]:
  length=np.linalg.norm(axis)
  if length<1e-8:continue
  axis=axis/length;ra=np.sum(np.abs(axis@A)*ah);rb=np.sum(np.abs(axis@B)*bh)
  if abs(delta@axis)>=ra+rb-tol:return False
 return True

def collision_free(extra,base):
 from itertools import combinations
 visible=[p for p in base if p['alpha']<.99 or protect(p)]
 return not any(sat(a,b) for a in extra for b in visible) and not any(sat(a,b) for a,b in combinations(extra,2))

def within_bounds(extra,base):
 blo,bhi=bounds(base);lo,hi=bounds(base+extra)
 return abs(lo[1]-blo[1])<1e-6 and all(abs((hi[i]-lo[i])-(bhi[i]-blo[i]))<=.2+1e-6 for i in range(3))

def setcolor(pr,c):
 e=pr.find("Color3[@name='Color']")
 if e is None:e=ET.SubElement(pr,'Color3',{'name':'Color'})
 for a,v in zip('RGB',rgb(c)):
  q=e.find(a)
  if q is None:q=ET.SubElement(e,a)
  q.text=str(v/255)
def setmaterial(pr,m):pr.find("token[@name='Material']").text=str(MAT[m])
def protect(p):return p['cls']=='Seat' or p['name'].startswith('BlueSeat') or p['name']=='SeatCushion'
def preserve_content(modelname,p):
 n=p['name'].lower()
 if modelname=='Posters':return p['name'] not in ['Frame','Pivot']
 if modelname=='ArtWall':return p['name'] not in ['ArtFrame','FrameGlow','GalleryFoot','GalleryPost']
 if modelname=='NeonSign':return p['name'] in ['ControllerNeon','DPadHorizontal','DPadVertical','ActionDot']
 return any(word in n for word in ['screen','pixel','character','cloud','appheader','timeline','editor','chart','trophy','ship','status','led','taplever','fadercap','mixknob','keycap','spacebar','keyboard','powerbutton','star','button','book','sodacan','canmark','fish','controllerpad','controllerbutton']) or p['name'] in ['Key','Space','FanHub','MarqueeGem','WatchFace','Display']

def stylecolor(p,style):
 n=p['name'].lower();c=p['c'];h,s,v=colorsys.rgb_to_hsv(*(a/255 for a in c))
 natural=any(a in n for a in ['leaf','foliage','weed','soil','fish','petal','book','pixel','editor','screen','key','chart','trophy','soda','canmark'])
 if natural:return None
 if style=='Neon':
  if p['mat']=='Neon' or any(a in n for a in ['edge','trim','stripe','pull','handle','seam','rib']):return '00E5FF' if sum(map(ord,n))%2 else '7C4DFF'
  return '303047' if 'cushion' in n or 'seat' in n else '1E1E2E'
 if style=='Cozy':
  if p['mat']=='Neon':return 'FFD9A0'
  if any(a in n for a in ['seat','cushion','fabric','sofa','bean','soft','backinset']):return '9BAF9C'
  if any(a in n for a in ['monitor','screen','tower','console','speaker','server','rack','fan']):return '414B52'
  return 'C8A27A' if (p['mat'] in ['Wood','WoodPlanks','Metal'] or any(a in n for a in ['case','frame','shelf','desktop','leg','rail','body'])) else 'E8DDC9'
 if p['mat']=='Neon':return 'B9DAD5'
 return 'C8A27A' if any(a in n for a in ['top','shelf','rail','foot','leg','wood']) else 'F2F2F2'

def variant(name,style):
 tree=ET.parse(ROOT/'baseline/models'/f'{name}.rbxmx');root=tree.getroot();mn=root.find("./Item[@class='Model']");mn.find("./Properties/string[@name='Name']").text=name+'_'+style
 elements=native_parts(root);base=[parsepart(e) for e in elements]
 for e,p in zip(elements,base):
  if p['alpha']>=.99 or preserve_content(name,p):continue
  pr=e.find('Properties');col=stylecolor(p,style)
  if col:setcolor(pr,col)
  if p['mat'] not in ['Glass','Neon'] and not protect(p):
   if style=='Neon' and col:setmaterial(pr,'Metal' if 'seat' not in p['name'].lower() else 'SmoothPlastic')
   elif style=='Cozy' and col and col=='C8A27A':setmaterial(pr,'Wood')
   elif style=='Minimal' and col:setmaterial(pr,'Wood' if col=='C8A27A' else 'SmoothPlastic')
 # Distinct physical trim without altering functional geometry or overall silhouette.
 budget=int(len(base)*.2+1e-8);extra=model('StyleDetail');normal=(0,0,1)
 candidates=[p for p in base if p['alpha']<.4 and not protect(p) and p['shape']=='box' and min(p['s'][0],p['s'][1])>.18 and not any(a in p['name'].lower() for a in ['screen','key','soil','pixel','leaf','joint'])]
 # Prefer usable front surface; a large frame/cabinet panel forms the visual anchor.
 if candidates and budget:
  visible=[p for p in candidates if 'DrawerFront' in p['name']] if name in ['Desk1','Desk2'] else []
  host=max(visible or candidates,key=lambda p:p['s'][0]*p['s'][1]);sx,sy,sz=host['s'];R=host['r'];pos=host['p'];w=max(.15,sx*.84);h=max(.04,min(sy*.18,.20,sx*.06));yy=-sy*.34;zz=sz/2+.035;normal=(R[2],R[5],R[8])
  def emit(n,off,size,c,shape='box',mat='SmoothPlastic'):
   part(extra,style+n,add(pos,mv(R,off)),size,c,shape,r=R,mat=mat)
  if style=='Neon':
   # Physical light strips inset along front corners, not additional PointLights.
   emit('LightRail',(0,yy,zz),(w,.045,.035),'00E5FF',mat='Neon')
   if budget>=2:emit('AccentRail',(0,min(sy*.35,sy/2-.05),zz),(w*.58,.04,.035),'7C4DFF',mat='Neon')
   if budget>=3:emit('StatusGem',(w*.42,yy+.12,zz),(.12,.12,.055),'7C4DFF',shape='ball',mat='Neon')
  elif style=='Cozy':
   # Raised textile/wood binding with visible seam strips; native curved end pads.
   emit('PaddedBinding',(0,yy,zz),(w,h,.045),'B5BEA0')
   if budget>=2:emit('StitchedSeam',(0,yy-h*.27,zz+.032),(w*.84,.024,.012),'EFE6D4')
   if budget>=4:
    for sign in [-1,1]:emit('SoftEnd',(sign*(w/2+h/2+.003),yy,zz),(h,h,.048),'B5BEA0',shape='ball')
  else:
   # Slim inset oak panel plus rounded white end caps creates a quieter silhouette.
   emit('OakInset',(0,yy,zz),(w*.7,h*.65,.034),'C8A27A',mat='Wood')
   if budget>=3:
    for sign in [-1,1]:emit('RoundedCap',(sign*(w*.35+h*.325+.003),yy,zz),(h*.65,h*.65,.038),'F2F2F2',shape='ball')
 if not extra['parts'] and budget:
  # Flat textiles such as Rug have no vertical panel: add physical woven/light inlay on top.
  horizontal=[p for p in base if p['alpha']<.4 and p['shape']=='box']
  if horizontal:
   host=max(horizontal,key=lambda p:p['s'][0]*p['s'][2]);sx,sy,sz=host['s'];R=host['r'];pos=host['p'];normal=(R[1],R[4],R[7])
   for j in range(min(budget,3)):
    off=(0,sy/2+.018,(j-1)*sz*.22);color=('00E5FF' if j%2==0 else '7C4DFF') if style=='Neon' else 'B5BEA0' if style=='Cozy' else 'C8A27A'
    part(extra,style+'WovenInlay',add(pos,mv(R,off)),(sx*.73,.024,max(.035,sz*.035)),color,r=R,mat='Neon' if style=='Neon' else 'Wood' if style=='Minimal' else 'SmoothPlastic')
 if not extra['parts'] and budget:
  # Two external partial rim bindings, not solid disks through the shade.
  lo,hi=bounds(base);normal=(0,0,1)
  for j in range(min(budget,2)):
   color=('00E5FF' if j==0 else '7C4DFF') if style=='Neon' else 'C8A27A' if style=='Cozy' else 'F2F2F2'
   box(extra,style+'RimBinding',(0,lo[1]+.34+j*.13,hi[2]+.025),(.62,.045,.03),color,mat='Neon' if style=='Neon' else 'Wood' if style=='Cozy' else 'SmoothPlastic')
 if name=='BeanBags':
  # Three visible textile knee pads/tuft inlays, one per seat; no hidden tag-only styling.
  extra['parts']=[]
  for seat in [p for p in base if p['name']=='SeatCushion']:
   pos=(seat['p'][0],seat['p'][1]+seat['s'][1]/2+.014,seat['p'][2]+.22)
   ball(extra,style+'SeatTuft',pos,(.82,.028,.58),'00E5FF' if style=='Neon' else 'E8DDC9' if style=='Cozy' else 'F2F2F2',mat='Neon' if style=='Neon' else 'SmoothPlastic')
 # Existing native light positions preserved, shadows disabled for all three styles.
 for light in root.findall(".//Item[@class='PointLight']"):
  pr=light.find('Properties');sh=pr.find("bool[@name='Shadows']")
  if sh is not None:sh.text='false'
  color='FFD9A0' if style=='Cozy' else 'BBDDD9' if style=='Minimal' else '79D5ED'
  setcolor(pr,color)
 # Monitor/display trim is placed above the physical bezel, never on its UI plane.
 monitor_name='MonitorCase' if name in ['PC1','PCPro'] else 'MonitorBezel' if name in ['OfficeDesk','FloorDesk'] else 'WideMonitor' if name=='SkyDesk' else 'Frame' if name=='Posters' else 'ArtFrame' if name=='ArtWall' else 'Shield' if name=='NeonSign' else None
 if monitor_name:
  extra['parts']=[];normal=(0,1,0)
  monitor=[p for p in base if p['name'].startswith(monitor_name)];lo,hi=bounds(monitor)
  # PCPro has two screens; leave each independent silhouette readable.
  groups=[[p for p in monitor if p['p'][0]<0],[p for p in monitor if p['p'][0]>0]] if name=='PCPro' else [monitor]
  if name in ['Posters','ArtWall']:groups=[[p for p in monitor if p['p'][0]==x] for x in sorted({p['p'][0] for p in monitor})]
  for group in groups:
   lo,hi=bounds(group);w=(hi[0]-lo[0])*.82;center=((lo[0]+hi[0])/2,hi[1]+.04,(lo[2]+hi[2])/2)
   part(extra,style+'BezelTopCap',center,(w,.06,.09),'00E5FF' if style=='Neon' else 'C8A27A' if style=='Cozy' else 'F2F2F2','ball' if style=='Cozy' else 'box',mat='Neon' if style=='Neon' else 'Wood' if style=='Cozy' else 'SmoothPlastic')
 # Find a real exterior surface using the complete base solids, not a rounded internal core.
 original=copy.deepcopy(extra['parts']);resolved=False
 for step in range(16):
  moved=copy.deepcopy(original)
  for p in moved:p['p']=add(p['p'],tuple(step*.01*x for x in normal))
  if collision_free(moved,base) and within_bounds(moved,base):extra['parts']=moved;resolved=True;break
 if not resolved:
  # Exposed outside frame/chassis edge. It stays outside every OBB and inside the dimension budget.
  # Do not cover monitors: those special top caps must succeed or fail visibly.
  if monitor_name:raise AssertionError((name,style,'monitor cap has no safe placement'))
  lo,hi=bounds(base);width=hi[0]-lo[0];height=hi[1]-lo[1];depth=hi[2]-lo[2]
  # A shallow narrow upper edge on the outermost +Z surface, away from seating apron volume.
  # Select a genuine solid on that surface, avoiding transparent glazing and fine UI art.
  visible=[p for p in base if p['alpha']<.4 and not protect(p)]
  front=max(visible,key=lambda p:bounds([p])[1][2]);fl,fh=bounds([front]);cy=(fl[1]+fh[1])/2;cx=(fl[0]+fh[0])/2
  w=max(.1,min((fh[0]-fl[0])*.65,width*.65,2.6));h=max(.025,min((fh[1]-fl[1])*.12,.12));z=hi[2]+.028
  extra['parts']=[]
  part(extra,style+'ExteriorBinding',(cx,cy,z),(w,h,.035),'00E5FF' if style=='Neon' else 'C8A27A' if style=='Cozy' else 'F2F2F2','ball' if style=='Cozy' else 'box',mat='Neon' if style=='Neon' else 'Wood' if style=='Cozy' else 'SmoothPlastic')
  assert collision_free(extra['parts'],base) and within_bounds(extra['parts'],base),(name,style,'no safe exterior binding')
 assert collision_free(extra['parts'],base),(name,style,'new/base or new/new collision')
 for i,p in enumerate(extra['parts']):write_part(p,mn,f'V15_{style}_{i}')
 assert len(extra['parts'])<=budget
 return root,len(extra['parts'])

def main():
 for zone,names in ZONES.items():
  for style in STYLES:
   out=ROOT/'models';out.mkdir(parents=True,exist_ok=True)
   for name in names:
    root,added=variant(name,style);dest=out/f'{name}_{style}.rbxmx';ET.ElementTree(root).write(dest,encoding='utf-8',xml_declaration=True)
    project=ROOT/'source'/'convert.project.json';project.write_text(json.dumps({'name':dest.stem,'tree':{'$path':str(dest)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(project),'-o',str(dest.with_suffix('.rbxm'))],check=True,capture_output=True)
   print(zone,style,len(names),'models built',flush=True)
 project.unlink()
if __name__=='__main__':main()
