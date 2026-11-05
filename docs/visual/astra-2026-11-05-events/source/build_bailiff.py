"""Original classic-clothing SVG artwork using the accepted exact Roblox UV map."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
UV=json.loads((ROOT/'UV_MAP.json').read_text())
def rect(x,y,w,h,c):return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{c}"/>'
def path(d,c):return f'<path d="{d}" fill="{c}"/>'
def panel(w,h,region,face,pants):
 dark='#293449';side='#242D3E';light='#3C4D67';s=rect(0,0,w,h,dark if face=='F' else side)
 if face in ('U','D'):return s
 if pants:
  if region=='torso':return s+rect(0,104,w,13,'#182331')+rect(57,105,14,11,'#B3BAC4')
  s+=rect(0,109,w,19,'#182331')+rect(0,124,w,4,'#727D8D')
  if face=='F':s+=rect(w/2-1,7,2,101,light)+path(f'M7 16 L{w-7} 16 L{w-12} 33 L12 33Z',side)
  return s
 s+=rect(0,h-9,w,9,side)
 if region!='torso':
  s+=rect(0,111,w,6,'#CFD9E6')+rect(0,117,w,11,'#202B3C')
  if face=='F':
   for x in (8,17):s+=rect(x,109,4,4,'#FFC93C')
  return s
 if face!='F':return s+rect(0,28,w,2,light)
 s+=path('M32 0 L96 0 L82 112 L46 112Z','#DDE9F2')
 s+=path('M56 0 L72 0 L68 17 L60 17Z','#3D7BFF')+path('M60 17 L68 17 L72 66 L64 76 L56 66Z','#3D7BFF')
 s+=path('M0 0 L30 0 L48 30 L37 42 L56 117 L0 117Z',light)+path('M128 0 L98 0 L80 30 L91 42 L72 117 L128 117Z',light)
 # A plain tablet-folder peeks from the jacket's wide breast pocket; no text or authority badge.
 s+=rect(85,43,28,34,'#D5B576')+rect(88,39,22,31,'#A6C6D9')+rect(91,44,16,19,'#3D5877')+rect(83,69,32,8,dark)
 for y in (78,98):s+=rect(61,y,6,6,'#FFC93C')
 return s
for pants in (False,True):
 svg=['<svg xmlns="http://www.w3.org/2000/svg" width="585" height="559" viewBox="0 0 585 559">']
 for region,key in [('torso','torso'),('right','right'),('left','left')]:
  for face,(x,y,w,h) in UV[key].items():svg.append(f'<svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'+panel(w,h,region,face,pants)+'</svg>')
 svg.append('</svg>');typ='pants' if pants else 'shirt';(ROOT/'contracts-bailiff'/'source-svg'/f'bailiff_{typ}.svg').write_text(''.join(svg))
