"""Original UV-mapped retail kiosk. Rebuild with Python3; no downloaded mesh assets."""
from pathlib import Path
import sys,math,json,shutil
sys.path.insert(0,'/private/tmp/gst-realism-libs')
import numpy as np
import trimesh
from PIL import Image,ImageDraw
from scipy.ndimage import gaussian_filter
OUT=Path(__file__).resolve().parent
TEX=OUT.parent/'textures'
rng=np.random.default_rng(7713)
groups={}
def rot(x=0,y=0,z=0):
 x,y,z=np.radians([x,y,z]);cx,sx,cy,sy,cz,sz=np.cos(x),np.sin(x),np.cos(y),np.sin(y),np.cos(z),np.sin(z)
 return np.array([[cz,-sz,0],[sz,cz,0],[0,0,1]])@np.array([[cy,0,sy],[0,1,0],[-sy,0,cy]])@np.array([[1,0,0],[0,cx,-sx],[0,sx,cx]])
def emit(group,mat,verts,faces,uv,colors=None):
 v=np.array(verts,float);f=np.array(faces,int)
 groups.setdefault(group,dict(v=[],f=[],uv=[],color=[],mat=mat))
 g=groups[group];assert g['mat']==mat;off=len(g['v']);g['v'].extend(v.tolist());g['f'].extend((f+off).tolist());g['uv'].extend(np.array(uv).tolist())
 col=np.ones((len(v),4))if colors is None else np.tile(colors,(len(v),1))
 g['color'].extend(col.tolist())
def box(group,mat,p,size,bevel=.018,R=None,color=None,grain_axis=None):
 h=np.array(size)/2;b=min(bevel,min(h)*.35)
 pts=[]
 for x in [-1,1]:
  for y in [-1,1]:
   for z in [-1,1]:
    c=np.array([x,y,z])*(h-b)
    for axis in range(3):
     q=c.copy();q[axis]+=[x,y,z][axis]*b;pts.append(q)
 hull=trimesh.convex.convex_hull(np.array(pts))
 v=[];f=[];uv=[];R=np.eye(3)if R is None else R;grain=int(np.argmax(size))if grain_axis is None else grain_axis
 offset=rng.uniform(0,5,2)
 for face,normal in zip(hull.faces,hull.face_normals):
  dom=int(np.argmax(np.abs(normal)))
  axes=[i for i in range(3)if i!=dom]
  va=grain if grain!=dom else axes[1];ua=next(i for i in axes if i!=va)
  for vert in hull.vertices[face]:
   v.append(R@vert+np.array(p));uv.append([vert[ua]/1.8+offset[0],vert[va]/1.8+offset[1]])
  f.append([len(v)-3,len(v)-2,len(v)-1])
 emit(group,mat,v,f,uv,color)
def cylinder(group,mat,p,r,length,axis='y',segments=12,color=None):
 R={'x':rot(z=-90),'y':np.eye(3),'z':rot(x=90)}[axis];v=[];uv=[];f=[]
 for yy in [-length/2,length/2]:
  for j in range(segments+1):
   a=math.tau*j/segments;v.append(R@np.array([r*math.cos(a),yy,r*math.sin(a)])+np.array(p));uv.append([j/segments,yy/length+.5])
 for j in range(segments):
  a=j;b=j+1;c=j+segments+1;d=c+1;f.extend([[a,c,b],[b,c,d]])
 for side in [0,1]:
  center=len(v);v.append(np.array(p)+R@np.array([0,(-1 if side==0 else 1)*length/2,0]));uv.append([.5,.5])
  start=side*(segments+1)
  for j in range(segments):
   tri=[center,start+j,start+j+1]
   if side==0:tri.reverse()
   f.append(tri)
 emit(group,mat,v,f,uv,color)
def cover(p,w,h,tile):
 # Project-owned poster cover art packed into a new UV atlas; no wording or brands.
 x,y,z=p;u0=(tile%2)/2;v0=1-(tile//2+1)/2;u1=u0+.5;v1=v0+.5
 emit('TradeStock','stock',[[x-w/2,y-h/2,z],[x+w/2,y-h/2,z],[x+w/2,y+h/2,z],[x-w/2,y+h/2,z]],[[0,1,2],[0,2,3]],[[u0,v0],[u1,v0],[u1,v1],[u0,v1]])
# Slab and subtly chamfered oak floor boards.
box('Foundation','stone',(0,.10,0),(9.6,.20,7.2),.035)
for j in range(12):
 z=-3.18+j*.57
 box('OakShell','wood',(0,.225,z),(9.05,.05,.55),.012,grain_axis=0)
# Steel frame; all main members are inside the plot envelope.
for x in [-4.40,4.40]:
 for z in [-3.10,3.10]:
  post_top=6.335-math.sin(math.radians(2.3))*z
  box('MetalFrame','paint',(x,(.25+post_top)/2,z),(.19,post_top-.25,.19),.018)
 for y in [.40,2.52,4.72]:
  box('MetalFrame','paint',(x,y,0),(.18,.16,6.0),.015)
 box('MetalFrame','paint',(x,3.62,0),(.16,2.04,.12),.014)
# Individually fitted oak rear and low side panels.
for j in range(10):
 x=-4.05+j*.90
 box('OakShell','wood',(x,2.44,-3.32),(.898,4.38,.12),.012,grain_axis=1)
for sign in [-1,1]:
 for j in range(9):
  z=-2.80+j*.70
  box('OakShell','wood',(sign*4.36,1.38,z),(.12,2.20,.68),.012,grain_axis=1)
# Serving counter with rebate seams and top plank joints.
for j in range(12):
 x=-3.90+j*.71
 box('Counter','wood',(x,1.53,2.91),(.69,2.56,.12),.018,grain_axis=1)
box('Counter','wood',(0,1.53,2.45),(8.48,2.56,.12),.018,grain_axis=0)
for x in [-4.18,4.18]:box('Counter','wood',(x,1.53,2.68),(.12,2.56,.34),.018,grain_axis=1)
for j in range(4):
 box('CounterTop','wood',(0,2.91,2.83+(j-1.5)*.31),(8.95,.20,.296),.035,grain_axis=0)
# Roof standing seams and a slim perimeter drip edge.
for j in range(5):
 box('MetalFrame','paint',(-3.80+j*1.90,6.40,0),(1.884,.13,7.40),.018,R=rot(x=2.3))
for x in [-4.75,-2.85,-.95,.95,2.85,4.75]:
 box('MetalFrame','paint',(x,6.48,0),(.035,.10,7.38),.008,R=rot(x=2.3))
for z,y in [(-3.75,6.55),(3.75,6.25)]:
 box('MetalFrame','paint',(0,y,z),(9.60,.22,.12),.015)
# Sign is its own matte plane with a fully unobstructed title area.
box('SignPanel','paint',(0,5.45,3.31),(6.20,1.05,.08),.012)
for x in [-3.20,3.20]:box('SignFrame','brass',(x,5.45,3.31),(.14,1.40,.12),.015)
for y in [4.82,6.08]:box('SignFrame','brass',(0,y,3.31),(6.54,.14,.12),.015)
# No cartridge, coin, decorative icon, geometry or text enters the sign rectangle.
# Rear stock shelves and visible angle brackets.
for y in [1.55,3.55]:
 box('Shelves','wood',(0,y,-2.88),(7.90,.14,.76),.018,grain_axis=0)
 for x in [-3.20,0,3.20]:
  box('Hardware','steel',(x,y-.19,-3.17),(.08,.30,.12),.010)
  box('Hardware','steel',(x,y-.08,-2.91),(.08,.08,.40),.010)
# Muted physical cartridge cases, each with a project-owned cover face.
colors=[(.19,.27,.32,1),(.38,.20,.18,1),(.28,.34,.22,1),(.34,.29,.22,1)]
for row,y in enumerate([1.55,3.55]):
 for j,x in enumerate([-3.15,-1.92,-.69,.54,1.77,3.0]):
  hh=.76+(j%3)*.09;cz=-2.86
  box('TradeStock','stock',(x,y+.07+hh/2,cz),(.65,hh,.17),.025,color=colors[(j+row)%4])
  # White texture sample for the case itself is assigned later; cover is a real UV rectangle.
  cover((x,y+.07+hh/2,cz+.091),.51,hh-.13,(j+row)%4)
# A small compact till and two presented cases on the counter.
box('TradeStock','stock',(-2.85,3.04,2.72),(.90,.06,.65),.025,color=(.12,.15,.16,1))
box('TradeStock','stock',(-2.85,3.26,2.63),(.70,.38,.32),.035,color=(.12,.15,.16,1))
box('Glass','glass',(-2.85,3.27,2.799),(.54,.23,.014),.004,color=(.28,.38,.36,.28))
for j,x in enumerate([1.55,2.70]):
 box('TradeStock','stock',(x,3.40,2.74),(.63,.78,.17),.025,color=colors[j])
 cover((x,3.40,2.831),.49,.65,j)
# Side glazing is deliberately transparent, preserving visibility into the shop.
for sign in [-1,1]:
 for z in [-1.54,1.54]:
  box('Glass','glass',(sign*4.40,3.59,z),(.028,2.00,2.79),.003,color=(.80,.90,.91,.12))
# Steel hardware seated on the frame faces: no floating screws.
for x in [-4.40,4.40]:
 for y in [.50,2.52,4.72,5.95]:
  cylinder('Hardware','steel',(x,y,3.204),.035,.018,axis='z',segments=10)
# Narrow gutter/downspout and side shelf rail add practical construction detail.
cylinder('Hardware','steel',(4.58,3.22,-3.40),.055,5.85,segments=10)
# UV color sample: all stock solids use a tiny white swatch, covers retain the atlas UVs.
# Identify solids through non-white vertex colors; their UVs point at the swatch.
g=groups['TradeStock']
for k,c in enumerate(g['color']):
 if np.max(np.abs(np.array(c)-1))>1e-6:g['uv'][k]=[.995,.005]

def make_paint():
 n=2048;r=np.random.default_rng(184)
 fine=gaussian_filter(r.normal(0,1,(n,n)),.7);broad=gaussian_filter(r.normal(0,1,(n,n)),15);broad/=max(broad.std(),1e-8)
 height=.0015*fine+.0004*broad
 color=np.clip(np.array([42,72,63])[None,None,:]*(1+fine[:,:,None]*.018+broad[:,:,None]*.008),0,255).astype('uint8')
 Image.fromarray(color).save(OUT/'paint_basecolor.png')
 dy,dx=np.gradient(height);normal=np.dstack([-dx*10,-dy*10,np.ones_like(dx)]);normal/=np.linalg.norm(normal,axis=2)[:,:,None]
 Image.fromarray(np.clip((normal*.5+.5)*255,0,255).astype('uint8')).save(OUT/'paint_normal.png')
 rough=np.clip(.73+fine*.025,.55,.9);orm=np.dstack([np.ones_like(rough),rough,np.zeros_like(rough)])
 Image.fromarray((orm*255).astype('uint8')).save(OUT/'paint_orm.png')
 Image.fromarray((rough*255).astype('uint8')).save(OUT/'paint_roughness.png')
 Image.new('L',(n,n),0).save(OUT/'paint_metallic.png')
def make_atlas():
 atlas=Image.new('RGB',(2048,2048),'white')
 source=Path('/Users/erland/Documents/ChatGPT/B-15/output')
 files=[source/'roblox-v36-posters-01/poster_pixelHero.png',source/'roblox-v36-posters-01/poster_turboRacer.png',source/'roblox-v36-posters-02/poster_dragonValley.png',source/'roblox-v36-posters-02/poster_ghostManor.png']
 for i,p in enumerate(files):
  im=Image.open(p).convert('RGB');im=im.resize((1024,1024),Image.Resampling.LANCZOS);atlas.paste(im,((i%2)*1024,(i//2)*1024))
 # White corner sample for vertex-tinted physical cases, negligible in cover presentation.
 ImageDraw.Draw(atlas).rectangle((2030,2030,2047,2047),fill='white');atlas.save(OUT/'stock_atlas.png')
make_paint();make_atlas()
# Root supplies original generated 2K textures. Do not silently export a placeholder.
assert (TEX/'wood_basecolor.png').exists(),'Shared wood texture not ready; rerun when root supplies it.'
assert (TEX/'stone_basecolor.png').exists(),'Shared stone texture not ready.'
materials=[
 dict(name='Oak_PBR',pbrMetallicRoughness=dict(baseColorTexture={'index':0},metallicFactor=0,roughnessFactor=1),normalTexture={'index':1}),
 dict(name='ForestPaint_PBR',pbrMetallicRoughness=dict(baseColorTexture={'index':3},metallicRoughnessTexture={'index':5},metallicFactor=1,roughnessFactor=1),normalTexture={'index':4}),
 dict(name='Sandstone_PBR',pbrMetallicRoughness=dict(baseColorTexture={'index':6},metallicFactor=0,roughnessFactor=.9),normalTexture={'index':7}),
 dict(name='AgedBrass',pbrMetallicRoughness=dict(baseColorFactor=[.55,.39,.16,1],metallicFactor=.8,roughnessFactor=.45)),
 dict(name='BrushedSteel',pbrMetallicRoughness=dict(baseColorFactor=[.31,.34,.33,1],metallicFactor=.9,roughnessFactor=.42)),
 dict(name='Glass',alphaMode='BLEND',doubleSided=True,pbrMetallicRoughness=dict(baseColorFactor=[.87,.95,.96,.13],metallicFactor=0,roughnessFactor=.16)),
 dict(name='GameCases_ArtAtlas',doubleSided=True,pbrMetallicRoughness=dict(baseColorTexture={'index':9},metallicFactor=0,roughnessFactor=.56))
]
if (TEX/'wood_orm.png').exists():materials[0]['pbrMetallicRoughness']['metallicRoughnessTexture']={'index':2}
if (TEX/'stone_orm.png').exists():materials[2]['pbrMetallicRoughness']['metallicRoughnessTexture']={'index':8}
paths=['../textures/wood_basecolor.png','../textures/wood_normal.png','../textures/wood_orm.png','paint_basecolor.png','paint_normal.png','paint_orm.png','../textures/stone_basecolor.png','../textures/stone_normal.png','../textures/stone_orm.png','stock_atlas.png']
for p in paths:assert (OUT/p).exists(),p
matids={'wood':0,'paint':1,'stone':2,'brass':3,'steel':4,'glass':5,'stock':6}
blob=bytearray();views=[];access=[];meshes=[];nodes=[dict(name='Pawnshop',children=list(range(1,len(groups)+1)))]
def acc(a,typ,ctype):
 a=np.ascontiguousarray(a);blob.extend(b'\0'*((-len(blob))%4));off=len(blob);blob.extend(a.tobytes());views.append(dict(buffer=0,byteOffset=off,byteLength=a.nbytes))
 item=dict(bufferView=len(views)-1,componentType=ctype,count=len(a),type=typ)
 if typ=='VEC3':item.update(min=a.min(0).tolist(),max=a.max(0).tolist())
 access.append(item);return len(access)-1
allv=[];stats=[];render=[]
for name,g in groups.items():
 v=np.array(g['v']);f=np.array(g['f']);uv=np.array(g['uv']);color=np.array(g['color']);m=trimesh.Trimesh(v,f,process=False)
 assert np.isfinite(v).all()and np.isfinite(uv).all()and (m.area_faces>1e-12).all(),name
 attrs={'POSITION':acc(v.astype('<f4'),'VEC3',5126),'NORMAL':acc(np.asarray(m.vertex_normals,dtype='<f4'),'VEC3',5126),'TEXCOORD_0':acc(uv.astype('<f4'),'VEC2',5126),'COLOR_0':acc(color.astype('<f4'),'VEC4',5126)}
 ix=acc(f.astype('<u4').ravel(),'SCALAR',5125);meshes.append(dict(name=name+'Geometry',primitives=[dict(attributes=attrs,indices=ix,material=matids[g['mat']])]))
 nodes.append(dict(name=name,mesh=len(meshes)-1))
 allv.extend(v.tolist());stats.append(dict(node=name,mesh=name+'Geometry',triangles=len(f),bounds=m.bounds.tolist(),uvFinite=True,zeroAreaTriangles=0))
 render.append((name,m,uv,color,g['mat']))
allv=np.array(allv);lo=allv.min(0);hi=allv.max(0);assert abs(lo[1])<1e-6;assert hi[0]-lo[0]<=10 and hi[2]-lo[2]<=8
assert abs(lo[0]+hi[0])<1e-6 and abs(lo[2]+hi[2])<1e-6
assert sum(s['triangles']for s in stats)<20000
gltf=dict(asset={'version':'2.0','generator':'Original Astra procedural kiosk'},scene=0,scenes=[{'nodes':[0]}],nodes=nodes,meshes=meshes,materials=materials,
 images=[{'uri':p}for p in paths],samplers=[{'wrapS':10497,'wrapT':10497,'magFilter':9729,'minFilter':9987}],textures=[{'source':i,'sampler':0}for i in range(len(paths))],buffers=[{'uri':'Pawnshop.bin','byteLength':len(blob)}],bufferViews=views,accessors=access)
(OUT/'Pawnshop.gltf').write_text(json.dumps(gltf,separators=(',',':')));(OUT/'Pawnshop.bin').write_bytes(blob)
reloaded=trimesh.load(OUT/'Pawnshop.gltf',force='scene');assert sum(len(g.faces)for g in reloaded.geometry.values())==sum(s['triangles']for s in stats)
report=dict(model='Pawnshop',triangles=sum(s['triangles']for s in stats),meshNodes=len(stats),materials=len(materials),bounds=[lo.tolist(),hi.tolist()],dimensions=(hi-lo).tolist(),baseY0=True,pivot='origin centered XZ',front='+Z',
 SignPanel={'node':'SignPanel','mesh':'SignPanelGeometry','bounds':next(s['bounds']for s in stats if s['node']=='SignPanel'),'blank':True,'reservedFrontFace':'+Z','robloxSurfaceGuiFace':'Back','frontPlaneZ':3.35},
 CounterNode='Counter',externalOriginalTextures=True,scripts=0,lights=0,glTFReimportTriangleCountMatches=True,parts=stats,StudioTested=False)
(OUT/'validation.json').write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items()if k!='parts'},indent=2))
# Render actual UV textures and triangle geometry using a CPU z-buffer.
def preview(yaw,label):
 W,H=1200,1000;im=np.full((H,W,3),[231,234,228],np.uint8);zbuf=np.full((H,W),-1e9)
 R=rot(x=12,y=yaw);vv=allv@R.T;a,b=vv.min(0),vv.max(0);scale=min(1080/(b[0]-a[0]),850/(b[1]-a[1]));mid=(a+b)/2
 texcache={};base={'brass':[140,100,41],'steel':[79,87,84],'glass':[211,232,233]}
 for name,m,uv,color,kind in sorted(render,key=lambda q:q[-1]=='glass'):
  if kind in ['wood','paint','stone','stock']:
   path={'wood':TEX/'wood_basecolor.png','paint':OUT/'paint_basecolor.png','stone':TEX/'stone_basecolor.png','stock':OUT/'stock_atlas.png'}[kind]
   if kind not in texcache:texcache[kind]=np.array(Image.open(path).convert('RGB').resize((1024,1024)))
   tex=texcache[kind]
  else:tex=np.array(base[kind],np.uint8)[None,None,:]
  v=m.vertices@R.T;screen=np.column_stack(((v[:,0]-mid[0])*scale+W/2,930-(v[:,1]-a[1])*scale,v[:,2]))
  for face in m.faces:
   p=screen[face];x0=max(0,int(p[:,0].min()));x1=min(W-1,int(p[:,0].max()+1));y0=max(0,int(p[:,1].min()));y1=min(H-1,int(p[:,1].max()+1))
   if x1<x0 or y1<y0:continue
   xx,yy=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5);den=(p[1,1]-p[2,1])*(p[0,0]-p[2,0])+(p[2,0]-p[1,0])*(p[0,1]-p[2,1])
   if abs(den)<1e-10:continue
   wa=((p[1,1]-p[2,1])*(xx-p[2,0])+(p[2,0]-p[1,0])*(yy-p[2,1]))/den;wb=((p[2,1]-p[0,1])*(xx-p[2,0])+(p[0,0]-p[2,0])*(yy-p[2,1]))/den;wc=1-wa-wb
   z=wa*p[0,2]+wb*p[1,2]+wc*p[2,2];mask=(wa>=0)&(wb>=0)&(wc>=0)&(z>zbuf[y0:y1+1,x0:x1+1]);u=wa*uv[face[0],0]+wb*uv[face[1],0]+wc*uv[face[2],0];v=wa*uv[face[0],1]+wb*uv[face[1],1]+wc*uv[face[2],1]
   col=tex[((1-(v%1))*(tex.shape[0]-1)).astype(int),(u%1*(tex.shape[1]-1)).astype(int)].astype(float)
   vc=wa[:,:,None]*color[face[0],:3]+wb[:,:,None]*color[face[1],:3]+wc[:,:,None]*color[face[2],:3];col*=vc
   normal=np.cross(m.vertices[face[1]]-m.vertices[face[0]],m.vertices[face[2]]-m.vertices[face[0]]);normal/=max(np.linalg.norm(normal),1e-10)
   light=.48+.52*max(0,np.dot(normal,[.30,.85,.43]));col=np.clip(col*light,0,255)
   target=im[y0:y1+1,x0:x1+1]
   if kind=='glass':target[mask]=(target[mask]*.88+col[mask]*.12).astype('uint8')
   else:target[mask]=col.astype('uint8')[mask];zbuf[y0:y1+1,x0:x1+1][mask]=z[mask]
 Image.fromarray(im).save(OUT/('Pawnshop_'+label+'.png'))
for yaw,label in [(0,'Front'),(32,'ThreeQuarter'),(155,'Rear')]:preview(yaw,label)
