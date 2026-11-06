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
def triangle(m,name,points,z,depth,color):
 # Split any planar triangle along its altitude into native right-triangle prisms.
 vs=[np.array([x,y,z],float)for x,y in points]
 i,j=max([(0,1),(1,2),(2,0)],key=lambda ij:np.linalg.norm(vs[ij[0]]-vs[ij[1]]))
 k=3-i-j;A,B,C=vs[i],vs[j],vs[k];d=B-A;D=A+d*np.dot(C-A,d)/np.dot(d,d)
 height=np.linalg.norm(C-D)
 if height<1e-9:return
 yy=(C-D)/height
 for P in [A,B]:
  length=np.linalg.norm(D-P)
  if length<1e-9:continue
  zz=(D-P)/length;xx=np.cross(yy,zz);rr=tuple(np.column_stack([xx,yy,zz]).reshape(-1))
  center=D+yy*height/2-zz*length/2
  part(m,name,tuple(center),(depth,height,length),color,shape='wedge',r=rr,cls='WedgePart')
def polygon(m,name,verts,z,depth,colors):
 c=np.mean(np.array(verts),axis=0)
 for i in range(len(verts)):triangle(m,name,[tuple(c),verts[i],verts[(i+1)%len(verts)]],z,depth,colors[i%len(colors)])
def star(m,x,y,z,r):
 vs=[]
 for i in range(10):
  a=math.radians(90+i*36);rr=r if i%2==0 else r*.46
  vs.append((x+rr*math.cos(a),y+rr*math.sin(a)))
 polygon(m,'GoldStar',vs,z,.08,['F5C64D','FFDF77'])
def owl():
 m=model('Mascot_robo_owl')
 body=ball(m,'Body',(0,.95,0),(1.30,1.15,.90),'246DD1')
 head=ball(m,'Head',(0,2.25,0),(1.95,1.45,1.10),'286CBE')
 # Feet and short posts tangent to Body, with all origins grounded later.
 for sign in [-1,1]:
  n=np.array([sign*.4,-1,0]);u=n/np.linalg.norm(n);h=np.array(body['s'])/2
  start=np.array(body['p'])+h*h*n/np.linalg.norm(h*n);end=start+u*.14;fh=np.array([.24,.13,.28])
  center=end+fh*fh*n/np.linalg.norm(fh*n)
  line(m,'Leg',tuple(start),tuple(end),.12,'7186AF');ball(m,'GoldFoot',tuple(center),(.48,.26,.56),'F3BC35')
  for dx in [-.10,.10]:box(m,'ToeLine',(center[0]+dx,center[1],.295),(.025,.12,.03),'A37322')
 for sign in [-1,1]:
  x=sign*.49
  disk(m,'SilverEyeRing',x,2.25,.60,.90,.98,.10,'BDC8DB')
  disk(m,'CyanEye',x,2.25,.68,.70,.78,.06,'1DDBE5')
  disk(m,'Pupil',x,2.25,.735,.47,.59,.05,'10213E')
  disk(m,'Gleam',x-.06,2.42,.775,.14,.16,.03,'FFFFFF')
  disk(m,'SmallGleam',x+.08,2.08,.775,.07,.07,.03,'FFFFFF')
  box(m,'BezelShine',(x,2.69,.665),(.22,.04,.03),'F4F8FA')
 # Two triangles create a gold/orange diamond beak.
 triangle(m,'UpperBeak',[(-.22,2.05),(.22,2.05),(0,2.24)],.82,.10,'F9CD48')
 triangle(m,'LowerBeak',[(-.22,2.05),(.22,2.05),(0,1.70)],.82,.10,'D99524')
 for sign in [-1,1]:
  n=np.array([sign*.65,1,0]);u=n/np.linalg.norm(n);h=np.array(head['s'])/2
  base=np.array(head['p'])+h*h*n/np.linalg.norm(h*n);v=np.array([u[1],-u[0],0])
  points=[tuple((base+v*.22)[:2]),tuple((base-v*.22)[:2]),tuple((base+u*.55)[:2])]
  triangle(m,'EarArmor',points,0,.30,'2178DA')
  center=np.mean(np.array(points),axis=0);inner=[tuple(center+(np.array(p)-center)*.55)for p in points]
  triangle(m,'EarGlow',inner,.175,.05,'28C9EA')
  wing=[(.65,.95),(1.50,1.68),(1.35,.65)]
  triangle(m,'WingArmor',[(sign*x,y)for x,y in wing],0,.40,'277EDD')
  triangle(m,'SilverFeather',[(sign*x,y)for x,y in [(.70,.90),(1.40,1.15),(1.16,.30)]],.27,.10,'B5C5DD')
  triangle(m,'BlueFeather',[(sign*x,y)for x,y in [(.73,.72),(1.23,.70),(1.02,.10)]],.40,.14,'254A8B')
  center=np.mean(np.array(wing),axis=0)
  inner=[tuple(center+(np.array(p)-center)*.45)for p in wing]
  triangle(m,'WingGlow',[(sign*x,y)for x,y in inner],.37,.04,'2AD6E4')
 disk(m,'ChestArmor',0,.95,.50,.72,.62,.10,'B5C5DD')
 triangle(m,'ChestGem',[(-.23,1.07),(.23,1.07),(0,.77)],.575,.05,'3CE4E5')
 box(m,'ForeheadPlate',(0,2.92,.575),(.25,.25,.05),'38DCE7',r=rot(z=45))
 return m
def slime():
 m=model('Mascot_slime_star')
 body=ball(m,'Body',(0,1.20,0),(2.0,2.10,1.40),'6CE3B4')
 for n in [(-.5,-1,0),(.5,-1,0)]:
  attached_lobe(m,'BasePuddle',body,n,(.60,.28,.65),'65DBAC')
 for n in [(-1,.30,0),(1,.05,0)]:
  attached_lobe(m,'SoftArm',body,n,(.50,.30,.50),'6CE3B4')
 curl=attached_lobe(m,'CurlStem',body,(.2,1,0),(.45,.62,.40),'7AEABD')
 attached_lobe(m,'CurlTip',curl,(1,.35,0),(.45,.34,.35),'8CEBC6')
 ball(m,'FloatingBubble',(1.05,2.80,0),(.20,.16,.20),'8CEBC6')
 face(m,1.65,.70,.43)
 # Slime's reference has no separate brows.
 m['parts']=[p for p in m['parts'] if p['name']!='Brow']
 mouth(m,1.20,.70,'6CE3B4')
 for sign in [-1,1]:
  n=np.array([sign*.9,0,1]);n=n/np.linalg.norm(n);h=np.array(body['s'])/2
  point=np.array(body['p'])+h*h*n/np.linalg.norm(h*n)
  yy=np.array([0,1,0]);zz=np.cross(n,yy);rr=tuple(np.column_stack([n,yy,zz]).reshape(-1))
  part(m,'PinkCheek',tuple(point+n*.02),(.04,.13,.24),'F38C9F',shape='cyl',r=rr)
 star(m,0,2.28,.88,.31)
 verts=[(-.68,.70),(-.43,1.035),(.43,1.035),(.68,.70),(.43,.365),(-.43,.365)]
 polygon(m,'BellyCrystal',verts,.78,.15,['20D9DF','55F1E9','21D0E4'])
 return m
rows=[]
for id,m in [('robo_owl',owl()),('slime_star',slime())]:
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
