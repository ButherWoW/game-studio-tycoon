"""V15 variants from exact accepted XML snapshots. Original transforms stay untouched."""
from geometry import *
import subprocess, colorsys, os
import sys
sys.path.insert(0,'/private/tmp/gst-render-libs')
import numpy as np
MANIFEST=json.loads((ROOT/'baseline/manifest.json').read_text());ZONES=MANIFEST['zones'];STYLES=['Aurora']
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


THEME='Aurora'
PALETTE={'navy':'24364F','deep':'172B42','ice':'D1E2EB','metal':'A7BECE','fabric':'727EC0','seam':'A9BAF2','cyan':'7DE1EC','violet':'A998EF'}
def recolor(p):
 n=p['name'].lower()
 if any(t in n for t in ['leaf','foliage','weed','soil','petal','stem','trunk','water','coffee','liquid']):return None,None
 if p['mat']=='Glass':return PALETTE['cyan'],'Glass'
 if p['mat']=='Neon':return PALETTE['cyan'] if sum(map(ord,n))%2 else PALETTE['violet'],'Neon'
 if any(t in n for t in ['seat','cushion','fabric','sofa','bean','soft','backinset']):return PALETTE['seam'] if any(t in n for t in ['seam','piping','stitch']) else PALETTE['fabric'],'SmoothPlastic'
 if any(t in n for t in ['edge','trim','handle','pull','seam','rib','accent','frameglow']):return PALETTE['cyan'] if sum(map(ord,n))%2 else PALETTE['violet'],'Metal'
 if any(t in n for t in ['monitor','tower','console','speaker','server','rack','fan','case','chassis']):return PALETTE['navy'],'Metal'
 if any(t in n for t in ['leg','rail','foot','post','frame','support','pedestal','hinge','bracket','rod','stem']):return PALETTE['metal'],'Metal'
 if p['mat'] in ['Wood','WoodPlanks'] or any(t in n for t in ['desktop','worktop','tabletop','shelf','drawer','board','top','door']):return PALETTE['ice'],'SmoothPlastic'
 return PALETTE['deep'] if sum(p['c'])<330 else PALETTE['ice'],'SmoothPlastic'

def build():
 changes={}
 for zone,names in ZONES.items():
  for name in names:
   root=ET.parse(ROOT/'baseline/models'/f'{name}.rbxmx').getroot();root.find("./Item/Properties/string[@name='Name']").text=name+'_'+THEME;count=0;protected=0
   for e in native_parts(root):
    p=parsepart(e)
    if p['alpha']>=.99 or preserve_content(name,p):protected+=1;continue
    col,mat=recolor(p)
    if not col:protected+=1;continue
    pr=e.find('Properties');setcolor(pr,col)
    if mat:setmaterial(pr,mat)
    count+=1
   for light in root.findall(".//Item[@class='PointLight']")+root.findall(".//Item[@class='SpotLight']")+root.findall(".//Item[@class='SurfaceLight']"):
    pr=light.find('Properties');setcolor(pr,PALETTE['cyan']);sh=pr.find("bool[@name='Shadows']")
    if sh is not None:sh.text='false'
   dest=ROOT.parent/'models'/f'{name}_{THEME}.rbxmx';ET.ElementTree(root).write(dest,encoding='utf-8',xml_declaration=True)
   prj=ROOT/'source'/'convert.project.json';prj.write_text(json.dumps({'name':dest.stem,'tree':{'$path':str(dest)}}));subprocess.run([os.environ.get('ROJO','rojo'),'build',str(prj),'-o',str(dest.with_suffix('.rbxm'))],check=True,capture_output=True)
   changes[name]={'zone':zone,'appearancePartsChanged':count,'semanticOrNaturalPartsPreserved':protected,'parts':len(native_parts(root))}
 prj.unlink();(ROOT/'DESIGN_MANIFEST.json').write_text(json.dumps({'theme':THEME,'palette':PALETTE,'models':changes,'geometryPolicy':'Appearance only; every native part, transform, class, functional name and pivot is unchanged from accepted classic XML.'},indent=2)+'\n')
if __name__=='__main__':build()
