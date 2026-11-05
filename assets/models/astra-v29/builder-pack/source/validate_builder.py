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
root,ps=parse(ROOT/'BuilderNPC.rbxmx');items=root.findall('.//Item');refs={i.attrib['referent']:i for i in items};assert len(refs)==len(items)
model=root.find('./Item');assert props(model)['Name'].text=='BuilderNPC' and props(model)['PrimaryPart'].text=='B_HumanoidRootPart'
body={p['name']:p for p in ps if not p['name'].startswith('FaceMark')};assert len(body)==16 and len(ps)==19
assert root.find('.//Item[@class="Humanoid"]').findtext('Properties/token[@name="RigType"]')=='1'
hum=props(root.find('.//Item[@class="Humanoid"]'));assert hum['HipHeight'].text=='2'
joints=root.findall('.//Item[@class="Motor6D"]');assert len(joints)==15
assert {props(j)['Name'].text for j in joints}=={'Root','Waist','Neck','RightShoulder','LeftShoulder','RightElbow','LeftElbow','RightWrist','LeftWrist','RightHip','LeftHip','RightKnee','LeftKnee','RightAnkle','LeftAnkle'}
edges=[]
for j in joints:
 pr=props(j);a=refs[pr['Part0'].text];b=refs[pr['Part1'].text];ap,ar=cf(props(a)['CFrame']);bp,br=cf(props(b)['CFrame']);c0,r0=cf(pr['C0']);c1,r1=cf(pr['C1']);wa=[ap[i]+mv(ar,c0)[i] for i in range(3)];wb=[bp[i]+mv(br,c1)[i] for i in range(3)];assert max(abs(x-y) for x,y in zip(wa,wb))<1e-5;edges.append((a.attrib['referent'],b.attrib['referent']))
seen={'B_HumanoidRootPart'}
while True:
 new=seen|{b for a,b in edges if a in seen}|{a for a,b in edges if b in seen}
 if new==seen:break
 seen=new
assert len(seen)==16
for p in ps:
 pr=props(p['item']);assert pr['CanCollide'].text==pr['CanTouch'].text==pr['CanQuery'].text=='false';assert pr['Massless'].text=='true';assert pr['Anchored'].text==('true' if p['name']=='HumanoidRootPart' else 'false')
visible=[p for p in ps if p['name']!='HumanoidRootPart'];pairs=list(itertools.combinations(visible,2));bad=[[a['name'],b['name']] for a,b in pairs if overlaps(a,b)];assert not bad,bad
assert bounds(visible)[0][1]==0
hrp=body['HumanoidRootPart'];assert hrp['p']==[0,3,0];assert float(hum['HipHeight'].text)+hrp['s'][1]/2==3
hroot,hps=parse(ROOT/'BuilderHat.rbxmx');assert hroot.find('./Item').attrib['class']=='Accessory';assert props(hroot.find('./Item'))['Name'].text=='BuilderHat';assert len(hps)==3
hhandle=next(p for p in hps if p['name']=='Handle');att=hhandle['item'].find('./Item[@class="Attachment"]');assert props(att)['Name'].text=='HatAttachment';assert cf(props(att)['CFrame'])[0]==[0,-.06,0]
assert not any(overlaps(a,b) for a,b in itertools.combinations(hps,2))
uv=json.loads((ROOT/'UV_MAP.json').read_text());mask=Image.new('L',(585,559));dr=ImageDraw.Draw(mask)
for region in ['torso','right','left']:
 for x,y,w,h in uv[region].values():dr.rectangle((x,y,x+w-1,y+h-1),fill=255)
clothes={}
for typ in ['shirt','pants']:
 f=ROOT/f'builder_{typ}.png';im=Image.open(f);assert im.size==(585,559) and im.mode=='RGBA' and im.getchannel('A').tobytes()==mask.tobytes();clothes[typ]={'size':[585,559],'exact18UVMask':True,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()}
assert Image.open(ROOT/'builder_preview.png').size==(512,512)
for n in ['BuilderHat','BuilderNPC']:assert (ROOT/(n+'.rbxm')).read_bytes().startswith(b'<roblox!')
report={'status':'PASS','studioTested':False,'rig':{'parts':19,'bodyPartsIncludingHRP':16,'motor6D':15,'connectedBodyGraph':True,'jointBindFramesCoincide':True,'rootPivotXYZ':[0,3,0],'footBaseY':0,'HipHeight':2,'StandHeight':3,'visiblePartPairs':len(pairs),'positiveVolumeIntersections':bad,'rootVolumeExcluded':'HumanoidRootPart is an intentionally overlapping invisible animation root'},'hat':{'name':'BuilderHat','parts':3,'attachment':'HatAttachment','noPositiveVolumeIntersections':True},'clothing':clothes,'templateTextureIDsPending':True,'preview':'Actual generated UV panels and same accessory geometry on canonical block rig'}
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
