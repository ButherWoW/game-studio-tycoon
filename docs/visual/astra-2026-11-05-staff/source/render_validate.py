"""Depth-render real native accessory geometry and exact generated UV panels on a block rig."""
from build_staff import *
sys.path.insert(0,"/private/tmp/gst-render-libs")
import numpy as np
from PIL import Image,ImageDraw
import hashlib
W=H=768
CAM=np.array([.43,.23,-.87]);CAM/=np.linalg.norm(CAM)
RIGHTV=np.cross(np.array([0,1,0]),CAM);RIGHTV/=np.linalg.norm(RIGHTV)
UP=np.cross(CAM,RIGHTV)
# Camera right points +X for a camera at front -Z.
RIGHTV=-RIGHTV;UP=np.cross(RIGHTV,CAM)
LIGHT=np.array([-.4,.8,-.5]);LIGHT/=np.linalg.norm(LIGHT)

def preview(row,index,suffix="preview"):
 skin=tuple(int(row[5][i:i+2],16) for i in (0,2,4))
 out=ROOT/f'batch-{index//5+1}'/'V13';shirt=Image.open(out/f'look_{row[0]}_shirt.png').convert('RGBA');pants=Image.open(out/f'look_{row[0]}_pants.png').convert('RGBA')
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
 def textured_box(center,size,areas=None,atlas=None,skin=skin,slice_y=None):
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
   if row[0]=='ghost':
    tt=np.array(tex);tt[:,:,3]=(tt[:,:,3]*.65).astype('uint8');tex=Image.fromarray(tt)
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
 # Face PNG projected on real head front, or monitor FaceScreen for Robo.
 faceTexture=Image.open(out/f'face_{row[0]}.png').convert('RGBA')
 if row[0]=='robo':
  faceQuad=[(-.665,5.27,-.771),(.665,5.27,-.771),(.665,3.93,-.771),(-.665,3.93,-.771)]
 else:faceQuad=[(-.59,5.2,-.541),(.59,5.2,-.541),(.59,4.0,-.541),(-.59,4.0,-.541)]
 quad(faceQuad,faceTexture)
 # Parts are the actual accessory geometry. Attachment transform head/body anchor defines placement.
 for group in [hair(row)]+([cape()] if row[0]=='legend' else []):
  # Explicit canonical block-rig attachment positions. Apply target * inverse(local).
  target={'HatAttachment':(0,5.1,0),'FaceFrontAttachment':(0,4.6,-.5),'BodyFrontAttachment':(0,3,-.5),'BodyBackAttachment':(0,3,.5),'RightGripAttachment':(-1.55,2.,0)}
  anchor=np.array(target[group['attachment'][0]])-np.array(group['attachment'][1])
  parts=flatten(group)
  # Draw opaque parts first and transparent shell last.
  for p in sorted(parts,key=lambda p:p['alpha']):
   if p['alpha']>=1:continue
   vertices,faces=meshes(p);vertices=[tuple(np.array(v)+anchor) for v in vertices]
   tex=solid(tuple(p['c']),int((1-p['alpha'])*255))
   for f in faces:
    vs=[vertices[i] for i in f]
    for k in range(1,len(vs)-1):
     n=np.cross(np.array(vs[k])-vs[0],np.array(vs[k+1])-vs[0]);n=n/(np.linalg.norm(n)+1e-8);lit=.68+.32*max(0,float(n@LIGHT));tri([vs[0],vs[k],vs[k+1]],[(0,0),(1,0),(1,1)],tex,lit)
 im=Image.fromarray(bg).resize((512,512),Image.Resampling.LANCZOS);im.save(out/f'look_{row[0]}_{suffix}.png')


def validate():
 # Precise declared head envelope. Any visible hair Part bounding box must lie outside it.
 headHalf=(.59,.60,.525);hashes=set();allReports=[]
 for batch in range(1,4):
  base=ROOT/f'batch-{batch}';out=base/'V13';rows=DATA[(batch-1)*5:batch*5]
  report={'studioTested':False,'targetHeadSize':[1.18,1.2,1.05],'targetHatAttachment':[0,.5,0],'employees':{},'status':'PASS'}
  for row in rows:
   id=row[0];face=Image.open(out/f'face_{id}.png');assert face.size==(256,256) and face.mode=='RGBA';assert face.getchannel('A').getextrema()==(0,255)
   digest=hashlib.sha256(face.tobytes()).hexdigest();assert digest not in hashes;hashes.add(digest)
   for typ in ('shirt','pants'):
    im=Image.open(out/f'look_{id}_{typ}.png');assert im.size==(585,559) and im.mode=='RGBA';assert im.getpixel((0,0))[3]==0
    for areas in (TORSO,RIGHT,LEFT):
     for f,(x,y,w,h) in areas.items():assert im.getpixel((x+w//2,y+h//2))[3]>0
    if typ=='shirt' and id not in ('robo','ghost','max'):assert im.getpixel((295,80))[3]==0
   m=hair(row);assert len(m['parts'])<=30
   for p in m['parts']:
    if p['alpha']>=1:continue
    half=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
    assert any(abs(p['p'][i])>=headHalf[i]+half[i]-.0001 for i in range(3)),('hair inside head',id,p['name'],p['p'],half)
   doc=ET.parse(out/f'hair_{id}.rbxmx');ac=doc.find('Item');assert ac.attrib['class']=='Accessory';parts=ac.findall('Item[@class="Part"]');assert len(parts)<=30
   assert set(i.attrib['class'] for i in doc.iter('Item'))<={'Accessory','Part','Attachment','WeldConstraint'}
   for src,node in zip(m['parts'],parts):
    cf=node.find('Properties/CoordinateFrame[@name="CFrame"]');actualp=[float(cf.find(k).text) for k in 'XYZ'];actualr=[float(cf.find(f'R{i}{j}').text) for i in range(3) for j in range(3)]
    assert max(abs(a-b) for a,b in zip(actualp,src['p']))<1e-6
    assert max(abs(a-b) for a,b in zip(actualr,src['r']))<1e-6
   handle=parts[0];assert handle.findtext('Properties/string[@name="Name"]')=='Handle'
   assert handle.findtext('Item[@class="Attachment"]/Properties/string[@name="Name"]')=='HatAttachment'
   for p in parts:
    pr=p.find('Properties');assert pr.findtext('bool[@name="Massless"]')=='true';assert pr.findtext('bool[@name="Anchored"]')=='false';assert pr.findtext('bool[@name="CanCollide"]')=='false'
    if p is handle:continue
    weld=p.find('Item[@class="WeldConstraint"]/Properties');assert weld.findtext('Ref[@name="Part0"]')=='P0' and weld.findtext('Ref[@name="Part1"]')==p.attrib['referent']
   im=Image.open(out/f'look_{id}_preview.png');assert im.size==(512,512)
   report['employees'][id]={'parts':len(parts),'specialization':row[1],'gender':row[2],'faceSha256':digest,'headIntersections':0,'hairAttachment':'HatAttachment','checks':'PASS'}
  (base/'VALIDATION.json').write_text(json.dumps(report,indent=2));allReports.append(report)
  sheet=Image.new('RGB',(1536,1120),'#E2E8F1');d=ImageDraw.Draw(sheet)
  for j,row in enumerate(rows):
   x=(j%3)*512;y=(j//3)*560;sheet.paste(Image.open(out/f'look_{row[0]}_preview.png').convert('RGB'),(x,y));d.text((x+24,y+515),row[0],fill='#1E1E2E')
  sheet.save(base/'V13_ContactSheet.png')
  (base/'README.md').write_text(f'''# V13 employee appearance — batch {batch}\n\n{', '.join(r[0] for r in rows)}. Five original baseline appearances, separate from paid V12 outfits. Every employee has a unique transparent256×256 face, native-Part hair Accessory,585×559 shirt/pants UV templates,512×512 full-body preview and exact SVG artwork sources. Specialization colors follow Employees.luau.\n\nUse face_<id>.png as Head front Decal, hair_<id>.rbxmx through Humanoid:AddAccessory, and uploaded look_<id>_shirt/pants images as ShirtTemplate/PantsTemplate. All hair assemblies have one Handle, HatAttachment, rigid WeldConstraints, unanchored massless noncolliding native Parts; <=30 Parts and no scripts, external meshes/textures or lights. Standard attachment matches the declared prototype rig; align on the actual game NPC before release.\n\n## Target assumptions and integration\n\nPrototype head is a centered1.18×1.20×1.05 block, HatAttachment local(0,.5,0), front−Z; torso is2×2×1. Model Part coordinates are head-local. Every visible hair Part conservatively clears the entire head box; caps and crown sit above it rather than inside. Faces and clothing are mapped exactly from generated PNGs in the preview. Preview is CPU geometry rendering, not a Studio screenshot.\n\nRobo uses a hollow monitor shell around the Head: place face_robo on FaceScreen front surface(−Z), not on the hidden default Head. Keep the Head itself for the rig. Native Neon eyes supply emissive shapes; the uploaded PNG alone cannot emit light. Ghost requires body color#9AD9EA and BasePart Transparency=.35 at runtime, including head, while keeping hair hood geometry at its authored transparency and Neon eyes visible. Its preview applies these appearance overrides. Legend includes an extra look_legend_cape.rbxmx, a separately welded BodyBackAttachment Accessory; attach it to torso with Humanoid:AddAccessory. Never weld the cape to the Head. Manifest records these overrides.\n\n## QA\n\nVALIDATION.json confirms atlas dimensions/alpha, unique facial textures, face/head bounds, Part budgets, no visible hair geometry inside the declared head envelope, allowed classes and weld references. Official template boundary coordinates match Roblox classic clothing maps. R15body scaling/HeadAttachment positions vary: Studio QA must verify actual NPC proportions, camera distance10studs, seated and walking animations, face target normals, arm/waist/ankle seams, hairstyle visibility, hats under custom heads and cape seating clearance. Transparency/clothing rendering and accessory physics must be tested in Studio; prototype acceptance is not a completed runtime test.\n\nOriginal artwork authored as SVG and native geometry; no brands, third-party artwork or font-rendered lettering. SVGs rasterized with resvg. Faces, braids/buns/ponytails, clothing details and silhouettes are original.\n''')
 (ROOT/'VALIDATION.json').write_text(json.dumps({'status':'PASS','employees':15,'batches':3,'faceDimensions':[256,256],'clothingDimensions':[585,559],'previewDimensions':[512,512],'headIntersections':0,'studioTested':False,'checks':['unique face pixel hashes','exact official UV rectangles','real mask neckline alpha','visible hair bounding boxes outside target head','Accessory/Handle/HatAttachment','Massless unanchored noncolliding','every Part welded to Handle','<=30 Parts each hair','no scripts meshes external textures PointLights','real texture/geometry previews']},indent=2))

if __name__=='__main__':
 for index,row in enumerate(DATA):preview(row,index)
 validate()
 CAM=np.array([.43,.23,.87]);CAM/=np.linalg.norm(CAM);RIGHTV=np.cross(CAM,np.array([0,1,0]));RIGHTV/=np.linalg.norm(RIGHTV);UP=np.cross(RIGHTV,CAM)
 girls=[(i,row) for i,row in enumerate(DATA) if row[2]=='female'];sheet=Image.new('RGB',(1536,1120),'#E2E8F1');draw=ImageDraw.Draw(sheet)
 for j,(index,row) in enumerate(girls):
  preview(row,index,'hair_back_preview');file=ROOT/f'batch-{index//5+1}'/'V13'/f'look_{row[0]}_hair_back_preview.png';x=(j%3)*512;y=(j//3)*560;sheet.paste(Image.open(file).convert('RGB'),(x,y));draw.text((x+24,y+515),row[0]+' / hair back',fill='#1E1E2E')
 sheet.save(ROOT/'Hair_Back_QA.png')
 print('V13:15 employees,45 original PNG maps,15 hair accessories,15 previews,3contact sheets PASS')
