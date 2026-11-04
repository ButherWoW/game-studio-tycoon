from build_objects import *
from render_geometry import preview
import subprocess,sys,itertools
# Workspace output name and repository asset name are both supported.
park_sources=[ROOT.parent/'astra-park'/'source',ROOT.parent/'roblox-park-kit'/'source']
park_source=next((p for p in park_sources if (p/'build_park.py').exists()),None)
assert park_source is not None,'Expected sibling astra-park/source/build_park.py (existing Park kit)'
sys.path.insert(0,str(park_source))
# Existing Park source only supplies landscape, unchanged.
import build_park as park
from PIL import Image,ImageDraw

def bounds(m):
 ps=flatten(m);lo=[1e9]*3;hi=[-1e9]*3
 for p in ps:
  h=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  for i in range(3):lo[i]=min(lo[i],p['p'][i]-h[i]);hi[i]=max(hi[i],p['p'][i]+h[i])
 return lo,hi
placements=[]
for i in range(6):
 a=30+i*60;x,z=park.polar(28,a);placements.append({'asset':'ParkBench','name':f'Bench{i+1}','pos':[x,0,z],'yaw':90-a})
placements.extend([{'asset':'JobBoard','name':'JobBoard','pos':[0,0,12],'yaw':180},{'asset':'Pawnshop','name':'Pawnshop','pos':[0,0,-12],'yaw':0},{'asset':'Fountain','name':'Fountain','pos':[*park.polar(45,15)[:1],0,park.polar(45,15)[1]],'yaw':0}])
currentConfig=copy.deepcopy(placements)
for pl in placements:
 if pl['asset']=='JobBoard':pl['pos']=[0,0,17]
 if pl['asset']=='Pawnshop':
  x,z=park.polar(44,258);pl['pos']=[x,0,z];pl['yaw']=12
# 2D OBB SAT, true rotated native box extents; cylinder/ball conservatively bounded.
def axes(p):return [(p['r'][0],p['r'][6]),(p['r'][2],p['r'][8])]
def overlap(a,b,footprint=False):
 if not footprint and abs(a['p'][1]-b['p'][1])>=(a['s'][1]+b['s'][1])/2-.01:return False
 # Exact projected native bounding boxes for arbitrary orientation.
 for axis in [(1,0),(0,1)]+axes(a)+axes(b):
  L=math.hypot(*axis)
  if L<1e-6:continue
  v=(axis[0]/L,axis[1]/L)
  def rad(p):return sum(abs(v[0]*p['r'][j]+v[1]*p['r'][6+j])*p['s'][j]/2 for j in range(3))
  d=abs((a['p'][0]-b['p'][0])*v[0]+(a['p'][2]-b['p'][2])*v[1])
  if d>=rad(a)+rad(b)-.01:return False
 return True
report={'studioTested':False,'components':{},'collisions':[],'pathFootprints':[],'placements':placements,'checks':[]}
for n,m in ASSETS.items():
 lo,hi=bounds(m);dims=[round(hi[i]-lo[i],5) for i in range(3)]
 assert abs(lo[1])<1e-6,(n,lo)
 assert abs(lo[0]+hi[0])<.001 and abs(lo[2]+hi[2])<.001,(n,'pivot footprint center',lo,hi)
 assert len(flatten(m))<=250
 maxx,maxz={'ParkBench':(6,3),'JobBoard':(7,1),'Pawnshop':(10,8),'Fountain':(12,12)}[n]
 assert dims[0]<=maxx and dims[2]<=maxz,(n,dims)
 report['components'][n]={'parts':len(flatten(m)),'dimensionsXYZ':dims,'pointLights':sum(bool(p.get('light')) for p in flatten(m))}
 export(m,ROOT/'models'/f'{n}.rbxmx')
 doc=ET.parse(ROOT/'models'/f'{n}.rbxmx');byref={i.attrib['referent']:i for i in doc.iter('Item')}
 root=next(i for i in doc.iter('Item') if i.attrib['class']=='Model');pr=root.find('Properties');primary=byref[pr.find('Ref[@name="PrimaryPart"]').text].find('Properties')
 def cf(e):return tuple(float(e.find(k).text) for k in 'XYZ'),tuple(float(e.find(f'R{i}{j}').text) for i in range(3) for j in range(3))
 p,r=cf(primary.find('CoordinateFrame[@name="CFrame"]'));op,orr=cf(primary.find('CoordinateFrame[@name="PivotOffset"]'))
 assert max(abs(v) for v in add(p,mv(r,op)))<1e-5
 assert max(abs(x-y) for x,y in zip(mul(r,orr),I))<1e-6
 assert all(i.attrib['class'] in ('Model','Part','Seat','PointLight') for i in doc.iter('Item'))
 if n=='ParkBench':
  seat=next(i for i in doc.iter('Item') if i.attrib['class']=='Seat');sp=seat.find('Properties')
  assert sp.find('string[@name="Name"]').text=='PcSeat'
  assert base64.b64decode(sp.find('BinaryString[@name="AttributesSerialize"]').text)==struct.pack('<II',1,6)+b'Public'+bytes([3,1])
 preview(flatten(m),ROOT/'previews'/f'{n}.png',yaw=25,elev=25,span=max(dims[0],dims[2])*1.6,target=(0,dims[1]*.46,0),W=1200,H=1100)
scene=copy.deepcopy(park.PARK);scene['name']='ParkObjectsLayout'
world=[]
for pl in placements:
 placed=put(scene,ASSETS[pl['asset']],tuple(pl['pos']),pl['yaw'],pl['name']);parts=flatten(placed);world.append((pl,parts))
 # Every placed object remains outside spawn plaza16x16.
 for p in parts:
  if p['p'][1]+max(p['s'])/2<.13:continue
  h=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  assert not(abs(p['p'][0])<8+h[0] and abs(p['p'][2])<8+h[2]),('plaza',pl['name'],p['name'])
 for child in park.PARK['children']:
  hits=[(a['name'],b['name']) for a in parts for b in flatten(child) if overlap(a,b)]
  if hits:report['collisions'].append({'object':pl['name'],'landscape':child['name'],'pairs':hits})
# Test actual rotated Part XZ footprints against actual Park path rectangles.
report['actualPathIntersections']=[]
for pl,parts in world:
 hits=[]
 for a in parts:
  for b in park.PARK['parts']:
   if 'segment' not in b['name'] and 'roundJoin' not in b['name']:continue
   aa=copy.deepcopy(a);bb=copy.deepcopy(b)
   aa['p']=(aa['p'][0],0,aa['p'][2]);bb['p']=(bb['p'][0],0,bb['p'][2])
   
   # Preserve original projected extents; the SAT footprint check ignores vertical separation.
   if overlap(aa,bb,True):hits.append([a['name'],b['name']])
 if hits:report['actualPathIntersections'].append({'object':pl['name'],'partPairs':hits,'action':'Config-specified placement overlaps landscape path. Dev2 should adjust routing or interactive placement; no gameplay edits in asset kit.'})

assert not report['collisions'],report['collisions']
assert not report['actualPathIntersections'],report['actualPathIntersections']
for (ap,aa),(bp,bb) in itertools.combinations(world,2):assert not any(overlap(a,b) for a in aa for b in bb),(ap['name'],bp['name'])
# Preserve the incompatible current-config placement as an integration finding only.
currentFindings=[]
pathParts=[p for p in park.PARK['parts'] if 'segment' in p['name'] or 'roundJoin' in p['name']]
for pl in currentConfig:
 if pl['asset'] not in ('JobBoard','Pawnshop'):continue
 t=model('current');placed=put(t,ASSETS[pl['asset']],pl['pos'],pl['yaw']);ps=flatten(placed)
 hits=[[a['name'],b['name']] for a in ps for b in pathParts if overlap(a,b,True)]
 currentFindings.append({'object':pl['name'],'position':pl['pos'],'yaw':pl['yaw'],'pathPartPairs':hits,'status':'INTEGRATION_CHANGE_REQUIRED'})
# Verify reserved front approaches against real landscape and all other installed interactive Parts.
apronChecks=[]
land=[p for child in park.PARK['children'] for p in flatten(child)]
for pl,ps in world:
 if pl['asset']=='Fountain':continue
 if pl['asset']=='ParkBench':off=-2.95;width=5.45;depth=3
 elif pl['asset']=='JobBoard':off=3.45;width=6;depth=6
 else:off=6.85;width=6;depth=6
 ap=model('apron');box(ap,'ClearAccess',(0,2.5,off),(width,5,depth))
 t=model('x');put(t,ap,pl['pos'],pl['yaw']);a=flatten(t)[0]
 for b in land:assert not overlap(a,b),('apron-landscape',pl['name'],b['name'])
 for other,parts in world:
  if other is pl:continue
  for b in parts:assert not overlap(a,b),('apron-object',pl['name'],other['name'],b['name'])
 hh=[sum(abs(a['r'][i*3+j])*a['s'][j]/2 for j in range(3)) for i in range(3)]
 assert not(abs(a['p'][0])<8+hh[0] and abs(a['p'][2])<8+hh[2]),('apron-plaza',pl['name'])
 apronChecks.append({'object':pl['name'],'clearWidth':width,'clearDepth':depth,'status':'PASS'})
report['currentConfig']={'status':'INTEGRATION_CHANGE_REQUIRED','findings':currentFindings}
report['approvedProposedLayout']={'status':'PASS','placements':placements,'landscapeIntersections':0,'pathIntersections':0,'objectIntersections':0,'aprons':apronChecks,'spawnPlaza16x16':'CLEAR'}
report['checks']=['native class allowlist','part budgets and exact footprint limits','Y0 ground and centered base pivot','PrimaryPart+PivotOffset reconstruction','PcSeat identity and Public=true serialized attribute','seated direction -Z, laptop display +Z','current bench transforms and revised board/pawn proposed placement','all Parts checked against existing Park child geometry using conservative OBB SAT','no overlaps between interactive objects','central16x16 unobstructed','one shadowless light per Pawnshop lamp','all proposed footprints clear of actual path segments/joins','6stud board/pawn approaches and3stud bench approaches clear of props and spawn plaza']
report['notes']=['Fountain placement is proposed at X43.467,Y0,Z11.647; no current WorldService Fountain builder placement exists. Keep separate and do not place on spawn plaza.','Offline OBB comparisons conservatively bound spheres/cylinders; no geometric intersections found. Studio avatar/access/raycast validation still needed.','ModelFactory must clone these templates; do not run fallback builder on top. Preserve Seat Public=true, JobBoard.Board, Pawnshop.Counter.']
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2));(ROOT/'layout.json').write_text(json.dumps({'coordinateFrame':'relative to spawn XZ, Y0','placements':placements,'approvedProposedLayout':report['approvedProposedLayout'],'currentConfig':report['currentConfig'],'fountainStatus':'proposed separate placement; gameplay integration required'},indent=2))
export(scene,ROOT/'Park_Objects_Layout.rbxmx')
rojo='/Users/erland/.local/gst-tools/rojo'
for f in list((ROOT/'models').glob('*.rbxmx'))+[ROOT/'Park_Objects_Layout.rbxmx']:
 project=ROOT/'source'/'convert.project.json';project.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(f)}}));r=subprocess.run([rojo,'build',str(project),'-o',str(f.with_suffix('.rbxm'))],capture_output=True,text=True);assert r.returncode==0,r.stderr
project.unlink()
preview(flatten(scene),ROOT/'previews'/'Park_Objects_Overview.png',yaw=28,elev=43,span=175,target=(0,2,0),W=1800,H=1400)
print(json.dumps(report['components'],indent=2));print('collision count',len(report['collisions']),'path proximity',len(report['pathFootprints']))
# Labelled plan makes integration conflicts and the separate fountain placement reviewable.
W=1400;scale=8.6;im=Image.new('RGB',(W,W),'#F3F0E9');d=ImageDraw.Draw(im)
pt=lambda x,z:(W/2+x*scale,W/2+z*scale)
d.ellipse((98,98,1302,1302),fill='#A4CE8E')
for a,b,w in park.PATHS:d.line([pt(*a),pt(*b)],fill='#D9C9A3',width=round(2*w*scale))
for o in park.OBSTACLES:
 x,y=pt(o['x'],o['z']);r=o['radius']*scale;d.ellipse((x-r,y-r,x+r,y+r),fill='#628C59')
d.rectangle((*pt(-8,-8),*pt(8,8)),fill='#DED6C5',outline='white',width=3)
for pl,ps in world:
 lo,hi=bounds({'name':'world','parts':ps,'children':[],'pos':(0,0,0),'r':I})
 x,y=pt(pl['pos'][0],pl['pos'][2]);color='#C16A48' if pl['asset'] in ('JobBoard','Pawnshop') else '#3D7BFF'
 d.rectangle((*pt(lo[0],lo[2]),*pt(hi[0],hi[2])),outline=color,width=4)
 d.text((x+10,y-12),pl['name'],fill='#182D37',stroke_width=0)
d.text((35,30),'PARK OBJECTS / PROPOSED CLEAR LAYOUT',fill='#283345')
d.text((35,1335),'PASS: all proposed object footprints clear paths and props. Board/pawn positions require Dev2 config changes.',fill='#283345')
d.text((35,1360),'Footprint boxes are world AABBs for review; collision checks use rotated Parts. Center plaza stays open.',fill='#283345')
im.save(ROOT/'previews'/'Park_Objects_Plan.png')
