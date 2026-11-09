"""Original park trees. Run with Python 3, numpy, Pillow, trimesh installed."""
from pathlib import Path
import sys,math,json,importlib.util
import numpy as np
from PIL import Image,ImageFilter,ImageDraw
import trimesh
from trimesh.visual.material import PBRMaterial
ROOT=Path(__file__).resolve().parent
# Reuse the previously delivered CPU rasterizer, copied into this package.
spec=importlib.util.spec_from_file_location('render',ROOT/'render_mesh.py');render=importlib.util.module_from_spec(spec);spec.loader.exec_module(render)
TAU=math.tau
class Batch:
 def __init__(self): self.v=[];self.f=[];self.uv=[]
 def tube(self,points,radii,sides=10):
  points=np.array(points,float);off=len(self.v)
  for j,p in enumerate(points):
   axis=points[min(j+1,len(points)-1)]-points[max(0,j-1)];axis/=np.linalg.norm(axis)
   u=np.cross(axis,[0,0,1]);u/=np.linalg.norm(u);v=np.cross(axis,u)
   for i in range(sides+1):
    a=TAU*i/sides;ridge=1+.055*math.sin(a*5+j*.4)
    self.v.append(p+(u*math.cos(a)+v*math.sin(a))*radii[j]*ridge);self.uv.append([i/sides,j/(len(points)-1)])
  for j in range(len(points)-1):
   for i in range(sides):
    a=off+j*(sides+1)+i;b=a+sides+1;self.f.extend([[a,a+1,b],[a+1,b+1,b]])
  for j,reverse in [(0,True),(len(points)-1,False)]:
   c=len(self.v);self.v.append(points[j]);self.uv.append([.5,.5])
   for i in range(sides):
    a=off+j*(sides+1)+i;self.f.append([c,a+1,a] if reverse else [c,a,a+1])
 def leaf(self,p,d,length,width,roll=0,needle=False):
  p=np.array(p,float);d=np.array(d,float);d/=np.linalg.norm(d);u=np.cross(d,[0,1,0])
  if np.linalg.norm(u)<.01:u=np.cross(d,[1,0,0])
  u/=np.linalg.norm(u);n=np.cross(u,d);u=u*math.cos(roll)+n*math.sin(roll);n=np.cross(u,d);off=len(self.v)
  self.v.append(p);self.uv.append([.5,0])
  for t in [.25,.5,.75]:
   half=width*.5*math.sin(math.pi*t)**(.4 if needle else .8)
   for s in [-1,0,1]:
    serration=1 if needle else 1+.06*math.sin(t*math.pi*12)
    self.v.append(p+d*length*t+u*half*s*serration+n*(length*.12*math.sin(math.pi*t)+abs(s)*width*.13));self.uv.append([(s+1)/2,t])
  tip=len(self.v);self.v.append(p+d*length+n*length*.02);self.uv.append([.5,1])
  self.f.extend([[off,off+1,off+2],[off,off+2,off+3]])
  for j in range(2):
   for i in range(2):
    a=off+1+j*3+i;self.f.extend([[a,a+3,a+1],[a+1,a+3,a+4]])
  self.f.extend([[tip,tip-3,tip-2],[tip,tip-2,tip-1]])
 def spray(self,p,d,length,width,roll=0):
  p=np.array(p,float);d=np.array(d,float);d/=np.linalg.norm(d);u=np.cross(d,[0,1,0]);u/=np.linalg.norm(u);n=np.cross(u,d);off=len(self.v)
  for pt,uv in [(p,[.5,0]),(p+d*length*.45-u*width*.5,[0,.45]),(p+d*length*.45+n*width*.2,[.5,.45]),(p+d*length*.45+u*width*.5,[1,.45]),(p+d*length,[.5,1])]:self.v.append(pt);self.uv.append(uv)
  self.f.extend([[off,off+1,off+2],[off,off+2,off+3],[off+1,off+4,off+2],[off+2,off+4,off+3]])
 def mesh(self,material):
  m=trimesh.Trimesh(vertices=self.v,faces=self.f,process=False);m.visual=trimesh.visual.TextureVisuals(uv=self.uv,material=material);return m

def maps():
 tex=ROOT/'textures';tex.mkdir(exist_ok=True);r=np.random.default_rng(751)
 for name,birch in [('oak_bark',False),('birch_bark',True)]:
  n=2048;yy,xx=np.mgrid[:n,:n];noise=r.normal(0,1,(n,n));warp=xx+9*np.sin(yy*.014)+4*np.sin(yy*.053)
  furrow=(np.sin(warp*.15)+.45*np.sin(warp*.39)+.25*np.sin(warp*.8))
  if birch:
   arr=np.clip(np.array([219,215,198])[None,None,:]+noise[:,:,None]*3+furrow[:,:,None]*2,0,255).astype('uint8');im=Image.fromarray(arr);dr=ImageDraw.Draw(im)
   for k in range(300):
    x=int(r.integers(0,n));y=int(r.integers(0,n));w=int(r.integers(8,95));h=int(r.integers(2,10));dr.ellipse((x,y,x+w,y+h),fill=(62,62,52))
   for k in range(20):
    x=int(r.integers(0,n));y=int(r.integers(0,n));dr.ellipse((x,y,x+int(r.integers(20,55)),y+int(r.integers(60,130))),fill=(85,79,62))
  else:
   grain=(furrow*13+noise*3+4*np.sin(yy*.035+xx*.01))[:,:,None];arr=np.clip(np.array([104,81,57])[None,None,:]+grain,0,255).astype('uint8');im=Image.fromarray(arr)
  im.save(tex/(name+'_basecolor.png'));height=np.array(im.convert('L').filter(ImageFilter.GaussianBlur(1)),float)/255;gx=(np.roll(height,-1,1)-np.roll(height,1,1))*2;gy=(np.roll(height,-1,0)-np.roll(height,1,0))*2;normal=np.dstack([-gx,gy,np.ones_like(gx)]);normal/=np.linalg.norm(normal,axis=2)[:,:,None];Image.fromarray(np.uint8((normal*.5+.5)*255)).save(tex/(name+'_normal.png'));orm=np.zeros((n,n,3),dtype='uint8');orm[:,:,0]=255;orm[:,:,1]=225;Image.fromarray(orm).save(tex/(name+'_orm.png'))
 # Shared original broadleaf albedo delivered in #319, copied locally for standalone import.
 leaf=Image.open(ROOT/'textures/leaf_source.png').convert('RGB')
 for name,tint in [('oak_leaf',[.65,.85,.53]),('birch_leaf',[.92,.99,.58]),('pine_needle',[.36,.62,.45])]:
  col=np.array(leaf,float)*np.array(tint)[None,None,:];Image.fromarray(np.uint8(np.clip(col,0,255))).save(tex/(name+'_basecolor.png'))
  Image.new('RGB',(2048,2048),(128,128,255)).save(tex/(name+'_normal.png'));Image.new('RGB',(2048,2048),(255,175,0)).save(tex/(name+'_orm.png'))

def material(name):
 return PBRMaterial(name=name,baseColorTexture=Image.open(ROOT/f'textures/{name}_basecolor.png'),normalTexture=Image.open(ROOT/f'textures/{name}_normal.png'),metallicRoughnessTexture=Image.open(ROOT/f'textures/{name}_orm.png'),metallicFactor=1,roughnessFactor=1,doubleSided=True)

def deciduous(birch=False):
 r=np.random.default_rng(1903 if birch else 521);wood=Batch();leaves=[Batch() for _ in range(3)];h=18.6 if birch else 16.6;width=5.4 if birch else 7.4;top=h-1;trunkr=.19 if birch else .38
 points=[[.08*math.sin(t*3),top*t,.12*math.sin(t*5)] for t in np.linspace(0,1,14)];radii=[trunkr*(1-t)**.8+.014 for t in np.linspace(0,1,14)];wood.tube(points,radii,18)
 for k in range(7):
  a=k*TAU/7;wood.tube([[0,.7,0],[math.cos(a)*trunkr*1.5,.18,math.sin(a)*trunkr*1.5],[math.cos(a)*trunkr*2.1,0,math.sin(a)*trunkr*2.1]],[trunkr*.36,trunkr*.25,.015],8)
 for k in range(19):
  t=k/18;a=k*2.4+r.uniform(-.3,.3);y=(8 if birch else 6)+t*(7.5 if birch else 8);radius=width*.45*(.6+.4*math.sin(math.pi*t))*(1-.35*t)
  start=np.array([0,y,0]);end=np.array([math.cos(a)*radius,y+1.2+r.uniform(.2,1.3),math.sin(a)*radius]);mid=start*.45+end*.55;mid[1]+=.2;wood.tube([start,mid,end],[trunkr*.38*(1-t*.65),.065,.018],8)
  for q in range(4):
   frac=.35+q*.19;p=start+(end-start)*frac;aa=a+(-1 if q%2 else 1)*.9;tip=p+np.array([math.cos(aa)*r.uniform(.5,1),r.uniform(.1,.7),math.sin(aa)*r.uniform(.5,1)]);wood.tube([p,(p+tip)/2,tip],[.035,.021,.005],6)
   for j in range(18):
    # Cluster leaves along the twig and around its tip, giving separated air gaps.
    pp=p+(tip-p)*r.uniform(.15,1.15)+r.normal(0,.22,3);d=[math.cos(aa+r.uniform(-2,2)),r.uniform(-.6,.65),math.sin(aa+r.uniform(-2,2))];length=r.uniform(.30,.46) if birch else r.uniform(.42,.64)
    leaves[(k+q+j)%3].leaf(pp,d,length,length*(.62 if birch else .48),r.uniform(-2,2))
 return [wood.mesh(material('birch_bark' if birch else 'oak_bark'))]+[x.mesh(material('birch_leaf' if birch else 'oak_leaf')) for x in leaves],np.array([width,h,width])

def pine():
 r=np.random.default_rng(329);wood=Batch();needles=[Batch() for _ in range(3)];h=18.2
 wood.tube([[.06*math.sin(t*4),h*t,.06*math.sin(t*6)] for t in np.linspace(0,1,16)],[.31*(1-t)+.009 for t in np.linspace(0,1,16)],16)
 for layer in range(16):
  y=2.8+layer*.91;radius=3.1*(1-layer/18)
  for arm in range(7):
   a=arm*TAU/7+layer*1.1;start=np.array([0,y,0]);end=np.array([radius*math.cos(a),y-.28+layer*.015,radius*math.sin(a)]);mid=(start+end)/2;mid[1]-=.22;wood.tube([start,mid,end],[.065*(1-layer/20),.035,.006],7)
   for q in range(4):
    p=start+(end-start)*(.23+q*.23);aa=a+(-1 if q%2 else 1)*.64;tip=p+np.array([math.cos(aa)*radius*.30,.17,math.sin(aa)*radius*.30]);wood.tube([p,tip],[.018,.003],5)
    for j in range(6):
     pp=p+(tip-p)*j/6+r.normal(0,.07,3);aa2=aa+(-1 if j%2 else 1)*1.1;needles[(layer+arm+q)%3].spray(pp,[math.cos(aa2),r.uniform(-.3,.65),math.sin(aa2)],r.uniform(.55,.95),r.uniform(.22,.34))
 return [wood.mesh(material('oak_bark'))]+[x.mesh(material('pine_needle')) for x in needles],np.array([6.2,h,6.2])

def export(name,ms,size):
 allv=np.vstack([m.vertices for m in ms]);lo=allv.min(0);hi=allv.max(0)
 for m in ms:m.vertices=(m.vertices-lo)*size/(hi-lo)-np.array([size[0]/2,0,size[2]/2])
 scene=trimesh.Scene(base_frame=name)
 for i,m in enumerate(ms):scene.add_geometry(m,node_name=f'{name}_{"Bark" if i==0 else "Foliage"+str(i)}',geom_name=f'{name}_Geometry_{i}')
 folder=ROOT/name;folder.mkdir(exist_ok=True);files=trimesh.exchange.gltf.export_gltf(scene,merge_buffers=True);d=json.loads(files.pop('model.gltf'));blob=files['gltf_buffer.bin'];imgviews=set()
 for i,img in enumerate(d['images']):
  vid=img.pop('bufferView');v=d['bufferViews'][vid];imgviews.add(vid);fn=f'texture_{i}.png';files[fn]=blob[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']];img['uri']=fn
 new=bytearray();views=[];remap={}
 for i,v in enumerate(d['bufferViews']):
  if i in imgviews:continue
  while len(new)%4:new.append(0)
  vv=dict(v);vv['byteOffset']=len(new);new.extend(blob[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]);remap[i]=len(views);views.append(vv)
 for acc in d['accessors']:
  if 'bufferView'in acc:acc['bufferView']=remap[acc['bufferView']]
 d['bufferViews']=views;d['buffers'][0]['byteLength']=len(new);files['gltf_buffer.bin']=bytes(new);files[name+'.gltf']=json.dumps(d,separators=(',',':')).encode()
 for fn,data in files.items():(folder/fn).write_bytes(data)
 stats=[]
 for m in ms:
  assert np.isfinite(m.vertices).all() and np.isfinite(m.visual.uv).all();assert not (m.area_faces<1e-12).any();assert len(m.faces)<20000
  stats.append({'triangles':len(m.faces),'vertices':len(m.vertices),'zero_area':int((m.area_faces<1e-12).sum()),'finite_uv':True})
 reloaded=trimesh.load(folder/(name+'.gltf'),force='scene');assert sum(len(g.faces) for g in reloaded.geometry.values())==sum(len(m.faces) for m in ms)
 render.preview(ms,ROOT/(name+'_preview.png'))
 return {'dimensionsStuds':size.tolist(),'baseY':0,'pivot':'center of base','meshNodes':len(ms),'triangles':sum(len(m.faces) for m in ms),'parts':stats,'gltf_reimport':'PASS','foliage':'open curved double-sided blades; no alpha cards','Studio':'not tested'}
if __name__=='__main__':
 maps();report={}
 for name,fn in [('TreeBroadleaf',deciduous),('TreeBirch',lambda:deciduous(True)),('TreePine',pine)]:
  ms,size=fn();report[name]=export(name,ms,size);print(name,report[name]['triangles'],flush=True)
 (ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n')
 sheet=Image.new('RGB',(1800,760),'#e7eae4')
 for i,name in enumerate(report):
  im=Image.open(ROOT/(name+'_preview.png'));im.thumbnail((600,700));sheet.paste(im,(i*600+(600-im.width)//2,100));ImageDraw.Draw(sheet).text((i*600+190,720),name,fill='#273d2c')
 sheet.save(ROOT/'Trees_preview.png')
