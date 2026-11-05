"""Independent audit of final RBXMX, without importing builder geometry.
SAT uses conservative oriented boxes; touching within1e-5 is accepted.
Run from anywhere: python3 path/to/independent_audit.py.
"""
from pathlib import Path
import xml.etree.ElementTree as ET
import math,json,itertools,re
ROOT=Path(__file__).resolve().parents[1]
EPS=1e-5
I=[1.,0.,0.,0.,1.,0.,0.,0.,1.]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def mv(r,v):return [dot(r[i*3:i*3+3],v) for i in range(3)]
def mm(a,b):return [sum(a[i*3+k]*b[k*3+j] for k in range(3)) for i in range(3) for j in range(3)]
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def props(item):return {e.attrib['name']:e for e in item.find('Properties')}
def cf(e):return [float(e.find(k).text) for k in 'XYZ'],[float(e.find(f'R{i}{j}').text) for i in range(3) for j in range(3)]
def axes(p):return [[p['r'][i*3+j] for i in range(3)] for j in range(3)]
def bounds(parts):
 los=[];his=[]
 for p in parts:
  ex=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  los.append([p['p'][i]-ex[i] for i in range(3)]);his.append([p['p'][i]+ex[i] for i in range(3)])
 return [[min(a[i] for a in los) for i in range(3)],[max(a[i] for a in his) for i in range(3)]]
def overlaps(a,b):
 aa,bb=axes(a),axes(b);delta=[b['p'][i]-a['p'][i] for i in range(3)]
 for axis in aa+bb+[cross(x,y) for x in aa for y in bb]:
  norm=math.sqrt(dot(axis,axis))
  if norm<1e-9:continue
  axis=[x/norm for x in axis]
  ra=sum(abs(dot(axis,aa[i]))*a['s'][i]/2 for i in range(3));rb=sum(abs(dot(axis,bb[i]))*b['s'][i]/2 for i in range(3))
  if ra+rb-abs(dot(delta,axis))<=EPS:return False
 return True

def parse(path):
 root=ET.parse(path).getroot();parts=[]
 for item in root.findall('.//Item'):
  if item.attrib['class'] not in ['Part','WedgePart','Seat']:continue
  pr=props(item);p,r=cf(pr['CFrame']);s=[float(pr['size'].find(k).text) for k in 'XYZ']
  parts.append({'name':pr['Name'].text,'p':p,'r':r,'s':s,'item':item,'shape':int(pr['shape'].text) if 'shape'in pr else 1})
 return root,parts


from PIL import Image,ImageDraw
import hashlib
root,ps=parse(ROOT/'InvestorCase.rbxmx');items=root.findall('.//Item');assert root.find('./Item').attrib['class']=='Accessory'
assert props(root.find('./Item'))['Name'].text=='InvestorCase'
assert len(ps)<=20
assert {i.attrib['class'] for i in items}<={'Accessory','Part','Attachment','WeldConstraint'}
refs={i.attrib['referent']:i for i in items};assert len(refs)==len(items)
handle=next(p for p in ps if p['name']=='Handle');hid=handle['item'].attrib['referent']
att=handle['item'].find('./Item[@class="Attachment"]');assert props(att)['Name'].text=='RightGripAttachment'
for p in ps:
 pr=props(p['item']);assert pr['Anchored'].text=='false' and pr['Massless'].text=='true' and pr['CanCollide'].text=='false'
 assert pr['CanTouch'].text=='false' and pr['CanQuery'].text=='false'
 if p is not handle:
  w=p['item'].find('./Item[@class="WeldConstraint"]');assert props(w)['Part0'].text==hid and props(w)['Part1'].text==p['item'].attrib['referent']
pairs=list(itertools.combinations(ps,2));bad=[[a['name'],b['name']] for a,b in pairs if overlaps(a,b)];assert not bad,bad
uv=json.loads((ROOT/'UV_MAP.json').read_text());mask=Image.new('L',(585,559));dr=ImageDraw.Draw(mask)
for region in ['torso','right','left']:
 for x,y,w,h in uv[region].values():dr.rectangle((x,y,x+w-1,y+h-1),fill=255)
clothes={}
for typ in ['shirt','pants']:
 f=ROOT/f'investor_{typ}.png';im=Image.open(f);assert im.size==(585,559) and im.mode=='RGBA';a=im.getchannel('A');assert a.tobytes()==mask.tobytes()
 clothes[typ]={'size':[585,559],'all18UVFacesOpaque':True,'outsideUVTransparent':True,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()}
assert Image.open(ROOT/'investor_preview.png').size==(512,512)
assert (ROOT/'InvestorCase.rbxm').read_bytes().startswith(b'<roblox!')
report={'status':'PASS','studioTested':False,'clothing':clothes,'accessory':{'name':'InvestorCase','parts':len(ps),'budget':20,'standardAttachment':'RightGripAttachment','attachmentLocalPosition':cf(props(att)['CFrame'])[0],'anchored':False,'massless':True,'collisions':False,'welds':len(ps)-1,'intersectionPairs':len(pairs),'positiveVolumeIntersections':bad,'bounds':bounds(ps)},'preview':'512x512 depth-render of actual UV panels and same accessory geometry on canonical block rig; not Studio'}
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
