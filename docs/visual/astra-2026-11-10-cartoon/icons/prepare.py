from pathlib import Path
import json, hashlib
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
rows = json.loads((ROOT / 'manifest.json').read_text())
report = []
sheet = Image.new('RGB', (1000, 720), '#e8edf5')
draw = ImageDraw.Draw(sheet)
for i, row in enumerate(rows):
    src = Image.open(ROOT / row['source']).convert('RGBA')
    im = src.resize((512, 512), Image.Resampling.LANCZOS)
    target = ROOT / ('icon_' + row['id'] + '.png')
    im.save(target)
    alpha = im.getchannel('A')
    hist = alpha.histogram()
    assert hist[0] > 0 and sum(hist[1:255]) > 0
    bbox = alpha.point(lambda p: 255 if p > 8 else 0).getbbox()
    assert bbox and min(bbox[0], bbox[1], 512-bbox[2], 512-bbox[3]) >= 6, (row['id'], bbox)
    x, y = (i % 5)*200, (i // 5)*240
    draw.text((x+8, y+8), row['id'], fill='#172134')
    for j, bg in enumerate(('#1e2433', '#f4e9dd')):
        tile = Image.new('RGBA', (92, 150), bg)
        tile.alpha_composite(im.resize((80,80), Image.Resampling.LANCZOS), (6,35))
        sheet.paste(tile.convert('RGB'), (x+4+j*96, y+35))
    report.append({'file':target.name, 'size':list(im.size), 'mode':im.mode,
                   'sourceSize':list(src.size), 'alphaZeroPixels':hist[0],
                   'alphaIntermediatePixels':sum(hist[1:255]), 'visibleBounds':bbox,
                   'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
sheet.save(ROOT/'PREVIEW_80px.png')
(ROOT/'VALIDATION.json').write_text(json.dumps({'assets':report, 'studioTested':False}, indent=2)+'\n')
print('Validated', len(report), 'RGBA icons; preview at 80px')
