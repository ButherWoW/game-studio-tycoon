"""V15 variants from exact accepted XML snapshots. Original transforms stay untouched."""
from geometry import *
import subprocess, colorsys
import sys
sys.path.insert(0,'/private/tmp/gst-render-libs')
import numpy as np
MANIFEST=json.loads((ROOT/'baseline/manifest.json').read_text());ZONES=MANIFEST['zones'];STYLES=['Sakura']
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


PALETTE={'wood':'E7CFAB','cream':'F8EBDD','pink':'D993AE','rose':'BF7294','brass':'CBA96E','dark':'55414A','metal':'DCCBB6','light':'FFD8B4'}

def finish_appearance(modelname,p):
 n=p['name'].lower(); c=p['c']
 if p['alpha']>=.99 or preserve_content(modelname,p):return None,None
 # Functional display artwork, books, vegetation, water and musical control marks stay legible.
 if any(w in n for w in ['leaf','foliage','soil','petal','water','liquid','bubble','drink','eye','fish']):return None,None
 if p['mat']=='Glass':return None,None
 if p['mat']=='Neon':return PALETTE['pink'],None
 if any(w in n for w in ['seat','cushion','fabric','sofa','bean','uphol','soft','backinset','rug','carpet']):return PALETTE['pink'],None
 if any(w in n for w in ['handle','pull','hinge','brass','trim','edge','seam','zip','accent','knob','spout','band']):return PALETTE['brass'],'Metal' if not protect(p) else None
 if p['mat'] in ['Wood','WoodPlanks'] or any(w in n for w in ['wood','desktop','tabletop','shelf','shelves','plank','slat']):return PALETTE['wood'],'Wood' if not protect(p) else None
 if any(w in n for w in ['monitor','bezel','screen','tower','speaker','server','console','fan','rack']):return PALETTE['dark'],None
 if any(w in n for w in ['leg','rail','stand','frame','support','foot','post']):return PALETTE['metal'],'Metal' if not protect(p) else None
 if min(c)<65 and max(c)<110:return PALETTE['dark'],None
 return PALETTE['cream'],'SmoothPlastic' if not protect(p) else None

def variant(name):
 root=ET.parse(ROOT/'baseline/models'/f'{name}.rbxmx').getroot();root.find("./Item[@class='Model']/Properties/string[@name='Name']").text=name+'_Sakura'
 count=0
 for e in native_parts(root):
  p=parsepart(e); col,mat=finish_appearance(name,p)
  if col:setcolor(e.find('Properties'),col);count+=1
  if mat:setmaterial(e.find('Properties'),mat)
 for light in root.findall(".//Item[@class='PointLight']"):
  pr=light.find('Properties');setcolor(pr,PALETTE['light']);sh=pr.find("bool[@name='Shadows']")
  if sh is not None:sh.text='false'
 return root,count

def main():
 metadata={}
 for zone,names in ZONES.items():
  for name in names:
   root,changed=variant(name);f=ROOT.parent/'models'/f'{name}_Sakura.rbxmx';ET.ElementTree(root).write(f,encoding='utf-8',xml_declaration=True)
   pr=ROOT/'source/convert.project.json';pr.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(f)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(pr),'-o',str(f.with_suffix('.rbxm'))],check=True,capture_output=True)
   metadata[name]={'zone':zone,'recoloredParts':changed,'parts':len(native_parts(root))}
 pr.unlink();(ROOT/'manifest.json').write_text(json.dumps({'theme':'Sakura','palette':PALETTE,'models':metadata,'geometryPolicy':'appearance-only; zero added parts'},indent=2)+'\n');print('Built',len(metadata),'Sakura variants')
if __name__=='__main__':main()
