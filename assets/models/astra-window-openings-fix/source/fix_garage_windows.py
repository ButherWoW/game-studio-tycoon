"""Restore real glass and cut its openings through the accepted rear door backing.
All fragments remain inside their original solids: no geometry moves or added overlap.
"""
from pathlib import Path
import xml.etree.ElementTree as E
import copy,json,subprocess,math
ROOT=Path(__file__).resolve().parents[1]
ROJO='/Users/erland/.local/gst-tools/rojo'
EPS=1e-7

def named(e,tag,name):return e.find(f'Properties/{tag}[@name="{name}"]')
def name(e):return e.findtext('Properties/string[@name="Name"]')
def xyz(e,tag,key):return [float(v.text) for v in named(e,tag,key) if v.tag in 'XYZ']
def bounds(e):
 p=xyz(e,'CoordinateFrame','CFrame');s=xyz(e,'Vector3','size');return [p[a]-s[a]/2 for a in range(3)],[p[a]+s[a]/2 for a in range(3)]
def intersect(a,b):
 lo=[max(a[0][j],b[0][j]) for j in range(3)];hi=[min(a[1][j],b[1][j]) for j in range(3)];return (lo,hi) if min(hi[j]-lo[j] for j in range(3))>EPS else None
def subtract(rect,cut):
 inter=intersect(rect,cut)
 if inter is None:return [rect]
 lo,hi=rect;il,ih=inter;worklo=lo.copy();workhi=hi.copy();result=[]
 for axis in range(3):
  if il[axis]-worklo[axis]>EPS:
   q=workhi.copy();q[axis]=il[axis];result.append((worklo.copy(),q));worklo[axis]=il[axis]
  if workhi[axis]-ih[axis]>EPS:
   q=worklo.copy();q[axis]=ih[axis];result.append((q,workhi.copy()));workhi[axis]=ih[axis]
 return result

def main():
 (ROOT/'models').mkdir(exist_ok=True);manifest=[]
 for f in sorted((ROOT/'baseline').glob('*.rbxmx')):
  tree=E.parse(f);root=tree.getroot();parents={c:p for p in root.iter() for c in p};parts=root.findall('.//Item[@class="Part"]');glass=[p for p in parts if name(p) in ['WindowGlass','DoorWindow']];assert len(glass)==12
  cuts=[]
  for pane in glass:
   named(pane,'float','Transparency').text='0.4';named(pane,'token','Material').text='1568'
   if name(pane)=='DoorWindow':
    lo,hi=bounds(pane);lo[2]=-30.1;hi[2]=-28.45;cuts.append((lo,hi))
  modified=[]
  for p in parts:
   if p in glass or float(p.findtext('Properties/float[@name="Transparency"]','0'))>=.99:continue
   original=bounds(p)
   if not any(intersect(original,c) for c in cuts):continue
   assert p.findtext('Properties/token[@name="shape"]','1')=='1',(f.name,name(p),'nonbox')
   rot=named(p,'CoordinateFrame','CFrame');assert all(abs(float(rot.findtext(f'R{i}{j}'))-(1 if i==j else 0))<1e-6 for i in range(3) for j in range(3))
   rects=[original]
   for cut in cuts:rects=[piece for rect in rects for piece in subtract(rect,cut)]
   assert rects
   parent=parents[p];index=list(parent).index(p);parent.remove(p);refs=[]
   for k,(lo,hi) in enumerate(rects):
    q=copy.deepcopy(p);ref=p.get('referent') if k==0 else p.get('referent')+f'_WindowCut{k}';q.set('referent',ref);refs.append(ref);named(q,'string','Name').text=name(p)+f'_WindowCut{k:02}'
    for axis,letter in enumerate('XYZ'):
     named(q,'CoordinateFrame','CFrame').find(letter).text=f'{(lo[axis]+hi[axis])/2:.9g}';named(q,'Vector3','size').find(letter).text=f'{hi[axis]-lo[axis]:.9g}'
    parent.insert(index+k,q)
   modified.append({'originalReferent':p.get('referent'),'name':name(p),'newReferents':refs,'originalBounds':original})
  out=ROOT/'models'/f.name;tree.write(out,encoding='utf-8',xml_declaration=True);proj=ROOT/'source'/'convert.project.json';proj.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(out)}}));subprocess.run([ROJO,'build',str(proj),'-o',str(out.with_suffix('.rbxm'))],check=True,capture_output=True);proj.unlink();manifest.append({'model':f.stem,'glassCount':len(glass),'cuts':cuts,'modified':modified})
 (ROOT/'GARAGE_CHANGES.json').write_text(json.dumps(manifest,indent=2)+'\n')
if __name__=='__main__':main()
