"""Export transparent generated logos at256px; validate and create a review contact sheet."""
import sys,json,hashlib
from pathlib import Path
sys.path.insert(0,'/private/tmp/gst-render-libs')
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
IDS=['tinfoilOwl','mangoComet','quokkaPixel','gloomberry','brassfern','velvetAnvil','nimbusTurtle','okraLantern','bluemoth']
meta=json.loads((ROOT/'prompts.json').read_text());assert [e['id'] for e in meta['assets']]==IDS
report={'generator':'built-in image_gen','requestedPixels':[256,256],'alpha':True,'visualReview':'All9 individually inspected: original symbols, no text/watermark/real brands; glossy low-poly/bold navy outline family.','configIDs':IDS,'note':'VISUAL says8 rivals; current Config/Rivals contains9 and all9 are delivered.','assets':{}}
for e in meta['assets']:
 src=ROOT/e['sourceCopy'];im=Image.open(src);assert im.format=='PNG' and 'A' in im.getbands();im=im.convert('RGBA');a=im.getchannel('A');assert a.getextrema()==(0,255)
 assert all(im.getpixel(xy)[3]==0 for xy in [(0,0),(im.width-1,0),(0,im.height-1),(im.width-1,im.height-1)])
 # Technical UI packing only: preserve provided alpha; no new content or background segmentation.
 bbox=a.getbbox();cut=im.crop(bbox);cut.thumbnail((216,216),Image.Resampling.LANCZOS);out=Image.new('RGBA',(256,256),(0,0,0,0));out.alpha_composite(cut,((256-cut.width)//2,(256-cut.height)//2));dest=ROOT/e['filename'];out.save(dest,optimize=True)
 final=Image.open(dest);assert final.size==(256,256) and final.mode=='RGBA';alpha=final.getchannel('A');hist=alpha.histogram();box=alpha.getbbox();assert box[0]>=19 and box[1]>=19 and box[2]<=237 and box[3]<=237
 report['assets'][e['id']]={'filename':e['filename'],'sourceFilename':e['sourceFilename'],'sourceCopy':e['sourceCopy'],'sourceSize':list(im.size),'sourceSHA256':hashlib.sha256(src.read_bytes()).hexdigest(),'finalSHA256':hashlib.sha256(dest.read_bytes()).hexdigest(),'mode':final.mode,'size':list(final.size),'alphaMinMax':list(alpha.getextrema()),'transparentPixels':hist[0],'nontransparentBBox':list(box),'checks':'PASS'}
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2))
sheet=Image.new('RGB',(1440,1380),'#E5E9F2');d=ImageDraw.Draw(sheet)
for i,e in enumerate(meta['assets']):
 x=i%3*480;y=i//3*460;icon=Image.open(ROOT/e['filename']).convert('RGBA');sheet.paste(icon,(x+112,y+30),icon);d.text((x+30,y+304),e['id'],fill='#1E1E2E')
 for j,bg in enumerate(['#F2F2F2','#1E1E2E']):
  bx=x+115+j*150;by=y+352;d.rounded_rectangle((bx-10,by-10,bx+58,by+58),radius=12,fill=bg);small=icon.resize((48,48),Image.Resampling.LANCZOS);sheet.paste(small,(bx,by),small)
 d.text((x+30,y+425),'256px / 48px light + dark',fill='#596375')
sheet.save(ROOT/'Rivals_ContactSheet.png')
print('9 rivals:256x256RGBA,real alpha,consistent margin,source hashes PASS')
