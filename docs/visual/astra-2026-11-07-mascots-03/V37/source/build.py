from geometry import *
from render_geometry import preview
from convex_support import parse,audit,support,np
import subprocess,json
ROOT=Path(__file__).resolve().parents[1]
for f in ['models','previews','references']:(ROOT/f).mkdir(exist_ok=True)
def disk(m,n,x,y,z,w,h,depth,c):
 return part(m,n,(x,y,z),(depth,h,w),c,shape='cyl',r=rot(y=90))
def face(m,y,z,spread=.40):
 for sign in [-1,1]:
  x=sign*spread
  disk(m,'EyeWhite',x,y,z+.035,.60,.70,.07,'FFF9EC')
  disk(m,'EyePupil',x,y,z+.09,.39,.53,.04,'14223E')
  disk(m,'BlueIris',x,y-.14,z+.125,.28,.20,.03,'2499DC')
  disk(m,'EyeGleam',x-.055,y+.17,z+.125,.13,.15,.03,'FFFFFF')
  box(m,'Brow',(x,y+.46,z+.025),(.31,.08,.05),'273047')
def mouth(m,y,z,color):
 # A flat upper lip and three decreasing rows make a smiling silhouette,
 # without an overlapping mask or a protruding rectangular face patch.
 for dy,w in [(.07,.43),(0,.35),(-.07,.20)]:
  box(m,'SmileRow',(0,y+dy,z+.02),(w,.07,.04),'542338')
 disk(m,'Tongue',0,y-.04,z+.055,.19,.07,.03,'F47889')
def attached_lobe(m,name,base,n,size,color):
 # Exact support-plane tangency between two ellipsoids.
 n=np.array(n,float);a=np.array(base['s'])/2;b=np.array(size)/2
 pos=np.array(base['p'])+a*a*n/np.linalg.norm(a*n)+b*b*n/np.linalg.norm(b*n)
 return ball(m,name,tuple(pos),size,color)
def ghost():
 m=model('Mascot_cloud_ghost')
 # Disjoint horizontal elliptical strips form a connected cloud silhouette.
 # This avoids detached sphere lobes while keeping the no-overlap requirement.
 H=.042;strips=[]
 for j in range(75):
  y=(j+.5)*H
  intervals=[]
  for cx,cy,rx,ry in [(0,1.43,.95,1.10),(0,2.64,.48,.51),(-.60,2.31,.49,.49),(.60,2.31,.49,.49)]:
   q=(y-cy)/ry
   if abs(q)<1:
    w=rx*math.sqrt(1-q*q);intervals.append((cx-w,cx+w))
  if y<.60:
   # Curl sweeps to the left near the base, then widens into the body.
   center=-.35*(1-y/.60);half=.13+.50*(y/.60)
   intervals.append((center-half,center+half))
  if not intervals:continue
  lo=min(q[0]for q in intervals);hi=max(q[1]for q in intervals)
  depth=.80 if y<.60 else 1.0
  d=part(m,'CloudStrip',((lo+hi)/2,y,0),(H,hi-lo,depth),'F5EEDD',shape='cyl',r=rot(z=90))
 # Body identifies an actual central strip, never a separate invisible helper.
 body=m['parts'].pop(33);body['name']='Body';m['parts'].insert(0,body)
 for sign in [-1,1]:
  ball(m,'SoftArm',(sign*1.23,1.40,0),(.55,.22,.40),'F5EEDD')
 disk(m,'FacePlaque',0,1.50,.54,1.50,1.35,.08,'F5EEDD')
 face(m,1.85,.58,.40)
 mouth(m,1.26,.58,'F5EEDD')
 for sign in [-1,1]:disk(m,'BlueCheek',sign*.64,1.38,.60,.22,.13,.04,'4CCCF2')
 return m
def bunny():
 m=model('Mascot_controller_bunny')
 ball(m,'Body',(0,.90,0),(1.15,1.10,.70),'8B3BC3')
 for sign in [-1,1]:
  n=np.array([sign*.4,-1,0]);u=n/np.linalg.norm(n)
  h=np.array([1.15,1.10,.70])/2
  start=np.array([0,.90,0])+h*h*n/np.linalg.norm(h*n)
  end=start+u*.15;fh=np.array([.25,.15,.325])
  center=end+fh*fh*n/np.linalg.norm(fh*n)
  line(m,'ShortLeg',tuple(start),tuple(end),.10,'8B3BC3')
  ball(m,'CyanFoot',tuple(center),(.50,.30,.65),'20D3DF')
  box(m,'ToeShine',(center[0],center[1],.34),(.22,.10,.03),'8EEEF0')
 head=ball(m,'PurpleHead',(0,2.05,0),(1.70,1.20,1.0),'AB4AD9')
 disk(m,'IvoryMuzzle',0,1.90,.54,1.50,.80,.08,'F4E8D2')
 face(m,2.15,.58,.43)
 disk(m,'Nose',0,1.98,.65,.18,.09,.05,'422645')
 mouth(m,1.73,.58,'F4E8D2')
 disk(m,'IvoryBelly',0,.93,.37,.55,.67,.04,'F4E8D2')
 for sign in [-1,1]:
  line(m,'Arm',(sign*.575,.90,0),(sign*.90,.90,0),.14,'8B3BC3')
  ball(m,'CyanMitten',(sign*1.09,.90,0),(.38,.38,.38),'20D3DF')
  ball(m,'Thumb',(sign*1.09,.90,.25),(.12,.12,.12),'20D3DF')
  # Tilted joystick ears, with cap planes outside the head's support plane.
  n=np.array([sign*.25,1,0]);u=n/np.linalg.norm(n);h=np.array(head['s'])/2
  start=np.array(head['p'])+h*h*u/np.linalg.norm(h*u);end=start+u*.65
  line(m,'BlueJoystick',tuple(start),tuple(end),.16,'278BD9')
  v=np.array([u[1],-u[0],0])
  for side in [-1,1]:
   line(m,'PurpleEarFrame',tuple(start+v*side*.20),tuple(end+v*side*.20),.12,'8B3BC3')
  tip=end+u*.22;ball(m,'JoystickBall',tuple(tip),(.44,.44,.44),'17E2E6')
  disk(m,'JoystickGleam',tip[0],tip[1]+.04,.235,.12,.14,.03,'A2FFFF')
 ball(m,'Tail',(0,.85,-.52),(.35,.35,.34),'F4E8D2')
 return m
rows=[]
for id,m in [('cloud_ghost',ghost()),('controller_bunny',bunny())]:
 # Exact footprint support bounds. Body remains first / PrimaryPart.
 temp=ROOT/'models'/'temp.rbxmx';export(m,temp);ps=parse(temp);lo=[min(support(p,-np.eye(3)[i])[i]for p in ps)for i in range(3)];hi=[max(support(p,np.eye(3)[i])[i]for p in ps)for i in range(3)]
 shift=[(lo[0]+hi[0])/2,lo[1],(lo[2]+hi[2])/2]
 for p in m['parts']:p['p']=tuple(p['p'][i]-shift[i]for i in range(3))
 path=ROOT/'models'/('Mascot_'+id+'.rbxmx');export(m,path);temp.unlink()
 ps=parse(path);cert,bad=audit(ps);assert not bad,(id,bad);assert len(ps)<=100
 project=ROOT/'source/build.project.json';project.write_text(json.dumps({'name':m['name'],'tree':{'$path':str(path)}}));subprocess.run(['/Users/erland/.local/gst-tools/rojo','build',str(project),'-o',str(path.with_suffix('.rbxm'))],check=True,capture_output=True);project.unlink()
 (ROOT/(id+'_CERTIFICATES.json')).write_text(json.dumps(cert,indent=2)+'\n')
 rows.append({'id':id,'parts':len(ps),'dimensionsXYZ':[hi[i]-lo[i]for i in range(3)],'pairs':len(cert),'overlaps':bad,'PrimaryPart':'Body','pivotXYZ':[0,0,0],'allAnchored':True,'runtimeTested':False})
 for label,yaw in [('Front',0),('ThreeQuarter',35),('Rear',150)]:
  preview(m['parts'],ROOT/'previews'/('Mascot_'+id+'_'+label+'.png'),yaw=yaw,elev=15,target=(0,1.80,0),span=5.2,W=900,H=900)
(ROOT/'VALIDATION.json').write_text(json.dumps(rows,indent=2)+'\n');print(json.dumps(rows,indent=2))
