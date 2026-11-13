from pathlib import Path
from PIL import Image, ImageDraw
import json, hashlib
root=Path(__file__).resolve().parent
rows=json.loads((root/'manifest.json').read_text())
sheet=Image.new('RGB',(1152,1100),'#dce6ed');draw=ImageDraw.Draw(sheet);report=[]
for i,row in enumerate(rows):
    src=Image.open(root/row['source']).convert('RGB')
    size=(512,512) if row['id']=='icon' else (1920,1080)
    out=src.resize(size,Image.Resampling.LANCZOS)
    name='game_icon.png' if row['id']=='icon' else row['id']+'.png'
    out.save(root/name)
    assert out.size==size and out.mode=='RGB'
    if i==0: sheet.paste(out.resize((256,256)),(448,20))
    else:
        x=((i-1)%2)*576;y=316+((i-1)//2)*360
        sheet.paste(out.resize((576,324)),(x,y));draw.text((x+12,y-24),row['id'],fill='#152638')
    report.append({'file':name,'size':list(out.size),'sourceSize':list(src.size),
                   'sourceAspect':src.width/src.height,'targetAspect':size[0]/size[1],
                   'mode':out.mode,'sha256':hashlib.sha256((root/name).read_bytes()).hexdigest()})
sheet.save(root/'PREVIEW.png')
(root/'VALIDATION.json').write_text(json.dumps({'assets':report,'studioTested':False,'isGameplayScreenshot':False},indent=2)+'\n')
print('Validated square icon and three 1920x1080 thumbnails')
