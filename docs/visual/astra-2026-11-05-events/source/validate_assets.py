from pathlib import Path
import json,sys,hashlib,math
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1];partial='--partial' in sys.argv
spec=json.loads((ROOT/'prompts.json').read_text());reports=[]
try:font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',15)
except OSError:font=ImageFont.load_default()
for folder in ('events-1','events-2','contracts-bailiff'):

 if '--batch' in sys.argv and folder!=sys.argv[sys.argv.index('--batch')+1]:continue
 base=ROOT/folder;expected=[a for a in spec['assets'] if a['folder']==folder];ready=[];pending=[]
 for a in expected:
  f=base/'V19'/a['file'];m=base/'metadata'/(a['id']+'.json')
  if not f.exists():pending.append(a['file']);continue
  im=Image.open(f);assert im.size==(256,256) and im.mode=='RGBA',(f,im.size,im.mode)
  alpha=im.getchannel('A');assert alpha.getextrema()==(0,255),(f,'alpha')
  assert alpha.getpixel((0,0))==0 and alpha.getpixel((255,255))==0,(f,'corners')
  active=alpha.point(lambda x:255 if x>16 else 0).getbbox();assert active[0]>0 and active[1]>0 and active[2]<256 and active[3]<256,(f,'clipped',active)
  meta=json.loads(m.read_text());assert meta['tool']=='built-in image_gen' and meta['transparent_background'] and meta['prompt']
  ready.append({'file':a['file'],'size':[256,256],'mode':im.mode,'alpha':[0,255],'visibleBounds':active,'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'exactPromptMetadata':str(m.relative_to(ROOT))})
 if not partial:assert not pending,(folder,pending)
 report={'status':'IN_PROGRESS' if pending else 'PASS','expected':len(expected),'ready':len(ready),'pending':pending,'assets':ready,'generation':'one built-in image_gen call per raster asset; genuine tool-generated alpha preserved; final resize through sips','studioTested':False}
 if folder=='contracts-bailiff':
  clothing=[]
  for typ in ('shirt','pants'):
   p=base/'V19'/f'bailiff_{typ}.png';im=Image.open(p);assert im.size==(585,559) and im.mode=='RGBA';assert im.getchannel('A').getextrema()==(0,255)
   clothing.append({'file':p.name,'size':[585,559],'mode':'RGBA','authored':'original SVG on exact accepted classic-clothing UV map'})
  report['clothing']=clothing
 (base/'VALIDATION.json').write_text(json.dumps(report,indent=2));reports.append({'batch':folder,'status':report['status'],'ready':len(ready),'expected':len(expected)})
 if ready:
  cols=3 if len(ready)>4 else 2;rows=math.ceil(len(ready)/cols);sheet=Image.new('RGB',(cols*320,rows*320),'#E7EAF1');d=ImageDraw.Draw(sheet)
  for j,a in enumerate(ready):
   x=(j%cols)*320;y=(j//cols)*320;im=Image.open(base/'V19'/a['file']);sheet.paste(im,(x+32,y+16),im);d.text((x+20,y+281),a['file'],font=font,fill='#1E1E2E')
  sheet.save(base/'V19_ContactSheet.png')
 (base/'README.md').write_text(f'''# V19 / {folder}\n\nExpected {len(expected)} icons; current status {report['status']}. All final raster icons are256×256 PNG with genuine transparency, thick dark#1E1E2E outlines, blue#3D7BFF and gold#FFC93C, plus a few subject accents. Built-in image_gen was called separately for every illustration; no SVG stand-ins were used for icons. Exact prompts, generated-source paths and final filenames are saved per asset in metadata/. PNGs are resized through sips and retain RGBA alpha. Contact sheet shows final256assets at native size.\n\nFilenames correspond to the actual origin/main config IDs. CONFIG_IDS.json records the discrepancy: VISUAL says20events/8rivals while CompanyEvents has22 and Rivals has9. All actual IDs are delivered across the four batches. Rival names are recorded in metadata for integration; only original pictograms are rendered, without studio names or real brands.\n\nUpload PNGs to Roblox and connect the resulting IDs in the existing UI. No gameplay code or Git state changed. Validate small-screen readability and moderation/upload results in Studio before release.\n\nThe contracts-bailiff batch additionally includes original585×559 shirt/pants SVG artwork and PNGs using the accepted classic-clothing UV system. Clothing is authored deterministically because exact UV geometry matters; its raster icons use image_gen like every other V19 icon.\n\nStandalone validation from the package root: `python3 source/validate_assets.py --batch {folder}`.\n''')
(ROOT/'VALIDATION.json').write_text(json.dumps({'batches':reports,'actualConfigCounts':{'events':22,'rivals':9,'extraIcons':4},'expectedRasterIcons':26,'rivalsOwnership':'Separate audit-agent deliverable; do not write or validate its directory from this script','readyRasterIcons':sum(r['ready'] for r in reports)},indent=2));print(json.dumps(reports))
