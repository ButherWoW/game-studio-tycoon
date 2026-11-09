"""Original curved botanical meshes. Rebuild: python3 build_flowerbed.py."""
import sys,os,json,math,struct,random
sys.path.insert(0,'/private/tmp/gst-realism-libs')
import numpy as np
from PIL import Image,ImageDraw
P=os.path.dirname(os.path.abspath(__file__)); random.seed(1515)
meshes=[]
def mesh(name,v,f,uv,mat):
 meshes.append(dict(name=name,v=np.array(v,float),f=np.array(f,int),uv=np.array(uv,float),mat=mat))
def grid(name,fn,nu,nv,mat,uvbox=(0,0,1,1),double=True):
 v=[];uv=[];f=[]
 for i in range(nu+1):
  for j in range(nv+1):
   u=i/nu;t=j/nv;v.append(fn(u,t));uv.append((uvbox[0]+u*(uvbox[2]-uvbox[0]),uvbox[1]+t*(uvbox[3]-uvbox[1])))
 for i in range(nu):
  for j in range(nv):
   a=i*(nv+1)+j;b=a+nv+1;f.extend([(a,b,a+1),(a+1,b,b+1)])
 mesh(name,v,f,uv,mat)
def tube(name,path,radius,mat=2,n=7):
 v=[];uv=[];f=[]
 for i,p in enumerate(path):
  for k in range(n):
   a=k*2*math.pi/n;v.append((p[0]+radius*math.cos(a),p[1],p[2]+radius*math.sin(a)));uv.append((k/n,i/(len(path)-1)))
 for i in range(len(path)-1):
  for k in range(n):
   a=i*n+k;b=i*n+(k+1)%n;c=a+n;d=b+n;f.extend([(a,c,b),(b,c,d)])
 mesh(name,v,f,uv,mat)
def leaf(name,p,angle,length,width,rise=.13):
 axis=np.array([math.cos(angle),0,math.sin(angle)]);side=np.array([-math.sin(angle),0,math.cos(angle)]);p=np.array(p)
 def fn(u,v):
  w=math.sin(math.pi*u)**.8*width*(v-.5)*2
  return p+axis*(length*u)+side*w+np.array([0,rise*math.sin(u*2.1)+.025*(abs(v-.5)*2)**2,0])
 grid(name,fn,6,2,2)
# Deliberately individual trapezoidal sandstone blocks with six-sided bevel profile.
R=1.9;inner=1.58
for k in range(24):
 a0=k*2*math.pi/24+.012;a1=(k+1)*2*math.pi/24-.012
 profile=[(inner,0),(R,0),(R,.22),(R-.035,.275),(inner+.03,.275),(inner,.23)]
 v=[];uv=[]
 for a in [a0,a1]:
  for r,y in profile:v.append((r*math.cos(a),y+(random.uniform(-.008,.008) if y else 0),r*math.sin(a)));uv.append((a/(2*math.pi)*4,r+y))
 f=[]
 for j in range(6):q=(j+1)%6;f.extend([(j,q,j+6),(q,q+6,j+6)])
 f.extend([(0,2,1),(0,3,2),(0,4,3),(0,5,4),(6,7,8),(6,8,9),(6,9,10),(6,10,11)])
 mesh('Sandstone edging %02d'%k,v,f,uv,0)
# Rich, uneven soil surface, UV projected at realistic texel density.
v=[(0,.16,0)];uv=[(.5,.5)];f=[]
for k in range(64):
 a=k*2*math.pi/64;r=1.59;v.append((r*math.cos(a),.155+random.random()*.012,r*math.sin(a)));uv.append((.5+.5*math.cos(a),.5+.5*math.sin(a)))
for k in range(64):f.append((0,k+1,(k+1)%64+1))
mesh('Cultivated dark soil',v,f,uv,1)
# Flower centers: sculpted domes, separate from their attached petal whorls.
def dome(name,c,r,mat):
 grid(name,lambda u,v:(c[0]+r*math.sin(v*math.pi)*math.cos(u*2*math.pi),c[1]+r*.48*math.cos(v*math.pi),c[2]+r*math.sin(v*math.pi)*math.sin(u*2*math.pi)),8,3,mat)
def flower(x,z,h,idx,kind):
 bend=random.uniform(-.10,.10);path=[(x+bend*(i/6)**2,.16+h*i/6,z+.04*math.sin(i/6*2)) for i in range(7)];tube(kind+' curved stalk '+str(idx),path,.011)
 for q in range(3):
  p=path[q+1];leaf(kind+' leaf '+str(idx)+'-'+str(q),p,q*2.4+idx,.25 if kind=='Tulip' else .18,.045 if kind=='Tulip' else .034,.13)
 c=np.array(path[-1])
 if kind=='Daisy':
  for k in range(11):
   a=k*2*math.pi/11+idx;axis=np.array([math.cos(a),0,math.sin(a)]);side=np.array([-math.sin(a),0,math.cos(a)])
   def fn(u,v):return c+axis*(.035+.18*u)+side*(.036*math.sin(math.pi*u)**.65*(2*v-1))+np.array([0,-.035*math.sin(u*math.pi)+.035*u*u+.014*(2*v-1)**2,0])
   grid('Daisy ivory ray %02d-%02d'%(idx,k),fn,5,2,3)
  dome('Daisy golden pollen '+str(idx),c+np.array([0,.012,0]),.062,4)
 else:
  for k in range(6):
   a=k*math.pi/3;axis=np.array([math.cos(a),0,math.sin(a)]);side=np.array([-math.sin(a),0,math.cos(a)])
   def fn(u,v):
    r=.045+.073*math.sin(u*math.pi*.8)
    return c+axis*r+side*(.075*math.sin(math.pi*(.08+.9*u))*(2*v-1))+np.array([0,.21*u-.08+.02*(2*v-1)**2,0])
   grid('Tulip cupped petal %02d-%02d'%(idx,k),fn,6,3,6)
for i,(x,z,h) in enumerate([(-.9,-.5,.62),(-.55,.3,.75),(.25,.6,.63),(.85,.35,.72),(.9,-.5,.66),(-.25,-.75,.78),(.05,.05,.84),(-.9,.65,.59)]):flower(x,z,h,i,'Daisy')
for i,(x,z,h) in enumerate([(-.6,-.95,.91),(.52,-.75,1.05),(.6,.85,.87),(-.6,.85,.99),(.15,-.35,.97)]):flower(x,z,h,i,'Tulip')
# Lavender clustered terminal florets, botanical alternating leaves.
for i,(x,z) in enumerate([(-1.18,-.05),(1.15,-.15),(.05,1.18),(-.1,-1.2)]):
 for s in range(3):
  a=s*2.1+i;x1=x+math.cos(a)*.10;z1=z+math.sin(a)*.10;h=.59+.09*s
  path=[(x1+.05*t,.16+h*t,z1+.04*t*t) for t in np.linspace(0,1,6)];tube('Lavender branching stem %d %d'%(i,s),path,.007,n=5)
  for q in range(2):leaf('Lavender lanceolate leaf %d %d %d'%(i,s,q),path[q+1],q*math.pi+a,.17,.015,.045)
  for q in range(5):
   for k in range(3):
    aa=k*math.pi*2/3+q*.8;c=(path[-1][0]+.021*math.cos(aa),path[-1][1]-.13+q*.035,path[-1][2]+.021*math.sin(aa));dome('Lavender tiny floret %d %d %d %d'%(i,s,q,k),c,.026-q*.002,5)
# Batch all components by material for repeated Roblox landscape instances.
for m in meshes:
 tri=m['v'][m['f']];area=np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1);m['f']=m['f'][area>1e-10]
semantic_manifest=[dict(name=m['name'],material=m['mat'],triangles=len(m['f'])) for m in meshes]
json.dump(semantic_manifest,open(P+'/semantic_manifest.json','w'),indent=2)
batches=[]
for mat in sorted(set(m['mat'] for m in meshes)):
 parts=[m for m in meshes if m['mat']==mat];verts=[];faces=[];uvs=[];offset=0
 for part in parts:
  verts.append(part['v']);faces.append(part['f']+offset);uvs.append(part['uv']);offset+=len(part['v'])
 batches.append(dict(name=['Sandstone','Soil','Foliage','DaisyPetals','Pollen','Lavender','TulipPetals'][mat],v=np.concatenate(verts),f=np.concatenate(faces),uv=np.concatenate(uvs),mat=mat))
meshes=batches
# Export minimal portable glTF 2.0 with one material per mesh and smooth vertex normals.
for m in meshes:
 if m['mat'] in (2,3,6):m['uv']=m['uv'][:,::-1].copy()
import trimesh
blob=bytearray();views=[];access=[]
def acc(a,typ,ctype):
 a=np.ascontiguousarray(a);pad=(-len(blob))%4;blob.extend(b'\0'*pad);off=len(blob);blob.extend(a.tobytes());views.append(dict(buffer=0,byteOffset=off,byteLength=a.nbytes));d=dict(bufferView=len(views)-1,componentType=ctype,count=len(a),type=typ)
 if typ=='VEC3':d.update(min=a.min(0).tolist(),max=a.max(0).tolist())
 access.append(d);return len(access)-1
out=[];nodes=[dict(name='Flowerbed',children=list(range(1,len(meshes)+1)))];tri=0
for m in meshes:
 tm=trimesh.Trimesh(m['v'],m['f'],process=False);tri+=len(m['f']);p=acc(m['v'].astype('<f4'),'VEC3',5126);n=acc(np.asarray(tm.vertex_normals,dtype='<f4'),'VEC3',5126);uv=acc(m['uv'].astype('<f4'),'VEC2',5126);ix=acc(m['f'].astype('<u4').ravel(),'SCALAR',5125)
 out.append(dict(name=m['name']+'.Geometry',primitives=[dict(attributes={'POSITION':p,'NORMAL':n,'TEXCOORD_0':uv},indices=ix,material=m['mat'])]));nodes.append(dict(name=m['name'],mesh=len(out)-1))
colors=[('Sandstone',[.68,.65,.56,1]),('Soil',[.19,.105,.05,1]),('Broadleaf',[.18,.39,.085,1]),('Petals',[1,1,1,1]),('Pollen',[.93,.57,.055,1]),('Lavender',[.43,.22,.65,1]),('Tulip coral',[.95,.24,.20,1])]
materials=[dict(name=n,doubleSided=True,pbrMetallicRoughness=dict(baseColorFactor=c,metallicFactor=0,roughnessFactor=.86)) for n,c in colors]
images=[];textures=[]
for mi,texture in [(0,'stone'),(1,'soil'),(2,'broadleaf'),(3,'petal'),(6,'petal')]:
 materials[mi]['pbrMetallicRoughness']['baseColorFactor']=[1,1,1,1] if mi in (0,1,2,3) else [.95,.24,.20,1]
 for suffix,key in [('basecolor','baseColorTexture'),('orm','metallicRoughnessTexture'),('normal','normalTexture')]:
  images.append(dict(uri='../textures/'+texture+'_'+suffix+'.png'));textures.append(dict(source=len(images)-1));ref=dict(index=len(textures)-1)
  if key=='normalTexture':materials[mi][key]=ref
  else:materials[mi]['pbrMetallicRoughness'][key]=ref
g=dict(images=images,textures=textures,asset=dict(version='2.0',generator='Original procedural botanical sculpture'),scene=0,scenes=[dict(nodes=[0])],nodes=nodes,meshes=out,materials=materials,buffers=[dict(uri='Flowerbed.bin',byteLength=len(blob))],bufferViews=views,accessors=access)
open(P+'/Flowerbed.bin','wb').write(blob);json.dump(g,open(P+'/Flowerbed.gltf','w'),indent=2)
allv=np.concatenate([m['v'] for m in meshes]);report=dict(triangles=tri,vertices=len(allv),mesh_count=len(meshes),mesh_nodes=len(meshes),per_mesh_triangles={m['name']:len(m['f']) for m in meshes},bounds_min=allv.min(0).tolist(),bounds_max=allv.max(0).tolist(),dimensions=np.ptp(allv,axis=0).tolist(),finite=bool(np.isfinite(allv).all()),uv_present=True)
json.dump(report,open(P+'/validation.json','w'),indent=2);print(json.dumps(report))

# Deterministic actual-mesh shaded preview (orthographic; no generated imagery).
W=1400;H=1050;im=Image.new('RGB',(W,H),(226,230,222));draw=ImageDraw.Draw(im)
right=np.array([.78,0,-.625]);up=np.array([.28,.894,.35]);depth=np.cross(right,up);light=np.array([-.35,.85,.4]);light/=np.linalg.norm(light)
polys=[]
for m in meshes:
 base=np.array(colors[m['mat']][1][:3]);vv=m['v'];xy=np.column_stack((vv@right,vv@up));xy=xy*290+np.array([700,450]);xy[:,1]=950-xy[:,1]
 for face in m['f']:
  a,b,c=vv[face];normal=np.cross(b-a,c-a);norm=np.linalg.norm(normal);shade=.55+.45*abs(np.dot(normal/max(norm,1e-10),light));col=tuple((np.clip(base*shade,0,1)*255).astype(int));polys.append((float(vv[face].mean(0)@depth),xy[face].tolist(),col))
for _,p,c in sorted(polys,key=lambda p:p[0],reverse=True):draw.polygon([tuple(q) for q in p],fill=c)
im.save(P+'/Flowerbed_provisional_untextured_preview.png')
