"""V15 variants from exact accepted XML snapshots. Original transforms stay untouched."""
from geometry import *
import subprocess, colorsys
import sys
sys.path.insert(0,'/private/tmp/gst-render-libs')
import numpy as np

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
