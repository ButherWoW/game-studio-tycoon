"""Depth-render real native accessory geometry and exact generated UV panels on a block rig."""
from build_skins import *
W=H=768
CAM=np.array([.43,.23,-.87]);CAM/=np.linalg.norm(CAM)
RIGHTV=np.cross(np.array([0,1,0]),CAM);RIGHTV/=np.linalg.norm(RIGHTV)
UP=np.cross(CAM,RIGHTV)
# Camera right points +X for a camera at front -Z.
RIGHTV=-RIGHTV;UP=np.cross(RIGHTV,CAM)
LIGHT=np.array([-.4,.8,-.5]);LIGHT/=np.linalg.norm(LIGHT)

def preview(row,index):
 out=ROOT/f'batch-{index//4+1}'/'V12';shirt=Image.open(out/f'skin_{row[0]}_shirt.png').convert('RGBA');pants=Image.open(out/f'skin_{row[0]}_pants.png').convert('RGBA')
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
 # Parts are the actual accessory geometry. Attachment transform head/body anchor defines placement.
 for group in accessories(row):
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
 im=Image.fromarray(bg).resize((512,512),Image.Resampling.LANCZOS);im.save(out/f'skin_{row[0]}_preview.png')

def validate_batch(b):
 rows=DATA[(b-1)*4:b*4];base=ROOT/f'batch-{b}';report={'studioTested':False,'renderer':'actual UV mapped block rig and exported accessory Part geometry','skins':{}}
 for row in rows:
  id=row[0];out=base/'V12'
  for typ in ['shirt','pants']:
   im=Image.open(out/f'skin_{id}_{typ}.png');assert im.size==(585,559) and im.mode=='RGBA';assert im.getpixel((0,0))[3]==0
   # All mapped faces contain ink; separator gutters remain transparent.
   for areas in [TORSO,RIGHT,LEFT]:
    for face,(x,y,w,h) in areas.items():assert im.getpixel((x+w//2,y+h//2))[3]>0
  xml=ET.parse(out/f'skin_{id}_acc.rbxmx').getroot();items=xml.findall('.//Item');parts=[i for i in items if i.get('class')=='Part'];assert len(parts)<=40
  allowed={'Model','Accessory','Part','Attachment','WeldConstraint'};assert {i.get('class') for i in items}<=allowed
  refs={i.get('referent'):i for i in items}
  for ac in xml.findall('.//Item[@class="Accessory"]'):
   pp=ac.findall('./Item[@class="Part"]');hh=[p for p in pp if p.findtext("Properties/string[@name='Name']")=='Handle'];assert len(hh)==1
   assert hh[0].find('./Item[@class="Attachment"]') is not None
   for p in pp:
    assert p.findtext("Properties/bool[@name='Anchored']")=='false' and p.findtext("Properties/bool[@name='Massless']")=='true'
    assert p.findtext("Properties/bool[@name='CanCollide']")=='false'
    if p is not hh[0]:
     weld=p.find('./Item[@class="WeldConstraint"]');assert weld is not None
     assert weld.findtext("Properties/Ref[@name='Part0']")==hh[0].get('referent') and weld.findtext("Properties/Ref[@name='Part1']")==p.get('referent')
  assert Image.open(out/f'skin_{id}_preview.png').size==(512,512)
  report['skins'][id]={'parts':len(parts),'accessories':len(xml.findall('.//Item[@class="Accessory"]')),'checks':'PASS','clothing':[585,559],'preview':[512,512]}
 (base/'VALIDATION.json').write_text(json.dumps(report,indent=2))
 sheet=Image.new('RGB',(1024,1120),'#E2E8F1');d=ImageDraw.Draw(sheet)
 for j,row in enumerate(rows):
  p=base/'V12'/f'skin_{row[0]}_preview.png';x=(j%2)*512;y=(j//2)*560;sheet.paste(Image.open(p).convert('RGB'),(x,y));d.text((x+25,y+515),row[0],fill='#1E1E2E')
 sheet.save(base/'V12_ContactSheet.png')
 (base/'README.md').write_text(f'''# Employee skins V12 — batch {b}\n\nFour original skins: {', '.join(r[0] for r in rows)}. {'Cash tier.' if b<3 else 'Premium tier with native Neon accessories.'}\n\nEach includes 585×559 transparent PNG shirt/pants mapped to the official classic Roblox R15 layout, a native-part accessory collection, and a 512×512 preview. SVG artwork sources are included. UV map/reference and shared generators are provided in the parent directory. No third-party artwork, brands, text, scripts, meshes or external textures are embedded in accessories. Clothing uses original geometric artwork authored as exact SVG panels and rasterized with resvg; no image model generated or guessed the UV layout.\n\nPreview is a local depth render using the actual exported clothing textures and the same accessory geometry on a segmented block rig, not a Roblox Studio screenshot or moderation guarantee.\n\n## Import and test\n\nUpload shirt/pants images and send IDs to Dev 2. For runtime Shirt/Pants, use ShirtTemplate/PantsTemplate texture IDs as appropriate; verify on Studio Block Avatar R15. The root skin_<id>_acc is a Model containing one or two Accessory instances. Extract children and add each using Humanoid:AddAccessory, rather than parenting the outer collection as one accessory. Each Accessory has Handle, one standard Attachment, unanchored massless noncolliding geometry and rigid welds. The collection PrimaryPart points to the first Handle. Maximum40 Parts total per skin.\n\nPreview uses explicit canonical block-rig attachment coordinates and targetAttachment × inverse(localAttachment); actual NPC attachment frames/body scales may differ. Test attachment alignment on the game's actual NPC body/head scale, idle and seated poses, sleeve/waist/ankle seams, transparency, item clipping and phone readability. Head size variants can need attachment adjustments. Classic clothing cannot emit light; only the premium native accessories use Neon. No PointLights. No Studio/runtime test performed here.\n\nOfficial mapping/testing reference: https://create.roblox.com/docs/avatar/classic-clothing\n''')
if __name__=='__main__':
 import argparse
 ap=argparse.ArgumentParser();ap.add_argument('--batch',type=int,choices=[1,2,3]);args=ap.parse_args()
 batches=[args.batch] if args.batch else [b for b in range(1,4) if (ROOT/f'batch-{b}'/'V12').exists()]
 for index,row in enumerate(DATA):
  if index//4+1 in batches:preview(row,index)
 for b in batches:validate_batch(b)
 print(f'{4*len(batches)} skins: UV maps, accessory collections and previews PASS')
