"""Build periodic game maps from original generated color sources. numpy + Pillow."""
from pathlib import Path
import json,hashlib,shutil
import numpy as np
from PIL import Image,ImageFilter,ImageDraw
ROOT=Path(__file__).resolve().parent
SPECS={'wood_floor':('WoodPlanks',.43,2.2,0),'wood_dark':('Wood',.52,1.9,0),'concrete_wall':('Concrete',.86,.9,0),'fabric_carpet':('Fabric',.96,2.4,0),'brushed_metal':('Metal',.44,.6,255),'brick_warm':('Brick',.88,3.2,0),'plastic_soft':('SmoothPlastic',.54,.28,0),'marble_light':('Marble',.28,.12,0)}
def periodic(a,width=40):
 a=a.copy().astype(float)
 # Opposing texel boundaries coincide. Cosine taper distributes corrections locally.
 for axis in [1,0]:
  b=np.moveaxis(a,axis,0);delta=(b[-1]-b[0])*.5
  for i in range(width):
   w=.5+.5*np.cos(np.pi*i/width);b[i]+=delta*w;b[-1-i]-=delta*w
  a=np.moveaxis(b,0,axis)
 return a

def fabric_surface(source):
 n=1024;y,x=np.meshgrid(np.linspace(0,1,n),np.linspace(0,1,n),indexing='ij');a=x*128;b=y*128
 # Stationary repeating warp/weft removes a visible stripe in the generated fabric.
 warp=np.cos(a*2*np.pi);weft=np.cos(b*2*np.pi);alternation=np.cos(a*np.pi)*np.cos(b*np.pi)
 relief=.55*warp+.55*weft+.26*alternation+.16*np.sin(a*6*np.pi+b*.0)+.13*np.sin(b*8*np.pi)
 variation=.035*np.sin(x*2*np.pi*3+y*2*np.pi*2)+.02*np.cos(y*2*np.pi*7-x*2*np.pi*2)
 palette=np.median(np.array(source.resize((128,128)),float),axis=(0,1))
 return np.uint8(np.clip(palette[None,None,:]*(1+relief[:,:,None]*.14+variation[:,:,None]),0,255))

def sphere(color,normal,rough,metal,n=300):
 yy,xx=np.mgrid[:n,:n];x=(xx-(n-1)/2)/(n*.46);y=-((yy-(n-1)/2)/(n*.46));r=x*x+y*y;mask=r<1;z=np.sqrt(np.clip(1-r,0,1));N=np.dstack((x,y,z));u=(np.arctan2(x,z)/np.pi+1)*.5;v=np.arccos(np.clip(y,-1,1))/np.pi
 tx=np.minimum((u*color.shape[1]).astype(int),color.shape[1]-1);ty=np.minimum((v*color.shape[0]).astype(int),color.shape[0]-1);base=color[ty,tx]/255
 light=np.array([-.4,.7,.6]);light/=np.linalg.norm(light);d=np.clip(N@light,0,1);h=light+np.array([0,0,1]);h/=np.linalg.norm(h);spec=np.clip(N@h,0,1)**(8+(1-rough)*100);lit=base*(.28+.72*d[:,:,None])+(spec[:,:,None]*(.08+.45*metal)*(1-rough*.5));out=np.full((n,n,3),238,dtype='uint8');out[mask]=np.uint8(np.clip(lit[mask]*255,0,255));return Image.fromarray(out)

def cube(color,n=300):
 out=Image.new('RGB',(n,n),'#eeeeee');a=np.array(out);yy,xx=np.mgrid[:n,:n]
 # Isometric cube, each face textured through inverse affine coordinates.
 for origin,U,V,shade in [([150,26],[116,58],[-116,58],1.05),([34,84],[116,58],[0,139],.73),([150,142],[116,-58],[0,139],.92)]:
  mat=np.array([U,V],float).T;coords=(np.dstack([xx-origin[0],yy-origin[1]])@np.linalg.inv(mat).T);u=coords[:,:,0];v=coords[:,:,1];mask=(u>=0)&(u<=1)&(v>=0)&(v<=1);tx=np.clip((u*(len(color)-1)).astype(int),0,len(color)-1);ty=np.clip((v*(len(color)-1)).astype(int),0,len(color)-1);a[mask]=np.uint8(np.clip(color[ty[mask],tx[mask]]*shade,0,255))
 return Image.fromarray(a)

def main():
 sources=json.loads((ROOT/'source_manifest.json').read_text());report=[];(ROOT/'source').mkdir(exist_ok=True);(ROOT/'512').mkdir(exist_ok=True);(ROOT/'previews').mkdir(exist_ok=True)
 for name,(enum,rough,strength,metal) in SPECS.items():
  p=Path(sources[name]['path']);p=p if p.is_absolute() else ROOT/p;raw=Image.open(p).convert('RGB');source=ROOT/'source'/f'{name}.png'
  if p.resolve()!=source.resolve():shutil.copy(p,source)
  sources[name]['path']=str(source.relative_to(ROOT));arr=np.array(raw.resize((1024,1024),Image.Resampling.LANCZOS),float);initial=float(np.sqrt(np.mean((arr[0]-arr[-1])**2)));arr=fabric_surface(raw) if name=='fabric_carpet' else arr;arr=np.uint8(np.clip(periodic(arr),0,255));Image.fromarray(arr).save(ROOT/f'{name}_color.png')
  height=np.array(Image.fromarray(arr).convert('L').filter(ImageFilter.GaussianBlur(.65)),float)/255;gx=(np.roll(height,-1,1)-np.roll(height,1,1))*.5;gy=(np.roll(height,-1,0)-np.roll(height,1,0))*.5;norm=np.dstack((-gx*strength,gy*strength,np.ones_like(gx)));norm/=np.linalg.norm(norm,axis=2)[:,:,None];norm=periodic(norm);norm/=np.linalg.norm(norm,axis=2)[:,:,None];norm8=np.uint8(np.clip((norm*.5+.5)*255,0,255));Image.fromarray(norm8).save(ROOT/f'{name}_normal.png')
  rr=np.uint8(np.clip(periodic(np.clip(rough+(height-height.mean())*.1,0,1)),0,1)*255);Image.fromarray(rr).save(ROOT/f'{name}_roughness.png');Image.new('L',(1024,1024),metal).save(ROOT/f'{name}_metalness.png');maps={}
  for suffix in ['color','normal','roughness','metalness']:
   fn=ROOT/f'{name}_{suffix}.png';im=Image.open(fn);a=np.array(im,float);edge=max(float(np.abs(a[0]-a[-1]).max()),float(np.abs(a[:,0]-a[:,-1]).max()));assert edge<=1,(name,suffix,edge);assert im.size==(1024,1024);assert np.isfinite(a).all();maps[suffix]={'mode':im.mode,'size':list(im.size),'oppositeBorderMaxDifference':edge,'sha256':hashlib.sha256(fn.read_bytes()).hexdigest()}
   small=np.array(im.resize((512,512),Image.Resampling.LANCZOS),float);small=np.uint8(np.clip(periodic(small,20),0,255));Image.fromarray(small).save(ROOT/'512'/fn.name)
  # Tile and 2x2 transition preview, plus actual mapped analytical primitives.
  sheet=Image.new('RGB',(1100,390),'#eeeeee');d=ImageDraw.Draw(sheet);d.text((22,12),name+' / '+enum,fill='#222222');tile=Image.fromarray(arr).resize((170,170));
  for x in range(2):
   for y in range(2):sheet.paste(tile,(15+x*170,40+y*170))
  sheet.paste(cube(arr),(390,48));sheet.paste(sphere(arr,norm8,rough,metal/255),(755,48));d.text((105,365),'2 x 2 repeat',fill='#222222');d.text((493,355),'cube',fill='#222222');d.text((845,355),'sphere',fill='#222222');sheet.save(ROOT/'previews'/f'{name}.png')
  report.append({'name':name,'Enum.Material':enum,'sourcePixels':list(raw.size),'deliveredPixels':[1024,1024],'source':'built-in image_gen original albedo','processing':'Lanczos size conversion; cosine-taper boundary projection; approximate tonal normal and roughness; not scans','fabricReconstruction':name=='fabric_carpet','sourceVerticalBorderRMSE':initial,'metalness':metal/255,'normalConvention':'OpenGL tangent +Y; RGB data, not sRGB albedo','maps':maps,'preview':'analytical CPU cube/sphere, approximate shading; normal map not applied in preview','StudioTested':False})
 (ROOT/'source_manifest.json').write_text(json.dumps(sources,indent=2)+'\n');(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n');contact=Image.new('RGB',(1100,390*8),'#eeeeee')
 for i,name in enumerate(SPECS):contact.paste(Image.open(ROOT/'previews'/f'{name}.png'),(0,i*390))
 contact.save(ROOT/'Materials_preview.png');print([(x['name'],x['sourcePixels'])for x in report])
if __name__=='__main__':main()
