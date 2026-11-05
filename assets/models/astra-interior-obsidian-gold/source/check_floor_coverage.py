import json,xml.etree.ElementTree as E
from pathlib import Path
root=Path(__file__).resolve().parents[1];out={}
for theme in ['.']:
 manifest=json.loads((root/theme/'manifest.json').read_text())
 for file in (root/theme/'models').glob('*.rbxmx'):
  rects=[];ys=[]
  for item in E.parse(file).getroot().iter('Item'):
   p=item.find('Properties')
   if p is None:continue
   name=p.findtext("string[@name='Name']") or ''
   if not name.startswith('FinishFloor_'):continue
   cf=p.find("CoordinateFrame[@name='CFrame']");s=p.find("Vector3[@name='size']")
   r=[float(cf.findtext(f'R{i}{j}')) for i in range(3) for j in range(3)];assert r==[1,0,0,0,1,0,0,0,1]
   x,y,z=[float(cf.findtext(k)) for k in 'XYZ'];w,h,d=[float(s.findtext(k)) for k in 'XYZ']
   rects.append((round(x-w/2,6),round(x+w/2,6),round(z-d/2,6),round(z+d/2,6)));ys.append((round(y-h/2,6),round(y+h/2,6)))
  assert len(rects)==169,(file,len(rects))
  half=30 if file.name.startswith('GarageWalls_') else 29
  assert set(ys)==({(-.24,0)} if half==30 else {(0,.02)}),(file,set(ys))
  X=sorted(set([v for r in rects for v in r[:2]]));Z=sorted(set([v for r in rects for v in r[2:]]));assert (X[0],X[-1],Z[0],Z[-1])==(-half,half,-half,half)
  cells=0
  for a,b in zip(X,X[1:]):
   for c,d in zip(Z,Z[1:]):
    x=(a+b)/2;z=(c+d)/2;n=sum(l<x<r and lo<z<hi for l,r,lo,hi in rects);assert n==1,(file,x,z,n);cells+=1
  area=sum((b-a)*(d-c) for a,b,c,d in rects);assert abs(area-(2*half)**2)<1e-5,(file,area)
  out[file.stem]={'floorTiles':169,'coverageCells':cells,'unionArea':round(area,6),'expectedArea':(2*half)**2,'gaps':0,'overlaps':0,'floorY':list(set(ys))[0],'checks':'PASS'}
assert len(out)==4,len(out)
(root/'FLOOR_COVERAGE_INDEPENDENT.json').write_text(json.dumps(out,indent=2));print('4 exact floor partitions: full area, zero gaps, zero overlaps PASS')
