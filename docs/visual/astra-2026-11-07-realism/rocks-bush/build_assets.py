"""Original deterministic park meshes. Python 3 + numpy, trimesh, Pillow.
Usage: PYTHONPATH=/private/tmp/gst-realism-libs python3 build_assets.py --textures ../textures
"""
import sys,os,json,math,argparse,shutil
from pathlib import Path
sys.path.insert(0,'/private/tmp/gst-realism-libs')
import numpy as np
import trimesh
from trimesh.visual.material import PBRMaterial
from PIL import Image,ImageDraw
OUT=Path(__file__).resolve().parent
rng=np.random.default_rng(4619)
def mesh(v,f,uv,name,texture,roughness=0.9):
 m=trimesh.Trimesh(vertices=v,faces=f,process=False)
 tp=Path(texture); normal=tp.with_name(tp.name.replace('_basecolor','_normal')); orm=tp.with_name(tp.name.replace('_basecolor','_orm'))
 m.visual=trimesh.visual.TextureVisuals(uv=uv,material=PBRMaterial(name=name,baseColorTexture=Image.open(texture).convert('RGB'),normalTexture=Image.open(normal) if normal.exists() else None,metallicRoughnessTexture=Image.open(orm) if orm.exists() else None,roughnessFactor=1 if orm.exists() else roughness,metallicFactor=1 if orm.exists() else 0,doubleSided=True))
 return m

def rock(size,seed,texture):
 r=np.random.default_rng(seed); phases=r.uniform(0,6.28,8); v=[];uv=[];f=[]; rings=30; n=56
 # Poles are separate so there are no collapsed quads or zero area faces.
 v.append([0,-1,0]);uv.append([.5,0])
 for j in range(1,rings):
  t=math.pi*j/rings; y=-math.cos(t)
  for i in range(n+1):
   a=2*math.pi*i/n
   wave=1+.10*math.sin(3*a+phases[0]+y)+.065*math.sin(5*a+phases[1]-2*y)+.035*math.sin(9*a+phases[2]+4*y)
   # Broad lobes and softened ledges form a non-spherical weathered stone.
   rad=math.sin(t)**.70*wave*(1+.03*math.sin(y*7+2*a+phases[3]))
   v.append([rad*math.cos(a)+.12*y,y+.035*math.sin(4*a+phases[4])*math.sin(t),rad*math.sin(a)])
   uv.append([i/n,j/rings])
 top=len(v);v.append([.12,1,0]);uv.append([.5,1])
 for i in range(n): f.append([0,1+i,2+i])
 for j in range(rings-2):
  for i in range(n):
   a=1+j*(n+1)+i;b=a+n+1; f.extend([[a,b,a+1],[a+1,b,b+1]])
 for i in range(n): f.append([top,1+(rings-2)*(n+1)+i+1,1+(rings-2)*(n+1)+i])
 v=np.array(v);v=(v-v.min(0))/(v.max(0)-v.min(0))*size;v[:,0]-=size[0]/2;v[:,2]-=size[2]/2
 m=mesh(v,f,uv,'Weathered granite',texture);return [m]

def bush(leaftex,barktex):
 lv=[];lf=[];lu=[];bv=[];bf=[];bu=[]
 def branch(a,b,r):
  a=np.array(a);b=np.array(b);axis=b-a;axis/=np.linalg.norm(axis);u=np.cross(axis,[0,0,1]);u/=np.linalg.norm(u);w=np.cross(axis,u);off=len(bv)
  for k,p in enumerate([a,b]):
   for i in range(7):
    ang=i*math.tau/6;bv.append(p+(u*math.cos(ang)+w*math.sin(ang))*r*(1 if k==0 else .4));bu.append([i/6,k])
  for i in range(6):bf.extend([[off+i,off+i+1,off+7+i],[off+i+1,off+8+i,off+7+i]])
 def leaf(center,direction,length,width,roll):
  d=np.array(direction);d/=np.linalg.norm(d);u=np.cross(d,[0,1,0]);
  if np.linalg.norm(u)<.01:u=np.cross(d,[1,0,0])
  u/=np.linalg.norm(u);n=np.cross(u,d);u=u*math.cos(roll)+n*math.sin(roll);n=np.cross(u,d)
  off=len(lv);rows=7
  # Narrow petiole/tip, widened curved blade, gently folded midrib.
  lv.append(center);lu.append([.5,0])
  for j in range(1,rows):
   t=j/rows; half=width*.5*math.sin(math.pi*t)**.8
   for s in [-1,0,1]:
    lv.append(np.array(center)+d*(length*t)+u*(half*s)+n*(length*.15*math.sin(math.pi*t)+abs(s)*width*.10))
    lu.append([(s+1)/2,t])
  tip=len(lv);lv.append(np.array(center)+d*length);lu.append([.5,1])
  lf.extend([[off,off+1,off+2],[off,off+2,off+3]])
  for j in range(rows-2):
   for i in range(2):
    a=off+1+j*3+i;lf.extend([[a,a+3,a+1],[a+1,a+3,a+4]])
  lf.extend([[tip,tip-3,tip-2],[tip,tip-2,tip-1]])
 branch([0,0,0],[0,.65,0],.07)
 for k in range(34):
  a=rng.uniform(0,math.tau);radius=rng.uniform(.5,1.12);height=rng.uniform(.55,1.3)
  end=np.array([math.cos(a)*radius,height,math.sin(a)*radius*.7]);start=np.array([0,.2,0]);branch(start,end,.018)
  for q in range(16):
   t=rng.uniform(.35,1);p=start+(end-start)*t+rng.normal(0,.10,3)
   angle=a+rng.uniform(-1.4,1.4);direction=[math.cos(angle),rng.uniform(-.1,.9),math.sin(angle)]
   leaf(p,direction,rng.uniform(.24,.40),rng.uniform(.12,.21),rng.uniform(-1.1,1.1))
 lm=mesh(lv,lf,lu,'Broadleaf foliage',leaftex);bm=mesh(bv,bf,bu,'Twigs',barktex)
 # Preserve source bush envelope approximately, at base origin.
 allv=np.vstack([lm.vertices,bm.vertices]);lo=allv.min(0);hi=allv.max(0);scale=np.array([3.1,1.7,2.0])/(hi-lo)
 for m in [lm,bm]:m.vertices=(m.vertices-lo)*scale-[1.55,0,1]
 return [lm,bm]

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

def main():
 # Original longitudinal twig bark, generated rather than borrowed.
 bark=OUT/'twig_bark_basecolor.png'
 rr=np.random.default_rng(903);gr=rr.normal(0,1,(2048,2048));lines=rr.normal(0,1,2048);lines=np.convolve(lines,np.ones(9)/9,mode='same');tone=np.clip(1+lines[None,:]*.35+gr*.035,.4,1.5);Image.fromarray(np.clip(tone[:,:,None]*np.array([89,67,43]),0,255).astype('uint8')).save(bark)
 p=argparse.ArgumentParser();p.add_argument('--stone',required=True);p.add_argument('--leaf',required=True);p.add_argument('--bark');a=p.parse_args();report={}
 for name,size,seed in [('RockSmall',[1.5,.9,1.1],12),('RockMedium',[2.5,1.5,1.85],45),('RockLarge',[4.1,2.45,3],79),('Bush',None,0)]:
  ms=bush(a.leaf,a.bark or str(bark)) if name=='Bush' else rock(size,seed,a.stone);folder=OUT/name;folder.mkdir(exist_ok=True);scene=trimesh.Scene()
  for i,m in enumerate(ms):scene.add_geometry(m,geom_name=f'{name}_{i}',node_name=f'{name}_{i}')
  files=trimesh.exchange.gltf.export_gltf(scene,merge_buffers=True)
  tree=json.loads(files['model.gltf']);blob=files['gltf_buffer.bin'];imageviews=set()
  for idx,img in enumerate(tree.get('images',[])):
   viewid=img.pop('bufferView');view=tree['bufferViews'][viewid];imageviews.add(viewid);fn=f'texture_{idx}.png';files[fn]=blob[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']];img['uri']=fn
  rebuilt=bytearray();views=[];remap={}
  for idx,view in enumerate(tree['bufferViews']):
   if idx in imageviews:continue
   while len(rebuilt)%4:rebuilt.append(0)
   offset=view.get('byteOffset',0);v=dict(view);v['byteOffset']=len(rebuilt);rebuilt.extend(blob[offset:offset+view['byteLength']]);remap[idx]=len(views);views.append(v)
  for acc in tree['accessors']:
   if 'bufferView' in acc:acc['bufferView']=remap[acc['bufferView']]
  tree['bufferViews']=views;tree['buffers'][0]['byteLength']=len(rebuilt);files['gltf_buffer.bin']=bytes(rebuilt);files['model.gltf']=json.dumps(tree,separators=(',',':')).encode()
  for fn,data in files.items():(folder/(name+'.gltf' if fn=='model.gltf' else fn)).write_bytes(data)
  stats=[]
  for m in ms:
   merged=m.copy();merged.merge_vertices(merge_tex=True,merge_norm=True)
   stats.append({'vertices':len(m.vertices),'triangles':len(m.faces),'uv_finite':bool(np.isfinite(m.visual.uv).all()),'uv_min':m.visual.uv.min(0).tolist(),'uv_max':m.visual.uv.max(0).tolist(),'degenerate_triangles':int((m.area_faces<1e-12).sum()),'signed_volume':float(merged.volume),'watertight_after_seam_weld':bool(merged.is_watertight),'bounds':m.bounds.tolist()})
  assert all(x['uv_finite'] and x['degenerate_triangles']==0 for x in stats),name
  assert sum(len(m.faces) for m in ms)<(15000 if name=='Bush' else 10000),name
  if name!='Bush':assert all(x['watertight_after_seam_weld'] and x['signed_volume']>0 for x in stats),name
  reloaded=trimesh.load(folder/(name+'.gltf'),force='scene');assert sum(len(g.faces) for g in reloaded.geometry.values())==sum(len(m.faces) for m in ms),name
  report[name]={'gltf_reimport_triangle_count_matches':True,'parts':stats,'total_triangles':sum(len(m.faces) for m in ms),'open_surfaces_expected':name=='Bush'};preview(ms,OUT/(name+'-preview.png'))
 (OUT/'validation.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
if __name__=='__main__':main()
