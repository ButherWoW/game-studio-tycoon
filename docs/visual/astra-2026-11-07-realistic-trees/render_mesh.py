from pathlib import Path
import math
import numpy as np
import trimesh
from PIL import Image
def preview(meshes,path):
 # Orthographic CPU rasterization of actual triangle UVs and supplied texture pixels.
 W=900;H=760;im=np.zeros((H,W,3),dtype=np.uint8);im[:]=[231,234,228];zbuf=np.full((H,W),-1e9)
 verts=np.vstack([m.vertices for m in meshes]);rot=trimesh.transformations.rotation_matrix(.55,[0,1,0])[:3,:3]@trimesh.transformations.rotation_matrix(.28,[1,0,0])[:3,:3]
 vv=verts@rot.T;lo=vv.min(0);hi=vv.max(0);scale=min(720/(hi[0]-lo[0]),600/(hi[1]-lo[1]));mid=(hi+lo)/2
 for m in meshes:
  v=m.vertices@rot.T;screen=np.column_stack(((v[:,0]-mid[0])*scale+450,620-(v[:,1]-lo[1])*scale,v[:,2]));tex=np.array(m.visual.material.baseColorTexture.convert('RGB'));uv=m.visual.uv
  for face in m.faces:
   p=screen[face];x0=max(0,int(p[:,0].min()));x1=min(W-1,int(p[:,0].max()+1));y0=max(0,int(p[:,1].min()));y1=min(H-1,int(p[:,1].max()+1))
   if x1<x0 or y1<y0:continue
   xx,yy=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5);den=(p[1,1]-p[2,1])*(p[0,0]-p[2,0])+(p[2,0]-p[1,0])*(p[0,1]-p[2,1])
   if abs(den)<1e-10:continue
   a=((p[1,1]-p[2,1])*(xx-p[2,0])+(p[2,0]-p[1,0])*(yy-p[2,1]))/den;b=((p[2,1]-p[0,1])*(xx-p[2,0])+(p[0,0]-p[2,0])*(yy-p[2,1]))/den;c=1-a-b;z=a*p[0,2]+b*p[1,2]+c*p[2,2];mask=(a>=0)&(b>=0)&(c>=0)&(z>zbuf[y0:y1+1,x0:x1+1]);u=a*uv[face[0],0]+b*uv[face[1],0]+c*uv[face[2],0];v=a*uv[face[0],1]+b*uv[face[1],1]+c*uv[face[2],1];col=tex[np.clip(((1-v)*(tex.shape[0]-1)).astype(int),0,tex.shape[0]-1),np.clip((u*(tex.shape[1]-1)).astype(int),0,tex.shape[1]-1)]
   normal=np.cross(m.vertices[face[1]]-m.vertices[face[0]],m.vertices[face[2]]-m.vertices[face[0]]);normal/=max(np.linalg.norm(normal),1e-10);light=.53+.47*abs(np.dot(normal,[.3,.85,.43]));im[y0:y1+1,x0:x1+1][mask]=(col*light).astype('uint8')[mask];zbuf[y0:y1+1,x0:x1+1][mask]=z[mask]
 Image.fromarray(im).save(path)

