"""Depth-render real native accessory geometry and exact generated UV panels on a block rig."""
from build_bailiff import *
import sys,math,copy
sys.path.insert(0,'/private/tmp/gst-render-libs')
import numpy as np
from PIL import Image
from geometry import *
ROOT=Path(__file__).resolve().parents[1]
TORSO=UV['torso'];RIGHT=UV['right'];LEFT=UV['left']
W=H=768
CAM=np.array([.43,.23,-.87]);CAM/=np.linalg.norm(CAM)
RIGHTV=np.cross(np.array([0,1,0]),CAM);RIGHTV/=np.linalg.norm(RIGHTV)
UP=np.cross(CAM,RIGHTV)
# Camera right points +X for a camera at front -Z.
RIGHTV=-RIGHTV;UP=np.cross(RIGHTV,CAM)
LIGHT=np.array([-.4,.8,-.5]);LIGHT/=np.linalg.norm(LIGHT)

def preview(row,index):
 out=ROOT/'contracts-bailiff'/'V19';shirt=Image.open(out/f'{row[0]}_shirt.png').convert('RGBA');pants=Image.open(out/f'{row[0]}_pants.png').convert('RGBA')
 bg=np.empty((H,W,4),dtype=np.uint8);bg[:]=[226,232,241,255];z=np.full((H,W),-1e8)
 # Orthographic shaded texture renderer with depth buffer.
 def proj(v):
  v=np.asarray(v)-[0,2.9,0];return np.array([W/2+v@RIGHTV*93,H/2-v@UP*93,v@CAM])
 def tri(vertices,uv,tex,light=1):
  p=np.array([proj(v) for v in vertices]);x0=max(0,int(p[:,0].min()));x1=min(W-1,int(p[:,0].max()+1));y0=max(0,int(p[:,1].min()));y1=min(H-1,int(p[:,1].max()+1))
  if x0>x1 or y0>y1:return
  X,Y=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5)
  a,b,c=p;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
  if abs(den)<1e-6:return
  A=((b[1]-c[1])*(X-c[0])+(c[0]-b[0])*(Y-c[1]))/den;B=((c[1]-a[1])*(X-c[0])+(a[0]-c[0])*(Y-c[1]))/den;C=1-A-B
  depth=A*a[2]+B*b[2]+C*c[2];mask=(A>=0)&(B>=0)&(C>=0)&(depth>z[y0:y1+1,x0:x1+1])
  if not mask.any():return
  uv=np.asarray(uv);u=A*uv[0,0]+B*uv[1,0]+C*uv[2,0];v=A*uv[0,1]+B*uv[1,1]+C*uv[2,1]
  t=np.asarray(tex);tx=np.clip((u*(t.shape[1]-1)).astype(int),0,t.shape[1]-1);ty=np.clip((v*(t.shape[0]-1)).astype(int),0,t.shape[0]-1);sample=t[ty,tx].copy();sample[:,:,:3]=(sample[:,:,:3].astype(float)*light).clip(0,255).astype(np.uint8)
  alpha=sample[:,:,3]/255.;mask&=alpha>.01
  target=bg[y0:y1+1,x0:x1+1];a2=alpha[mask,None];target[mask,:3]=(sample[mask,:3]*a2+target[mask,:3]*(1-a2)).astype(np.uint8)
  # Glass can blend but should still occlude its back face.
  z[y0:y1+1,x0:x1+1][mask]=depth[mask]
 def quad(vs,tex):
  n=np.cross(np.array(vs[1])-vs[0],np.array(vs[2])-vs[0]);n=n/(np.linalg.norm(n)+1e-8)
  lit=.68+.32*max(0,float(n@LIGHT));uv=[(0,0),(1,0),(1,1),(0,1)]
  for ids in [(0,1,2),(0,2,3)]:tri([vs[i] for i in ids],[uv[i] for i in ids],tex,lit)
 def solid(c,alpha=255):return Image.new('RGBA',(2,2),c+(alpha,))
 def textured_box(center,size,areas=None,atlas=None,skin=(242,197,153),slice_y=None):
  x,y,zz=center;a,b,c=np.array(size)/2
  faces={
   'F':[(-a,b,-c),(a,b,-c),(a,-b,-c),(-a,-b,-c)],
   'B':[(a,b,c),(-a,b,c),(-a,-b,c),(a,-b,c)],
   'R':[(-a,b,c),(-a,b,-c),(-a,-b,-c),(-a,-b,c)],
   'L':[(a,b,-c),(a,b,c),(a,-b,c),(a,-b,-c)],
   'U':[(-a,b,c),(a,b,c),(a,b,-c),(-a,b,-c)],
   'D':[(-a,-b,-c),(a,-b,-c),(a,-b,c),(-a,-b,c)]}
  # Base skin under transparent neckline.
  for face,verts in faces.items():
   vs=[(X+x,Y+y,Z+zz) for X,Y,Z in verts];tex=solid(skin)
   if atlas:
    X,Y,ww,hh=areas[face];tex=atlas.crop((X,Y,X+ww,Y+hh))
    if slice_y and face not in ['U','D']:tex=tex.crop((0,int(slice_y[0]*hh),ww,int(slice_y[1]*hh)))
    under=Image.new('RGBA',tex.size,skin+(255,));under.alpha_composite(tex);tex=under
   quad(vs,tex)
 # Exact atlas boundaries on block rig (segmented R15 style arms and legs).
 textured_box((0,3.25,0),(2,1.5,1),TORSO,shirt,slice_y=(0,.75));textured_box((0,2.25,0),(2,.5,1),TORSO,shirt,slice_y=(.75,1))
 for sign,areas in [(-1,RIGHT),(1,LEFT)]:
  for lo,hi in [(0,.44),(.44,.88),(.88,1)]:
   height=(hi-lo)*2;yy=4-(lo+hi)
   textured_box((sign*1.55,yy,0),(1,height,.99),areas,shirt,slice_y=(lo,hi))
  for lo,hi in [(0,.45),(.45,.86),(.86,1)]:
   height=(hi-lo)*2;yy=2-(lo+hi)
   textured_box((sign*.53,yy,0),(.99,height,.99),areas,pants,slice_y=(lo,hi))
 textured_box((0,4.6,0),(1.18,1.2,1.05))
 # Neutral face geometry, original simple expression.
 for xx in [-.25,.25]:textured_box((xx,4.66,-.539),(.08,.16,.025),skin=(40,42,53))
 textured_box((0,4.38,-.54),(.31,.055,.025),skin=(100,62,49))
 im=Image.fromarray(bg).resize((512,512),Image.Resampling.LANCZOS);im.save(out/f'{row[0]}_preview.png')


if __name__=='__main__':preview(('bailiff',),0)
