from pathlib import Path
from PIL import Image,ImageDraw
import json,shutil,hashlib
ROOT=Path(__file__).resolve().parent;sources=json.loads((ROOT/'source_manifest.json').read_text());(ROOT/'source').mkdir(exist_ok=True);report=[];sheet=Image.new('RGB',(1280,600),'#eef0ec');draw=ImageDraw.Draw(sheet)
for index,(name,row) in enumerate(sources.items()):
 p=Path(row['path']);p=p if p.is_absolute() else ROOT/p;src=Image.open(p);assert src.mode=='RGBA',(name,src.mode);copy=ROOT/'source'/(name+'.png')
 if copy.resolve()!=p.resolve():shutil.copy(p,copy)
 row['path']=str(copy.relative_to(ROOT));im=src.resize((256,256),Image.Resampling.LANCZOS);im.save(ROOT/(name+'.png'));alpha=im.getchannel('A');h=alpha.histogram();assert sum(h[1:255])>0;assert h[0]>0;assert alpha.getbbox() is not None
 edge=max(alpha.crop((0,0,256,1)).getextrema()[1],alpha.crop((0,255,256,256)).getextrema()[1],alpha.crop((0,0,1,256)).getextrema()[1],alpha.crop((255,0,256,256)).getextrema()[1]);assert edge<16,(name,edge)
 for j,bg in enumerate(['#203241','#efe9db']):
  tile=Image.new('RGBA',(256,256),bg);tile.alpha_composite(im);sheet.paste(tile.convert('RGB'),(index*256,j*292+24));draw.text((index*256+8,j*292+4),name,fill='#202020')
 report.append({'name':name,'size':[256,256],'mode':'RGBA','sourceSize':list(src.size),'alphaZeroPixels':h[0],'alphaIntermediatePixels':sum(h[1:255]),'maxEdgeAlpha':edge,'sha256':hashlib.sha256((ROOT/(name+'.png')).read_bytes()).hexdigest(),'source':'built-in image_gen with transparent_background=true; only Lanczos normalization','StudioTested':False})
sheet.save(ROOT/'FX_preview.png');(ROOT/'source_manifest.json').write_text(json.dumps(sources,indent=2)+'\n');(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n');print([(x['name'],x['maxEdgeAlpha'])for x in report])
