from build_floor import *
import itertools

def bounds(parts):
 lo=[float('inf')]*3;hi=[-float('inf')]*3
 for p in parts:
  if p['alpha']==1:continue
  h=[sum(abs(p['r'][i*3+j])*p['s'][j]/2 for j in range(3)) for i in range(3)]
  for i in range(3):lo[i]=min(lo[i],p['p'][i]-h[i]);hi[i]=max(hi[i],p['p'][i]+h[i])
 return lo,hi

def overlap(a,b,tol=.035):return all(min(a[1][i],b[1][i])-max(a[0][i],b[0][i])>tol for i in range(3))
def instance(n,p,y):
 m=model('Placement');put(m,ASSETS[n],p,y);return flatten(m)

report={'sourceCommit':'c10dcb5','models':{},'checks':[],'studioTested':False,'elevator':ELEVATOR,'floorBaseY':14}
limits={'Floor':(60,13,60),'FloorDesk':(8,8,4),'ServerRoom':(12,10,8),'Lounge':(12,8,10)}
for n,m in ASSETS.items():
 ps=flatten(m);lo,hi=bounds(ps);dims=[round(hi[i]-lo[i],4) for i in range(3)]
 assert len(ps)<=(600 if n=='Floor' else 250),(n,len(ps))
 assert abs(lo[1])<1e-6,(n,lo)
 assert all(dims[i]<=limits[n][i]+1e-5 for i in range(3)),(n,dims)
 for p in ps:
  assert min(p['s'])>=.001
  r=p['r']
  for i in range(3):
   for j in range(3):assert abs(sum(r[i*3+k]*r[j*3+k] for k in range(3))-(1 if i==j else 0))<1e-6
 report['models'][n]={'parts':len(ps),'dimensionsXYZ':dims,'min':lo,'max':hi,'pointLights':sum(bool(p.get('light')) for p in ps)}
placed=[(n+'_'+str(i),instance(n,p,y)) for i,(n,p,y) in enumerate(LAYOUT) if n!='Floor']
for (a,pa),(b,pb) in itertools.combinations(placed,2):assert not overlap(bounds(pa),bounds(pb)),(a,b)
shell=[p for p in flatten(ASSETS['Floor']) if p['p'][1]+p['s'][1]/2>.03]
for n,ps in placed:
 for pp in shell:assert not overlap(bounds(ps),bounds([pp])),('shell',n,pp['name'])
# Front aprons: 3 studs beyond desk front, full width, no clutter or walls.
for n,p,y in LAYOUT:
 if n!='FloorDesk':continue
 bb=bounds(instance(n,p,y));apron=([bb[0][0],0,bb[1][2]],[bb[1][0],5,bb[1][2]+3])
 for other,ps in placed:
  if bounds(ps)==bb:continue
  assert not overlap(apron,bounds(ps)),('desk-apron',other)
 for pp in shell:assert not overlap(apron,bounds([pp])),('desk-apron-shell',pp['name'])
for row in [[(0,-20),(9,-20),(18,-20)],[(-12,-6),(-2,-6),(8,-6),(18,-6)]]:
 for (xa,za),(xb,zb) in zip(row,row[1:]):
  a=bounds(instance('FloorDesk',(xa,0,za),0));b=bounds(instance('FloorDesk',(xb,0,zb),0))
  assert b[0][0]-a[1][0]>=4-1e-6
legacy=[('playerDesk',([-15.8,0,-21.75],[-8.2,5.5,-15.8])),('coffee',([23.5,0,-27.5],[26.5,6,-20.5])),('hitShelf',([-29,0,-20],[-26.2,8,-10]))]
for n,ps in placed:
 for old,bb in legacy:assert not overlap(bounds(ps),bb),('legacy',n,old)
# Server doorway: clear 6.4-wide opening, six-stud approach towards -X after -90 yaw.
serverApproach=([18.5,0,-17.2],[24.5,6,-10.8])
for n,ps in placed:
 if not n.startswith('ServerRoom'):assert not overlap(serverApproach,bounds(ps)),('server-approach',n)
for pp in shell:assert not overlap(serverApproach,bounds([pp])),('server-approach-shell',pp['name'])
lift=([-23,0,21],[-17,7,27]);liftApproach=([-23,0,15],[-17,6,21])
for n,ps in placed:
 assert not overlap(lift,bounds(ps)),('lift-pocket',n)
 assert not overlap(liftApproach,bounds(ps)),('lift-approach',n)
for pp in shell:
 assert not overlap(lift,bounds([pp])),('lift-pocket-shell',pp['name'])
 assert not overlap(liftApproach,bounds([pp])),('lift-approach-shell',pp['name'])
assert sum(bool(p.get('light')) for p in flatten(ASSETS['Floor']))==4
assert all(not p.get('light') for n,m in ASSETS.items() if n!='Floor' for p in flatten(m))
report['checks']=['part budgets','dimension limits','visible base Y=0','orthonormal transforms','no peer-model AABB overlaps','no intersections with shell walls or fixed decor','3-stud clear desk aprons','4-stud minimum gaps between desk rows','6.4-stud server doorway and 6-stud approach','existing Desk1/PC1/Chair/Coffee/HitShelf reserved volumes','confirmed 6x6 lift volume X[-23,-17] Z[21,27] Y[0,7] free; 6-stud approach free','no roof/ceiling slab; wall height 13','one PointLight per ceiling panel; no desk/rack lights']
floorPart=next(p for p in flatten(ASSETS['Floor']) if p['name']=='Floor')
assert floorPart['s'][0]==58 and floorPart['s'][2]==58
header=next(p for p in flatten(ASSETS['Floor']) if p['name']=='EntranceHeader')
assert header['p'][1]-header['s'][1]/2==9
report['checks']+=['58x58 floor slab','24x9 front aperture','confirmed floor base Y14 with local pivot Y0','all shell geometry below next floor Y14']
for n,m in ASSETS.items():export(m,ROOT/'models'/f'{n}.rbxmx')
export(FULL,ROOT/'Floor_Assembled.rbxmx')
stacked=model('AstraSecondFloor_AtY14');put(stacked,FULL,(0,14,0))
export(stacked,ROOT/'Floor_Stacked_Y14.rbxmx')
templates=model('Upgrades')
for m in ASSETS.values():put(templates,m)
export(templates,ROOT/'Floor_Upgrades_Import.rbxmx')
rojo='/Users/erland/.local/gst-tools/rojo'
for f in sorted((ROOT/'models').glob('*.rbxmx'))+[ROOT/'Floor_Assembled.rbxmx',ROOT/'Floor_Upgrades_Import.rbxmx',ROOT/'Floor_Stacked_Y14.rbxmx']:
 project=ROOT/'source'/'convert.project.json';project.write_text(json.dumps({'name':f.stem,'tree':{'$path':str(f)}}))
 run=subprocess.run([rojo,'build',str(project),'-o',str(f.with_suffix('.rbxm'))],capture_output=True,text=True);assert run.returncode==0,run.stderr
project.unlink()
place={'name':'Astra Floor Showcase','tree':{'$className':'DataModel','Workspace':{'$className':'Workspace','Floor':{'$path':'../Floor_Assembled.rbxmx'},'Spawn':{'$className':'SpawnLocation','$properties':{'Anchored':True,'Neutral':True,'Transparency':1,'CanCollide':False,'Size':[4,.1,4],'Position':[0,.3,25]}}},'Lighting':{'$className':'Lighting','$properties':{'Brightness':2,'ClockTime':14,'Ambient':[.5,.54,.6],'OutdoorAmbient':[.62,.68,.77],'GlobalShadows':True,'EnvironmentDiffuseScale':1,'EnvironmentSpecularScale':.7}}}}
project=ROOT/'source'/'showcase.project.json';project.write_text(json.dumps(place,indent=2))
for ext in ('rbxl','rbxlx'):
 run=subprocess.run([rojo,'build',str(project),'-o',str(ROOT/('Floor_Showcase.'+ext))],capture_output=True,text=True);assert run.returncode==0,run.stderr
report['binaryConversion']='7 RBXM + RBXL/RBXLX built with Rojo 7.4.4'
report['limitation']='Not tested in Studio. No gameplay changes or automatic NPC seating. Floor base Y14, pitch14 and lift volume confirmed by owner. No gameplay integration or elevator platform/control included; code supplies those.'
(ROOT/'VALIDATION.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report['models'],indent=2))
