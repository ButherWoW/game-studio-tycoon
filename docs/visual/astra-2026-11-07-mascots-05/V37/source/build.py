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
def surface_patch(m,name,base,n,size,color):
 n=np.array(n,float);n/=np.linalg.norm(n);h=np.array(base['s'])/2
 point=np.array(base['p'])+h*h*n/np.linalg.norm(h*n)
 ref=np.array([0,1,0]);yy=ref-n*np.dot(ref,n);yy/=np.linalg.norm(yy);zz=np.cross(n,yy)
 part(m,name,tuple(point+n*size[0]/2),size,color,r=tuple(np.column_stack([n,yy,zz]).reshape(-1)))
def feet_on_body(m,body,color):
 for sign in [-1,1]:
  n=np.array([sign*.4,-1,0]);u=n/np.linalg.norm(n);h=np.array(body['s'])/2
  start=np.array(body['p'])+h*h*n/np.linalg.norm(h*n);end=start+u*.14;fh=np.array([.225,.135,.275])
  center=end+fh*fh*n/np.linalg.norm(fh*n)
  line(m,'Leg',tuple(start),tuple(end),.12,color);ball(m,'Foot',tuple(center),(.45,.27,.55),color)
  for dx in [-.10,.10]:box(m,'Toe',(center[0]+dx,center[1],.29),(.07,.10,.03),'F2E2AC')
def whale():
 m=model('Mascot_cosmic_whale')
 body=ball(m,'Body',(0,1.20,0),(2.30,1.80,1.70),'2D3A9A')
 for sign in [-1,1]:
  n=np.array([sign*1,-.6,0]);h=np.array(body['s'])/2
  p=np.array(body['p'])+h*h*n/np.linalg.norm(h*n)
  points=[tuple(p[:2]),(p[0]+sign*.80,p[1]-.50),(p[0]+sign*.45,p[1]+.15)]
  triangle(m,'PurpleFin',points,0,.30,'864BD0')
  c=np.mean(np.array(points),axis=0)
  inner=[tuple(c+(np.array(q)-c)*.55)for q in points]
  triangle(m,'FinFacet',inner,.18,.06,'A65CE5')
 tail=attached_lobe(m,'TailStem',body,(0,.3,-1),(.45,.60,.75),'2D3A9A')
 tip=attached_lobe(m,'TailRise',tail,(0,1,-.2),(.35,.50,.45),'2D3A9A')
 top=tip['p'][1]+tip['s'][1]/2;zz=tip['p'][2]
 for sign in [-1,1]:
  points=[(0,top),(sign*.65,top+.45),(sign*.57,top+.05)]
  triangle(m,'TailFluke',points,zz,.35,'864BD0')
  c=np.mean(np.array(points),axis=0);inner=[tuple(c+(np.array(q)-c)*.55)for q in points]
  triangle(m,'TailFacet',inner,zz+.205,.06,'A65CE5')
 face(m,1.70,.85,.43);mouth(m,1.18,.85,'2D3A9A')
 for sign in [-1,1]:surface_patch(m,'PinkCheek',body,(sign*.8,.3,1),(.04,.12,.22),'EE80AF')
 verts=[(-.85,.80),(-.55,1.04),(.55,1.04),(.85,.80),(.50,.30),(-.50,.30)]
 polygon(m,'CyanBelly',verts,.93,.15,['37D2E6','6AE4EE','1FAACF'])
 star(m,.45,2.17,1.05,.22)
 for n in [(1,0,-.4),(1,.2,-.7),(1,.4,-1)]:
  surface_patch(m,'StarPixel',body,n,(.025,.11,.11),'F5CB52')
 return m
def dragon():
 m=model('Mascot_dragon_byte')
 body=ball(m,'Body',(0,.95,0),(1.10,1.20,.80),'58B93F')
 head=ball(m,'Head',(0,2.175,0),(1.75,1.25,1.10),'78D650')
 feet_on_body(m,body,'58B93F')
 disk(m,'LightMuzzle',0,1.76,.59,1.55,.46,.08,'94E567')
 face(m,2.35,.55,.43);mouth(m,1.75,.63,'94E567')
 for sign in [-1,1]:disk(m,'Nostril',sign*.20,1.95,.66,.07,.045,.03,'367A2C')
 verts=[(-.34,1.40),(.34,1.40),(.38,.70),(0,.45),(-.38,.70)]
 polygon(m,'CyanBelly',verts,.49,.10,['4AD3D8','70E4DA'])
 for sign in [-1,1]:
  n=np.array([sign*.6,1,0]);u=n/np.linalg.norm(n);h=np.array(head['s'])/2
  base=np.array(head['p'])+h*h*n/np.linalg.norm(h*n);v=np.array([u[1],-u[0],0])
  pts=[tuple((base+v*.13)[:2]),tuple((base-v*.13)[:2]),tuple((base+u*.47)[:2])]
  triangle(m,'GoldHorn',pts,0,.25,'F5CC4C')
  wing=[(.55,1.05),(1.50,1.85),(1.70,1.25),(1.25,.85)]
  polygon(m,'BlueWing',[(sign*x,y)for x,y in wing],0,.40,['2168CB','2E89E0'])
  c=np.mean(np.array(wing),axis=0);inner=[tuple(c+(np.array(q)-c)*.60)for q in wing]
  polygon(m,'CyanWing',[(sign*x,y)for x,y in inner],.24,.06,['38C2EF','62D9F4'])
 triangle(m,'GreenCrest',[(-.17,2.80),(.17,2.80),(0,3.25)],-.10,.25,'58B93F')
 tail=attached_lobe(m,'Tail',body,(0,.3,-1),(.35,.35,.70),'58B93F')
 attached_lobe(m,'TailTip',tail,(0,.4,-1),(.20,.25,.30),'94E567')
 return m
def trophy():
 m=model('Mascot_golden_trophy')
 # Tapered cup as twelve disjoint native elliptical slices.
 for j in range(12):
  y=1.0+(j+.5)*.12;d=.90+(j+1)/12
  cyl(m,'CupSlice',(0,y,0),.12,d,'F5BE37',mat='Metal')
 body=m['parts'].pop(6);body['name']='Body';m['parts'].insert(0,body)
 for sign in [-1,1]:
  box(m,'Boot',(sign*.40,.15,0),(.52,.30,.64),'2868C6')
  box(m,'ShortLeg',(sign*.40,.425,0),(.18,.25,.20),'EAB234')
 cyl(m,'Base',(0,.625,0),.15,1.25,'2868C6')
 cyl(m,'Stem',(0,.85,0),.30,.35,'F5BE37',mat='Metal')
 for j in range(12):
  t=TAU*j/12
  box(m,'GoldRim',(.98*math.sin(t),2.505,.98*math.cos(t)),(.43,.13,.15),'FFD052',r=rot(y=j*30),mat='Metal')
 cyl(m,'InnerCup',(0,2.455,0),.03,1.65,'AC6C1F',mat='Metal')
 disk(m,'GoldenFace',0,1.82,1.0,1.60,1.20,.08,'F5BE37')
 face(m,1.94,1.04,.40);mouth(m,1.39,1.04,'F5BE37')
 for sign in [-1,1]:
  box(m,'HandleUpper',(sign*1.02,2.35,0),(.12,.14,.25),'F5BE37',mat='Metal')
  box(m,'HandleLower',(sign*.88,1.45,0),(.40,.14,.25),'F5BE37',mat='Metal')
  for j in range(8):
   theta=math.radians(-78.75+j*22.5)
   part(m,'CurvedHandle',(sign*(1.08+.45*math.cos(theta)),1.90+.45*math.sin(theta),0),(.105,.14,.25),'F5BE37',r=rot(z=sign*(math.degrees(theta)+90)),mat='Metal')
  line(m,'Arm',(sign*.56,1.15,0),(sign*1.0,1.15,0),.14,'F5BE37')
  ball(m,'Fist',(sign*1.17,1.15,0),(.34,.34,.34),'F5BE37')
 star(m,1.28,1.60,.23,.34)
 return m
rows=[]
for id,m in [('cosmic_whale',whale()),('dragon_byte',dragon()),('golden_trophy',trophy())]:
 scale={'cosmic_whale':1.21,'golden_trophy':1.20}.get(id,1.0)
 for p in m['parts']:
  p['p']=tuple(v*scale for v in p['p']);p['s']=tuple(v*scale for v in p['s'])
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
  preview(m['parts'],ROOT/'previews'/('Mascot_'+id+'_'+label+'.png'),yaw=yaw,elev=15,target=(0,1.65,-.35) if id=='cosmic_whale' else (0,1.65,0),span=6.0,W=900,H=900)
(ROOT/'VALIDATION.json').write_text(json.dumps(rows,indent=2)+'\n');print(json.dumps(rows,indent=2))
