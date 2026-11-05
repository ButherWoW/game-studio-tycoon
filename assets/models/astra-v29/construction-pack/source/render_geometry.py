"""Depth-tested, shadow-mapped previews of exported Part geometry. No image generation."""
import sys, math
sys.path.insert(0,'/private/tmp/gst-render-libs')
import numpy as np
from PIL import Image
from build_construction import *

def basis(yaw,elev):
 a,b=math.radians(yaw),math.radians(elev)
 return np.array([(math.cos(a),0,-math.sin(a)),(-math.sin(a)*math.sin(b),math.cos(b),-math.cos(a)*math.sin(b)),(math.sin(a)*math.cos(b),math.sin(b),math.cos(a)*math.cos(b))],dtype=np.float32)

def triangles(parts):
 out=[]
 for p in parts:
  if p['alpha']>.4:continue
  vs,fs=meshes(p);vs=np.array(vs,dtype=np.float32);center=np.array(p['p'])
  for f in fs:
   for i in range(1,len(f)-1):
    tri=vs[[f[0],f[i],f[i+1]]];n=np.cross(tri[1]-tri[0],tri[2]-tri[0]);length=np.linalg.norm(n)
    if length<1e-7:continue
    n/=length
    if np.dot(n,tri.mean(axis=0)-center)<0:n=-n
    out.append((tri,n,np.array(p['c'],dtype=np.float32),p['mat']=='Neon',p['mat']!='Neon'))
 return out

def raster(tris,W,H,span,B,target,shadow=False):
 depth=np.full((H,W),-1e8,dtype=np.float32)
 if not shadow:
  colors=np.zeros((H,W,3),dtype=np.float32);world=np.zeros_like(colors);normals=np.zeros_like(colors);emiss=np.zeros((H,W),dtype=bool)
 scale=W/span;target=np.array(target)
 for tri,n,col,neon,casts in tris:
  if shadow and not casts:continue
  if np.dot(n,B[2])<-.001:continue
  projected=(tri-target)@B.T;projected[:,:2]*=scale;projected[:,0]+=W/2;projected[:,1]=H*.53-projected[:,1]
  x0=max(0,int(np.floor(projected[:,0].min())));x1=min(W-1,int(np.ceil(projected[:,0].max())))
  y0=max(0,int(np.floor(projected[:,1].min())));y1=min(H-1,int(np.ceil(projected[:,1].max())))
  if x0>x1 or y0>y1:continue
  x,y=np.meshgrid(np.arange(x0,x1+1,dtype=np.float32)+.5,np.arange(y0,y1+1,dtype=np.float32)+.5)
  a,b,c=projected;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
  if abs(den)<1e-7:continue
  u=((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(y-c[1]))/den
  v=((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(y-c[1]))/den;w=1-u-v
  z=u*a[2]+v*b[2]+w*c[2];patch=depth[y0:y1+1,x0:x1+1];mask=(u>=-1e-5)&(v>=-1e-5)&(w>=-1e-5)&(z>patch)
  if not mask.any():continue
  patch[mask]=z[mask]
  if not shadow:
   colors[y0:y1+1,x0:x1+1][mask]=col
   normals[y0:y1+1,x0:x1+1][mask]=n
   emiss[y0:y1+1,x0:x1+1][mask]=neon
   world[y0:y1+1,x0:x1+1][mask]=u[mask,None]*tri[0]+v[mask,None]*tri[1]+w[mask,None]*tri[2]
 return depth if shadow else (depth,colors,world,normals,emiss)

def preview(parts,path,yaw=24,elev=31,target=(0,3,0),span=68,W=1920,H=1360):
 ts=triangles(parts);B=basis(yaw,elev);LB=basis(-35,58)
 # shadow framing based on scene extent.
 xyz=np.concatenate([t[0] for t in ts]);lo=xyz.min(axis=0);hi=xyz.max(axis=0);st=(lo+hi)/2;ss=max(hi-lo)*1.7
 sd=raster(ts,1300,1300,ss,LB,st,True)
 depth,col,world,normals,emiss=raster(ts,W,H,span,B,target)
 vis=depth>-1e7
 sproj=(world-st)@LB.T
 sx=np.clip((sproj[:,:,0]*1300/ss+650).astype(int),0,1299)
 sy=np.clip((1300*.53-sproj[:,:,1]*1300/ss).astype(int),0,1299)
 lit=np.zeros((H,W),dtype=np.float32)
 for dx,dy in [(0,0),(1,0),(-1,0),(0,1),(0,-1)]:lit+=(sproj[:,:,2]+.08>=sd[np.clip(sy+dy,0,1299),np.clip(sx+dx,0,1299)])/5
 lambert=np.maximum(0,normals@LB[2]);factor=.6+.4*lambert*(.35+.65*lit)
 factor[emiss]=1.06
 result=np.clip(col*factor[:,:,None]*np.array([1.035,1,.965]),0,255)
 bg=np.empty_like(result);bg[:]=[236,230,221];result[~vis]=bg[~vis]
 # Composite the nearest actual glass layer against depth-tested opaque geometry.
 glass=[]
 for p in parts:
  if .4<p['alpha']<.95:
   p=copy.deepcopy(p);p['alpha']=0;glass.append(p)
 if glass:
  gd,gc,_,_,_=raster(triangles(glass),W,H,span,B,target)
  mask=(gd>-1e7)&(gd>depth+.01)
  result[mask]=result[mask]*.8+gc[mask]*.2
 im=Image.fromarray(result.astype('uint8'));im.save(path)
 print(path.name,flush=True)

