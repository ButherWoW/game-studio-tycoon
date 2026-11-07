from pathlib import Path
import sys,json,hashlib
sys.path.insert(0,'/private/tmp/gst-realism-libs')
import numpy as np
from PIL import Image,ImageOps,ImageFilter,ImageDraw
ROOT=Path(__file__).resolve().parent;out=ROOT/'textures';out.mkdir(exist_ok=True)
inputs=json.loads((ROOT/'texture_sources.json').read_text());report=[]
settings={'stone':(.86,4),'soil':(.95,3),'wood':(.60,3),'broadleaf':(.56,2),'petal':(.72,1.5)}
sheet=Image.new('RGB',(1280,560),'#eee9e0');d=ImageDraw.Draw(sheet)
for index,(name,row)in enumerate(inputs.items()):
 source=Image.open(row['path']).convert('RGB');original=source.size
 image=ImageOps.fit(source,(2048,2048),method=Image.Resampling.LANCZOS)
 image.save(out/f'{name}_basecolor.png')
 # Artist-authored material data: approximate micro-bump from tonal relief.
 # Not calibrated scans and not normals baked from a high-poly mesh.
 height=np.asarray(image.convert('L').filter(ImageFilter.GaussianBlur(1)),dtype=float)/255
 gx=(np.roll(height,-1,axis=1)-np.roll(height,1,axis=1))/2
 gy=(np.roll(height,-1,axis=0)-np.roll(height,1,axis=0))/2
 rough,strength=settings[name];n=np.dstack((-gx*strength,gy*strength,np.ones_like(height)));n/=np.linalg.norm(n,axis=2)[:,:,None]
 Image.fromarray(np.uint8(np.clip((n*.5+.5)*255,0,255))).save(out/f'{name}_normal.png')
 r=np.uint8(np.clip(rough+(height-height.mean())*.10,0,1)*255)
 Image.fromarray(r).save(out/f'{name}_roughness.png')
 Image.new('L',(2048,2048),0).save(out/f'{name}_metallic.png')
 Image.fromarray(np.dstack((np.full_like(r,255),r,np.zeros_like(r)))).save(out/f'{name}_orm.png')
 thumb=image.resize((240,420));sheet.paste(thumb,(index*256+8,16));d.text((index*256+8,455),name,fill='#222')
 report.append({'name':name,'sourcePixels':original,'deliveredPixels':[2048,2048],'upscaled':max(original)<2048,'normalConvention':'OpenGL tangent +Y','maps':['basecolor','normal','roughness','metallic','orm'],'metallic':0,'roughnessBase':rough,'provenance':'built-in image_gen albedo; derived artist-authored approximate micro-normal/roughness; not scans or high-poly bake','hashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in out.glob(name+'_*.png')}})
sheet.save(ROOT/'MATERIAL_PREVIEW.png')
(ROOT/'MATERIAL_VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n')
(ROOT/'TEXTURE_PROMPTS.md').write_text('# Built-in image_gen prompts\n\n'+'\n\n'.join('## '+k+'\n\n'+v['prompt']for k,v in inputs.items()))
print([(r['name'],r['sourcePixels'],r['upscaled'])for r in report])
